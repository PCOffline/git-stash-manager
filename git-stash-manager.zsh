#!/usr/bin/env zsh
# Git Stash Manager - Interactive TUI for managing git stashes
# Uses fzf when available, falls back to simple numbered menu otherwise

# Configuration
CONFIG_DIR="$HOME/.config/git-stash-manager"
CONFIG_FILE="$CONFIG_DIR/config"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# Load default action from config file
load_default_action() {
    if [[ -f "$CONFIG_FILE" ]]; then
        grep "^default_action=" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2
    fi
}

# Save default action to config file
save_default_action() {
    mkdir -p "$CONFIG_DIR"
    echo "default_action=$1" > "$CONFIG_FILE"
}

# Prompt user to choose default action for Enter key
prompt_default_action() {
    echo "" >&2
    echo "${BOLD}What should Enter do by default?${NC}" >&2
    echo "  ${CYAN}a)${NC} Apply stash" >&2
    echo "  ${CYAN}v)${NC} View full diff in pager" >&2
    echo "  ${CYAN}p)${NC} Pop stash (apply + remove)" >&2
    echo "  ${CYAN}r)${NC} Rename stash" >&2
    echo "" >&2
    echo -n "${YELLOW}Choice [a/v/p/r]: ${NC}" >&2
    read -r choice
    case "$choice" in
        a|A) echo "apply" ;;
        v|V) echo "view" ;;
        p|P) echo "pop" ;;
        r|R) echo "rename" ;;
        *) echo "apply" ;;
    esac
}

# Get or prompt for default action
get_default_action() {
    local action=$(load_default_action)
    if [[ -z "$action" ]]; then
        action=$(prompt_default_action)
        save_default_action "$action"
        echo "${GREEN}Saved '$action' as default Enter action${NC}" >&2
        sleep 1
    fi
    echo "$action"
}

# Check if we're in a git repository
check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "${RED}Error: Not a git repository${NC}"
        exit 1
    fi
}

# Check if fzf is available
has_fzf() {
    command -v fzf > /dev/null 2>&1
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
    echo -n "${YELLOW}${prompt} [y/N]: ${NC}"
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
            echo "${GREEN}Applied $stash_ref${NC}"
        else
            echo "${RED}Failed to apply $stash_ref${NC}"
        fi
    fi
}

# Pop stash
do_pop() {
    local stash_ref="$1"
    
    if confirm "Pop $stash_ref? (will remove from stash list)"; then
        if git stash pop "$stash_ref"; then
            echo "${GREEN}Popped $stash_ref${NC}"
        else
            echo "${RED}Failed to pop $stash_ref${NC}"
        fi
    fi
}

# Drop stash
do_drop() {
    local stash_ref="$1"
    
    if confirm "Drop $stash_ref? (PERMANENTLY DELETES)"; then
        if git stash drop "$stash_ref"; then
            echo "${GREEN}Dropped $stash_ref${NC}"
        else
            echo "${RED}Failed to drop $stash_ref${NC}"
        fi
    fi
}

# Rename stash
do_rename() {
    local stash_ref="$1"
    local stash_commit
    local new_message
    
    stash_commit=$(git rev-parse "$stash_ref")
    
    echo -n "${BLUE}Enter new message: ${NC}"
    read -r new_message
    
    if [[ -z "$new_message" ]]; then
        echo "${YELLOW}Cancelled (empty message)${NC}"
        return
    fi
    
    # Drop old stash and store with new message
    git stash drop "$stash_ref" > /dev/null 2>&1
    git stash store -m "$new_message" "$stash_commit"
    echo "${GREEN}Renamed stash${NC}"
}

# FZF mode - full interactive experience
fzf_mode() {
    local stashes
    local selection
    local action
    local stash_ref
    local last_pos=1
    
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
    
    while true; do
        stashes=$(get_stashes)
        
        if [[ -z "$stashes" ]]; then
            echo "${YELLOW}No stashes found${NC}"
            return 0
        fi
        
        # Use fzf with preview and keybindings
        # Starts in action mode (--disabled), press / to search
        selection=$(echo "$stashes" | fzf \
            --ansi \
            --no-multi \
            --sync \
            --disabled \
            --preview 'stash=$(echo {} | grep -o "stash@{[0-9]*}"); if command -v delta >/dev/null 2>&1; then git stash show -p "$stash" | delta --paging=never; else git stash show -p "$stash"; fi' \
            --preview-window=right:60%:wrap \
            --header "$action_header" \
            --header-first \
            --bind "start:pos($last_pos)" \
            --bind '/:unbind(a,p,d,r,v,enter)+enable-search+clear-query+transform-header(printf '"'"'%s'"'"' "'"$search_header"'")' \
            --bind 'esc:disable-search+rebind(a,p,d,r,v,enter)+first+transform-header(printf '"'"'%s'"'"' "'"$action_header"'")' \
            --bind 'enter:become(echo ENTER:{})' \
            --bind 'a:become(echo apply:{})' \
            --bind 'p:become(echo pop:{})' \
            --bind 'd:become(echo drop:{})' \
            --bind 'r:become(echo rename:{})' \
            --bind 'v:execute(stash=$(echo {} | grep -o "stash@{[0-9]*}"); if command -v delta >/dev/null 2>&1; then git stash show -p "$stash" | delta --paging=always; else git stash show -p "$stash" | less; fi)' \
            --bind 'q:abort' \
            )
        
        # Parse the selection (format: "action:stash_line" from become())
        if [[ -z "$selection" ]]; then
            return 0
        fi
        
        # Extract action and stash ref from "action:stash_line" format
        if [[ "$selection" != *":"* ]]; then
            continue
        fi
        
        action="${selection%%:*}"
        stash_ref=$(get_stash_ref "${selection#*:}")
        
        if [[ -z "$stash_ref" ]]; then
            continue
        fi
        
        # Extract stash number for position tracking (stash@{N} -> N+1 for 1-indexed fzf)
        local stash_num="${stash_ref#stash@\{}"
        stash_num="${stash_num%\}}"
        
        # Execute the action
        case "$action" in
            ENTER)
                # Get or prompt for default action (lazy - only prompts if not configured)
                local default_action=$(get_default_action)
                case "$default_action" in
                    apply)
                        do_apply "$stash_ref"
                        sleep 1
                        ;;
                    view)
                        do_view "$stash_ref"
                        last_pos=$((stash_num + 1))
                        ;;
                    pop)
                        do_pop "$stash_ref"
                        sleep 1
                        ;;
                    rename)
                        do_rename "$stash_ref"
                        sleep 1
                        last_pos=$((stash_num + 1))
                        ;;
                esac
                ;;
            apply)
                do_apply "$stash_ref"
                sleep 1
                ;;
            view)
                do_view "$stash_ref"
                last_pos=$((stash_num + 1))
                ;;
            pop)
                do_pop "$stash_ref"
                sleep 1
                ;;
            drop)
                do_drop "$stash_ref"
                sleep 1
                ;;
            rename)
                do_rename "$stash_ref"
                sleep 1
                last_pos=$((stash_num + 1))
                ;;
        esac
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
            echo "${YELLOW}No stashes found${NC}"
            return 0
        fi
        
        echo ""
        echo "${BOLD}=== Git Stashes ===${NC}"
        echo ""
        
        # Display numbered list
        local i=1
        stash_array=()
        while IFS= read -r line; do
            stash_array+=("$line")
            echo "  ${BLUE}[$i]${NC} $line"
            ((i++))
        done <<< "$stashes"
        
        echo ""
        echo "${BOLD}Actions:${NC} ${GREEN}v${NC}=view ${GREEN}a${NC}=apply ${GREEN}p${NC}=pop ${RED}d${NC}=drop ${BLUE}r${NC}=rename ${YELLOW}q${NC}=quit"
        echo ""
        echo -n "Enter number (1-$((i-1))) then action key, or q to quit: "
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
            echo "${RED}Invalid input. Use format: <number><action> (e.g., 1v, 2d)${NC}"
            sleep 1
            continue
        fi
        
        if [[ "$num" -lt 1 || "$num" -gt "${#stash_array[@]}" ]]; then
            echo "${RED}Invalid stash number${NC}"
            sleep 1
            continue
        fi
        
        stash_line="${stash_array[$num]}"
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
                echo "${RED}Unknown action: $action_key${NC}"
                sleep 1
                ;;
        esac
    done
}

# Main entry point
main() {
    check_git_repo
    
    if has_fzf; then
        fzf_mode
    else
        echo "${YELLOW}Note: Install fzf for a better experience (brew install fzf)${NC}"
        echo ""
        simple_mode
    fi
}

main "$@"
