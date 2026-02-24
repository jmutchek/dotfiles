# OpenAI Codex CLI in Container (cx)
# Runs Codex CLI in a sandboxed podman container with network isolation

# ---------------------------------------------------------------------------
# Private helpers (_cx_ prefix)
# ---------------------------------------------------------------------------

_cx_help() {
    cat <<'EOF'
cx - OpenAI Codex CLI in Container

Usage:
  cx [arguments...]         Run Codex with arguments
  cx --cx-rebuild           Rebuild container image (updates Codex CLI)
  cx --cx-update            Same as --cx-rebuild
  cx --cx-no-sessions       Disable session persistence (ephemeral mode)
  cx --cx-no-firewall       Disable network isolation (allow local network access)
  cx --cx-help              Show this help message

Examples:
  cx                        Interactive Codex TUI (isolated, with sessions)
  cx --version              Check Codex version
  cx resume --last          Resume most recent session
  cx exec "fix the bug"     Run Codex non-interactively
  cx -m gpt-5-codex "..."   Use a specific model
  cx --cx-rebuild           Update to latest Codex CLI
  cx --cx-no-sessions       Run without mounting .codex directory
  cx --cx-no-firewall       Run with local network access enabled

Authentication:
  Set OPENAI_API_KEY in your host environment before running.
  The key is passed into the container automatically.

Session Persistence:
  By default, cx mounts ~/.codex to persist sessions across container runs.
  This allows you to use 'cx resume --last' to restore previous sessions.
  Use --cx-no-sessions to run in ephemeral mode (no session persistence).

Network Isolation:
  By default, cx isolates the container from your local network using an
  OCI hook that configures a firewall in the container's network namespace.
  
  What's blocked:
    • Local network access (192.168.x.x, 10.x.x.x, etc.)
    • Local DNS servers (uses public DNS: Google, Cloudflare, Quad9)
  
  What's allowed:
    • Public internet (OpenAI API, npm, git, etc.)
    • Container-internal services (localhost inside container)
    • Public DNS servers only
  
  Use --cx-no-firewall to disable network isolation.
  
  Setup: The firewall hook is configured automatically on first use.
  For details, see: ~/.local/containers/codex/scripts/configure-firewall.sh

All flags not starting with --cx- are passed through to the codex command.

AGENTS.md:
  If an AGENTS.md with YAML front-matter is found in the current directory or a parent
  (up to the git repo root), cx may set defaults like --model (user --model wins).

The container auto-builds on first use and mounts your current directory.
EOF
}

# Remove the existing image and rebuild it from the Containerfile.
_cx_rebuild() {
    local container_name="$1" container_dir="$2"
    echo "Rebuilding $container_name image..." >&2
    podman rmi "$container_name" 2>/dev/null || true
    podman build -t "$container_name" -f "$container_dir/Containerfile" "$container_dir"
}

# Build the container image if it doesn't already exist.
_cx_build_image() {
    local container_name="$1" container_dir="$2"
    if ! podman image exists "$container_name" 2>/dev/null; then
        echo "Building $container_name image..." >&2
        podman build -t "$container_name" -f "$container_dir/Containerfile" "$container_dir" || return 1
    fi
}

# Ensure the OCI hooks directory and firewall hook policy file exist.
_cx_setup_firewall_hook() {
    local hooks_dir="$1"
    local hook_policy="$hooks_dir/cx-firewall.json"

    [[ -d "$hooks_dir" ]] || mkdir -p "$hooks_dir"

    if [[ ! -f "$hook_policy" ]]; then
        printf '{
  "version": "1.0.0",
  "hook": {
    "path": "%s/.local/containers/codex/scripts/configure-firewall.sh"
  },
  "when": {
    "annotations": {
      "^cx-firewall$": "enabled"
    }
  },
  "stages": ["createContainer"]
}\n' "$HOME" > "$hook_policy"
    fi
}

# Walk from search_dir up to repo_root (or /) looking for AGENTS.md with a
# model: field in its YAML front-matter. Prints the model name to stdout, or
# nothing if none is found.
_cx_detect_model() {
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

cx() {
    local container_name="codex-sandbox"
    local container_dir="$HOME/.local/containers/codex"
    local hooks_dir="$HOME/.config/containers/hooks.d"
    local persist_sessions=true
    local firewall_enabled=true
    local user_model_specified=false
    local args=()

    # --- Argument parsing ---------------------------------------------------
    for arg in "$@"; do
        case "$arg" in
            --cx-rebuild|--cx-update)
                _cx_rebuild "$container_name" "$container_dir"
                return $?
                ;;
            --cx-help)
                _cx_help
                return 0
                ;;
            --cx-no-sessions)
                persist_sessions=false
                ;;
            --cx-no-firewall)
                firewall_enabled=false
                ;;
            *)
                [[ "$arg" == "--model" || "$arg" == "-m" || "$arg" == --model=* ]] && user_model_specified=true
                args+=("$arg")
                ;;
        esac
    done

    # --- Setup --------------------------------------------------------------
    _cx_build_image "$container_name" "$container_dir" || return 1

    [[ "$firewall_enabled" == "true" ]] && _cx_setup_firewall_hook "$hooks_dir"

    if [[ "$user_model_specified" == "false" ]]; then
        local repo_root=""
        repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || true
        local agents_model=""
        agents_model="$(_cx_detect_model "$PWD" "$repo_root")"
        [[ -n "$agents_model" ]] && args=(--model "$agents_model" "${args[@]}")
    fi

    # --- Warn if API key is not set -----------------------------------------
    if [[ -z "${OPENAI_API_KEY:-}" ]]; then
        echo "Warning: OPENAI_API_KEY is not set. Codex will likely fail to authenticate." >&2
    fi

    # --- Assemble and run podman command ------------------------------------
    local podman_args=(run -it --rm)

    if [[ "$firewall_enabled" == "true" ]]; then
        podman_args+=(--hooks-dir "$hooks_dir" --annotation cx-firewall=enabled)
        podman_args+=(--dns=8.8.8.8 --dns=1.1.1.1)
    fi

    podman_args+=(-v "$PWD:/workspace:Z")
    [[ "$persist_sessions" == "true" ]] && podman_args+=(-v "$HOME/.codex:/root/.codex:z")

    podman_args+=(-e "OPENAI_API_KEY=${OPENAI_API_KEY:-}")
    podman_args+=("$container_name")

    podman "${podman_args[@]}" "${args[@]}"
}
