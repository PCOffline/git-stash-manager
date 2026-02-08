#!/usr/bin/env bash
set -euo pipefail
# Git Stash Manager - Interactive TUI for managing git stashes
# Uses fzf when available, falls back to simple numbered menu otherwise

# Configuration
CONFIG_DIR="$HOME/.config/git-stash-manager"
CONFIG_FILE="$CONFIG_DIR/config"

# Colors
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m' # No Color

# Helper functions for colored output
msg() { printf "%s%s%s\n" "$1" "$2" "$NC"; }

# Load default action from config file
load_default_action() {
    if [[ -f "$CONFIG_FILE" ]]; then
        local action
        action=$(grep "^default_action=" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2)
        # Migrate stale "rename" config - delete and let user choose again
        if [[ "$action" == "rename" ]]; then
            rm -f "$CONFIG_FILE"
            return
        fi
        echo "$action"
    fi
}

# Save default action to config file
save_default_action() {
    mkdir -p "$CONFIG_DIR"
    echo "default_action=$1" > "$CONFIG_FILE"
}

# Prompt user to choose default action for Enter key
prompt_default_action() {
    printf "\n" >&2
    printf "%sWhat should Enter do by default?%s\n" "$BOLD" "$NC" >&2
    printf "  %sa)%s Apply stash\n" "$CYAN" "$NC" >&2
    printf "  %sv)%s View full diff in pager\n" "$CYAN" "$NC" >&2
    printf "  %sp)%s Pop stash (apply + remove)\n" "$CYAN" "$NC" >&2
    printf "\n" >&2
    printf "%sChoice [a/v/p]: %s" "$YELLOW" "$NC" >&2
    read -r choice
    case "$choice" in
        a|A) echo "apply" ;;
        v|V) echo "view" ;;
        p|P) echo "pop" ;;
        *) echo "apply" ;;
    esac
}

# Get or prompt for default action
get_default_action() {
    local action=$(load_default_action)
    if [[ -z "$action" ]]; then
        action=$(prompt_default_action)
        save_default_action "$action"
        printf "%sSaved '%s' as default Enter action%s\n" "$GREEN" "$action" "$NC" >&2
        sleep 1
    fi
    echo "$action"
}

# Check if we're in a git repository
check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        msg "$RED" "Error: Not a git repository"
        exit 1
    fi
}

# Check if fzf is available
has_fzf() {
    command -v fzf > /dev/null 2>&1
}

# Check if fzf version is sufficient (requires 0.45.0+ for transform action)
check_fzf_version() {
    local version min_version="0.45.0"
    version=$(fzf --version 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')
    [[ -z "$version" ]] && return 1
    
    # Compare versions using sort -V
    printf '%s\n%s\n' "$min_version" "$version" | sort -V | head -n1 | grep -q "^$min_version$"
}

# Check if delta is available (for better diff display)
has_delta() {
    command -v delta > /dev/null 2>&1
}

# Get stash list
get_stashes() {
    git stash list 2>/dev/null
}

# Extract stash reference from a stash line (e.g., "stash@{0}")
get_stash_ref() {
    echo "$1" | grep -o 'stash@{[0-9]*}'
}

# Confirm action (returns 0 for yes, 1 for no)
confirm() {
    local prompt="$1"
    local response
    printf "%s%s [y/N]: %s" "$YELLOW" "$prompt" "$NC"
    read -r response
    [[ "$response" =~ ^[Yy]$ ]]
}

# Show stash diff in pager
do_view() {
    local stash_ref="$1"
    if has_delta; then
        git stash show -p "$stash_ref" | delta --paging=always
    else
        git stash show -p "$stash_ref" | ${PAGER:-less}
    fi
}

# Apply stash
do_apply() {
    local stash_ref="$1"
    
    if confirm "Apply $stash_ref?"; then
        if git stash apply "$stash_ref"; then
            msg "$GREEN" "Applied $stash_ref"
        else
            msg "$RED" "Failed to apply $stash_ref"
        fi
    fi
}

# Pop stash
do_pop() {
    local stash_ref="$1"
    
    if confirm "Pop $stash_ref? (will remove from stash list)"; then
        if git stash pop "$stash_ref"; then
            msg "$GREEN" "Popped $stash_ref"
        else
            msg "$RED" "Failed to pop $stash_ref"
        fi
    fi
}

# Drop stash
do_drop() {
    local stash_ref="$1"
    
    if confirm "Drop $stash_ref? (PERMANENTLY DELETES)"; then
        if git stash drop "$stash_ref"; then
            msg "$GREEN" "Dropped $stash_ref"
        else
            msg "$RED" "Failed to drop $stash_ref"
        fi
    fi
}

# Rename stash
do_rename() {
    local stash_ref="$1"
    local stash_commit
    local new_message
    
    stash_commit=$(git rev-parse "$stash_ref") || {
        msg "$RED" "Failed to get stash commit"
        return 1
    }
    
    printf "%sEnter new message: %s" "$BLUE" "$NC"
    read -r new_message
    
    if [[ -z "$new_message" ]]; then
        msg "$YELLOW" "Cancelled (empty message)"
        return
    fi
    
    # Drop first (removes from reflog), then store with new message
    if git stash drop "$stash_ref" > /dev/null 2>&1; then
        if git stash store -m "$new_message" "$stash_commit"; then
            msg "$GREEN" "Renamed stash"
        else
            msg "$RED" "Failed to store renamed stash"
            return 1
        fi
    else
        msg "$RED" "Failed to drop stash"
        return 1
    fi
}

# FZF mode - full interactive experience
fzf_mode() {
    local stashes
    local selection
    
    # Header for action mode
    local action_header=$'
  ╭──────────────────────────────────────────────────────────╮
  │  a Apply   p Pop   d Drop   r Rename   v View   q Quit   │
  │  Press / to search  ·  Enter for default action          │
  ╰──────────────────────────────────────────────────────────╯
'
    
    # Header for search mode
    local search_header=$'
  ╭──────────────────────────────────────────────────────────╮
  │  [SEARCH MODE]  Type to filter  ·  Esc return to actions │
  ╰──────────────────────────────────────────────────────────╯
'
    
    # Header for rename mode
    local rename_header=$'
  ╭──────────────────────────────────────────────────────────╮
  │  [RENAME]  Enter to save  ·  Esc to cancel               │
  ╰──────────────────────────────────────────────────────────╯
'
    
    # Header for confirm mode (used for apply/pop/drop)
    local confirm_header=$'
  ╭──────────────────────────────────────────────────────────╮
  │  [CONFIRM]  y to confirm  ·  n or Esc to cancel          │
  ╰──────────────────────────────────────────────────────────╯
'
    
    # Get default action once (will prompt user if not configured)
    local default_action=$(get_default_action)
    
    while true; do
        stashes=$(get_stashes)
        
        if [[ -z "$stashes" ]]; then
            msg "$YELLOW" "No stashes found"
            return 0
        fi
        
        # Use fzf with preview and keybindings
        # Starts in action mode (--disabled), press / to search
        # Export default_action for use in transform bindings
        selection=$(echo "$stashes" | DEFAULT_ACTION="$default_action" fzf \
            --ansi \
            --no-multi \
            --sync \
            --disabled \
            --preview 'stash=$(echo {} | grep -o "stash@{[0-9]*}"); if command -v delta >/dev/null 2>&1; then git stash show -p "$stash" | delta --paging=never; else git stash show -p "$stash"; fi' \
            --preview-window=right:60%:wrap \
            --header "$action_header" \
            --header-first \
            --bind 'start:unbind(y,n)' \
            --bind '/:unbind(a,p,d,r,v,enter)+enable-search+clear-query+transform-header(printf '"'"'%s'"'"' "'"$search_header"'")' \
            --bind 'esc:disable-search+rebind(a,p,d,r,v,enter,/,q)+unbind(y,n)+clear-query+first+transform-header(printf '"'"'%s'"'"' "'"$action_header"'")+change-prompt(> )' \
            --bind 'enter:transform:
                if [[ "$FZF_PROMPT" == Rename\ stash@* ]]; then
                    # Extract stash ref from prompt "Rename stash@{N}: "
                    stash_ref=$(echo "$FZF_PROMPT" | grep -o "stash@{[0-9]*}")
                    new_msg="$FZF_QUERY"
                    if [[ -z "$new_msg" ]]; then
                        printf "%s" "rebind(a,p,d,r,v,/,q)+disable-search+clear-query+change-prompt(> )+transform-header(printf '"'"'%s'"'"' \"'"$action_header"'\")"
                    else
                        # Perform the rename
                        commit=$(git rev-parse "$stash_ref" 2>&1) || {
                            printf "%s" "change-header(  ✗ Failed to get stash commit)+rebind(a,p,d,r,v,/,q)+disable-search+clear-query+change-prompt(> )"
                            exit 0
                        }
                        if git stash drop "$stash_ref" > /dev/null 2>&1; then
                            if git stash store -m "$new_msg" "$commit" 2>&1; then
                                printf "%s" "reload(git stash list)+rebind(a,p,d,r,v,/,q)+disable-search+clear-query+change-prompt(> )+first+transform-header(printf '"'"'%s'"'"' \"'"$action_header"'\")"
                            else
                                printf "%s" "change-header(  ✗ Failed to store renamed stash)+rebind(a,p,d,r,v,/,q)+disable-search+clear-query+change-prompt(> )"
                            fi
                        else
                            printf "%s" "change-header(  ✗ Failed to drop stash)+rebind(a,p,d,r,v,/,q)+disable-search+clear-query+change-prompt(> )"
                        fi
                    fi
                elif [[ "$FZF_PROMPT" == "> " ]] || [[ "$FZF_PROMPT" == "" ]]; then
                    # Default action mode - trigger based on DEFAULT_ACTION
                    stash=$(echo {} | grep -o "stash@{[0-9]*}")
                    case "$DEFAULT_ACTION" in
                        view)
                            printf "%s" "execute(if command -v delta >/dev/null 2>&1; then git stash show -p $stash | delta --paging=always; else git stash show -p $stash | less; fi)"
                            ;;
                        apply)
                            printf "%s" "unbind(a,p,d,r,v,/,enter)+rebind(y,n)+change-prompt(Apply $stash? )+transform-header(printf '"'"'%s'"'"' \"'"$confirm_header"'\")"
                            ;;
                        pop)
                            printf "%s" "unbind(a,p,d,r,v,/,enter)+rebind(y,n)+change-prompt(Pop $stash? )+transform-header(printf '"'"'%s'"'"' \"'"$confirm_header"'\")"
                            ;;
                    esac
                fi
            ' \
            --bind 'a:transform:
                stash=$(echo {} | grep -o "stash@{[0-9]*}")
                printf "%s" "unbind(a,p,d,r,v,/,enter)+rebind(y,n)+change-prompt(Apply $stash? )+transform-header(printf '"'"'%s'"'"' \"'"$confirm_header"'\")"
            ' \
            --bind 'p:transform:
                stash=$(echo {} | grep -o "stash@{[0-9]*}")
                printf "%s" "unbind(a,p,d,r,v,/,enter)+rebind(y,n)+change-prompt(Pop $stash? )+transform-header(printf '"'"'%s'"'"' \"'"$confirm_header"'\")"
            ' \
            --bind 'd:transform:
                stash=$(echo {} | grep -o "stash@{[0-9]*}")
                printf "%s" "unbind(a,p,d,r,v,/,enter)+rebind(y,n)+change-prompt(Drop $stash? )+transform-header(printf '"'"'%s'"'"' \"'"$confirm_header"'\")"
            ' \
            --bind 'y:transform:
                if [[ "$FZF_PROMPT" == Apply\ stash@* ]]; then
                    stash_ref=$(echo "$FZF_PROMPT" | grep -o "stash@{[0-9]*}")
                    if git stash apply "$stash_ref" > /dev/null 2>&1; then
                        printf "%s" "rebind(a,p,d,r,v,/,enter)+unbind(y,n)+change-prompt(> )+transform-header(printf '"'"'%s'"'"' \"'"$action_header"'\")"
                    else
                        printf "%s" "change-header(  ✗ Failed to apply $stash_ref)+rebind(a,p,d,r,v,/,enter)+unbind(y,n)+change-prompt(> )"
                    fi
                elif [[ "$FZF_PROMPT" == Pop\ stash@* ]]; then
                    stash_ref=$(echo "$FZF_PROMPT" | grep -o "stash@{[0-9]*}")
                    if git stash pop "$stash_ref" > /dev/null 2>&1; then
                        printf "%s" "reload(git stash list)+rebind(a,p,d,r,v,/,enter)+unbind(y,n)+change-prompt(> )+first+transform-header(printf '"'"'%s'"'"' \"'"$action_header"'\")"
                    else
                        printf "%s" "change-header(  ✗ Failed to pop $stash_ref)+rebind(a,p,d,r,v,/,enter)+unbind(y,n)+change-prompt(> )"
                    fi
                elif [[ "$FZF_PROMPT" == Drop\ stash@* ]]; then
                    stash_ref=$(echo "$FZF_PROMPT" | grep -o "stash@{[0-9]*}")
                    if git stash drop "$stash_ref" > /dev/null 2>&1; then
                        printf "%s" "reload(git stash list)+rebind(a,p,d,r,v,/,enter)+unbind(y,n)+change-prompt(> )+first+transform-header(printf '"'"'%s'"'"' \"'"$action_header"'\")"
                    else
                        printf "%s" "change-header(  ✗ Failed to drop $stash_ref)+rebind(a,p,d,r,v,/,enter)+unbind(y,n)+change-prompt(> )"
                    fi
                fi
            ' \
            --bind 'n:transform:
                if [[ "$FZF_PROMPT" == Apply\ stash@* ]] || [[ "$FZF_PROMPT" == Pop\ stash@* ]] || [[ "$FZF_PROMPT" == Drop\ stash@* ]]; then
                    printf "%s" "rebind(a,p,d,r,v,/,enter)+unbind(y,n)+change-prompt(> )+transform-header(printf '"'"'%s'"'"' \"'"$action_header"'\")"
                fi
            ' \
            --bind 'r:transform:
                stash=$(echo {} | grep -o "stash@{[0-9]*}")
                msg=$(echo {} | sed "s/^stash@{[0-9]*}: //" | sed "s/)+/) +/g")
                printf "%s" "unbind(a,p,d,r,v,/,q)+disable-search+change-prompt(Rename $stash: )+change-query($msg)+transform-header(printf '"'"'%s'"'"' \"'"$rename_header"'\")"
            ' \
            --bind 'v:execute(stash=$(echo {} | grep -o "stash@{[0-9]*}"); if command -v delta >/dev/null 2>&1; then git stash show -p "$stash" | delta --paging=always; else git stash show -p "$stash" | less; fi)' \
            --bind 'q:abort' \
            )
        
        # FZF exited - either user quit or all stashes were processed
        if [[ -z "$selection" ]]; then
            return 0
        fi
    done
}

# Simple mode - numbered menu fallback
simple_mode() {
    local stashes
    local stash_array
    local choice
    local action
    local stash_ref
    local stash_line
    
    while true; do
        stashes=$(get_stashes)
        
        if [[ -z "$stashes" ]]; then
            msg "$YELLOW" "No stashes found"
            return 0
        fi
        
        printf "\n"
        msg "$BOLD" "=== Git Stashes ==="
        printf "\n"
        
        # Display numbered list
        local i=1
        stash_array=()
        while IFS= read -r line; do
            stash_array+=("$line")
            printf "  %s[%d]%s %s\n" "$BLUE" "$i" "$NC" "$line"
            i=$((i + 1))
        done <<< "$stashes"
        
        printf "\n"
        printf "%sActions:%s %sv%s=view %sa%s=apply %sp%s=pop %sd%s=drop %sr%s=rename %sq%s=quit\n" "$BOLD" "$NC" "$GREEN" "$NC" "$GREEN" "$NC" "$GREEN" "$NC" "$RED" "$NC" "$BLUE" "$NC" "$YELLOW" "$NC"
        printf "\n"
        printf "Enter number (1-%d) then action key, or q to quit: " "$((i-1))"
        read -r choice
        
        # Check for quit
        if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
            return 0
        fi
        
        # Parse input: expect "number" followed by "action" (e.g., "1v", "2d", "1 a")
        local num action_key
        num=$(echo "$choice" | grep -o '^[0-9]*')
        action_key=$(echo "$choice" | grep -o '[a-zA-Z]$')
        
        if [[ -z "$num" || -z "$action_key" ]]; then
            msg "$RED" "Invalid input. Use format: <number><action> (e.g., 1v, 2d)"
            sleep 1
            continue
        fi
        
        if [[ "$num" -lt 1 || "$num" -gt "${#stash_array[@]}" ]]; then
            msg "$RED" "Invalid stash number"
            sleep 1
            continue
        fi
        
        stash_line="${stash_array[$((num-1))]}"
        stash_ref=$(get_stash_ref "$stash_line")
        
        case "$action_key" in
            v|V)
                do_view "$stash_ref"
                ;;
            a|A)
                do_apply "$stash_ref"
                sleep 1
                ;;
            p|P)
                do_pop "$stash_ref"
                sleep 1
                ;;
            d|D)
                do_drop "$stash_ref"
                sleep 1
                ;;
            r|R)
                do_rename "$stash_ref"
                sleep 1
                ;;
            *)
                msg "$RED" "Unknown action: $action_key"
                sleep 1
                ;;
        esac
    done
}

# Main entry point
main() {
    check_git_repo
    
    if has_fzf && check_fzf_version; then
        fzf_mode
    else
        if has_fzf; then
            msg "$YELLOW" "Note: fzf 0.45.0+ required for interactive mode (found older version)"
        else
            msg "$YELLOW" "Note: Install fzf for a better experience (brew install fzf)"
        fi
        printf "\n"
        simple_mode
    fi
}

main "$@"
