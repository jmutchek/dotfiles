# Dotfiles

Personal configuration files managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Structure

Each directory represents a "package" that contains configuration files. When stowed, the contents are symlinked to your home directory, preserving the directory structure.

```
dotfiles/
├── bash/          # Bash configuration
├── git/           # Git configuration
├── tmux/          # Tmux configuration
├── dircolors/     # Directory colors
├── config/        # ~/.config directory contents
└── local/         # ~/.local directory contents
```

## Prerequisites

Install GNU Stow:

```bash
# Fedora/RHEL/CentOS
sudo dnf install stow

# Debian/Ubuntu
sudo apt install stow

# macOS
brew install stow
```

## Installation

1. Clone this repository:
   ```bash
   git clone <repository-url> ~/github/dotfiles
   cd ~/github/dotfiles
   ```

2. Stow the packages you want:
   ```bash
   # Install individual packages
   stow bash
   stow git
   stow tmux
   stow dircolors
   stow config
   stow local
   
   # Or install everything at once
   stow */
   ```

3. Stow creates symlinks in your home directory pointing to files in this repo. If you have existing files, you may need to remove or backup them first.

## Usage

### Adding new configurations

1. Create a package directory if it doesn't exist
2. Mirror the home directory structure within the package
3. Add your config files
4. Stow the package

Example - adding a new vim config:
```bash
mkdir -p vim
cp ~/.vimrc vim/.vimrc
stow vim
```

### Removing configurations

To unlink a package:
```bash
stow -D bash  # Removes bash symlinks
```

### Updating configurations

Simply edit the files in this repo - since they're symlinked, changes take effect immediately!

### Restowing

If you add new files to an already-stowed package:
```bash
stow -R bash  # Restow to pick up new files
```

## Security Notes

- **Never commit sensitive data** like SSH keys, GPG keys, or authentication tokens
- Review `.gitignore` to ensure sensitive patterns are excluded
- Check git and onedrive configs before committing to ensure no tokens are present
- Use `git diff --cached` before committing to review what will be added

## Deployment on New Systems

```bash
# 1. Clone the repo
git clone <repository-url> ~/github/dotfiles

# 2. Install stow
sudo dnf install stow  # or appropriate package manager

# 3. Backup existing configs (optional)
mkdir ~/dotfiles-backup
cp ~/.bashrc ~/.gitconfig ~/dotfiles-backup/

# 4. Deploy configurations
cd ~/github/dotfiles
stow bash git tmux dircolors config local

# 5. Reload shell
exec bash
```

## Troubleshooting

### Conflicts with existing files

If stow reports conflicts:
```bash
# Option 1: Backup and remove existing files
mv ~/.bashrc ~/.bashrc.backup
stow bash

# Option 2: Use --adopt to take over existing files
stow --adopt bash
# This moves existing files into the repo - review with git diff!
```

### Verifying symlinks

```bash
ls -la ~ | grep "\->"  # Show symlinks in home directory
```

## License

Personal dotfiles - use at your own risk!
