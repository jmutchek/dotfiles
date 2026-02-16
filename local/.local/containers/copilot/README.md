# GitHub Copilot CLI Sandbox Container

This container provides a sandboxed environment for running GitHub Copilot CLI with restricted access to your host system.

## Building the Container

```bash
podman build -t copilot-sandbox -f Containerfile .
```

## Running the Container

### Using the Helper Script (Recommended)
The easiest way to run the container with authentication:

```bash
./run.sh /path/to/your/project
```

This automatically:
- Mounts your project directory to `/workspace`
- Passes your GitHub authentication token to the container

### Manual Usage
Mount a folder from your host into the container's `/workspace` directory:

```bash
podman run -it --rm \
  -v /path/to/your/project:/workspace:Z \
  -e GH_TOKEN="$(gh auth token)" \
  copilot-sandbox
```

The `:Z` flag is important for SELinux systems to properly label the volume.

## First-Time Setup

1. Ensure you're authenticated with GitHub CLI on your host:
   ```bash
   gh auth login
   ```
2. Build the container:
   ```bash
   podman build -t copilot-sandbox -f Containerfile .
   ```
3. Run the container using the helper script or manual command above

## Usage Examples

Once inside the container:

```bash
# Ask Copilot a question
gh copilot suggest "how to list files recursively"

# Explain a command
gh copilot explain "tar -xzvf file.tar.gz"

# Get help
gh copilot --help
```

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

### SELinux Issues
If you encounter permission errors on SELinux systems, ensure you use `:Z` or `:z` flags.

### GitHub Authentication
The container uses your host's GitHub authentication via the `GH_TOKEN` environment variable. Ensure you're authenticated on your host with `gh auth login` before running the container.
