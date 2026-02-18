# GitHub Copilot in Container (ghcp)
# Runs copilot CLI in a sandboxed podman container with network isolation

ghcp() {
    local container_name="copilot-sandbox"
    local container_dir="$HOME/.local/containers/copilot"
    local hooks_dir="$HOME/.config/containers/hooks.d"
    local persist_sessions=true
    local firewall_enabled=true
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
  ghcp [arguments...]        Run copilot with arguments
  ghcp --ghcp-rebuild        Rebuild container image (updates Copilot CLI)
  ghcp --ghcp-update         Same as --ghcp-rebuild
  ghcp --ghcp-no-sessions    Disable session persistence (ephemeral mode)
  ghcp --ghcp-no-firewall    Disable network isolation (allow local network access)
  ghcp --ghcp-help           Show this help message

Examples:
  ghcp                       Interactive copilot (isolated, with sessions)
  ghcp --version             Check copilot version
  ghcp --continue            Resume most recent session
  ghcp --resume              Pick a previous session to resume
  ghcp suggest "..."         Ask copilot a question
  ghcp explain "..."         Explain a command
  ghcp --ghcp-rebuild        Update to latest Copilot CLI
  ghcp --ghcp-no-sessions    Run without mounting .copilot directory
  ghcp --ghcp-no-firewall    Run with local network access enabled

Session Persistence:
  By default, ghcp mounts ~/.copilot to persist sessions across container runs.
  This allows you to use --continue and --resume to restore previous sessions.
  Use --ghcp-no-sessions to run in ephemeral mode (no session persistence).

Network Isolation:
  By default, ghcp isolates the container from your local network using an
  OCI hook that configures a firewall in the container's network namespace.
  
  What's blocked:
    • Local network access (192.168.x.x, 10.x.x.x, etc.)
    • Local DNS servers (uses public DNS: Google, Cloudflare, Quad9)
  
  What's allowed:
    • Public internet (GitHub Copilot API, npm, git, etc.)
    • Container-internal services (localhost inside container)
    • Public DNS servers only
  
  Use --ghcp-no-firewall to disable network isolation.
  
  Setup: The firewall hook is configured automatically on first use.
  For details, see: ~/.local/containers/copilot/scripts/configure-firewall.sh

All flags not starting with --ghcp- are passed through to the copilot command.
The container auto-builds on first use and mounts your current directory.
EOF
                return 0
                ;;
            --ghcp-no-sessions)
                persist_sessions=false
                ;;
            --ghcp-no-firewall)
                firewall_enabled=false
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
    
    # Ensure hooks directory and policy exist
    if [[ "$firewall_enabled" == "true" ]]; then
        if [[ ! -d "$hooks_dir" ]]; then
            mkdir -p "$hooks_dir"
        fi
        
        # Create hook policy if it doesn't exist
        local hook_policy="$hooks_dir/ghcp-firewall.json"
        if [[ ! -f "$hook_policy" ]]; then
            cat > "$hook_policy" <<'HOOKEOF'
{
  "version": "1.0.0",
  "hook": {
    "path": "/home/jmutchek/.local/containers/copilot/scripts/configure-firewall.sh"
  },
  "when": {
    "annotations": {
      "^ghcp-firewall$": "enabled"
    }
  },
  "stages": ["createContainer"]
}
HOOKEOF
            # Replace hardcoded path with actual home directory
            sed -i "s|/home/jmutchek|$HOME|g" "$hook_policy"
        fi
    fi
    
    # Build denied tools arguments from config file
    local denied_tools_args=()
    local denied_tools_config="$container_dir/denied-tools.conf"
    if [[ -f "$denied_tools_config" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Skip empty lines and comments
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
            # Add --deny-tool flag for each tool pattern
            denied_tools_args+=(--deny-tool "$line")
        done < "$denied_tools_config"
    fi
    
    # Build podman command arguments as array
    local podman_args=(run -it --rm)
    
    # Add firewall arguments
    if [[ "$firewall_enabled" == "true" ]]; then
        podman_args+=(--hooks-dir "$hooks_dir" --annotation ghcp-firewall=enabled)
        podman_args+=(--dns=8.8.8.8 --dns=1.1.1.1)
    fi
    
    # Add mount arguments
    podman_args+=(-v "$PWD:/workspace:Z")
    if [[ "$persist_sessions" == "true" ]]; then
        podman_args+=(-v "$HOME/.copilot:/root/.copilot:z")
    fi
    
    # Add environment and container name
    podman_args+=(-e "GH_TOKEN=$(gh auth token 2>/dev/null)")
    podman_args+=("$container_name")
    
    # Run container with all arguments
    podman "${podman_args[@]}" "${denied_tools_args[@]}" "${args[@]}"
}
