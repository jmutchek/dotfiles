# Claude Code Sandbox Container

This container provides a sandboxed environment for running Claude Code CLI with restricted access to your host system.

## Features

- **Sandboxed execution** - Runs in isolated container environment
- **Network isolation** - Blocks local network access, allows public internet only
- **Session persistence** - Resume Claude Code sessions across container instances
- **Credential mount** - Authentication via mounted `~/.claude` credential files
- **Auto-build** - Container image builds automatically on first use

## Quick Start

The easiest way to use this container is via the `cld` shell function (installed via dotfiles):

```bash
# From any directory - automatically mounts current directory
cld

# Check version
cld --version

# Run Claude Code with a prompt
cld "fix the failing tests"

# Resume your most recent session
cld --continue

# Use a specific model
cld --model claude-opus-4-5 "refactor this module"
```

## Authentication

Run `claude auth login` on the host before using `cld`. The credential files
(`~/.claude/.credentials.json` and `~/.claude.json`) are mounted into the container
automatically:

```bash
# Log in on the host first
claude auth login

# Then use cld — credentials are mounted automatically
cld
```

In `--cld-no-sessions` mode, the credential files are mounted read-only so
authentication works but sessions are not persisted.

## Session Persistence

**By default, `cld` persists Claude Code sessions** by mounting your `~/.claude` directory into the container. This enables:

- **Session resumption** - Use `cld --continue` to resume your most recent conversation
- **Shared config** - Model preferences and settings (`~/.claude/`) work across container and host

### How It Works

Rootless podman maps the container's root user (UID 0) to your host user (UID 1000), ensuring:
- Files created in the container are owned by your host user
- Permissions are preserved correctly
- Both container and host Claude Code can access sessions

### Ephemeral Mode

If you prefer isolated sessions that don't persist:

```bash
cld --cld-no-sessions [command...]
```

This runs Claude Code without mounting the `.claude` directory, creating a fresh ephemeral session each time.

## Network Isolation

**By default, `cld` isolates the container from your local network** using an OCI hook that configures a firewall in the container's network namespace.

### What's Blocked

- ❌ Local network access (192.168.x.x, 10.x.x.x, 172.16.x.x, etc.)
- ❌ Local DNS servers
- ❌ Link-local addresses (169.254.x.x)
- ❌ Multicast and reserved ranges

### What's Allowed

- ✅ Public internet (Anthropic API, npm, git, HTTPS, etc.)
- ✅ Container-internal services (127.0.0.1 inside container)
- ✅ Public DNS servers only (Google: 8.8.8.8, Cloudflare: 1.1.1.1, Quad9: 9.9.9.9)

### How It Works

The network isolation uses an **OCI createContainer hook** that:
1. Runs before the container starts
2. Configures nftables firewall in the container's network namespace
3. Enforces rules that the container cannot modify (no NET_ADMIN capability)

The firewall script is located at: `~/.local/containers/claude/scripts/configure-firewall.sh`

### Disable Network Isolation

If you need to access local network resources:

```bash
cld --cld-no-firewall [command...]
```

This disables the firewall and allows full network access including local networks.

### Technical Details

The firewall uses nftables with these rules:
- Allow established/related connections
- Allow loopback (127.0.0.1)
- Allow DNS to public servers: 8.8.8.8, 8.8.4.4, 1.1.1.1, 1.0.0.1, 9.9.9.9, 149.112.112.112
- Block all private IP ranges
- Allow all other traffic (public internet)

## Using cld

The `cld` command:
- Auto-builds the container image on first use
- Mounts your current directory to `/workspace` in the container
- Mounts `~/.claude` and `~/.claude.json` for authentication
- Configures network isolation by default (blocks local network access)
- Uses public DNS servers (8.8.8.8, 1.1.1.1)
- Forwards all arguments to the `claude` command

**Built-in Commands:**
- `cld --cld-rebuild` - Rebuild container to update Claude Code CLI to latest version
- `cld --cld-no-sessions` - Run in ephemeral mode (no session persistence)
- `cld --cld-no-firewall` - Disable network isolation for this session
- `cld --cld-help` - Show cld help (for claude help, use `cld --help`)

All flags not starting with `--cld-` are passed through to `claude`.

### AGENTS.md defaults

If an `AGENTS.md` file with YAML front-matter is found in the current directory or a parent
directory (walking upward until the git repo root or `/`), `cld` may apply defaults to the
Claude Code CLI invocation.

- Currently supported: `model: claude-opus-4-5` → adds `--model claude-opus-4-5`
- Precedence: if you pass `--model ...` or `-m ...` yourself, `cld` will not override it.

Note: Claude Code also reads `AGENTS.md` natively for agent instructions. The front-matter `model:`
field is only used by the `cld` wrapper for model selection.

## Installation

1. Log in to Claude on the host:
   ```bash
   claude auth login
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
podman build -t claude-sandbox -f Containerfile .

# Run with current directory and credentials mounted
podman run -it --rm \
  -v "$PWD:/workspace:Z" \
  -v "$HOME/.claude:/root/.claude:z" \
  -v "$HOME/.claude.json:/root/.claude.json:z" \
  claude-sandbox
```

The `:Z` flag is important for SELinux systems to properly label the volume.

## Container Details

**Base Image:** node:20-bookworm-slim  
**Installed:** git, @anthropic-ai/claude-code CLI  
**Default Working Directory:** `/workspace`

## Security Features

- **Rootless Podman** - Container root maps to your unprivileged host user
- **Network Isolation** - OCI hook-based firewall blocks local network access
  - Blocks: 192.168.x.x, 10.x.x.x, 172.16.x.x, 169.254.x.x, multicast, reserved
  - Allows: Public internet only, container-internal localhost
  - DNS: Public servers only (Google, Cloudflare, Quad9)
  - Container cannot bypass (no NET_ADMIN capability)
- **Isolated Container** - Separated from host system (except mounted volumes)
- **Credential mount** - Auth files mounted from host (read-only in ephemeral mode)
- **SELinux Support** - Proper volume labeling for additional confinement

## Volume Mount Options

- `:z` - For SELinux, allows multiple containers to share the volume
- `:Z` - For SELinux, private unshared volume (recommended for workspace)
- `:ro` - Read-only mount
- `:rw` - Read-write mount (default)

Note: `~/.claude` uses `:z` (shared) since both the container and host may access it.
The workspace uses `:Z` (private) for stronger isolation.

## Updating Claude Code CLI

### Recommended: Use Built-in Rebuild Command
```bash
cld --cld-rebuild
```

This removes the old container image and rebuilds it with the latest Claude Code CLI from npm.

### Alternative: Manual Rebuild
```bash
# Remove old image
podman rmi claude-sandbox

# Next cld command will auto-rebuild
cld --version
```

## Troubleshooting

### SELinux Relabeling Errors
If you encounter "SELinux relabeling not allowed" errors, run from a subdirectory rather than from `/tmp` or your home directory root.

### Authentication Errors
Ensure you have logged in on the host with `claude auth login` before running `cld`.
Verify the credential files exist: `ls ~/.claude/.credentials.json ~/.claude.json`

### Rebuilding the Container
See "Updating Claude Code CLI" section above for instructions on updating to the latest version.
