# GitHub Copilot in Container (ghcp)
# Runs copilot CLI in a sandboxed podman container

ghcp() {
    local container_name="copilot-sandbox"
    local container_dir="$HOME/.local/containers/copilot"
    
    # Handle ghcp-specific flags (namespaced with --ghcp-)
    case "${1:-}" in
        --ghcp-rebuild|--ghcp-update)
            echo "Rebuilding $container_name image..." >&2
            podman rmi "$container_name" 2>/dev/null || true
            podman build -t "$container_name" -f "$container_dir/Containerfile" "$container_dir"
            return $?
            ;;
        --ghcp-help)
            cat <<'EOF'
ghcp - GitHub Copilot in Container

Usage:
  ghcp [arguments...]       Run copilot with arguments
  ghcp --ghcp-rebuild       Rebuild container image (updates Copilot CLI)
  ghcp --ghcp-update        Same as --ghcp-rebuild
  ghcp --ghcp-help          Show this help message

Examples:
  ghcp                      Interactive copilot
  ghcp --version            Check copilot version (passed to copilot)
  ghcp suggest "..."        Ask copilot a question
  ghcp explain "..."        Explain a command
  ghcp --ghcp-rebuild       Update to latest Copilot CLI

All flags not starting with --ghcp- are passed through to the copilot command.
The container auto-builds on first use and mounts your current directory.
EOF
            return 0
            ;;
    esac
    
    # Check if image exists, build if not
    if ! podman image exists "$container_name" 2>/dev/null; then
        echo "Building $container_name image..." >&2
        podman build -t "$container_name" -f "$container_dir/Containerfile" "$container_dir" || return 1
    fi
    
    # Run container with current directory mounted
    podman run -it --rm \
        -v "$PWD:/workspace:Z" \
        -e GH_TOKEN="$(gh auth token 2>/dev/null)" \
        "$container_name" \
        "$@"
}
