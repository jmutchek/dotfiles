#!/bin/bash
# Unit tests for bash/.bashrc.d/50-ghcp.sh
# Run from anywhere: bash ~/.local/containers/copilot/scripts/test-ghcp.sh

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
# shellcheck source=bash/.bashrc.d/50-ghcp.sh
source "$SCRIPT_DIR/bash/.bashrc.d/50-ghcp.sh"

# ---------------------------------------------------------------------------
# _ghcp_detect_model
# ---------------------------------------------------------------------------
test_detect_model() {
    echo ""
    echo "--- _ghcp_detect_model ---"
    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' RETURN

    # No AGENTS.md at all
    assert_eq "no AGENTS.md → empty" \
        "$(_ghcp_detect_model "$tmpdir" "")" ""

    # Supported model in front-matter
    printf '%s\n' '---' 'model: claude-sonnet-4.5' '---' > "$tmpdir/AGENTS.md"
    assert_eq "model returned from front-matter" \
        "$(_ghcp_detect_model "$tmpdir" "")" "claude-sonnet-4.5"

    # Model value with surrounding whitespace is trimmed
    printf '%s\n' '---' 'model:   gpt-5.2   ' '---' > "$tmpdir/AGENTS.md"
    assert_eq "model value trimmed" \
        "$(_ghcp_detect_model "$tmpdir" "")" "gpt-5.2"

    # No YAML front-matter fence → model ignored
    printf '%s\n' '# Just content' 'model: sneaky' > "$tmpdir/AGENTS.md"
    assert_eq "no front-matter → empty" \
        "$(_ghcp_detect_model "$tmpdir" "")" ""

    # AGENTS.md found in parent directory when missing from child
    local subdir="$tmpdir/project"
    mkdir "$subdir"
    printf '%s\n' '---' 'model: gpt-5' '---' > "$tmpdir/AGENTS.md"
    assert_eq "AGENTS.md found in parent directory" \
        "$(_ghcp_detect_model "$subdir" "")" "gpt-5"

    # Walk stops at repo root, does not continue to parent AGENTS.md
    mkdir -p "$tmpdir/repo/sub"
    printf '%s\n' '---' 'model: should-not-find' '---' > "$tmpdir/AGENTS.md"
    assert_eq "walk stops at repo root" \
        "$(_ghcp_detect_model "$tmpdir/repo/sub" "$tmpdir/repo")" ""
}

# ---------------------------------------------------------------------------
# _ghcp_load_denied_tools
# ---------------------------------------------------------------------------
test_load_denied_tools() {
    echo ""
    echo "--- _ghcp_load_denied_tools ---"
    local tmpdir arr=()
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' RETURN

    # Missing config file → empty array, no error
    _ghcp_load_denied_tools "$tmpdir/nonexistent.conf" arr
    assert_eq "missing file → empty array" "${arr[*]:-}" ""

    # Empty file → empty array
    : > "$tmpdir/denied-tools.conf"
    _ghcp_load_denied_tools "$tmpdir/denied-tools.conf" arr
    assert_eq "empty file → empty array" "${arr[*]:-}" ""

    # Comments and blank lines are skipped; entries produce --deny-tool pairs
    printf '%s\n' '# comment' 'tool-a' '  # indented comment' '' 'tool-b' \
        > "$tmpdir/denied-tools.conf"
    _ghcp_load_denied_tools "$tmpdir/denied-tools.conf" arr
    assert_eq "two entries → four array elements" "${#arr[@]}" "4"
    assert_eq "array contains --deny-tool pairs" \
        "${arr[*]}" "--deny-tool tool-a --deny-tool tool-b"
}

# ---------------------------------------------------------------------------
# _ghcp_setup_firewall_hook
# ---------------------------------------------------------------------------
test_setup_firewall_hook() {
    echo ""
    echo "--- _ghcp_setup_firewall_hook ---"
    local tmpdir hooks_dir
    tmpdir=$(mktemp -d)
    hooks_dir="$tmpdir/hooks.d"
    trap 'rm -rf "$tmpdir"' RETURN

    _ghcp_setup_firewall_hook "$hooks_dir"

    assert_dir_exists  "hooks directory created"   "$hooks_dir"
    assert_file_exists "policy file created"        "$hooks_dir/ghcp-firewall.json"

    local content
    content="$(cat "$hooks_dir/ghcp-firewall.json")"
    assert_contains "\$HOME substituted (not hardcoded username)" "$content" "$HOME"
    assert_contains "policy has version field"            "$content" '"version"'
    assert_contains "policy references configure-firewall.sh" "$content" 'configure-firewall.sh'
    assert_contains "policy has ghcp-firewall annotation" "$content" 'ghcp-firewall'
    assert_contains "policy has createContainer stage"    "$content" 'createContainer'

    # Idempotent: existing policy file is not overwritten
    echo "sentinel" > "$hooks_dir/ghcp-firewall.json"
    _ghcp_setup_firewall_hook "$hooks_dir"
    assert_eq "existing policy not overwritten" \
        "$(cat "$hooks_dir/ghcp-firewall.json")" "sentinel"
}

# ---------------------------------------------------------------------------
# _ghcp_help
# ---------------------------------------------------------------------------
test_help() {
    echo ""
    echo "--- _ghcp_help ---"
    local output
    output="$(_ghcp_help)"
    assert_contains "contains Usage section"           "$output" "Usage:"
    assert_contains "documents --ghcp-help"            "$output" "--ghcp-help"
    assert_contains "documents --ghcp-rebuild"         "$output" "--ghcp-rebuild"
    assert_contains "documents --ghcp-no-sessions"     "$output" "--ghcp-no-sessions"
    assert_contains "documents --ghcp-no-firewall"     "$output" "--ghcp-no-firewall"
    assert_contains "documents AGENTS.md"              "$output" "AGENTS.md"
    assert_contains "documents Session Persistence"    "$output" "Session Persistence"
    assert_contains "documents Network Isolation"      "$output" "Network Isolation"
}

# ---------------------------------------------------------------------------
# ghcp() argument parsing  (podman + gh mocked; no real container needed)
#
# podman() writes its arguments to $_GHCP_TEST_CAPTURE so tests can inspect
# exactly what would have been passed to the container runtime.
# ---------------------------------------------------------------------------

# Global used by the podman mock — local vars are not visible across function
# call boundaries so we use a predictable global instead.
_GHCP_TEST_CAPTURE=""

test_ghcp_arg_parsing() {
    echo ""
    echo "--- ghcp() argument parsing ---"
    local tmpdir
    tmpdir=$(mktemp -d)
    _GHCP_TEST_CAPTURE="$tmpdir/capture"
    trap 'rm -rf "$tmpdir"; unset -f podman gh _ghcp_build_image _ghcp_setup_firewall_hook' RETURN

    # Mock external commands so no real podman/gh/image operations occur.
    podman()                  { echo "podman $*" > "$_GHCP_TEST_CAPTURE"; }
    gh()                      { echo "mock-token"; }
    _ghcp_build_image()       { return 0; }
    _ghcp_setup_firewall_hook() { return 0; }

    local out

    # --ghcp-help: prints help and does NOT invoke podman
    ghcp --ghcp-help > "$_GHCP_TEST_CAPTURE" 2>&1
    out="$(cat "$_GHCP_TEST_CAPTURE")"
    assert_contains     "--ghcp-help prints help"            "$out" "Usage:"
    assert_not_contains "--ghcp-help does not invoke podman" "$out" "podman run"

    # Default run: firewall args and session mount both present
    ghcp 2>/dev/null; out="$(cat "$_GHCP_TEST_CAPTURE")"
    assert_contains "firewall enabled by default"        "$out" "--hooks-dir"
    assert_contains "session mount present by default"   "$out" ".copilot"

    # --ghcp-no-sessions: session mount omitted
    ghcp --ghcp-no-sessions 2>/dev/null; out="$(cat "$_GHCP_TEST_CAPTURE")"
    assert_not_contains "--ghcp-no-sessions omits session mount" "$out" ".copilot"
    assert_contains     "--ghcp-no-sessions keeps firewall"      "$out" "--hooks-dir"

    # --ghcp-no-firewall: firewall args omitted
    ghcp --ghcp-no-firewall 2>/dev/null; out="$(cat "$_GHCP_TEST_CAPTURE")"
    assert_not_contains "--ghcp-no-firewall omits --hooks-dir"   "$out" "--hooks-dir"
    assert_not_contains "--ghcp-no-firewall omits --dns"         "$out" "--dns"
    assert_contains     "--ghcp-no-firewall keeps session mount" "$out" ".copilot"

    # Arbitrary pass-through args appear verbatim in the podman call
    ghcp --continue 2>/dev/null; out="$(cat "$_GHCP_TEST_CAPTURE")"
    assert_contains "pass-through args forwarded to podman" "$out" "--continue"

    # AGENTS.md model is prepended when the user has not specified --model
    printf '%s\n' '---' 'model: claude-sonnet-4.5' '---' > "$tmpdir/AGENTS.md"
    (cd "$tmpdir" && ghcp 2>/dev/null); out="$(cat "$_GHCP_TEST_CAPTURE")"
    assert_contains "AGENTS.md model prepended to args" "$out" "--model claude-sonnet-4.5"

    # User --model (space form) suppresses AGENTS.md model
    (cd "$tmpdir" && ghcp --model my-model 2>/dev/null); out="$(cat "$_GHCP_TEST_CAPTURE")"
    assert_not_contains "user --model suppresses AGENTS.md model"  "$out" "claude-sonnet-4.5"
    assert_contains     "user --model value forwarded to podman"    "$out" "--model my-model"

    # User --model=value form also suppresses AGENTS.md model
    (cd "$tmpdir" && ghcp --model=my-model 2>/dev/null); out="$(cat "$_GHCP_TEST_CAPTURE")"
    assert_not_contains "--model=value suppresses AGENTS.md model"  "$out" "claude-sonnet-4.5"

    # --ghcp-rebuild invokes _ghcp_rebuild (not podman run)
    _ghcp_rebuild() { echo "rebuild called" > "$_GHCP_TEST_CAPTURE"; }
    ghcp --ghcp-rebuild 2>/dev/null; out="$(cat "$_GHCP_TEST_CAPTURE")"
    assert_contains     "--ghcp-rebuild calls _ghcp_rebuild"      "$out" "rebuild called"
    assert_not_contains "--ghcp-rebuild does not invoke podman run" "$out" "podman run"
    unset -f _ghcp_rebuild
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------
echo "=== ghcp tests ==="

test_detect_model
test_load_denied_tools
test_setup_firewall_hook
test_help
test_ghcp_arg_parsing

echo ""
if (( _fail == 0 )); then
    echo "=== All $_pass tests passed ==="
else
    echo "=== $_pass passed, $_fail FAILED ==="
    exit 1
fi
