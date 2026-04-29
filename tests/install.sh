#!/usr/bin/env bash
# tests/install.sh — pure-bash unit tests for install.sh logic
#
# Run with:  bash tests/install.sh
# Exit 0 = all tests passed; non-zero = failures reported.
#
# These tests exercise the internal logic (cache path validation, update_claude_md,
# bootstrap-only detection, critical-template guard, version string validation) without invoking the real claude CLI or GitHub API.
# Each test runs in its own temporary directory that is cleaned up on exit.
# Functions are sourced directly from install.sh — no manual re-implementations needed.

# Note: we intentionally do NOT use set -e here because individual test assertions
# may call functions that return non-zero (e.g. is_bootstrap_only returning false),
# and we want to accumulate all failures rather than aborting on the first one.
set -uo pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../install.sh"
set +e  # install.sh activates set -e; tests intentionally omit it to accumulate failures

PASS=0
FAIL=0
TMP_ROOTS=()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

cleanup() {
    for d in "${TMP_ROOTS[@]:-}"; do
        [ -d "$d" ] && rm -rf "$d"
    done
}
trap cleanup EXIT

mk_tmp() {
    local d
    d=$(mktemp -d "${TMPDIR:-/tmp}/agent-context.XXXXXX")
    TMP_ROOTS+=("$d")
    echo "$d"
}

pass() { printf "  PASS  %s\n" "$1"; PASS=$(( PASS + 1 )); }
fail() { printf "  FAIL  %s\n    => %s\n" "$1" "$2"; FAIL=$(( FAIL + 1 )); }

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        pass "$label"
    else
        fail "$label" "expected '$expected', got '$actual'"
    fi
}

assert_file_contains() {
    local label="$1" file="$2" pattern="$3"
    if grep -q "$pattern" "$file" 2>/dev/null; then
        pass "$label"
    else
        fail "$label" "pattern '$pattern' not found in $file"
    fi
}

assert_file_not_contains() {
    local label="$1" file="$2" pattern="$3"
    if grep -q "$pattern" "$file" 2>/dev/null; then
        fail "$label" "pattern '$pattern' unexpectedly found in $file"
    else
        pass "$label"
    fi
}

assert_exit_0() {
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        pass "$label"
    else
        fail "$label" "command exited non-zero: $*"
    fi
}

# ---------------------------------------------------------------------------
# TEST SUITE
# ---------------------------------------------------------------------------

echo "=== install.sh unit tests ==="
echo ""

# ---------------------------------------------------------------------------
# 1. update_claude_md: no CLAUDE.md exists → creates .claude/CLAUDE.md
# ---------------------------------------------------------------------------
echo "--- update_claude_md ---"

t=$(mk_tmp)
(cd "$t" && update_claude_md)
if [ -f "$t/.claude/CLAUDE.md" ]; then
    pass "creates .claude/CLAUDE.md when neither CLAUDE.md exists"
else
    fail "creates .claude/CLAUDE.md when neither CLAUDE.md exists" "file not created"
fi
assert_file_contains "created file has @AGENTS.md pointer" "$t/.claude/CLAUDE.md" "@AGENTS.md"

# ---------------------------------------------------------------------------
# 2. update_claude_md: .claude/CLAUDE.md already bootstrap-only → not touched
# ---------------------------------------------------------------------------
t=$(mk_tmp)
mkdir -p "$t/.claude"
printf '@AGENTS.md\n' > "$t/.claude/CLAUDE.md"
_mtime_before=$(date -r "$t/.claude/CLAUDE.md" +%s 2>/dev/null || stat -f %m "$t/.claude/CLAUDE.md" 2>/dev/null || echo 0)
sleep 1
(cd "$t" && update_claude_md)
_mtime_after=$(date -r "$t/.claude/CLAUDE.md" +%s 2>/dev/null || stat -f %m "$t/.claude/CLAUDE.md" 2>/dev/null || echo 0)
assert_eq "bootstrap-only .claude/CLAUDE.md is not rewritten" "$_mtime_before" "$_mtime_after"

# ---------------------------------------------------------------------------
# 3. update_claude_md: CLAUDE.md has real content → overwritten with @AGENTS.md
# ---------------------------------------------------------------------------
t=$(mk_tmp)
printf 'some real conventions here\n' > "$t/CLAUDE.md"
(cd "$t" && update_claude_md)
assert_file_contains "CLAUDE.md with real content is replaced with @AGENTS.md" "$t/CLAUDE.md" "@AGENTS.md"
assert_file_not_contains "old content is gone" "$t/CLAUDE.md" "some real conventions"

# ---------------------------------------------------------------------------
# 4. update_claude_md: CLAUDE.md has @AGENTS.md but also extra content → overwritten
# ---------------------------------------------------------------------------
t=$(mk_tmp)
printf '@AGENTS.md\n# Extra conventions\n' > "$t/CLAUDE.md"
(cd "$t" && update_claude_md)
content=$(cat "$t/CLAUDE.md")
assert_eq "mixed CLAUDE.md reduced to bootstrap-only" "@AGENTS.md" "$content"

# ---------------------------------------------------------------------------
# 5. update_claude_md: CLAUDE.md has exactly @AGENTS.md (no trailing newline) → not touched
#    Tests the awk 'END{print NR}' fix (wc -l would return 0 for no-trailing-newline)
# ---------------------------------------------------------------------------
t=$(mk_tmp)
printf '@AGENTS.md' > "$t/CLAUDE.md"   # no trailing newline
_mtime_before=$(date -r "$t/CLAUDE.md" +%s 2>/dev/null || stat -f %m "$t/CLAUDE.md" 2>/dev/null || echo 0)
sleep 1
(cd "$t" && update_claude_md)
_mtime_after=$(date -r "$t/CLAUDE.md" +%s 2>/dev/null || stat -f %m "$t/CLAUDE.md" 2>/dev/null || echo 0)
assert_eq "@AGENTS.md without trailing newline is still treated as bootstrap-only" "$_mtime_before" "$_mtime_after"

# ---------------------------------------------------------------------------
# 6. Cache path validation: absolute path → appended with /agent-context
# ---------------------------------------------------------------------------
echo ""
echo "--- cache path validation ---"

result=$(resolve_cache_dir "/home/user/.cache")
assert_eq "absolute XDG_CACHE_HOME gets /agent-context appended" "/home/user/.cache/agent-context" "$result"

# ---------------------------------------------------------------------------
# 7. Cache path validation: relative path → falls back to /tmp/agent-context
# ---------------------------------------------------------------------------
result=$(resolve_cache_dir "relative/path")
assert_eq "relative cache path falls back to /tmp/agent-context" "/tmp/agent-context" "$result"

# ---------------------------------------------------------------------------
# 8. Cache path validation: path with .. segment → falls back to /tmp/agent-context
# ---------------------------------------------------------------------------
result=$(resolve_cache_dir "/home/user/../etc")
assert_eq "path with .. segment falls back to /tmp/agent-context" "/tmp/agent-context" "$result"

# ---------------------------------------------------------------------------
# 9. Cache path validation: empty string → falls back to /tmp/agent-context
# ---------------------------------------------------------------------------
result=$(resolve_cache_dir "")
assert_eq "empty cache path falls back to /tmp/agent-context" "/tmp/agent-context" "$result"

# ---------------------------------------------------------------------------
# 10. Bootstrap-only check: file with only @AGENTS.md → true
# ---------------------------------------------------------------------------
echo ""
echo "--- bootstrap-only check (is_bootstrap_only) ---"

t=$(mk_tmp)
printf '@AGENTS.md\n' > "$t/test.md"
if is_bootstrap_only "$t/test.md"; then
    pass "@AGENTS.md-only file is bootstrap-only"
else
    fail "@AGENTS.md-only file is bootstrap-only" "returned false"
fi

# ---------------------------------------------------------------------------
# 11. Bootstrap-only check: file with @AGENTS.md + extra content → false
# ---------------------------------------------------------------------------
t=$(mk_tmp)
printf '@AGENTS.md\n# real content\n' > "$t/test.md"
if ! is_bootstrap_only "$t/test.md"; then
    pass "file with @AGENTS.md + extra content is NOT bootstrap-only"
else
    fail "file with @AGENTS.md + extra content is NOT bootstrap-only" "returned true"
fi

# ---------------------------------------------------------------------------
# 12. Bootstrap-only check: file with only whitespace lines + @AGENTS.md → true
# ---------------------------------------------------------------------------
t=$(mk_tmp)
printf '\n@AGENTS.md\n\n' > "$t/test.md"
if is_bootstrap_only "$t/test.md"; then
    pass "file with blank lines + @AGENTS.md is bootstrap-only"
else
    fail "file with blank lines + @AGENTS.md is bootstrap-only" "returned false"
fi

# ---------------------------------------------------------------------------
# 13. Bootstrap-only check: missing file → false (not bootstrap-only)
# ---------------------------------------------------------------------------
t=$(mk_tmp)
if ! is_bootstrap_only "$t/nonexistent.md"; then
    pass "missing file is not bootstrap-only"
else
    fail "missing file is not bootstrap-only" "returned true"
fi

# ---------------------------------------------------------------------------
# 14. Bootstrap-only check: file with 6 non-blank lines containing @AGENTS.md → false
#     (exceeds the ≤5 line guard)
# ---------------------------------------------------------------------------
t=$(mk_tmp)
printf '@AGENTS.md\n@AGENTS.md\n@AGENTS.md\n@AGENTS.md\n@AGENTS.md\n@AGENTS.md\n' > "$t/test.md"
if ! is_bootstrap_only "$t/test.md"; then
    pass "6-line @AGENTS.md-only file exceeds guard and is not bootstrap-only"
else
    fail "6-line @AGENTS.md-only file exceeds guard and is not bootstrap-only" "returned true"
fi

# ---------------------------------------------------------------------------
# 15. update_claude_md: both .claude/CLAUDE.md and CLAUDE.md exist with real content
#     → both are overwritten
# ---------------------------------------------------------------------------
echo ""
echo "--- update_claude_md (both files) ---"

t=$(mk_tmp)
mkdir -p "$t/.claude"
printf 'real content A\n' > "$t/.claude/CLAUDE.md"
printf 'real content B\n' > "$t/CLAUDE.md"
(cd "$t" && update_claude_md)
assert_file_contains ".claude/CLAUDE.md overwritten" "$t/.claude/CLAUDE.md" "@AGENTS.md"
assert_file_not_contains ".claude/CLAUDE.md old content gone" "$t/.claude/CLAUDE.md" "real content A"
assert_file_contains "CLAUDE.md overwritten" "$t/CLAUDE.md" "@AGENTS.md"
assert_file_not_contains "CLAUDE.md old content gone" "$t/CLAUDE.md" "real content B"

# ---------------------------------------------------------------------------
# 16–21. Fast-path critical-template guard (check_critical_templates)
# ---------------------------------------------------------------------------
echo ""
echo "--- critical-template guard (check_critical_templates) ---"

_mk_complete_install() {
    local dir="$1"
    mkdir -p "$dir/.agent-context/skills" "$dir/.agent-context/memory"
    touch "$dir/AGENTS.md"
    touch "$dir/.agent-context/layer1-bootstrap.md"
    touch "$dir/.agent-context/layer2-project-core.md"
    touch "$dir/.agent-context/layer3-guidebook.md"
    touch "$dir/.agent-context/skills/index.md"
}

# 16. All critical templates present → returns 0
t=$(mk_tmp)
_mk_complete_install "$t"
if (cd "$t" && check_critical_templates); then
    pass "all critical templates present → returns 0 (fast-path allowed)"
else
    fail "all critical templates present → returns 0" "returned non-zero"
fi

# 17. AGENTS.md missing → returns 1
t=$(mk_tmp)
_mk_complete_install "$t"
rm "$t/AGENTS.md"
if ! (cd "$t" && check_critical_templates); then
    pass "missing AGENTS.md → returns 1 (fast-path blocked)"
else
    fail "missing AGENTS.md → returns 1" "returned 0 (fast-path not blocked)"
fi

# 18. layer1 missing → returns 1
t=$(mk_tmp)
_mk_complete_install "$t"
rm "$t/.agent-context/layer1-bootstrap.md"
if ! (cd "$t" && check_critical_templates); then
    pass "missing layer1-bootstrap.md → returns 1"
else
    fail "missing layer1-bootstrap.md → returns 1" "returned 0"
fi

# 19. layer2 missing → returns 1
t=$(mk_tmp)
_mk_complete_install "$t"
rm "$t/.agent-context/layer2-project-core.md"
if ! (cd "$t" && check_critical_templates); then
    pass "missing layer2-project-core.md → returns 1"
else
    fail "missing layer2-project-core.md → returns 1" "returned 0"
fi

# 20. layer3 missing → returns 1
t=$(mk_tmp)
_mk_complete_install "$t"
rm "$t/.agent-context/layer3-guidebook.md"
if ! (cd "$t" && check_critical_templates); then
    pass "missing layer3-guidebook.md → returns 1"
else
    fail "missing layer3-guidebook.md → returns 1" "returned 0"
fi

# 21. skills/index.md missing → returns 1
t=$(mk_tmp)
_mk_complete_install "$t"
rm "$t/.agent-context/skills/index.md"
if ! (cd "$t" && check_critical_templates); then
    pass "missing skills/index.md → returns 1"
else
    fail "missing skills/index.md → returns 1" "returned 0"
fi

# ---------------------------------------------------------------------------
# 22–27. Version string validation (validate_version_string)
# Tests the extracted validate_version_string() function from install.sh:
#   [[ "$version" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]
# ---------------------------------------------------------------------------
echo ""
echo "--- version string validation ---"

# 22. canonical tag with v prefix
if validate_version_string "v1.2.3"; then
    pass "v1.2.3 is a valid version tag"
else
    fail "v1.2.3 is a valid version tag" "returned false"
fi

# 23. tag without v prefix
if validate_version_string "1.2.3"; then
    pass "1.2.3 (no v prefix) is a valid version tag"
else
    fail "1.2.3 (no v prefix) is a valid version tag" "returned false"
fi

# 24. two-part version rejected (previously accepted by old regex ^v?[0-9]+\.[0-9])
if ! validate_version_string "v1.2"; then
    pass "v1.2 (two-part) is rejected"
else
    fail "v1.2 (two-part) is rejected" "returned true — regex too permissive"
fi

# 25. trailing garbage rejected
if ! validate_version_string "v1.2.3abc"; then
    pass "v1.2.3abc (trailing garbage) is rejected"
else
    fail "v1.2.3abc (trailing garbage) is rejected" "returned true"
fi

# 26. empty string rejected
if ! validate_version_string ""; then
    pass "empty string is rejected"
else
    fail "empty string is rejected" "returned true"
fi

# 27. pre-release suffix rejected (pre-releases not cached; agent handles them)
if ! validate_version_string "v1.2.3-rc1"; then
    pass "v1.2.3-rc1 (pre-release) is rejected by cache regex"
else
    fail "v1.2.3-rc1 (pre-release) is rejected by cache regex" "returned true"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "================================================"
TOTAL=$(( PASS + FAIL ))
printf "Results: %d/%d passed\n" "$PASS" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then
    echo "FAILED"
    exit 1
else
    echo "ALL PASSED"
    exit 0
fi
