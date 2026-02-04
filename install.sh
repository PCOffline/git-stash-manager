#!/usr/bin/env bash
# Install script for Git Stash Manager
# Installs fzf and optionally adds the script to PATH

set -e

# Colors
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="git-stash-manager.sh"
SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_NAME"

# ============================================================================
# Package Manager Abstraction
# ============================================================================

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Darwin*)              echo "macos" ;;
        Linux*)               echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *)                    echo "unknown" ;;
    esac
}

# Detect available package manager
detect_package_manager() {
    local os
    os=$(detect_os)
    case "$os" in
        macos)
            command -v brew >/dev/null 2>&1 && echo "brew" || echo "none"
            ;;
        linux)
            if command -v apt-get >/dev/null 2>&1; then echo "apt"
            elif command -v dnf >/dev/null 2>&1; then echo "dnf"
            elif command -v pacman >/dev/null 2>&1; then echo "pacman"
            elif command -v apk >/dev/null 2>&1; then echo "apk"
            else echo "none"
            fi
            ;;
        windows)
            if command -v winget >/dev/null 2>&1; then echo "winget"
            elif command -v choco >/dev/null 2>&1; then echo "choco"
            elif command -v scoop >/dev/null 2>&1; then echo "scoop"
            else echo "none"
            fi
            ;;
        *)
            echo "none"
            ;;
    esac
}

# Run install command for a package manager
install_with() {
    local pm="$1" pkg="$2"
    case "$pm" in
        brew)   brew install "$pkg" ;;
        apt)    sudo apt-get update && sudo apt-get install -y "$pkg" ;;
        dnf)    sudo dnf install -y "$pkg" ;;
        pacman) sudo pacman -S --noconfirm "$pkg" ;;
        apk)    sudo apk add "$pkg" ;;
        winget) winget install "$pkg" ;;
        choco)  choco install "$pkg" -y ;;
        scoop)  scoop install "$pkg" ;;
        *)      return 1 ;;
    esac
}

# Get the correct package name for a given package manager
get_package_name() {
    local pkg="$1" pm="$2"
    case "$pkg:$pm" in
        fzf:winget)     echo "junegunn.fzf" ;;
        delta:brew)     echo "git-delta" ;;
        delta:apt)      echo "git-delta" ;;
        delta:dnf)      echo "git-delta" ;;
        delta:pacman)   echo "git-delta" ;;
        delta:winget)   echo "dandavison.delta" ;;
        *)              echo "$pkg" ;;
    esac
}

# Generic package installer
install_package() {
    local pkg="$1"
    local pm
    pm=$(detect_package_manager)
    
    if [[ "$pm" == "none" ]]; then
        printf "%sNo package manager found. Please install %s manually.%s\n" "$YELLOW" "$pkg" "$NC"
        case "$pkg" in
            fzf)   printf "  https://github.com/junegunn/fzf#installation\n" ;;
            delta) printf "  https://github.com/dandavison/delta#installation\n" ;;
        esac
        return 1
    fi
    
    local pkg_name
    pkg_name=$(get_package_name "$pkg" "$pm")
    
    printf "%sInstalling %s via %s...%s\n" "$YELLOW" "$pkg" "$pm" "$NC"
    if install_with "$pm" "$pkg_name"; then
        printf "%s%s installed successfully%s\n" "$GREEN" "$pkg" "$NC"
        return 0
    else
        printf "%sFailed to install %s%s\n" "$RED" "$pkg" "$NC"
        return 1
    fi
}

# ============================================================================
# Dependency Checks
# ============================================================================

check_fzf() {
    command -v fzf >/dev/null 2>&1
}

check_delta() {
    command -v delta >/dev/null 2>&1
}

# ============================================================================
# PATH Setup
# ============================================================================

# Create symlink (Unix)
create_symlink() {
    local target_dir="$1"
    local link_name="${2:-gsm}"
    local link_path="$target_dir/$link_name"
    
    if [[ -e "$link_path" ]]; then
        printf "%s%s already exists%s\n" "$YELLOW" "$link_path" "$NC"
        printf "Overwrite? [y/N]: "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            return 1
        fi
        rm -f "$link_path"
    fi
    
    ln -s "$SCRIPT_PATH" "$link_path"
    printf "%sCreated symlink: %s -> %s%s\n" "$GREEN" "$link_path" "$SCRIPT_PATH" "$NC"
}

# Create wrapper script (Windows Git Bash)
create_wrapper_script() {
    local target_dir="$1"
    local script_name="${2:-gsm}"
    local wrapper_path="$target_dir/$script_name"
    
    mkdir -p "$target_dir"
    
    if [[ -e "$wrapper_path" ]]; then
        printf "%s%s already exists%s\n" "$YELLOW" "$wrapper_path" "$NC"
        printf "Overwrite? [y/N]: "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    cat > "$wrapper_path" << EOF
#!/usr/bin/env bash
# Wrapper script for git-stash-manager
exec "$SCRIPT_PATH" "\$@"
EOF
    chmod +x "$wrapper_path"
    printf "%sCreated wrapper script: %s%s\n" "$GREEN" "$wrapper_path" "$NC"
}

# Setup PATH for Unix systems
setup_path_unix() {
    printf "%sAdd to PATH?%s\n" "$BLUE" "$NC"
    printf "This will create a symlink so you can run 'gsm' from anywhere.\n"
    printf "\n"
    printf "Options:\n"
    printf "  1) /usr/local/bin (requires sudo, system-wide)\n"
    printf "  2) ~/.local/bin (user only, no sudo)\n"
    printf "  3) Skip\n"
    printf "\n"
    printf "Choice [1/2/3]: "
    read -r choice
    
    case "$choice" in
        1)
            sudo mkdir -p /usr/local/bin
            sudo ln -sf "$SCRIPT_PATH" /usr/local/bin/gsm
            printf "%sCreated symlink: /usr/local/bin/gsm%s\n" "$GREEN" "$NC"
            ;;
        2)
            mkdir -p ~/.local/bin
            create_symlink ~/.local/bin gsm
            if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
                printf "\n"
                printf "%sNote: Add ~/.local/bin to your PATH:%s\n" "$YELLOW" "$NC"
                printf "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc\n"
            fi
            ;;
        3|*)
            printf "%sSkipping symlink creation%s\n" "$YELLOW" "$NC"
            printf "\n"
            printf "You can run the script directly:\n"
            printf "  %s\n" "$SCRIPT_PATH"
            ;;
    esac
}

# Setup PATH for Windows (Git Bash)
setup_path_windows() {
    printf "%sAdd to PATH?%s\n" "$BLUE" "$NC"
    printf "This will create a wrapper script so you can run 'gsm' from Git Bash.\n"
    printf "\n"
    printf "Options:\n"
    printf "  1) ~/bin (Git Bash user bin)\n"
    printf "  2) Skip (and show PowerShell instructions)\n"
    printf "\n"
    printf "Choice [1/2]: "
    read -r choice
    
    case "$choice" in
        1)
            create_wrapper_script ~/bin gsm
            if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
                printf "\n"
                printf "%sNote: Add ~/bin to your PATH in ~/.bashrc:%s\n" "$YELLOW" "$NC"
                printf "  echo 'export PATH=\"\$HOME/bin:\$PATH\"' >> ~/.bashrc\n"
            fi
            ;;
        2|*)
            printf "%sSkipping wrapper script creation%s\n" "$YELLOW" "$NC"
            ;;
    esac
    
    printf "\n"
    printf "%sFor PowerShell users:%s\n" "$BLUE" "$NC"
    printf "You can create a PowerShell function in your \$PROFILE:\n"
    printf "\n"
    printf "  function gsm { & bash '%s' \$args }\n" "$SCRIPT_PATH"
    printf "\n"
    printf "Or run directly from PowerShell:\n"
    printf "  bash %s\n" "$SCRIPT_PATH"
}

# ============================================================================
# Main
# ============================================================================

main() {
    printf "%sGit Stash Manager - Installation%s\n" "$BLUE" "$NC"
    printf "\n"
    
    # Check if script exists
    if [[ ! -f "$SCRIPT_PATH" ]]; then
        printf "%sError: %s not found%s\n" "$RED" "$SCRIPT_PATH" "$NC"
        exit 1
    fi
    
    # Ensure script is executable
    chmod +x "$SCRIPT_PATH"
    
    # Install fzf if not present
    if check_fzf; then
        printf "%s✓ fzf is already installed%s\n" "$GREEN" "$NC"
    else
        printf "%sfzf is not installed%s\n" "$YELLOW" "$NC"
        printf "Install fzf? [Y/n]: "
        read -r response
        if [[ ! "$response" =~ ^[Nn]$ ]]; then
            install_package fzf || true
        else
            printf "%sSkipping fzf installation. The script will use fallback mode.%s\n" "$YELLOW" "$NC"
        fi
    fi
    
    printf "\n"
    
    # Install delta if not present (optional, for better diffs)
    if check_delta; then
        printf "%s✓ delta is already installed (syntax-highlighted diffs)%s\n" "$GREEN" "$NC"
    else
        printf "%sdelta is not installed (optional, for better diff display)%s\n" "$YELLOW" "$NC"
        printf "Install delta? [Y/n]: "
        read -r response
        if [[ ! "$response" =~ ^[Nn]$ ]]; then
            install_package delta || true
        else
            printf "%sSkipping delta installation. Diffs will use basic formatting.%s\n" "$YELLOW" "$NC"
        fi
    fi
    
    printf "\n"
    
    # Setup PATH based on OS
    local os
    os=$(detect_os)
    if [[ "$os" == "windows" ]]; then
        setup_path_windows
    else
        setup_path_unix
    fi
    
    printf "\n"
    printf "%sInstallation complete!%s\n" "$GREEN" "$NC"
    printf "\n"
    printf "Usage:\n"
    printf "  gsm              # Run the stash manager (if symlinked)\n"
    printf "  %s     # Run directly\n" "$SCRIPT_PATH"
}

main "$@"
