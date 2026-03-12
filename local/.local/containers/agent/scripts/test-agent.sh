#!/bin/bash
# Unit tests for bash/.bashrc.d/80-agent.sh
# Run from anywhere: bash ~/.local/containers/agent/scripts/test-agent.sh

set -uo pipefail

# Resolve dotfiles repo root via the symlink target — stow deploys this script
# as a symlink into ~/.local/…, so readlink -f gives the real path inside the
# repo, and five levels up lands at the dotfiles root.
REAL_SCRIPT="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$REAL_SCRIPT")/../../../../../" && pwd)"

# ---------------------------------------------------------------------------
# Test framework
# ---------------------------------------------------------------------------
_pass=0
_fail=0

pass() { echo "  ✓ $1"; _pass=$(( _pass + 1 )); }
fail() { echo "  ✗ $1"; _fail=$(( _fail + 1 )); }

assert_eq() {
    local desc="$1" got="$2" want="$3"
    if [[ "$got" == "$want" ]]; then
        pass "$desc"
    else
        fail "$desc"
        echo "      got:  $(printf '%q' "$got")"
        echo "      want: $(printf '%q' "$want")"
    fi
}

assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        pass "$desc"
    else
        fail "$desc (missing: $(printf '%q' "$needle"))"
    fi
}

assert_not_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        pass "$desc"
    else
        fail "$desc (unexpectedly found: $(printf '%q' "$needle"))"
    fi
}

assert_file_exists() { [[ -f "$2" ]] && pass "$1" || fail "$1 (missing: $2)"; }
assert_dir_exists()  { [[ -d "$2" ]] && pass "$1" || fail "$1 (missing: $2)"; }

# ---------------------------------------------------------------------------
# Source the script under test
# ---------------------------------------------------------------------------
# shellcheck source=bash/.bashrc.d/80-agent.sh
source "$SCRIPT_DIR/bash/.bashrc.d/80-agent.sh"

# ---------------------------------------------------------------------------
# _agent_detect_model
# ---------------------------------------------------------------------------
test_detect_model() {
    echo ""
    echo "--- _agent_detect_model ---"
    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' RETURN

    # No AGENTS.md at all
    assert_eq "no AGENTS.md → empty" \
        "$(_agent_detect_model "$tmpdir" "")" ""

    # Supported model in front-matter
    printf '%s\n' '---' 'model: claude-opus-4-5' '---' > "$tmpdir/AGENTS.md"
    assert_eq "model returned from front-matter" \
        "$(_agent_detect_model "$tmpdir" "")" "claude-opus-4-5"

    # Model value with surrounding whitespace is trimmed
    printf '%s\n' '---' 'model:   gpt-5   ' '---' > "$tmpdir/AGENTS.md"
    assert_eq "model value trimmed" \
        "$(_agent_detect_model "$tmpdir" "")" "gpt-5"

    # No YAML front-matter fence → model ignored
    printf '%s\n' '# Just content' 'model: sneaky' > "$tmpdir/AGENTS.md"
    assert_eq "no front-matter → empty" \
        "$(_agent_detect_model "$tmpdir" "")" ""

    # AGENTS.md found in parent directory when missing from child
    local subdir="$tmpdir/project"
    mkdir "$subdir"
    printf '%s\n' '---' 'model: claude-opus-4-5' '---' > "$tmpdir/AGENTS.md"
    assert_eq "AGENTS.md found in parent directory" \
        "$(_agent_detect_model "$subdir" "")" "claude-opus-4-5"

    # Walk stops at repo root, does not continue to parent AGENTS.md
    mkdir -p "$tmpdir/repo/sub"
    printf '%s\n' '---' 'model: should-not-find' '---' > "$tmpdir/AGENTS.md"
    assert_eq "walk stops at repo root" \
        "$(_agent_detect_model "$tmpdir/repo/sub" "$tmpdir/repo")" ""
}

# ---------------------------------------------------------------------------
# _agent_setup_firewall_hook
# ---------------------------------------------------------------------------
test_setup_firewall_hook() {
    echo ""
    echo "--- _agent_setup_firewall_hook ---"
    local tmpdir hooks_dir
    tmpdir=$(mktemp -d)
    hooks_dir="$tmpdir/hooks.d"
    trap 'rm -rf "$tmpdir"' RETURN

    # claude: creates claude-specific hook file
    _agent_setup_firewall_hook "$hooks_dir" "claude"

    assert_dir_exists  "hooks directory created"          "$hooks_dir"
    assert_file_exists "claude policy file created"       "$hooks_dir/claude-firewall.json"

    local content
    content="$(cat "$hooks_dir/claude-firewall.json")"
    assert_contains "\$HOME substituted (not hardcoded username)" "$content" "$HOME"
    assert_contains "policy has version field"                    "$content" '"version"'
    assert_contains "policy references configure-firewall.sh"    "$content" 'configure-firewall.sh'
    assert_contains "policy references claude container dir"      "$content" 'containers/claude'
    assert_contains "policy has claude-firewall annotation"       "$content" 'claude-firewall'
    assert_contains "policy has createContainer stage"            "$content" 'createContainer'

    # Idempotent: existing policy file is not overwritten
    echo "sentinel" > "$hooks_dir/claude-firewall.json"
    _agent_setup_firewall_hook "$hooks_dir" "claude"
    assert_eq "existing policy not overwritten" \
        "$(cat "$hooks_dir/claude-firewall.json")" "sentinel"

    # codex: creates codex-specific hook file
    _agent_setup_firewall_hook "$hooks_dir" "codex"
    assert_file_exists "codex policy file created" "$hooks_dir/codex-firewall.json"
    content="$(cat "$hooks_dir/codex-firewall.json")"
    assert_contains "codex policy references codex container dir"  "$content" 'containers/codex'
    assert_contains "codex policy has codex-firewall annotation"   "$content" 'codex-firewall'

    # copilot: creates copilot-specific hook file
    _agent_setup_firewall_hook "$hooks_dir" "copilot"
    assert_file_exists "copilot policy file created" "$hooks_dir/copilot-firewall.json"
    content="$(cat "$hooks_dir/copilot-firewall.json")"
    assert_contains "copilot policy references copilot container dir"  "$content" 'containers/copilot'
    assert_contains "copilot policy has copilot-firewall annotation"   "$content" 'copilot-firewall'
}

# ---------------------------------------------------------------------------
# _agent_load_denied_tools
# ---------------------------------------------------------------------------
test_load_denied_tools() {
    echo ""
    echo "--- _agent_load_denied_tools ---"
    local tmpdir arr=()
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' RETURN

    # Missing config file → empty array, no error
    _agent_load_denied_tools "$tmpdir/nonexistent.conf" arr
    assert_eq "missing file → empty array" "${arr[*]:-}" ""

    # Empty file → empty array
    : > "$tmpdir/denied-tools.conf"
    _agent_load_denied_tools "$tmpdir/denied-tools.conf" arr
    assert_eq "empty file → empty array" "${arr[*]:-}" ""

    # Comments and blank lines are skipped; entries produce --deny-tool pairs
    printf '%s\n' '# comment' 'tool-a' '  # indented comment' '' 'tool-b' \
        > "$tmpdir/denied-tools.conf"
    _agent_load_denied_tools "$tmpdir/denied-tools.conf" arr
    assert_eq "two entries → four array elements" "${#arr[@]}" "4"
    assert_eq "array contains --deny-tool pairs" \
        "${arr[*]}" "--deny-tool tool-a --deny-tool tool-b"
}

# ---------------------------------------------------------------------------
# _agent_help
# ---------------------------------------------------------------------------
test_help() {
    echo ""
    echo "--- _agent_help ---"
    local output
    output="$(_agent_help)"
    assert_contains "contains Usage section"           "$output" "Usage:"
    assert_contains "documents --agent-help"           "$output" "--agent-help"
    assert_contains "documents --agent-rebuild"        "$output" "--agent-rebuild"
    assert_contains "documents --agent-no-sessions"    "$output" "--agent-no-sessions"
    assert_contains "documents --agent-no-firewall"    "$output" "--agent-no-firewall"
    assert_contains "documents AGENTS.md"              "$output" "AGENTS.md"
    assert_contains "documents Session Persistence"    "$output" "Session Persistence"
    assert_contains "documents Network Isolation"      "$output" "Network Isolation"
    assert_contains "documents Authentication"         "$output" "Authentication"
    assert_contains "lists claude agent"               "$output" "claude"
    assert_contains "lists codex agent"                "$output" "codex"
    assert_contains "lists copilot agent"              "$output" "copilot"
}

# ---------------------------------------------------------------------------
# agent() top-level dispatch  (no real containers needed)
# ---------------------------------------------------------------------------
test_agent_dispatch() {
    echo ""
    echo "--- agent() top-level dispatch ---"
    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' RETURN

    local out

    # No args → help
    out="$(agent 2>&1)"
    assert_contains "no args prints help"        "$out" "Usage:"
    assert_not_contains "no args no podman run"  "$out" "podman run"

    # --agent-help → help
    out="$(agent --agent-help 2>&1)"
    assert_contains "--agent-help prints help"        "$out" "Usage:"
    assert_not_contains "--agent-help no podman run"  "$out" "podman run"

    # Unknown agent → error on stderr, non-zero exit
    out="$(agent unknown-agent 2>&1)"
    assert_contains "unknown agent prints error" "$out" "unknown agent"
}

# ---------------------------------------------------------------------------
# agent claude argument parsing  (podman + git mocked; no real container)
#
# podman() writes its arguments to $_AGENT_TEST_CAPTURE so tests can inspect
# exactly what would have been passed to the container runtime.
# ---------------------------------------------------------------------------

_AGENT_TEST_CAPTURE=""

test_agent_claude() {
    echo ""
    echo "--- agent claude argument parsing ---"
    local tmpdir
    tmpdir=$(mktemp -d)
    _AGENT_TEST_CAPTURE="$tmpdir/capture"
    trap 'rm -rf "$tmpdir"; unset -f podman git _agent_build_image _agent_setup_firewall_hook' RETURN

    podman()                    { echo "podman $*" > "$_AGENT_TEST_CAPTURE"; }
    git()                       { return 1; }
    _agent_build_image()        { return 0; }
    _agent_setup_firewall_hook() { return 0; }

    local out

    # --agent-help mid-command: prints help and does NOT invoke podman
    agent claude --agent-help > "$_AGENT_TEST_CAPTURE" 2>&1
    out="$(cat "$_AGENT_TEST_CAPTURE")"
    assert_contains     "claude --agent-help prints help"    "$out" "Usage:"
    assert_not_contains "claude --agent-help no podman run"  "$out" "podman run"

    # Default run: firewall args and session mounts both present
    agent claude 2>/dev/null; out="$(cat "$_AGENT_TEST_CAPTURE")"
    assert_contains "claude: firewall enabled by default"          "$out" "--hooks-dir"
    assert_contains "claude: claude-firewall annotation"           "$out" "claude-firewall=enabled"
    assert_contains "claude: session mount present by default"     "$out" ".claude:/root/.claude"
    assert_contains "claude: .claude.json mounted by default"      "$out" ".claude.json:/root/.claude.json"
    assert_not_contains "claude: no ANTHROPIC_API_KEY env"         "$out" "ANTHROPIC_API_KEY"

    # --agent-no-sessions: credentials.json mounted read-only, full dir not mounted
    agent claude --agent-no-sessions 2>/dev/null; out="$(cat "$_AGENT_TEST_CAPTURE")"
    assert_not_contains "claude --agent-no-sessions omits full .claude mount"    "$out" ".claude:/root/.claude"
    assert_contains     "claude --agent-no-sessions mounts credentials.json ro"  "$out" ".credentials.json:/root/.claude/.credentials.json:ro"
    assert_contains     "claude --agent-no-sessions mounts .claude.json ro"      "$out" ".claude.json:/root/.claude.json:ro"
    assert_contains     "claude --agent-no-sessions keeps firewall"              "$out" "--hooks-dir"

    # --agent-no-firewall: firewall args omitted
    agent claude --agent-no-firewall 2>/dev/null; out="$(cat "$_AGENT_TEST_CAPTURE")"
    assert_not_contains "claude --agent-no-firewall omits --hooks-dir"   "$out" "--hooks-dir"
    assert_not_contains "claude --agent-no-firewall omits --dns"         "$out" "--dns"
    assert_contains     "claude --agent-no-firewall keeps session mount" "$out" ".claude:/root/.claude"

    # Arbitrary pass-through args appear verbatim in the podman call
    agent claude "fix the tests" 2>/dev/null; out="$(cat "$_AGENT_TEST_CAPTURE")"
    assert_contains "claude: pass-through args forwarded" "$out" "fix the tests"

    # AGENTS.md model is prepended when the user has not specified --model
    printf '%s\n' '---' 'model: claude-opus-4-5' '---' > "$tmpdir/AGENTS.md"
    (cd "$tmpdir" && agent claude 2>/dev/null); out="$(cat "$_AGENT_TEST_CAPTURE")"
    assert_contains "claude: AGENTS.md model prepended" "$out" "--model claude-opus-4-5"

    # User --model (space form) suppresses AGENTS.md model
    (cd "$tmpdir" && agent claude --model my-model 2>/dev/null); out="$(cat "$_AGENT_TEST_CAPTURE")"
    assert_not_contains "claude: user --model suppresses AGENTS.md model" "$out" "claude-opus-4-5"
    assert_contains     "claude: user --model value forwarded"             "$out" "--model my-model"

    # User --model=value form also suppresses AGENTS.md model
    (cd "$tmpdir" && agent claude --model=my-model 2>/dev/null); out="$(cat "$_AGENT_TEST_CAPTURE")"
    assert_not_contains "claude: --model=value suppresses AGENTS.md model" "$out" "claude-opus-4-5"

    # User -m (short form) also suppresses AGENTS.md model
    (cd "$tmpdir" && agent claude -m my-model 2>/dev/null); out="$(cat "$_AGENT_TEST_CAPTURE")"
    assert_not_contains "claude: -m suppresses AGENTS.md model" "$out" "claude-opus-4-5"
    assert_contains     "claude: -m value forwarded"             "$out" "-m my-model"

    # --agent-rebuild invokes _agent_rebuild (not podman run)
    _agent_rebuild() { echo "rebuild called" > "$_AGENT_TEST_CAPTURE"; }
    agent claude --agent-rebuild 2>/dev/null; out="$(cat "$_AGENT_TEST_CAPTURE")"
    assert_contains     "claude: --agent-rebuild calls _agent_rebuild"   "$out" "rebuild called"
    assert_not_contains "claude: --agent-rebuild does not invoke podman" "$out" "podman run"
    unset -f _agent_rebuild

    # --agent-update is an alias for --agent-rebuild
    _agent_rebuild() { echo "rebuild called" > "$_AGENT_TEST_CAPTURE"; }
    agent claude --agent-update 2>/dev/null; out="$(cat "$_AGENT_TEST_CAPTURE")"
    assert_contains "claude: --agent-update calls _agent_rebuild" "$out" "rebuild called"
    unset -f _agent_rebuild
}

# ---------------------------------------------------------------------------
# agent codex argument parsing
# ---------------------------------------------------------------------------
test_agent_codex() {
    echo ""
    echo "--- agent codex argument parsing ---"
    local tmpdir
    tmpdir=$(mktemp -d)
    _AGENT_TEST_CAPTURE="$tmpdir/capture"
    trap 'rm -rf "$tmpdir"; unset -f podman git _agent_build_image _agent_setup_firewall_hook' RETURN

    podman()                    { echo "podman $*" > "$_AGENT_TEST_CAPTURE"; }
    git()                       { return 1; }
    _agent_build_image()        { return 0; }
    _agent_setup_firewall_hook() { return 0; }

    local old_key="${OPENAI_API_KEY:-}"
    OPENAI_API_KEY="sk-test"

    local out

    # Default run: firewall args, session mount, and API key present
    agent codex 2>/dev/null; out="$(cat "$_AGENT_TEST_CAPTURE")"
    assert_contains "codex: firewall enabled by default"        "$out" "--hooks-dir"
    assert_contains "codex: codex-firewall annotation"          "$out" "codex-firewall=enabled"
    assert_contains "codex: session mount present by default"   "$out" ".codex:/root/.codex"
    assert_contains "codex: OPENAI_API_KEY passed to container" "$out" "OPENAI_API_KEY"

    # --agent-no-sessions: session mount omitted
    agent codex --agent-no-sessions 2>/dev/null; out="$(cat "$_AGENT_TEST_CAPTURE")"
    assert_not_contains "codex --agent-no-sessions omits session mount" "$out" ".codex:/root/.codex"
    assert_contains     "codex --agent-no-sessions keeps firewall"      "$out" "--hooks-dir"

    # --agent-no-firewall: firewall args omitted
    agent codex --agent-no-firewall 2>/dev/null; out="$(cat "$_AGENT_TEST_CAPTURE")"
    assert_not_contains "codex --agent-no-firewall omits --hooks-dir"   "$out" "--hooks-dir"
    assert_not_contains "codex --agent-no-firewall omits --dns"         "$out" "--dns"
    assert_contains     "codex --agent-no-firewall keeps session mount" "$out" ".codex"

    # Arbitrary pass-through args appear verbatim
    agent codex exec "fix the bug" 2>/dev/null; out="$(cat "$_AGENT_TEST_CAPTURE")"
    assert_contains "codex: pass-through args forwarded" "$out" "exec"

    # AGENTS.md model detection
    printf '%s\n' '---' 'model: gpt-5-codex' '---' > "$tmpdir/AGENTS.md"
    (cd "$tmpdir" && agent codex 2>/dev/null); out="$(cat "$_AGENT_TEST_CAPTURE")"
    assert_contains "codex: AGENTS.md model prepended" "$out" "--model gpt-5-codex"

    # User --model suppresses AGENTS.md model
    (cd "$tmpdir" && agent codex --model my-model 2>/dev/null); out="$(cat "$_AGENT_TEST_CAPTURE")"
    assert_not_contains "codex: user --model suppresses AGENTS.md model" "$out" "gpt-5-codex"

    # User -m suppresses AGENTS.md model
    (cd "$tmpdir" && agent codex -m my-model 2>/dev/null); out="$(cat "$_AGENT_TEST_CAPTURE")"
    assert_not_contains "codex: -m suppresses AGENTS.md model" "$out" "gpt-5-codex"

    # API key warning printed when OPENAI_API_KEY is unset
    OPENAI_API_KEY=""
    agent codex 2>"$tmpdir/stderr"; out="$(cat "$tmpdir/stderr")"
    assert_contains "codex: warns when OPENAI_API_KEY unset" "$out" "OPENAI_API_KEY"

    OPENAI_API_KEY="$old_key"
}

# ---------------------------------------------------------------------------
# agent copilot argument parsing
# ---------------------------------------------------------------------------
test_agent_copilot() {
    echo ""
    echo "--- agent copilot argument parsing ---"
    local tmpdir
    tmpdir=$(mktemp -d)
    _AGENT_TEST_CAPTURE="$tmpdir/capture"
    trap 'rm -rf "$tmpdir"; unset -f podman gh git _agent_build_image _agent_setup_firewall_hook' RETURN

    podman()                    { echo "podman $*" > "$_AGENT_TEST_CAPTURE"; }
    gh()                        { echo "mock-token"; }
    git()                       { return 1; }
    _agent_build_image()        { return 0; }
    _agent_setup_firewall_hook() { return 0; }

    local out

    # Default run: firewall args, session mount, and GH_TOKEN present
    agent copilot 2>/dev/null; out="$(cat "$_AGENT_TEST_CAPTURE")"
    assert_contains "copilot: firewall enabled by default"       "$out" "--hooks-dir"
    assert_contains "copilot: copilot-firewall annotation"       "$out" "copilot-firewall=enabled"
    assert_contains "copilot: session mount present by default"  "$out" ".copilot:/root/.copilot"
    assert_contains "copilot: GH_TOKEN passed to container"      "$out" "GH_TOKEN"

    # --agent-no-sessions: session mount omitted
    agent copilot --agent-no-sessions 2>/dev/null; out="$(cat "$_AGENT_TEST_CAPTURE")"
    assert_not_contains "copilot --agent-no-sessions omits session mount" "$out" ".copilot:/root/.copilot"
    assert_contains     "copilot --agent-no-sessions keeps firewall"      "$out" "--hooks-dir"

    # --agent-no-firewall: firewall args omitted
    agent copilot --agent-no-firewall 2>/dev/null; out="$(cat "$_AGENT_TEST_CAPTURE")"
    assert_not_contains "copilot --agent-no-firewall omits --hooks-dir"   "$out" "--hooks-dir"
    assert_not_contains "copilot --agent-no-firewall omits --dns"         "$out" "--dns"
    assert_contains     "copilot --agent-no-firewall keeps session mount" "$out" ".copilot"

    # Arbitrary pass-through args appear verbatim
    agent copilot --continue 2>/dev/null; out="$(cat "$_AGENT_TEST_CAPTURE")"
    assert_contains "copilot: pass-through args forwarded" "$out" "--continue"

    # AGENTS.md model detection
    printf '%s\n' '---' 'model: claude-sonnet-4.5' '---' > "$tmpdir/AGENTS.md"
    (cd "$tmpdir" && agent copilot 2>/dev/null); out="$(cat "$_AGENT_TEST_CAPTURE")"
    assert_contains "copilot: AGENTS.md model prepended" "$out" "--model claude-sonnet-4.5"

    # User --model suppresses AGENTS.md model
    (cd "$tmpdir" && agent copilot --model my-model 2>/dev/null); out="$(cat "$_AGENT_TEST_CAPTURE")"
    assert_not_contains "copilot: user --model suppresses AGENTS.md model"  "$out" "claude-sonnet-4.5"
    assert_contains     "copilot: user --model value forwarded"              "$out" "--model my-model"

    # User --model=value form also suppresses AGENTS.md model
    (cd "$tmpdir" && agent copilot --model=my-model 2>/dev/null); out="$(cat "$_AGENT_TEST_CAPTURE")"
    assert_not_contains "copilot: --model=value suppresses AGENTS.md model"  "$out" "claude-sonnet-4.5"

    # copilot does NOT treat -m as a model flag (no -m short form)
    (cd "$tmpdir" && agent copilot -m my-model 2>/dev/null); out="$(cat "$_AGENT_TEST_CAPTURE")"
    assert_contains "copilot: -m is passed through (not a model flag)" "$out" "claude-sonnet-4.5"

    # Denied tools from config file are forwarded
    # The container_dir is $HOME/.local/containers/copilot, so create the file there
    mkdir -p "$tmpdir/.local/containers/copilot"
    printf '%s\n' 'shell(op)' 'shell(ssh)' > "$tmpdir/.local/containers/copilot/denied-tools.conf"
    local HOME_SAVE="$HOME"
    HOME="$tmpdir"
    agent copilot 2>/dev/null; out="$(cat "$_AGENT_TEST_CAPTURE")"
    HOME="$HOME_SAVE"
    assert_contains "copilot: denied tools forwarded" "$out" "--deny-tool"

    # --agent-rebuild invokes _agent_rebuild (not podman run)
    _agent_rebuild() { echo "rebuild called" > "$_AGENT_TEST_CAPTURE"; }
    agent copilot --agent-rebuild 2>/dev/null; out="$(cat "$_AGENT_TEST_CAPTURE")"
    assert_contains     "copilot: --agent-rebuild calls _agent_rebuild"   "$out" "rebuild called"
    assert_not_contains "copilot: --agent-rebuild does not invoke podman" "$out" "podman run"
    unset -f _agent_rebuild
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------
echo "=== agent tests ==="

test_detect_model
test_setup_firewall_hook
test_load_denied_tools
test_help
test_agent_dispatch
test_agent_claude
test_agent_codex
test_agent_copilot

echo ""
if (( _fail == 0 )); then
    echo "=== All $_pass tests passed ==="
else
    echo "=== $_pass passed, $_fail FAILED ==="
    exit 1
fi
