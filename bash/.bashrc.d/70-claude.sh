# Claude Code in Container (cld)
# Runs Claude Code CLI in a sandboxed podman container with network isolation

# ---------------------------------------------------------------------------
# Private helpers (_cld_ prefix)
# ---------------------------------------------------------------------------

_cld_help() {
    cat <<'EOF'
cld - Claude Code in Container

Usage:
  cld [arguments...]        Run Claude Code with arguments
  cld --cld-rebuild         Rebuild container image (updates Claude Code CLI)
  cld --cld-update          Same as --cld-rebuild
  cld --cld-no-sessions     Disable session persistence (ephemeral mode)
  cld --cld-no-firewall     Disable network isolation (allow local network access)
  cld --cld-help            Show this help message

Examples:
  cld                       Interactive Claude Code (isolated, with sessions)
  cld --version             Check Claude Code version
  cld --continue            Resume most recent session
  cld "fix the failing tests"  Run Claude Code with a prompt
  cld --model claude-opus-4-5 "..."  Use a specific model
  cld --cld-rebuild         Update to latest Claude Code CLI
  cld --cld-no-sessions     Run without mounting .claude directory
  cld --cld-no-firewall     Run with local network access enabled

Authentication:
  Credentials are provided by mounting host files into the container:
  - ~/.claude/.credentials.json (OAuth credentials from 'claude auth login')
  - ~/.claude.json (additional auth configuration)
  Run 'claude auth login' on the host first to create these files.

Session Persistence:
  By default, cld mounts ~/.claude to persist sessions across container runs.
  This allows you to use --continue to restore previous sessions.
  Use --cld-no-sessions to run in ephemeral mode (auth files are still
  mounted read-only, but sessions are not persisted).

Network Isolation:
  By default, cld isolates the container from your local network using an
  OCI hook that configures a firewall in the container's network namespace.
  
  What's blocked:
    • Local network access (192.168.x.x, 10.x.x.x, etc.)
    • Local DNS servers (uses public DNS: Google, Cloudflare, Quad9)
  
  What's allowed:
    • Public internet (Anthropic API, npm, git, etc.)
    • Container-internal services (localhost inside container)
    • Public DNS servers only
  
  Use --cld-no-firewall to disable network isolation.
  
  Setup: The firewall hook is configured automatically on first use.
  For details, see: ~/.local/containers/claude/scripts/configure-firewall.sh

All flags not starting with --cld- are passed through to the claude command.

AGENTS.md:
  If an AGENTS.md with YAML front-matter is found in the current directory or a parent
  (up to the git repo root), cld may set defaults like --model (user --model wins).

The container auto-builds on first use and mounts your current directory.
EOF
}

# Remove the existing image and rebuild it from the Containerfile.
_cld_rebuild() {
    local container_name="$1" container_dir="$2"
    echo "Rebuilding $container_name image..." >&2
    podman rmi "$container_name" 2>/dev/null || true
    podman build -t "$container_name" -f "$container_dir/Containerfile" "$container_dir"
}

# Build the container image if it doesn't already exist.
_cld_build_image() {
    local container_name="$1" container_dir="$2"
    if ! podman image exists "$container_name" 2>/dev/null; then
        echo "Building $container_name image..." >&2
        podman build -t "$container_name" -f "$container_dir/Containerfile" "$container_dir" || return 1
    fi
}

# Ensure the OCI hooks directory and firewall hook policy file exist.
_cld_setup_firewall_hook() {
    local hooks_dir="$1"
    local hook_policy="$hooks_dir/cld-firewall.json"

    [[ -d "$hooks_dir" ]] || mkdir -p "$hooks_dir"

    if [[ ! -f "$hook_policy" ]]; then
        printf '{
  "version": "1.0.0",
  "hook": {
    "path": "%s/.local/containers/claude/scripts/configure-firewall.sh"
  },
  "when": {
    "annotations": {
      "^cld-firewall$": "enabled"
    }
  },
  "stages": ["createContainer"]
}\n' "$HOME" > "$hook_policy"
    fi
}

# Walk from search_dir up to repo_root (or /) looking for AGENTS.md with a
# model: field in its YAML front-matter. Prints the model name to stdout, or
# nothing if none is found.
_cld_detect_model() {
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

cld() {
    local container_name="claude-sandbox"
    local container_dir="$HOME/.local/containers/claude"
    local hooks_dir="$HOME/.config/containers/hooks.d"
    local persist_sessions=true
    local firewall_enabled=true
    local user_model_specified=false
    local args=()

    # --- Argument parsing ---------------------------------------------------
    for arg in "$@"; do
        case "$arg" in
            --cld-rebuild|--cld-update)
                _cld_rebuild "$container_name" "$container_dir"
                return $?
                ;;
            --cld-help)
                _cld_help
                return 0
                ;;
            --cld-no-sessions)
                persist_sessions=false
                ;;
            --cld-no-firewall)
                firewall_enabled=false
                ;;
            *)
                [[ "$arg" == "--model" || "$arg" == "-m" || "$arg" == --model=* ]] && user_model_specified=true
                args+=("$arg")
                ;;
        esac
    done

    # --- Setup --------------------------------------------------------------
    _cld_build_image "$container_name" "$container_dir" || return 1

    [[ "$firewall_enabled" == "true" ]] && _cld_setup_firewall_hook "$hooks_dir"

    if [[ "$user_model_specified" == "false" ]]; then
        local repo_root=""
        repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || true
        local agents_model=""
        agents_model="$(_cld_detect_model "$PWD" "$repo_root")"
        [[ -n "$agents_model" ]] && args=(--model "$agents_model" "${args[@]}")
    fi

    # --- Assemble and run podman command ------------------------------------
    local podman_args=(run -it --rm)

    if [[ "$firewall_enabled" == "true" ]]; then
        podman_args+=(--hooks-dir "$hooks_dir" --annotation cld-firewall=enabled)
        podman_args+=(--dns=8.8.8.8 --dns=1.1.1.1)
    fi

    podman_args+=(-v "$PWD:/workspace:Z")

    if [[ "$persist_sessions" == "true" ]]; then
        podman_args+=(-v "$HOME/.claude:/root/.claude:z")
        podman_args+=(-v "$HOME/.claude.json:/root/.claude.json:z")
    else
        podman_args+=(-v "$HOME/.claude/.credentials.json:/root/.claude/.credentials.json:ro,z")
        podman_args+=(-v "$HOME/.claude.json:/root/.claude.json:ro,z")
    fi

    podman_args+=("$container_name")

    podman "${podman_args[@]}" "${args[@]}"
}
