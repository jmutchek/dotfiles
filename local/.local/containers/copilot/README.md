# GitHub Copilot CLI Sandbox Container

This container provides a sandboxed environment for running GitHub Copilot CLI with restricted access to your host system.

## Features

- **Sandboxed execution** - Runs in isolated container environment
- **Network isolation** - Blocks local network access, allows public internet only
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

## Network Isolation

**By default, `ghcp` isolates the container from your local network** using an OCI hook that configures a firewall in the container's network namespace.

### What's Blocked

- ❌ Local network access (192.168.x.x, 10.x.x.x, 172.16.x.x, etc.)
- ❌ Local DNS servers
- ❌ Link-local addresses (169.254.x.x)
- ❌ Multicast and reserved ranges

### What's Allowed

- ✅ Public internet (GitHub Copilot API, npm, git, HTTPS, etc.)
- ✅ Container-internal services (127.0.0.1 inside container)
- ✅ Public DNS servers only (Google: 8.8.8.8, Cloudflare: 1.1.1.1, Quad9: 9.9.9.9)

### How It Works

The network isolation uses an **OCI createContainer hook** that:
1. Runs before the container starts
2. Configures nftables firewall in the container's network namespace
3. Enforces rules that the container cannot modify (no NET_ADMIN capability)

The firewall script is located at: `~/.local/containers/copilot/scripts/configure-firewall.sh`

### Disable Network Isolation

If you need to access local network resources:

```bash
ghcp --ghcp-no-firewall [command...]
```

This disables the firewall and allows full network access including local networks.

### Technical Details

The firewall uses nftables with these rules:
- Allow established/related connections
- Allow loopback (127.0.0.1)
- Allow DNS to public servers: 8.8.8.8, 8.8.4.4, 1.1.1.1, 1.0.0.1, 9.9.9.9, 149.112.112.112
- Block all private IP ranges
- Allow all other traffic (public internet)

For implementation details, see the firewall script or refer to the [podman networking docs](https://github.com/eriksjolund/podman-networking-docs#set-up-container-firewall).

## Using ghcp## Using ghcp

The `ghcp` command:
- Auto-builds the container image on first use
- Mounts your current directory to `/workspace` in the container
- Passes your GitHub authentication via `GH_TOKEN` environment variable
- Configures network isolation by default (blocks local network access)
- Uses public DNS servers (8.8.8.8, 1.1.1.1)
- Forwards all arguments to the copilot command

**Built-in Commands:**
- `ghcp --ghcp-rebuild` - Rebuild container to update Copilot CLI to latest version
- `ghcp --ghcp-no-sessions` - Run in ephemeral mode (no session persistence)
- `ghcp --ghcp-no-firewall` - Disable network isolation for this session
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

- **Rootless Podman** - Container root maps to your unprivileged host user
- **Network Isolation** - OCI hook-based firewall blocks local network access
  - Blocks: 192.168.x.x, 10.x.x.x, 172.16.x.x, 169.254.x.x, multicast, reserved
  - Allows: Public internet only, container-internal localhost
  - DNS: Public servers only (Google, Cloudflare, Quad9)
  - Container cannot bypass (no NET_ADMIN capability)
- **Tool Restrictions** - Configure which tools Copilot can use (see Denied Tools section)
- **Isolated Container** - Separated from host system (except mounted volumes)
- **Token-based Auth** - GitHub token passed as environment variable (no credential files)
- **SELinux Support** - Proper volume labeling for additional confinement

## Denied Tools

The sandbox supports restricting which tools GitHub Copilot can use via the `--deny-tool` flag. This helps prevent Copilot from accessing sensitive systems or credentials through shell commands.

### Configuration File

Tool restrictions are configured in: `~/.local/containers/copilot/denied-tools.conf`

**Format:**
- One tool pattern per line
- Lines starting with `#` are comments
- Blank lines are ignored
- Each pattern is passed to: `copilot --deny-tool 'PATTERN'`

**Example configuration:**
```
# Denied Tools Configuration

# 1Password CLI - prevent access to password manager
shell(op)

# Kubernetes CLI - prevent cluster access
shell(kubectl)

# AWS CLI - prevent cloud access
shell(aws)
```

### Tool Pattern Examples

- `shell(op)` - Denies the specific shell command `op` (1Password CLI)
- `shell(kubectl)` - Denies kubectl command
- `shell(aws)` - Denies AWS CLI
- `shell(ssh)` - Denies SSH access
- `bash` - Denies a tool by name

### Default Configuration

By default, the sandbox denies:
- `shell(op)` - 1Password CLI (to protect password manager access)

Additional security-sensitive tools are included as commented examples in the config file.

### Editing the Configuration

1. Edit the config file:
   ```bash
   nano ~/.local/containers/copilot/denied-tools.conf
   ```

2. Add or remove tool patterns as needed

3. Changes take effect on the next `ghcp` invocation (no rebuild needed)

### Disabling Tool Restrictions

To temporarily disable all tool restrictions, you can:
- Comment out all entries in the config file, or
- Rename/remove the config file


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
