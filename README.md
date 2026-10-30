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

### Optional: Starship prompt

The `bash` package expects [Starship](https://starship.rs) for its prompt (config
lives in `config/.config/starship.toml`). The shell init in
`bash/.bashrc.d/90-prompt.sh` no-ops gracefully if Starship isn't installed, so
this step is optional but recommended:

```bash
# Install to ~/.local/bin (already on PATH via bash/.bashrc, no sudo needed)
curl -fsSL https://starship.rs/install.sh | sh -s -- --yes --bin-dir ~/.local/bin
```

The prompt uses Nerd Font glyphs for the git branch and prompt characters. If they
render as boxes, install a [Nerd Font](https://www.nerdfonts.com/) in your terminal.

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/jmutchek/dotfiles.git ~/github/jmutchek/dotfiles/main
   cd ~/github/jmutchek/dotfiles/main
   ```

2. Stow the packages you want, **always passing `--no-folding -t ~` explicitly**:
   ```bash
   # Install individual packages
   stow --no-folding -t ~ bash
   stow --no-folding -t ~ git
   stow --no-folding -t ~ tmux
   stow --no-folding -t ~ dircolors
   stow --no-folding -t ~ config
   stow --no-folding -t ~ local

   # Or install everything at once
   stow --no-folding -t ~ */
   ```

   `--no-folding` creates real directories in your home directory and symlinks
   individual files rather than whole directories. For example,
   `~/.config/herdr/config.toml` links into this repo, while Herdr's logs,
   sockets, and session state stay in the local `~/.config/herdr/` directory.
   Without this option, a whole-directory symlink can send those generated
   files into the repo. Git ignore rules do not change Stow's behavior.

   > **Important:** stow's default target is the *parent* of the current
   > directory, not `$HOME`. Since this repo lives at
   > `~/github/jmutchek/dotfiles/main`, running plain `stow <package>` from
   > inside `main/` silently symlinks into `~/github/jmutchek/dotfiles/`
   > instead of your actual home directory — it looks like it worked, but
   > nothing lands in `$HOME`. Always use `-t ~` (or `-t $HOME`) to avoid
   > this trap.

3. Stow creates symlinks in your home directory pointing to files in this repo. If you have existing files, you may need to remove or back them up first — or use `stow --no-folding -t ~ --adopt <package>` to pull the existing file into the repo and replace it with a symlink (review the resulting `git diff` before committing, since `--adopt` overwrites the repo copy with whatever's on disk).

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
stow --no-folding -t ~ vim
```

### Removing configurations

To unlink a package:
```bash
stow --no-folding -t ~ -D bash  # Removes bash symlinks
```

### Updating configurations

Simply edit the files in this repo - since they're symlinked, changes take effect immediately!

### Restowing

If you add new files to an already-stowed package:
```bash
stow --no-folding -t ~ -R config  # Restow to pick up new files
```

Keep `--no-folding` when restowing so new directories are not replaced with
whole-directory symlinks. To convert existing Stow-managed directory symlinks
into real directories with individual file links, use `-R` with `--no-folding`:

```bash
stow --no-folding -t ~ -R config local
```

Move any generated runtime files out of the repo before restowing; Stow would
otherwise link those files too, even if Git ignores them.

## Security Notes

- **Never commit sensitive data** like SSH keys, GPG keys, or authentication tokens
- Review `.gitignore` to ensure sensitive patterns are excluded
- Check git and onedrive configs before committing to ensure no tokens are present
- Use `git diff --cached` before committing to review what will be added

## Deployment on New Systems

```bash
# 1. Clone the repo
git clone <repository-url> ~/github/jmutchek/dotfiles

# 2. Install stow
sudo dnf install stow  # or appropriate package manager

# 3. Backup existing configs (optional)
mkdir ~/dotfiles-backup
cp ~/.bashrc ~/.gitconfig ~/dotfiles-backup/

# 4. Deploy configurations
cd ~/github/jmutchek/dotfiles
stow --no-folding -t ~ bash git tmux dircolors config local

# 5. Reload shell
exec bash
```

## Troubleshooting

### Conflicts with existing files

If stow reports conflicts:
```bash
# Option 1: Backup and remove existing files
mv ~/.bashrc ~/.bashrc.backup
stow --no-folding -t ~ bash

# Option 2: Use --adopt to take over existing files
stow --no-folding -t ~ --adopt bash
# This moves existing files into the repo - review with git diff!
```

### Verifying symlinks

```bash
ls -la ~ | grep "\->"  # Show symlinks in home directory
```

## License

Personal dotfiles - use at your own risk!
