# Unified agent command - runs AI coding agents in sandboxed containers
# Usage: agent <name> [arguments...]

# ---------------------------------------------------------------------------
# Shared helpers (_agent_ prefix)
# ---------------------------------------------------------------------------

_agent_help() {
    cat <<'EOF'
agent - Run AI coding agents in sandboxed containers

Usage:
  agent <name> [arguments...]       Run the specified agent
  agent <name> --agent-rebuild      Rebuild container image (updates CLI)
  agent <name> --agent-update       Same as --agent-rebuild
  agent --agent-rebuild-all         Rebuild all agent container images
  agent <name> --agent-no-sessions  Disable session persistence (ephemeral mode)
  agent <name> --agent-no-firewall  Disable network isolation (allow local network access)
  agent <name> --agent-help         Show this help message
  agent --agent-help                Show this help message

Agents:
  claude    Claude Code (Anthropic) - auth via ~/.claude credentials
  codex     OpenAI Codex CLI        - auth via OPENAI_API_KEY env var
  copilot   GitHub Copilot          - auth via gh auth token

Examples:
  agent claude                          Interactive Claude Code (isolated, with sessions)
  agent claude --version                Check Claude Code version
  agent claude --continue               Resume most recent Claude session
  agent claude "fix the failing tests"  Run Claude Code with a prompt
  agent codex exec "fix the bug"        Run Codex non-interactively
  agent codex -m gpt-5 "..."            Use a specific model
  agent copilot --continue              Resume most recent copilot session
  agent claude --agent-rebuild          Update Claude Code container
  agent claude --agent-no-sessions      Run Claude without session persistence
  agent claude --agent-no-firewall      Run Claude with local network access
  agent --agent-rebuild-all             Update all agent containers at once

Authentication:
  claude   - Mount ~/.claude (credentials from 'claude auth login' on host)
  codex    - Set OPENAI_API_KEY in your host environment before running
  copilot  - Requires 'gh auth login' on the host first

Session Persistence:
  By default, agent mounts the agent's config directory to persist sessions.
  Use --agent-no-sessions to run in ephemeral mode.
  For claude, auth credentials are still mounted read-only in ephemeral mode.

Network Isolation:
  By default, agent isolates the container from your local network using an
  OCI hook that configures a firewall in the container's network namespace.

  What's blocked:
    • Local network access (192.168.x.x, 10.x.x.x, etc.)
    • Local DNS servers (uses public DNS: Google, Cloudflare, Quad9)

  What's allowed:
    • Public internet (agent APIs, npm, git, etc.)
    • Container-internal services (localhost inside container)
    • Public DNS servers only

  Use --agent-no-firewall to disable network isolation.

All flags not starting with --agent- are passed through to the agent command.

AGENTS.md:
  If an AGENTS.md with YAML front-matter is found in the current directory or a
  parent (up to the git repo root), agent may set defaults like --model
  (user --model wins).

The container auto-builds on first use and mounts your current directory.
EOF
}

# Remove the existing image and rebuild it from the Containerfile.
_agent_rebuild() {
    local container_name="$1" container_dir="$2"
    echo "Rebuilding $container_name image..." >&2
    podman rmi "$container_name" 2>/dev/null || true
    podman build -t "$container_name" -f "$container_dir/Containerfile" "$container_dir"
}

# Build the container image if it doesn't already exist.
_agent_build_image() {
    local container_name="$1" container_dir="$2"
    if ! podman image exists "$container_name" 2>/dev/null; then
        echo "Building $container_name image..." >&2
        podman build -t "$container_name" -f "$container_dir/Containerfile" "$container_dir" || return 1
    fi
}

# Ensure the OCI hooks directory and firewall hook policy file exist.
_agent_setup_firewall_hook() {
    local hooks_dir="$1" agent_name="$2"
    local hook_policy="$hooks_dir/${agent_name}-firewall.json"

    [[ -d "$hooks_dir" ]] || mkdir -p "$hooks_dir"

    if [[ ! -f "$hook_policy" ]]; then
        printf '{
  "version": "1.0.0",
  "hook": {
    "path": "%s/.local/containers/%s/scripts/configure-firewall.sh"
  },
  "when": {
    "annotations": {
      "^%s-firewall$": "enabled"
    }
  },
  "stages": ["createContainer"]
}\n' "$HOME" "$agent_name" "$agent_name" > "$hook_policy"
    fi
}

# Walk from search_dir up to repo_root (or /) looking for AGENTS.md with a
# model: field in its YAML front-matter. Prints the model name to stdout, or
# nothing if none is found.
_agent_detect_model() {
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

# Read denied-tools.conf and populate the caller's array (via nameref) with
# the corresponding --deny-tool flag pairs. (Used by the copilot agent.)
_agent_load_denied_tools() {
    local config_file="$1"
    local -n _denied_tools_result="$2"
    _denied_tools_result=()
    [[ -f "$config_file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        _denied_tools_result+=(--deny-tool "$line")
    done < "$config_file"
}

# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

agent() {
    # Show help when no arguments given or when the first argument is --agent-help
    if [[ $# -eq 0 || "$1" == "--agent-help" ]]; then
        _agent_help
        return 0
    fi

    # Rebuild all agent containers in sequence (no agent name required)
    if [[ "$1" == "--agent-rebuild-all" ]]; then
        local rc=0
        for _name in claude codex copilot; do
            _agent_rebuild "${_name}-sandbox" "$HOME/.local/containers/${_name}" || rc=$?
        done
        return $rc
    fi

    local agent_name="$1"
    shift

    # Validate agent name and set agent-specific config
    local container_name container_dir
    case "$agent_name" in
        claude)
            container_name="claude-sandbox"
            container_dir="$HOME/.local/containers/claude"
            ;;
        codex)
            container_name="codex-sandbox"
            container_dir="$HOME/.local/containers/codex"
            ;;
        copilot)
            container_name="copilot-sandbox"
            container_dir="$HOME/.local/containers/copilot"
            ;;
        *)
            echo "agent: unknown agent '$agent_name'. Valid agents: claude, codex, copilot" >&2
            return 1
            ;;
    esac

    local hooks_dir="$HOME/.config/containers/hooks.d"
    local persist_sessions=true
    local firewall_enabled=true
    local user_model_specified=false
    local args=()

    # --- Argument parsing ---------------------------------------------------
    for arg in "$@"; do
        case "$arg" in
            --agent-rebuild|--agent-update)
                _agent_rebuild "$container_name" "$container_dir"
                return $?
                ;;
            --agent-help)
                _agent_help
                return 0
                ;;
            --agent-no-sessions)
                persist_sessions=false
                ;;
            --agent-no-firewall)
                firewall_enabled=false
                ;;
            *)
                # Track whether the user explicitly specified a model so we
                # don't override it with the AGENTS.md default.
                # copilot does not support the -m short flag.
                if [[ "$arg" == "--model" || "$arg" == --model=* || \
                      ( "$agent_name" != "copilot" && "$arg" == "-m" ) ]]; then
                    user_model_specified=true
                fi
                args+=("$arg")
                ;;
        esac
    done

    # --- Setup --------------------------------------------------------------
    _agent_build_image "$container_name" "$container_dir" || return 1

    [[ "$firewall_enabled" == "true" ]] && _agent_setup_firewall_hook "$hooks_dir" "$agent_name"

    if [[ "$user_model_specified" == "false" ]]; then
        local repo_root=""
        repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || true
        local agents_model=""
        agents_model="$(_agent_detect_model "$PWD" "$repo_root")"
        [[ -n "$agents_model" ]] && args=(--model "$agents_model" "${args[@]}")
    fi

    # --- Assemble and run podman command ------------------------------------
    local podman_args=(run -it --rm)

    if [[ "$firewall_enabled" == "true" ]]; then
        podman_args+=(--hooks-dir "$hooks_dir" --annotation "${agent_name}-firewall=enabled")
        podman_args+=(--dns=8.8.8.8 --dns=1.1.1.1 --dns=9.9.9.9)
    fi

    podman_args+=(-v "$PWD:/workspace:Z")
    podman_args+=(-e "HOST_CWD=$(basename "$PWD")")

    # Agent-specific: session persistence, authentication, and extra args
    local denied_tools_args=()
    case "$agent_name" in
        claude)
            podman_args+=(-e "GH_TOKEN=$(gh auth token 2>/dev/null)")
            if [[ "$persist_sessions" == "true" ]]; then
                podman_args+=(-v "$HOME/.claude:/root/.claude:z")
                podman_args+=(-v "$HOME/.claude.json:/root/.claude.json:z")
            else
                podman_args+=(-v "$HOME/.claude/.credentials.json:/root/.claude/.credentials.json:ro,z")
                podman_args+=(-v "$HOME/.claude.json:/root/.claude.json:ro,z")
            fi
            ;;
        codex)
            [[ "$persist_sessions" == "true" ]] && podman_args+=(-v "$HOME/.codex:/root/.codex:z")
            if [[ -z "${OPENAI_API_KEY:-}" ]]; then
                echo "Warning: OPENAI_API_KEY is not set. Codex will likely fail to authenticate." >&2
            fi
            podman_args+=(-e "OPENAI_API_KEY=${OPENAI_API_KEY:-}")
            podman_args+=(-e "GH_TOKEN=$(gh auth token 2>/dev/null)")
            ;;
        copilot)
            [[ "$persist_sessions" == "true" ]] && podman_args+=(-v "$HOME/.copilot:/root/.copilot:z")
            podman_args+=(-e "GH_TOKEN=$(gh auth token 2>/dev/null)")
            _agent_load_denied_tools "$container_dir/denied-tools.conf" denied_tools_args
            ;;
    esac

    podman_args+=("$container_name")

    podman "${podman_args[@]}" "${denied_tools_args[@]}" "${args[@]}"
}
