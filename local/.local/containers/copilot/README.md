# GitHub Copilot CLI Sandbox Container

This container provides a sandboxed environment for running GitHub Copilot CLI with restricted access to your host system.

## Quick Start

The easiest way to use this container is via the `ghcp` shell function (installed via dotfiles):

```bash
# From any directory - automatically mounts current directory
ghcp

# Check version
ghcp --version

# Ask Copilot a question
ghcp suggest "how to list files recursively"

# Explain a command
ghcp explain "tar -xzvf file.tar.gz"
```

The `ghcp` command:
- Auto-builds the container image on first use
- Mounts your current directory to `/workspace` in the container
- Passes your GitHub authentication via `GH_TOKEN` environment variable
- Forwards all arguments to the copilot command

## Installation

1. Ensure you're authenticated with GitHub CLI on your host:
   ```bash
   gh auth login
   ```

2. Deploy dotfiles with GNU Stow:
   ```bash
   cd ~/github/dotfiles
   stow -t ~ local bash
   ```

3. Reload your shell:
   ```bash
   exec bash
   ```

## Manual Container Usage

If you want to build and run the container manually:

```bash
# Build the image
podman build -t copilot-sandbox -f Containerfile .

# Run with current directory mounted
podman run -it --rm \
  -v "$PWD:/workspace:Z" \
  -e GH_TOKEN="$(gh auth token)" \
  copilot-sandbox
```

The `:Z` flag is important for SELinux systems to properly label the volume.

## Container Details

**Base Image:** node:20-bookworm-slim  
**Installed:** git, @github/copilot CLI  
**Default Working Directory:** `/workspace`



## Security Features

- Rootless Podman maps container root to your unprivileged host user
- Isolated from host system (except mounted volumes)
- GitHub token passed as environment variable (no credential files in container)

## Volume Mount Options

- `:z` - For SELinux, allows multiple containers to share the volume
- `:Z` - For SELinux, private unshared volume (recommended)
- `:ro` - Read-only mount
- `:rw` - Read-write mount (default)

## Troubleshooting

### SELinux Relabeling Errors
If you encounter "SELinux relabeling not allowed" errors, run from a subdirectory rather than from `/tmp` or your home directory root.

### GitHub Authentication
The container uses your host's GitHub authentication via the `GH_TOKEN` environment variable. Ensure you're authenticated on your host with `gh auth login` before running the container.

### Rebuilding the Container
To rebuild the container image (e.g., to update Copilot CLI):
```bash
podman rmi copilot-sandbox
ghcp copilot  # Will auto-rebuild on next run
```
