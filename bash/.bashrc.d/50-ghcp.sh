# GitHub Copilot in Container (ghcp)
# Runs copilot CLI in a sandboxed podman container

ghcp() {
    local container_name="copilot-sandbox"
    local container_dir="$HOME/.local/containers/copilot"
    local persist_sessions=true
    local args=()
    
    # Parse arguments for ghcp-specific flags
    for arg in "$@"; do
        case "$arg" in
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
  ghcp --ghcp-no-sessions   Disable session persistence (ephemeral mode)
  ghcp --ghcp-help          Show this help message

Examples:
  ghcp                      Interactive copilot (with session persistence)
  ghcp --version            Check copilot version
  ghcp --continue           Resume most recent session
  ghcp --resume             Pick a previous session to resume
  ghcp suggest "..."        Ask copilot a question
  ghcp explain "..."        Explain a command
  ghcp --ghcp-rebuild       Update to latest Copilot CLI
  ghcp --ghcp-no-sessions   Run without mounting .copilot directory

Session Persistence:
  By default, ghcp mounts ~/.copilot to persist sessions across container runs.
  This allows you to use --continue and --resume to restore previous sessions.
  Use --ghcp-no-sessions to run in ephemeral mode (no session persistence).

All flags not starting with --ghcp- are passed through to the copilot command.
The container auto-builds on first use and mounts your current directory.
EOF
                return 0
                ;;
            --ghcp-no-sessions)
                persist_sessions=false
                ;;
            *)
                args+=("$arg")
                ;;
        esac
    done
    
    # Check if image exists, build if not
    if ! podman image exists "$container_name" 2>/dev/null; then
        echo "Building $container_name image..." >&2
        podman build -t "$container_name" -f "$container_dir/Containerfile" "$container_dir" || return 1
    fi
    
    # Build mount arguments
    local mount_args="-v $PWD:/workspace:Z"
    if [[ "$persist_sessions" == "true" ]]; then
        mount_args="$mount_args -v $HOME/.copilot:/root/.copilot:z"
    fi
    
    # Run container with current directory mounted
    podman run -it --rm \
        $mount_args \
        -e GH_TOKEN="$(gh auth token 2>/dev/null)" \
        "$container_name" \
        "${args[@]}"
}
