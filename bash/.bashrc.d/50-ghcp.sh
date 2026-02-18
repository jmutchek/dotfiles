# GitHub Copilot in Container (ghcp)
# Runs copilot CLI in a sandboxed podman container with network isolation

# ---------------------------------------------------------------------------
# Private helpers (_ghcp_ prefix)
# ---------------------------------------------------------------------------

_ghcp_help() {
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

AGENTS.md:
  If an AGENTS.md with YAML front-matter is found in the current directory or a parent
  (up to the git repo root), ghcp may set defaults like --model (user --model wins).

The container auto-builds on first use and mounts your current directory.
EOF
}

# Remove the existing image and rebuild it from the Containerfile.
_ghcp_rebuild() {
    local container_name="$1" container_dir="$2"
    echo "Rebuilding $container_name image..." >&2
    podman rmi "$container_name" 2>/dev/null || true
    podman build -t "$container_name" -f "$container_dir/Containerfile" "$container_dir"
}

# Build the container image if it doesn't already exist.
_ghcp_build_image() {
    local container_name="$1" container_dir="$2"
    if ! podman image exists "$container_name" 2>/dev/null; then
        echo "Building $container_name image..." >&2
        podman build -t "$container_name" -f "$container_dir/Containerfile" "$container_dir" || return 1
    fi
}

# Ensure the OCI hooks directory and firewall hook policy file exist.
_ghcp_setup_firewall_hook() {
    local hooks_dir="$1"
    local hook_policy="$hooks_dir/ghcp-firewall.json"

    [[ -d "$hooks_dir" ]] || mkdir -p "$hooks_dir"

    if [[ ! -f "$hook_policy" ]]; then
        printf '{
  "version": "1.0.0",
  "hook": {
    "path": "%s/.local/containers/copilot/scripts/configure-firewall.sh"
  },
  "when": {
    "annotations": {
      "^ghcp-firewall$": "enabled"
    }
  },
  "stages": ["createContainer"]
}\n' "$HOME" > "$hook_policy"
    fi
}

# Read denied-tools.conf and populate the caller's array (via nameref) with
# the corresponding --deny-tool flag pairs.
_ghcp_load_denied_tools() {
    local config_file="$1"
    local -n _denied_tools_result="$2"
    _denied_tools_result=()
    [[ -f "$config_file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        _denied_tools_result+=(--deny-tool "$line")
    done < "$config_file"
}

# Walk from search_dir up to repo_root (or /) looking for AGENTS.md with a
# model: field in its YAML front-matter. Prints the model name to stdout, or
# nothing if none is found.
_ghcp_detect_model() {
    local search_dir="$1" repo_root="$2"
    local agents_file=""

    while :; do
        if [[ -f "$search_dir/AGENTS.md" ]]; then
            agents_file="$search_dir/AGENTS.md"
            break
        fi
        [[ "$search_dir" == "/" ]] && break
        [[ -n "$repo_root" && "$search_dir" == "$repo_root" ]] && break
        search_dir="$(dirname "$search_dir")"
    done

    [[ -z "$agents_file" ]] && return 0

    local model
    model="$(awk '
        NR==1 && $0!="---" { exit }
        NR==1 { in_frontmatter=1; next }
        in_frontmatter && $0=="---" { exit }
        in_frontmatter && $0 ~ /^[[:space:]]*model[[:space:]]*:/ {
            sub(/^[[:space:]]*model[[:space:]]*:[[:space:]]*/, "", $0)
            gsub(/[[:space:]]+$/, "", $0)
            print $0
            exit
        }' "$agents_file" 2>/dev/null)"

    [[ -n "$model" ]] && printf '%s' "$model"
}

# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

ghcp() {
    local container_name="copilot-sandbox"
    local container_dir="$HOME/.local/containers/copilot"
    local hooks_dir="$HOME/.config/containers/hooks.d"
    local persist_sessions=true
    local firewall_enabled=true
    local user_model_specified=false
    local args=()

    # --- Argument parsing ---------------------------------------------------
    for arg in "$@"; do
        case "$arg" in
            --ghcp-rebuild|--ghcp-update)
                _ghcp_rebuild "$container_name" "$container_dir"
                return $?
                ;;
            --ghcp-help)
                _ghcp_help
                return 0
                ;;
            --ghcp-no-sessions)
                persist_sessions=false
                ;;
            --ghcp-no-firewall)
                firewall_enabled=false
                ;;
            *)
                [[ "$arg" == "--model" || "$arg" == --model=* ]] && user_model_specified=true
                args+=("$arg")
                ;;
        esac
    done

    # --- Setup --------------------------------------------------------------
    _ghcp_build_image "$container_name" "$container_dir" || return 1

    [[ "$firewall_enabled" == "true" ]] && _ghcp_setup_firewall_hook "$hooks_dir"

    local denied_tools_args=()
    _ghcp_load_denied_tools "$container_dir/denied-tools.conf" denied_tools_args

    if [[ "$user_model_specified" == "false" ]]; then
        local repo_root=""
        repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || true
        local agents_model=""
        agents_model="$(_ghcp_detect_model "$PWD" "$repo_root")"
        [[ -n "$agents_model" ]] && args=(--model "$agents_model" "${args[@]}")
    fi

    # --- Assemble and run podman command ------------------------------------
    local podman_args=(run -it --rm)

    if [[ "$firewall_enabled" == "true" ]]; then
        podman_args+=(--hooks-dir "$hooks_dir" --annotation ghcp-firewall=enabled)
        podman_args+=(--dns=8.8.8.8 --dns=1.1.1.1)
    fi

    podman_args+=(-v "$PWD:/workspace:Z")
    [[ "$persist_sessions" == "true" ]] && podman_args+=(-v "$HOME/.copilot:/root/.copilot:z")

    podman_args+=(-e "GH_TOKEN=$(gh auth token 2>/dev/null)")
    podman_args+=("$container_name")

    podman "${podman_args[@]}" "${denied_tools_args[@]}" "${args[@]}"
}
