#!/bin/bash
# Unit tests for bash/.bashrc.d/70-claude.sh
# Run from anywhere: bash ~/.local/containers/claude/scripts/test-claude.sh

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
# shellcheck source=bash/.bashrc.d/70-claude.sh
source "$SCRIPT_DIR/bash/.bashrc.d/70-claude.sh"

# ---------------------------------------------------------------------------
# _cld_detect_model
# ---------------------------------------------------------------------------
test_detect_model() {
    echo ""
    echo "--- _cld_detect_model ---"
    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' RETURN

    # No AGENTS.md at all
    assert_eq "no AGENTS.md → empty" \
        "$(_cld_detect_model "$tmpdir" "")" ""

    # Supported model in front-matter
    printf '%s\n' '---' 'model: claude-opus-4-5' '---' > "$tmpdir/AGENTS.md"
    assert_eq "model returned from front-matter" \
        "$(_cld_detect_model "$tmpdir" "")" "claude-opus-4-5"

    # Model value with surrounding whitespace is trimmed
    printf '%s\n' '---' 'model:   claude-sonnet-4-5   ' '---' > "$tmpdir/AGENTS.md"
    assert_eq "model value trimmed" \
        "$(_cld_detect_model "$tmpdir" "")" "claude-sonnet-4-5"

    # No YAML front-matter fence → model ignored
    printf '%s\n' '# Just content' 'model: sneaky' > "$tmpdir/AGENTS.md"
    assert_eq "no front-matter → empty" \
        "$(_cld_detect_model "$tmpdir" "")" ""

    # AGENTS.md found in parent directory when missing from child
    local subdir="$tmpdir/project"
    mkdir "$subdir"
    printf '%s\n' '---' 'model: claude-opus-4-5' '---' > "$tmpdir/AGENTS.md"
    assert_eq "AGENTS.md found in parent directory" \
        "$(_cld_detect_model "$subdir" "")" "claude-opus-4-5"

    # Walk stops at repo root, does not continue to parent AGENTS.md
    mkdir -p "$tmpdir/repo/sub"
    printf '%s\n' '---' 'model: should-not-find' '---' > "$tmpdir/AGENTS.md"
    assert_eq "walk stops at repo root" \
        "$(_cld_detect_model "$tmpdir/repo/sub" "$tmpdir/repo")" ""
}

# ---------------------------------------------------------------------------
# _cld_setup_firewall_hook
# ---------------------------------------------------------------------------
test_setup_firewall_hook() {
    echo ""
    echo "--- _cld_setup_firewall_hook ---"
    local tmpdir hooks_dir
    tmpdir=$(mktemp -d)
    hooks_dir="$tmpdir/hooks.d"
    trap 'rm -rf "$tmpdir"' RETURN

    _cld_setup_firewall_hook "$hooks_dir"

    assert_dir_exists  "hooks directory created"   "$hooks_dir"
    assert_file_exists "policy file created"        "$hooks_dir/cld-firewall.json"

    local content
    content="$(cat "$hooks_dir/cld-firewall.json")"
    assert_contains "\$HOME substituted (not hardcoded username)" "$content" "$HOME"
    assert_contains "policy has version field"                    "$content" '"version"'
    assert_contains "policy references configure-firewall.sh"    "$content" 'configure-firewall.sh'
    assert_contains "policy has cld-firewall annotation"         "$content" 'cld-firewall'
    assert_contains "policy has createContainer stage"           "$content" 'createContainer'

    # Idempotent: existing policy file is not overwritten
    echo "sentinel" > "$hooks_dir/cld-firewall.json"
    _cld_setup_firewall_hook "$hooks_dir"
    assert_eq "existing policy not overwritten" \
        "$(cat "$hooks_dir/cld-firewall.json")" "sentinel"
}

# ---------------------------------------------------------------------------
# _cld_help
# ---------------------------------------------------------------------------
test_help() {
    echo ""
    echo "--- _cld_help ---"
    local output
    output="$(_cld_help)"
    assert_contains "contains Usage section"        "$output" "Usage:"
    assert_contains "documents --cld-help"          "$output" "--cld-help"
    assert_contains "documents --cld-rebuild"       "$output" "--cld-rebuild"
    assert_contains "documents --cld-no-sessions"   "$output" "--cld-no-sessions"
    assert_contains "documents --cld-no-firewall"   "$output" "--cld-no-firewall"
    assert_contains "documents AGENTS.md"           "$output" "AGENTS.md"
    assert_contains "documents Session Persistence" "$output" "Session Persistence"
    assert_contains "documents Network Isolation"   "$output" "Network Isolation"
    assert_contains "documents Authentication"      "$output" "Authentication"
}

# ---------------------------------------------------------------------------
# _cld_get_oauth_token
# ---------------------------------------------------------------------------
test_get_oauth_token() {
    echo ""
    echo "--- _cld_get_oauth_token ---"
    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' RETURN

    local creds_dir="$tmpdir/.claude"
    local creds_file="$creds_dir/.credentials.json"
    mkdir -p "$creds_dir"

    # No credentials file → empty output
    assert_eq "no credentials file → empty" \
        "$(_cld_get_oauth_token)" ""

    # Valid credentials file → access token returned
    printf '{"claudeAiOauth":{"accessToken":"sk-ant-oat-abc123","refreshToken":"rt","expiresAt":9999999999000,"scopes":["user:inference"]}}\n' \
        > "$creds_file"
    assert_eq "access token extracted from credentials" \
        "$(_cld_get_oauth_token "$creds_file")" "sk-ant-oat-abc123"

    # No claudeAiOauth key → empty output
    printf '{"someOtherKey":{"accessToken":"other"}}\n' > "$creds_file"
    assert_eq "missing claudeAiOauth key → empty" \
        "$(_cld_get_oauth_token "$creds_file")" ""

    # Malformed JSON → empty output (no error)
    printf 'not-valid-json\n' > "$creds_file"
    assert_eq "malformed JSON → empty" \
        "$(_cld_get_oauth_token "$creds_file")" ""

    local old_home="$HOME"
    HOME="$old_home"
}

# ---------------------------------------------------------------------------
# cld() argument parsing  (podman + git mocked; no real container needed)
#
# podman() writes its arguments to $_CLD_TEST_CAPTURE so tests can inspect
# exactly what would have been passed to the container runtime.
# ---------------------------------------------------------------------------

# Global used by the podman mock — local vars are not visible across function
# call boundaries so we use a predictable global instead.
_CLD_TEST_CAPTURE=""

test_cld_arg_parsing() {
    echo ""
    echo "--- cld() argument parsing ---"
    local tmpdir
    tmpdir=$(mktemp -d)
    _CLD_TEST_CAPTURE="$tmpdir/capture"
    trap 'rm -rf "$tmpdir"; unset -f podman git _cld_build_image _cld_setup_firewall_hook _cld_get_oauth_token' RETURN

    # Mock external commands so no real podman/git/image operations occur.
    podman()                  { echo "podman $*" > "$_CLD_TEST_CAPTURE"; }
    git()                     { return 1; }
    _cld_build_image()        { return 0; }
    _cld_setup_firewall_hook() { return 0; }

    # Ensure API key warning doesn't interfere — set a dummy key
    local old_key="${ANTHROPIC_API_KEY:-}"
    ANTHROPIC_API_KEY="sk-ant-test"

    local out

    # --cld-help: prints help and does NOT invoke podman
    cld --cld-help > "$_CLD_TEST_CAPTURE" 2>&1
    out="$(cat "$_CLD_TEST_CAPTURE")"
    assert_contains     "--cld-help prints help"            "$out" "Usage:"
    assert_not_contains "--cld-help does not invoke podman" "$out" "podman run"

    # Default run: firewall args and session mount both present
    cld 2>/dev/null; out="$(cat "$_CLD_TEST_CAPTURE")"
    assert_contains "firewall enabled by default"           "$out" "--hooks-dir"
    assert_contains "session mount present by default"      "$out" ".claude"
    assert_contains "ANTHROPIC_API_KEY passed to container" "$out" "ANTHROPIC_API_KEY"

    # --cld-no-sessions: session mount omitted
    cld --cld-no-sessions 2>/dev/null; out="$(cat "$_CLD_TEST_CAPTURE")"
    assert_not_contains "--cld-no-sessions omits session mount" "$out" ".claude:/root/.claude"
    assert_contains     "--cld-no-sessions keeps firewall"      "$out" "--hooks-dir"

    # --cld-no-firewall: firewall args omitted
    cld --cld-no-firewall 2>/dev/null; out="$(cat "$_CLD_TEST_CAPTURE")"
    assert_not_contains "--cld-no-firewall omits --hooks-dir"   "$out" "--hooks-dir"
    assert_not_contains "--cld-no-firewall omits --dns"         "$out" "--dns"
    assert_contains     "--cld-no-firewall keeps session mount" "$out" ".claude"

    # Arbitrary pass-through args appear verbatim in the podman call
    cld "fix the tests" 2>/dev/null; out="$(cat "$_CLD_TEST_CAPTURE")"
    assert_contains "pass-through args forwarded to podman" "$out" "fix the tests"

    # AGENTS.md model is prepended when the user has not specified --model
    printf '%s\n' '---' 'model: claude-opus-4-5' '---' > "$tmpdir/AGENTS.md"
    (cd "$tmpdir" && cld 2>/dev/null); out="$(cat "$_CLD_TEST_CAPTURE")"
    assert_contains "AGENTS.md model prepended to args" "$out" "--model claude-opus-4-5"

    # User --model (space form) suppresses AGENTS.md model
    (cd "$tmpdir" && cld --model my-model 2>/dev/null); out="$(cat "$_CLD_TEST_CAPTURE")"
    assert_not_contains "user --model suppresses AGENTS.md model" "$out" "claude-opus-4-5"
    assert_contains     "user --model value forwarded to podman"   "$out" "--model my-model"

    # User --model=value form also suppresses AGENTS.md model
    (cd "$tmpdir" && cld --model=my-model 2>/dev/null); out="$(cat "$_CLD_TEST_CAPTURE")"
    assert_not_contains "--model=value suppresses AGENTS.md model" "$out" "claude-opus-4-5"

    # User -m (short form) also suppresses AGENTS.md model
    (cd "$tmpdir" && cld -m my-model 2>/dev/null); out="$(cat "$_CLD_TEST_CAPTURE")"
    assert_not_contains "-m suppresses AGENTS.md model" "$out" "claude-opus-4-5"
    assert_contains     "-m value forwarded to podman"   "$out" "-m my-model"

    # --cld-rebuild invokes _cld_rebuild (not podman run)
    _cld_rebuild() { echo "rebuild called" > "$_CLD_TEST_CAPTURE"; }
    cld --cld-rebuild 2>/dev/null; out="$(cat "$_CLD_TEST_CAPTURE")"
    assert_contains     "--cld-rebuild calls _cld_rebuild"          "$out" "rebuild called"
    assert_not_contains "--cld-rebuild does not invoke podman run"  "$out" "podman run"
    unset -f _cld_rebuild

    # --cld-update is an alias for --cld-rebuild
    _cld_rebuild() { echo "rebuild called" > "$_CLD_TEST_CAPTURE"; }
    cld --cld-update 2>/dev/null; out="$(cat "$_CLD_TEST_CAPTURE")"
    assert_contains "--cld-update calls _cld_rebuild" "$out" "rebuild called"
    unset -f _cld_rebuild

    # OAuth token from credentials file is passed as CLAUDE_CODE_OAUTH_TOKEN
    # when ANTHROPIC_API_KEY is unset. Mock _cld_get_oauth_token to return a
    # test token (actual JSON parsing is tested in test_get_oauth_token).
    ANTHROPIC_API_KEY=""
    _cld_get_oauth_token() { echo "sk-ant-oat-test"; }
    cld 2>/dev/null; out="$(cat "$_CLD_TEST_CAPTURE")"
    assert_contains     "OAuth token passed as CLAUDE_CODE_OAUTH_TOKEN" "$out" "CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat-test"
    assert_not_contains "ANTHROPIC_API_KEY not set when using OAuth"    "$out" "ANTHROPIC_API_KEY=sk-ant"

    # Warning printed when neither ANTHROPIC_API_KEY nor OAuth token available
    _cld_get_oauth_token() { return 0; }
    cld 2>"$tmpdir/stderr"; out="$(cat "$tmpdir/stderr")"
    assert_contains "warns when no auth available" "$out" "No authentication found"
    unset -f _cld_get_oauth_token

    # Restore
    ANTHROPIC_API_KEY="$old_key"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------
echo "=== cld tests ==="

test_detect_model
test_setup_firewall_hook
test_help
test_get_oauth_token
test_cld_arg_parsing

echo ""
if (( _fail == 0 )); then
    echo "=== All $_pass tests passed ==="
else
    echo "=== $_pass passed, $_fail FAILED ==="
    exit 1
fi
