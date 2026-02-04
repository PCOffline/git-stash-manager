#!/usr/bin/env bash
# Install script for Git Stash Manager
# Installs fzf and optionally adds the script to PATH

set -e

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="git-stash-manager.zsh"
SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_NAME"

printf "%sGit Stash Manager - Installation%s\n" "$BLUE" "$NC"
printf "\n"

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Darwin*) echo "macos" ;;
        Linux*)  echo "linux" ;;
        *)       echo "unknown" ;;
    esac
}

# Check if fzf is installed
check_fzf() {
    command -v fzf > /dev/null 2>&1
}

# Check if delta is installed
check_delta() {
    command -v delta > /dev/null 2>&1
}

# Install delta
install_delta() {
    local os=$(detect_os)
    
    printf "%sInstalling delta...%s\n" "$YELLOW" "$NC"
    
    case "$os" in
        macos)
            if command -v brew > /dev/null 2>&1; then
                brew install git-delta
            else
                printf "%sHomebrew not found. Please install delta manually: https://github.com/dandavison/delta#installation%s\n" "$RED" "$NC"
                return 1
            fi
            ;;
        linux)
            if command -v apt-get > /dev/null 2>&1; then
                sudo apt-get update && sudo apt-get install -y git-delta
            elif command -v dnf > /dev/null 2>&1; then
                sudo dnf install -y git-delta
            elif command -v pacman > /dev/null 2>&1; then
                sudo pacman -S --noconfirm git-delta
            else
                printf "%sCould not detect package manager. Please install delta manually: https://github.com/dandavison/delta#installation%s\n" "$YELLOW" "$NC"
                return 1
            fi
            ;;
        *)
            printf "%sPlease install delta manually: https://github.com/dandavison/delta#installation%s\n" "$YELLOW" "$NC"
            return 1
            ;;
    esac
    
    printf "%sdelta installed successfully%s\n" "$GREEN" "$NC"
}

# Install fzf
install_fzf() {
    local os=$(detect_os)
    
    printf "%sInstalling fzf...%s\n" "$YELLOW" "$NC"
    
    case "$os" in
        macos)
            if command -v brew > /dev/null 2>&1; then
                brew install fzf
            else
                printf "%sHomebrew not found. Please install Homebrew first:%s\n" "$RED" "$NC"
                printf "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"\n"
                exit 1
            fi
            ;;
        linux)
            if command -v apt-get > /dev/null 2>&1; then
                sudo apt-get update && sudo apt-get install -y fzf
            elif command -v dnf > /dev/null 2>&1; then
                sudo dnf install -y fzf
            elif command -v pacman > /dev/null 2>&1; then
                sudo pacman -S --noconfirm fzf
            elif command -v apk > /dev/null 2>&1; then
                sudo apk add fzf
            else
                printf "%sCould not detect package manager. Installing fzf from git...%s\n" "$YELLOW" "$NC"
                git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
                ~/.fzf/install --all
            fi
            ;;
        *)
            printf "%sUnknown OS. Please install fzf manually: https://github.com/junegunn/fzf#installation%s\n" "$RED" "$NC"
            exit 1
            ;;
    esac
    
    printf "%sfzf installed successfully%s\n" "$GREEN" "$NC"
}

# Create symlink to PATH
create_symlink() {
    local target_dir="$1"
    local link_name="${2:-gsm}"
    local link_path="$target_dir/$link_name"
    
    if [[ -e "$link_path" ]]; then
        printf "%s%s already exists%s\n" "$YELLOW" "$link_path" "$NC"
        read -p "Overwrite? [y/N]: " response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            return 1
        fi
        rm -f "$link_path"
    fi
    
    ln -s "$SCRIPT_PATH" "$link_path"
    printf "%sCreated symlink: %s -> %s%s\n" "$GREEN" "$link_path" "$SCRIPT_PATH" "$NC"
}

# Main installation
main() {
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
        read -p "Install fzf? [Y/n]: " response
        if [[ ! "$response" =~ ^[Nn]$ ]]; then
            install_fzf
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
        read -p "Install delta? [Y/n]: " response
        if [[ ! "$response" =~ ^[Nn]$ ]]; then
            install_delta || true
        else
            printf "%sSkipping delta installation. Diffs will use basic formatting.%s\n" "$YELLOW" "$NC"
        fi
    fi
    
    printf "\n"
    
    # Offer to create symlink
    printf "%sAdd to PATH?%s\n" "$BLUE" "$NC"
    printf "This will create a symlink so you can run 'gsm' from anywhere.\n"
    printf "\n"
    printf "Options:\n"
    printf "  1) /usr/local/bin (requires sudo, system-wide)\n"
    printf "  2) ~/.local/bin (user only, no sudo)\n"
    printf "  3) Skip\n"
    printf "\n"
    read -p "Choice [1/2/3]: " choice
    
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
                printf "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc\n"
            fi
            ;;
        3|*)
            printf "%sSkipping symlink creation%s\n" "$YELLOW" "$NC"
            printf "\n"
            printf "You can run the script directly:\n"
            printf "  %s\n" "$SCRIPT_PATH"
            ;;
    esac
    
    printf "\n"
    printf "%sInstallation complete!%s\n" "$GREEN" "$NC"
    printf "\n"
    printf "Usage:\n"
    printf "  gsm              # Run the stash manager (if symlinked)\n"
    printf "  %s     # Run directly\n" "$SCRIPT_PATH"
}

main "$@"
