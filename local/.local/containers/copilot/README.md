# GitHub Copilot CLI Sandbox Container

This container provides a sandboxed environment for running GitHub Copilot CLI with restricted access to your host system.

## Features

- **Sandboxed execution** - Runs in isolated container environment
- **Session persistence** - Resume copilot sessions across container instances
- **Token-based auth** - Simple GitHub authentication via token
- **Auto-build** - Container image builds automatically on first use

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

# Resume your most recent session
ghcp --continue

# Pick from previous sessions
ghcp --resume
```

## Session Persistence

**By default, `ghcp` persists copilot sessions** by mounting your `~/.copilot` directory into the container. This enables:

- **Session resumption** - Use `--continue` to resume your most recent conversation
- **Session history** - Use `--resume` to pick from any previous session
- **Shared config** - Model preferences and settings work across container and host
- **Command history** - Your copilot command history is preserved

### How It Works

Rootless podman maps the container's root user (UID 0) to your host user (UID 1000), ensuring:
- Files created in the container are owned by your host user
- Permissions are preserved correctly
- Both container and host copilot can access sessions

### Ephemeral Mode

If you prefer isolated sessions that don't persist:

```bash
ghcp --ghcp-no-sessions [command...]
```

This runs copilot without mounting the `.copilot` directory, creating a fresh ephemeral session each time.

The `ghcp` command:
- Auto-builds the container image on first use
- Mounts your current directory to `/workspace` in the container
- Passes your GitHub authentication via `GH_TOKEN` environment variable
- Forwards all arguments to the copilot command

**Built-in Commands:**
- `ghcp --ghcp-rebuild` - Rebuild container to update Copilot CLI to latest version
- `ghcp --ghcp-help` - Show ghcp help (for copilot help, use `ghcp --help`)

All flags not starting with `--ghcp-` are passed through to copilot.

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

## Updating Copilot CLI

### Recommended: Use Built-in Rebuild Command
```bash
ghcp --ghcp-rebuild
```

This removes the old container image and rebuilds it with the latest Copilot CLI from npm.

### Alternative: Manual Rebuild
```bash
# Remove old image
podman rmi copilot-sandbox

# Next ghcp command will auto-rebuild
ghcp --version
```

## Troubleshooting

### SELinux Relabeling Errors
If you encounter "SELinux relabeling not allowed" errors, run from a subdirectory rather than from `/tmp` or your home directory root.

### GitHub Authentication
The container uses your host's GitHub authentication via the `GH_TOKEN` environment variable. Ensure you're authenticated on your host with `gh auth login` before running the container.

### Rebuilding the Container
See "Updating Copilot CLI" section above for instructions on updating to the latest version.
