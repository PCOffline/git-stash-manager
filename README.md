# Git Stash Manager

An interactive terminal UI for managing git stashes with live diff preview.

<img width="1720" height="354" alt="screenshot of Git Stash Manager" src="https://github.com/user-attachments/assets/127cc7e4-cfe5-4b9c-8466-bfc614defa00" />

## Features

- Browse stashes with a live diff preview panel
- Rich syntax-highlighted diffs
- Apply, pop, drop, or rename stashes with a single keypress
- Search/filter stashes by name
- Configurable default action for Enter key

## Installation

### Quick Install

```bash
./install.sh
```

The installer will:
- Install [fzf](https://github.com/junegunn/fzf) for the interactive interface
- Install [delta](https://github.com/dandavison/delta) for rich syntax-highlighted diffs
- Create a `gsm` command you can run from anywhere

After installation, restart your shell or open a new terminal.

### Windows

1. Open Git Bash and run `./install.sh`
2. Restart your shell
3. Run `gsm` from Git Bash

For PowerShell, add this function to your `$PROFILE`:

```powershell
function gsm { & bash 'path/to/git-stash-manager.sh' $args }
```

## Usage

Run `gsm` inside any git repository:

```bash
gsm
```

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `a` | Apply stash |
| `p` | Pop stash (apply + remove) |
| `d` | Drop stash (delete) |
| `r` | Rename stash |
| `v` | View full diff in pager |
| `/` | Search/filter stashes |
| `Esc` | Exit search mode |
| `q` | Quit |

Use arrow keys to navigate between stashes. The diff preview updates automatically.

### Default Action

On first run, you'll be prompted to choose a default action for the Enter key (apply, view, or pop). This preference is saved to `~/.config/git-stash-manager/config`.

## Troubleshooting

### No interactive interface / numbered menu appears

The interactive UI requires [fzf](https://github.com/junegunn/fzf). Without it, a fallback numbered menu is used instead.

Install fzf manually:

```bash
# macOS
brew install fzf

# Debian/Ubuntu
sudo apt install fzf

# Arch
sudo pacman -S fzf
```

### Diffs are not syntax-highlighted

Rich diff highlighting requires [delta](https://github.com/dandavison/delta). Without it, diffs display in plain text.

Install delta manually:

```bash
# macOS
brew install git-delta

# Debian/Ubuntu
sudo apt install git-delta

# Arch
sudo pacman -S git-delta
```

## Contributing

Contributions are welcome!

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes
4. Push to your branch and open a Pull Request

Please ensure your code follows the existing style and includes appropriate error handling.

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE).
