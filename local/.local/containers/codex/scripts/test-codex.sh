#!/bin/bash
# Unit tests for bash/.bashrc.d/60-codex.sh
# Run from anywhere: bash ~/.local/containers/codex/scripts/test-codex.sh

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
# shellcheck source=bash/.bashrc.d/60-codex.sh
source "$SCRIPT_DIR/bash/.bashrc.d/60-codex.sh"

# ---------------------------------------------------------------------------
# _cx_detect_model
# ---------------------------------------------------------------------------
test_detect_model() {
    echo ""
    echo "--- _cx_detect_model ---"
    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' RETURN

    # No AGENTS.md at all
    assert_eq "no AGENTS.md → empty" \
        "$(_cx_detect_model "$tmpdir" "")" ""

    # Supported model in front-matter
    printf '%s\n' '---' 'model: gpt-5-codex' '---' > "$tmpdir/AGENTS.md"
    assert_eq "model returned from front-matter" \
        "$(_cx_detect_model "$tmpdir" "")" "gpt-5-codex"

    # Model value with surrounding whitespace is trimmed
    printf '%s\n' '---' 'model:   gpt-5.2   ' '---' > "$tmpdir/AGENTS.md"
    assert_eq "model value trimmed" \
        "$(_cx_detect_model "$tmpdir" "")" "gpt-5.2"

    # No YAML front-matter fence → model ignored
    printf '%s\n' '# Just content' 'model: sneaky' > "$tmpdir/AGENTS.md"
    assert_eq "no front-matter → empty" \
        "$(_cx_detect_model "$tmpdir" "")" ""

    # AGENTS.md found in parent directory when missing from child
    local subdir="$tmpdir/project"
    mkdir "$subdir"
    printf '%s\n' '---' 'model: gpt-5' '---' > "$tmpdir/AGENTS.md"
    assert_eq "AGENTS.md found in parent directory" \
        "$(_cx_detect_model "$subdir" "")" "gpt-5"

    # Walk stops at repo root, does not continue to parent AGENTS.md
    mkdir -p "$tmpdir/repo/sub"
    printf '%s\n' '---' 'model: should-not-find' '---' > "$tmpdir/AGENTS.md"
    assert_eq "walk stops at repo root" \
        "$(_cx_detect_model "$tmpdir/repo/sub" "$tmpdir/repo")" ""
}

# ---------------------------------------------------------------------------
# _cx_setup_firewall_hook
# ---------------------------------------------------------------------------
test_setup_firewall_hook() {
    echo ""
    echo "--- _cx_setup_firewall_hook ---"
    local tmpdir hooks_dir
    tmpdir=$(mktemp -d)
    hooks_dir="$tmpdir/hooks.d"
    trap 'rm -rf "$tmpdir"' RETURN

    _cx_setup_firewall_hook "$hooks_dir"

    assert_dir_exists  "hooks directory created"   "$hooks_dir"
    assert_file_exists "policy file created"        "$hooks_dir/cx-firewall.json"

    local content
    content="$(cat "$hooks_dir/cx-firewall.json")"
    assert_contains "\$HOME substituted (not hardcoded username)" "$content" "$HOME"
    assert_contains "policy has version field"                    "$content" '"version"'
    assert_contains "policy references configure-firewall.sh"    "$content" 'configure-firewall.sh'
    assert_contains "policy has cx-firewall annotation"          "$content" 'cx-firewall'
    assert_contains "policy has createContainer stage"           "$content" 'createContainer'

    # Idempotent: existing policy file is not overwritten
    echo "sentinel" > "$hooks_dir/cx-firewall.json"
    _cx_setup_firewall_hook "$hooks_dir"
    assert_eq "existing policy not overwritten" \
        "$(cat "$hooks_dir/cx-firewall.json")" "sentinel"
}

# ---------------------------------------------------------------------------
# _cx_help
# ---------------------------------------------------------------------------
test_help() {
    echo ""
    echo "--- _cx_help ---"
    local output
    output="$(_cx_help)"
    assert_contains "contains Usage section"        "$output" "Usage:"
    assert_contains "documents --cx-help"           "$output" "--cx-help"
    assert_contains "documents --cx-rebuild"        "$output" "--cx-rebuild"
    assert_contains "documents --cx-no-sessions"    "$output" "--cx-no-sessions"
    assert_contains "documents --cx-no-firewall"    "$output" "--cx-no-firewall"
    assert_contains "documents AGENTS.md"           "$output" "AGENTS.md"
    assert_contains "documents Session Persistence" "$output" "Session Persistence"
    assert_contains "documents Network Isolation"   "$output" "Network Isolation"
    assert_contains "documents Authentication"      "$output" "Authentication"
}

# ---------------------------------------------------------------------------
# cx() argument parsing  (podman + git mocked; no real container needed)
#
# podman() writes its arguments to $_CX_TEST_CAPTURE so tests can inspect
# exactly what would have been passed to the container runtime.
# ---------------------------------------------------------------------------

# Global used by the podman mock — local vars are not visible across function
# call boundaries so we use a predictable global instead.
_CX_TEST_CAPTURE=""

test_cx_arg_parsing() {
    echo ""
    echo "--- cx() argument parsing ---"
    local tmpdir
    tmpdir=$(mktemp -d)
    _CX_TEST_CAPTURE="$tmpdir/capture"
    trap 'rm -rf "$tmpdir"; unset -f podman git _cx_build_image _cx_setup_firewall_hook' RETURN

    # Mock external commands so no real podman/git/image operations occur.
    podman()                  { echo "podman $*" > "$_CX_TEST_CAPTURE"; }
    git()                     { return 1; }
    _cx_build_image()         { return 0; }
    _cx_setup_firewall_hook() { return 0; }

    # Ensure API key warning doesn't interfere — set a dummy key
    local old_key="${OPENAI_API_KEY:-}"
    OPENAI_API_KEY="sk-test"

    local out

    # --cx-help: prints help and does NOT invoke podman
    cx --cx-help > "$_CX_TEST_CAPTURE" 2>&1
    out="$(cat "$_CX_TEST_CAPTURE")"
    assert_contains     "--cx-help prints help"            "$out" "Usage:"
    assert_not_contains "--cx-help does not invoke podman" "$out" "podman run"

    # Default run: firewall args and session mount both present
    cx 2>/dev/null; out="$(cat "$_CX_TEST_CAPTURE")"
    assert_contains "firewall enabled by default"        "$out" "--hooks-dir"
    assert_contains "session mount present by default"   "$out" ".codex"
    assert_contains "OPENAI_API_KEY passed to container" "$out" "OPENAI_API_KEY"

    # --cx-no-sessions: session mount omitted
    cx --cx-no-sessions 2>/dev/null; out="$(cat "$_CX_TEST_CAPTURE")"
    assert_not_contains "--cx-no-sessions omits session mount" "$out" ".codex:/root/.codex"
    assert_contains     "--cx-no-sessions keeps firewall"      "$out" "--hooks-dir"

    # --cx-no-firewall: firewall args omitted
    cx --cx-no-firewall 2>/dev/null; out="$(cat "$_CX_TEST_CAPTURE")"
    assert_not_contains "--cx-no-firewall omits --hooks-dir" "$out" "--hooks-dir"
    assert_not_contains "--cx-no-firewall omits --dns"       "$out" "--dns"
    assert_contains     "--cx-no-firewall keeps session mount" "$out" ".codex"

    # Arbitrary pass-through args appear verbatim in the podman call
    cx exec "fix the tests" 2>/dev/null; out="$(cat "$_CX_TEST_CAPTURE")"
    assert_contains "pass-through args forwarded to podman" "$out" "exec"

    # AGENTS.md model is prepended when the user has not specified --model
    printf '%s\n' '---' 'model: gpt-5-codex' '---' > "$tmpdir/AGENTS.md"
    (cd "$tmpdir" && cx 2>/dev/null); out="$(cat "$_CX_TEST_CAPTURE")"
    assert_contains "AGENTS.md model prepended to args" "$out" "--model gpt-5-codex"

    # User --model (space form) suppresses AGENTS.md model
    (cd "$tmpdir" && cx --model my-model 2>/dev/null); out="$(cat "$_CX_TEST_CAPTURE")"
    assert_not_contains "user --model suppresses AGENTS.md model" "$out" "gpt-5-codex"
    assert_contains     "user --model value forwarded to podman"   "$out" "--model my-model"

    # User --model=value form also suppresses AGENTS.md model
    (cd "$tmpdir" && cx --model=my-model 2>/dev/null); out="$(cat "$_CX_TEST_CAPTURE")"
    assert_not_contains "--model=value suppresses AGENTS.md model" "$out" "gpt-5-codex"

    # User -m (short form) also suppresses AGENTS.md model
    (cd "$tmpdir" && cx -m my-model 2>/dev/null); out="$(cat "$_CX_TEST_CAPTURE")"
    assert_not_contains "-m suppresses AGENTS.md model" "$out" "gpt-5-codex"
    assert_contains     "-m value forwarded to podman"   "$out" "-m my-model"

    # --cx-rebuild invokes _cx_rebuild (not podman run)
    _cx_rebuild() { echo "rebuild called" > "$_CX_TEST_CAPTURE"; }
    cx --cx-rebuild 2>/dev/null; out="$(cat "$_CX_TEST_CAPTURE")"
    assert_contains     "--cx-rebuild calls _cx_rebuild"          "$out" "rebuild called"
    assert_not_contains "--cx-rebuild does not invoke podman run" "$out" "podman run"
    unset -f _cx_rebuild

    # --cx-update is an alias for --cx-rebuild
    _cx_rebuild() { echo "rebuild called" > "$_CX_TEST_CAPTURE"; }
    cx --cx-update 2>/dev/null; out="$(cat "$_CX_TEST_CAPTURE")"
    assert_contains "--cx-update calls _cx_rebuild" "$out" "rebuild called"
    unset -f _cx_rebuild

    # API key warning printed when OPENAI_API_KEY is unset
    OPENAI_API_KEY=""
    cx 2>"$tmpdir/stderr"; out="$(cat "$tmpdir/stderr")"
    assert_contains "warns when OPENAI_API_KEY unset" "$out" "OPENAI_API_KEY"

    # Restore API key
    OPENAI_API_KEY="$old_key"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------
echo "=== cx tests ==="

test_detect_model
test_setup_firewall_hook
test_help
test_cx_arg_parsing

echo ""
if (( _fail == 0 )); then
    echo "=== All $_pass tests passed ==="
else
    echo "=== $_pass passed, $_fail FAILED ==="
    exit 1
fi
