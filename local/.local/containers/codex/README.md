# OpenAI Codex CLI Sandbox Container

This container provides a sandboxed environment for running OpenAI Codex CLI with restricted access to your host system.

## Features

- **Sandboxed execution** - Runs in isolated container environment
- **Network isolation** - Blocks local network access, allows public internet only
- **Session persistence** - Resume Codex sessions across container instances
- **API key auth** - Simple authentication via `OPENAI_API_KEY` environment variable
- **Auto-build** - Container image builds automatically on first use

## Quick Start

The easiest way to use this container is via the `agent` command (installed via dotfiles):

```bash
# From any directory - automatically mounts current directory
agent codex

# Check version
agent codex --version

# Run Codex non-interactively
agent codex exec "fix the failing tests"

# Resume your most recent session (interactive)
agent codex resume --last

# Fork most recent session into a new thread
agent codex fork --last
```

## Authentication

Set `OPENAI_API_KEY` in your host environment before running `agent codex`. The key is
passed into the container automatically:

```bash
export OPENAI_API_KEY="sk-..."
agent codex
```

If the variable is unset, `agent codex` will warn and Codex will fail with an auth error.

## Session Persistence

**By default, `agent codex` persists Codex sessions** by mounting your `~/.codex` directory into the container. This enables:

- **Session resumption** - Use `agent codex resume --last` to resume your most recent conversation
- **Session history** - Use `agent codex resume` to pick from any previous session
- **Shared config** - Model preferences and settings (`~/.codex/config.toml`) work across container and host
- **Fork sessions** - Use `agent codex fork --last` to branch a previous conversation

### How It Works

Rootless podman maps the container's root user (UID 0) to your host user (UID 1000), ensuring:
- Files created in the container are owned by your host user
- Permissions are preserved correctly
- Both container and host Codex can access sessions

### Ephemeral Mode

If you prefer isolated sessions that don't persist:

```bash
agent codex --agent-no-sessions [command...]
```

This runs Codex without mounting the `.codex` directory, creating a fresh ephemeral session each time.

## Network Isolation

**By default, `agent codex` isolates the container from your local network** using an OCI hook that configures a firewall in the container's network namespace.

### What's Blocked

- ❌ Local network access (192.168.x.x, 10.x.x.x, 172.16.x.x, etc.)
- ❌ Local DNS servers
- ❌ Link-local addresses (169.254.x.x)
- ❌ Multicast and reserved ranges

### What's Allowed

- ✅ Public internet (OpenAI API, npm, git, HTTPS, etc.)
- ✅ Container-internal services (127.0.0.1 inside container)
- ✅ Public DNS servers only (Google: 8.8.8.8, Cloudflare: 1.1.1.1, Quad9: 9.9.9.9)

### How It Works

The network isolation uses an **OCI createContainer hook** that:
1. Runs before the container starts
2. Configures nftables firewall in the container's network namespace
3. Enforces rules that the container cannot modify (no NET_ADMIN capability)

The firewall script is located at: `~/.local/containers/codex/scripts/configure-firewall.sh`

### Disable Network Isolation

If you need to access local network resources:

```bash
agent codex --agent-no-firewall [command...]
```

This disables the firewall and allows full network access including local networks.

### Technical Details

The firewall uses nftables with these rules:
- Allow established/related connections
- Allow loopback (127.0.0.1)
- Allow DNS to public servers: 8.8.8.8, 8.8.4.4, 1.1.1.1, 1.0.0.1, 9.9.9.9, 149.112.112.112
- Block all private IP ranges
- Allow all other traffic (public internet)

## Using agent codex

The `agent codex` command:
- Auto-builds the container image on first use
- Mounts your current directory to `/workspace` in the container
- Passes your `OPENAI_API_KEY` into the container via environment variable
- Configures network isolation by default (blocks local network access)
- Uses public DNS servers (8.8.8.8, 1.1.1.1, 9.9.9.9)
- Forwards all arguments to the `codex` command

**Built-in Commands:**
- `agent codex --agent-rebuild` - Rebuild container to update Codex CLI to latest version
- `agent codex --agent-no-sessions` - Run in ephemeral mode (no session persistence)
- `agent codex --agent-no-firewall` - Disable network isolation for this session
- `agent codex --agent-help` - Show agent help (for codex help, use `agent codex --help`)

All flags not starting with `--agent-` are passed through to `codex`.

### AGENTS.md defaults

If an `AGENTS.md` file with YAML front-matter is found in the current directory or a parent
directory (walking upward until the git repo root or `/`), `agent codex` may apply defaults to the
Codex CLI invocation.

- Currently supported: `model: gpt-5-codex` → adds `--model gpt-5-codex`
- Precedence: if you pass `--model ...` or `-m ...` yourself, `agent` will not override it.

Note: Codex also reads `AGENTS.md` natively for agent instructions. The front-matter `model:`
field is only used by the `agent` wrapper for model selection.

## Installation

1. Ensure `OPENAI_API_KEY` is set in your host environment:
   ```bash
   export OPENAI_API_KEY="sk-..."
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
podman build -t codex-sandbox -f Containerfile .

# Run with current directory mounted
podman run -it --rm \
  -v "$PWD:/workspace:Z" \
  -e OPENAI_API_KEY="$OPENAI_API_KEY" \
  codex-sandbox
```

The `:Z` flag is important for SELinux systems to properly label the volume.

## Container Details

**Base Image:** node:20-bookworm-slim  
**Installed:** git, @openai/codex CLI  
**Default Working Directory:** `/workspace`

## Security Features

- **Rootless Podman** - Container root maps to your unprivileged host user
- **Network Isolation** - OCI hook-based firewall blocks local network access
  - Blocks: 192.168.x.x, 10.x.x.x, 172.16.x.x, 169.254.x.x, multicast, reserved
  - Allows: Public internet only, container-internal localhost
  - DNS: Public servers only (Google, Cloudflare, Quad9)
  - Container cannot bypass (no NET_ADMIN capability)
- **Isolated Container** - Separated from host system (except mounted volumes)
- **API key auth** - Key passed as environment variable (no credential files mounted)
- **SELinux Support** - Proper volume labeling for additional confinement

## Volume Mount Options

- `:z` - For SELinux, allows multiple containers to share the volume
- `:Z` - For SELinux, private unshared volume (recommended for workspace)
- `:ro` - Read-only mount
- `:rw` - Read-write mount (default)

Note: `~/.codex` uses `:z` (shared) since both the container and host may access it.
The workspace uses `:Z` (private) for stronger isolation.

## Updating Codex CLI

### Recommended: Use Built-in Rebuild Command
```bash
agent codex --agent-rebuild
```

This removes the old container image and rebuilds it with the latest Codex CLI from npm.

### Alternative: Manual Rebuild
```bash
# Remove old image
podman rmi codex-sandbox

# Next agent codex command will auto-rebuild
agent codex --version
```

## Troubleshooting

### SELinux Relabeling Errors
If you encounter "SELinux relabeling not allowed" errors, run from a subdirectory rather than from `/tmp` or your home directory root.

### Authentication Errors
Ensure `OPENAI_API_KEY` is set and valid in your host environment before running `agent codex`.
Check the key is exported: `echo $OPENAI_API_KEY`

### Rebuilding the Container
See "Updating Codex CLI" section above for instructions on updating to the latest version.
