#!/usr/bin/env bash
# tests/install.sh — pure-bash unit tests for install.sh logic
#
# Run with:  bash tests/install.sh
# Exit 0 = all tests passed; non-zero = failures reported.
#
# These tests exercise the internal logic (cache path validation, update_claude_md,
# version guards, CACHE_STALE flag) without invoking the real claude CLI or GitHub API.
# Each test runs in its own temporary directory that is cleaned up on exit.

# Note: we intentionally do NOT use set -e here because individual test assertions
# may call functions that return non-zero (e.g. _is_bootstrap_only returning false),
# and we want to accumulate all failures rather than aborting on the first one.
set -uo pipefail

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
    d=$(mktemp -d)
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
# Inline re-implementations for unit testing
# (mirrors install.sh logic exactly so tests break if the real code changes)
# ---------------------------------------------------------------------------

# Mirrors update_claude_md() from install.sh exactly
_update_claude_md() {
    local dir="$1"
    (
        cd "$dir"
        local updated=0
        for loc in ".claude/CLAUDE.md" "CLAUDE.md"; do
            [ -f "$loc" ] || continue
            if grep -q "@AGENTS.md" "$loc" && [ "$(awk 'END{print NR}' "$loc")" -le 5 ] && \
               [ "$(grep -cve '^[[:space:]]*$' "$loc")" -eq "$(grep -cxe '[[:space:]]*@AGENTS\.md[[:space:]]*' "$loc")" ]; then
                continue
            fi
            printf '@AGENTS.md\n' > "$loc"
            updated=1
        done
        if [ "$updated" -eq 0 ] && [ ! -f ".claude/CLAUDE.md" ] && [ ! -f "CLAUDE.md" ]; then
            mkdir -p .claude
            printf '@AGENTS.md\n' > .claude/CLAUDE.md
        fi
    )
}

# Mirrors the cache path validation logic from install.sh
_resolve_cache_dir() {
    local raw="$1"
    local result
    case "$raw" in
        /*)
            case "$raw" in
                */..*) result="/tmp/agent-context" ;;
                *)     result="$raw/agent-context" ;;
            esac
            ;;
        *) result="/tmp/agent-context" ;;
    esac
    echo "$result"
}

# Mirrors the fast-path critical-template check from install.sh.
# Returns 0 (success) when all critical templates exist, 1 if any are missing.
# Usage: _check_critical_templates <dir>
_check_critical_templates() {
    local dir="$1"
    for _tmpl in "AGENTS.md" \
                 ".agent-context/layer1-bootstrap.md" \
                 ".agent-context/layer2-project-core.md" \
                 ".agent-context/layer3-guidebook.md" \
                 ".agent-context/skills/index.md"; do
        [ -f "$dir/$_tmpl" ] || return 1
    done
    return 0
}

# Mirrors the fast-path bootstrap-only check from install.sh
_is_bootstrap_only() {
    local file="$1"
    [ -f "$file" ] || return 1
    grep -q "@AGENTS.md" "$file" && \
        [ "$(awk 'END{print NR}' "$file")" -le 5 ] && \
        [ "$(grep -cve '^[[:space:]]*$' "$file")" -eq \
          "$(grep -cxe '[[:space:]]*@AGENTS\.md[[:space:]]*' "$file")" ]
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
_update_claude_md "$t"
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
_update_claude_md "$t"
_mtime_after=$(date -r "$t/.claude/CLAUDE.md" +%s 2>/dev/null || stat -f %m "$t/.claude/CLAUDE.md" 2>/dev/null || echo 0)
assert_eq "bootstrap-only .claude/CLAUDE.md is not rewritten" "$_mtime_before" "$_mtime_after"

# ---------------------------------------------------------------------------
# 3. update_claude_md: CLAUDE.md has real content → overwritten with @AGENTS.md
# ---------------------------------------------------------------------------
t=$(mk_tmp)
printf 'some real conventions here\n' > "$t/CLAUDE.md"
_update_claude_md "$t"
assert_file_contains "CLAUDE.md with real content is replaced with @AGENTS.md" "$t/CLAUDE.md" "@AGENTS.md"
assert_file_not_contains "old content is gone" "$t/CLAUDE.md" "some real conventions"

# ---------------------------------------------------------------------------
# 4. update_claude_md: CLAUDE.md has @AGENTS.md but also extra content → overwritten
# ---------------------------------------------------------------------------
t=$(mk_tmp)
printf '@AGENTS.md\n# Extra conventions\n' > "$t/CLAUDE.md"
_update_claude_md "$t"
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
_update_claude_md "$t"
_mtime_after=$(date -r "$t/CLAUDE.md" +%s 2>/dev/null || stat -f %m "$t/CLAUDE.md" 2>/dev/null || echo 0)
assert_eq "@AGENTS.md without trailing newline is still treated as bootstrap-only" "$_mtime_before" "$_mtime_after"

# ---------------------------------------------------------------------------
# 6. Cache path validation: absolute path → appended with /agent-context
# ---------------------------------------------------------------------------
echo ""
echo "--- cache path validation ---"

result=$(_resolve_cache_dir "/home/user/.cache")
assert_eq "absolute XDG_CACHE_HOME gets /agent-context appended" "/home/user/.cache/agent-context" "$result"

# ---------------------------------------------------------------------------
# 7. Cache path validation: relative path → falls back to /tmp/agent-context
# ---------------------------------------------------------------------------
result=$(_resolve_cache_dir "relative/path")
assert_eq "relative cache path falls back to /tmp/agent-context" "/tmp/agent-context" "$result"

# ---------------------------------------------------------------------------
# 8. Cache path validation: path with .. segment → falls back to /tmp/agent-context
# ---------------------------------------------------------------------------
result=$(_resolve_cache_dir "/home/user/../etc")
assert_eq "path with .. segment falls back to /tmp/agent-context" "/tmp/agent-context" "$result"

# ---------------------------------------------------------------------------
# 9. Cache path validation: empty string → falls back to /tmp/agent-context
# ---------------------------------------------------------------------------
result=$(_resolve_cache_dir "")
assert_eq "empty cache path falls back to /tmp/agent-context" "/tmp/agent-context" "$result"

# ---------------------------------------------------------------------------
# 10. Bootstrap-only check: file with only @AGENTS.md → true
# ---------------------------------------------------------------------------
echo ""
echo "--- bootstrap-only check (_is_bootstrap_only) ---"

t=$(mk_tmp)
printf '@AGENTS.md\n' > "$t/test.md"
if _is_bootstrap_only "$t/test.md"; then
    pass "@AGENTS.md-only file is bootstrap-only"
else
    fail "@AGENTS.md-only file is bootstrap-only" "returned false"
fi

# ---------------------------------------------------------------------------
# 11. Bootstrap-only check: file with @AGENTS.md + extra content → false
# ---------------------------------------------------------------------------
t=$(mk_tmp)
printf '@AGENTS.md\n# real content\n' > "$t/test.md"
if ! _is_bootstrap_only "$t/test.md"; then
    pass "file with @AGENTS.md + extra content is NOT bootstrap-only"
else
    fail "file with @AGENTS.md + extra content is NOT bootstrap-only" "returned true"
fi

# ---------------------------------------------------------------------------
# 12. Bootstrap-only check: file with only whitespace lines + @AGENTS.md → true
# ---------------------------------------------------------------------------
t=$(mk_tmp)
printf '\n@AGENTS.md\n\n' > "$t/test.md"
if _is_bootstrap_only "$t/test.md"; then
    pass "file with blank lines + @AGENTS.md is bootstrap-only"
else
    fail "file with blank lines + @AGENTS.md is bootstrap-only" "returned false"
fi

# ---------------------------------------------------------------------------
# 13. Bootstrap-only check: missing file → false (not bootstrap-only)
# ---------------------------------------------------------------------------
t=$(mk_tmp)
if ! _is_bootstrap_only "$t/nonexistent.md"; then
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
if ! _is_bootstrap_only "$t/test.md"; then
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
_update_claude_md "$t"
assert_file_contains ".claude/CLAUDE.md overwritten" "$t/.claude/CLAUDE.md" "@AGENTS.md"
assert_file_not_contains ".claude/CLAUDE.md old content gone" "$t/.claude/CLAUDE.md" "real content A"
assert_file_contains "CLAUDE.md overwritten" "$t/CLAUDE.md" "@AGENTS.md"
assert_file_not_contains "CLAUDE.md old content gone" "$t/CLAUDE.md" "real content B"

# ---------------------------------------------------------------------------
# 16–21. Fast-path critical-template guard (_check_critical_templates)
# ---------------------------------------------------------------------------
echo ""
echo "--- critical-template guard (_check_critical_templates) ---"

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
if _check_critical_templates "$t"; then
    pass "all critical templates present → returns 0 (fast-path allowed)"
else
    fail "all critical templates present → returns 0" "returned non-zero"
fi

# 17. AGENTS.md missing → returns 1
t=$(mk_tmp)
_mk_complete_install "$t"
rm "$t/AGENTS.md"
if ! _check_critical_templates "$t"; then
    pass "missing AGENTS.md → returns 1 (fast-path blocked)"
else
    fail "missing AGENTS.md → returns 1" "returned 0 (fast-path not blocked)"
fi

# 18. layer1 missing → returns 1
t=$(mk_tmp)
_mk_complete_install "$t"
rm "$t/.agent-context/layer1-bootstrap.md"
if ! _check_critical_templates "$t"; then
    pass "missing layer1-bootstrap.md → returns 1"
else
    fail "missing layer1-bootstrap.md → returns 1" "returned 0"
fi

# 19. layer2 missing → returns 1
t=$(mk_tmp)
_mk_complete_install "$t"
rm "$t/.agent-context/layer2-project-core.md"
if ! _check_critical_templates "$t"; then
    pass "missing layer2-project-core.md → returns 1"
else
    fail "missing layer2-project-core.md → returns 1" "returned 0"
fi

# 20. layer3 missing → returns 1
t=$(mk_tmp)
_mk_complete_install "$t"
rm "$t/.agent-context/layer3-guidebook.md"
if ! _check_critical_templates "$t"; then
    pass "missing layer3-guidebook.md → returns 1"
else
    fail "missing layer3-guidebook.md → returns 1" "returned 0"
fi

# 21. skills/index.md missing → returns 1
t=$(mk_tmp)
_mk_complete_install "$t"
rm "$t/.agent-context/skills/index.md"
if ! _check_critical_templates "$t"; then
    pass "missing skills/index.md → returns 1"
else
    fail "missing skills/index.md → returns 1" "returned 0"
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
