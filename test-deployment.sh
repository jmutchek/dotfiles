#!/bin/bash
# Deployment test script for dotfiles
# This script will help you test stow deployment

set -e

DOTFILES_DIR="$HOME/github/dotfiles"

echo "=== Dotfiles Deployment Test ==="
echo ""

# Check if stow is installed
if ! command -v stow &> /dev/null; then
    echo "ERROR: GNU Stow is not installed"
    echo "Install with: sudo dnf install -y stow"
    exit 1
fi

echo "✓ GNU Stow is installed"
echo ""

# Check if we're in the right directory
if [ ! -d "$DOTFILES_DIR" ]; then
    echo "ERROR: Dotfiles directory not found at $DOTFILES_DIR"
    exit 1
fi

echo "✓ Dotfiles directory found"
echo ""

# Show current symlinks
echo "Current symlinks in home directory:"
ls -la ~ | grep "\->" || echo "  (no symlinks yet)"
echo ""

# Dry run test
echo "=== Running dry-run test ==="
echo "This will show what stow WOULD do without actually doing it"
echo ""

cd "$DOTFILES_DIR"

for package in bash git tmux dircolors config local; do
    echo "Testing package: $package"
    if stow -n -v "$package" 2>&1 | grep -i "conflict\|error"; then
        echo "  ⚠️  Conflicts detected for $package"
    else
        echo "  ✓ No conflicts for $package"
    fi
    echo ""
done

echo "=== Dry-run complete ==="
echo ""
echo "Next steps:"
echo "1. Review any conflicts above"
echo "2. Backup or remove conflicting files"
echo "3. Run actual deployment with: cd $DOTFILES_DIR && stow bash git tmux dircolors config local"
echo ""
