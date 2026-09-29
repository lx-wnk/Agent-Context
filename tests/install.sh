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

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

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
assert_eq "created .claude/CLAUDE.md points one level up" "@../AGENTS.md" "$(cat "$t/.claude/CLAUDE.md")"

# ---------------------------------------------------------------------------
# 2. update_claude_md: .claude/CLAUDE.md already bootstrap-only → not touched
# ---------------------------------------------------------------------------
t=$(mk_tmp)
mkdir -p "$t/.claude"
printf '@AGENTS.md\n' > "$t/.claude/CLAUDE.md"
cp "$t/.claude/CLAUDE.md" "$t/.claude/CLAUDE.md.orig"
(cd "$t" && update_claude_md)
if cmp -s "$t/.claude/CLAUDE.md" "$t/.claude/CLAUDE.md.orig"; then
    pass "bootstrap-only .claude/CLAUDE.md is not rewritten"
else
    fail "bootstrap-only .claude/CLAUDE.md is not rewritten" "content changed"
fi

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
cp "$t/CLAUDE.md" "$t/CLAUDE.md.orig"
(cd "$t" && update_claude_md)
if cmp -s "$t/CLAUDE.md" "$t/CLAUDE.md.orig"; then
    pass "@AGENTS.md without trailing newline is still treated as bootstrap-only"
else
    fail "@AGENTS.md without trailing newline is still treated as bootstrap-only" "content changed"
fi

# ---------------------------------------------------------------------------
# 6. Cache path validation: absolute path → appended with /agent-context
# ---------------------------------------------------------------------------
echo ""
echo "--- cache path validation ---"

result=$(resolve_cache_dir "/home/user/.cache")
assert_eq "absolute XDG_CACHE_HOME gets /agent-context appended" "/home/user/.cache/agent-context" "$result"

# ---------------------------------------------------------------------------
# 7-9. Cache path validation: relative, .. segment or empty → no cache (never a shared /tmp dir)
# ---------------------------------------------------------------------------
assert_eq "relative cache path disables the cache" "" "$(resolve_cache_dir "relative/path")"
assert_eq "path with .. segment disables the cache" "" "$(resolve_cache_dir "/home/user/../etc")"
assert_eq "empty cache path disables the cache" "" "$(resolve_cache_dir "")"


# CACHE_DIR default: XDG_CACHE_HOME wins, HOME/.cache is the fallback.
INSTALL_SH="$(dirname "${BASH_SOURCE[0]}")/../install.sh"
# shellcheck disable=SC2016  # $1 expands inside the child bash, not here
assert_eq "CACHE_DIR follows XDG_CACHE_HOME" "/xdg/agent-context" \
    "$(XDG_CACHE_HOME=/xdg bash -c 'source "$1"; echo "$CACHE_DIR"' _ "$INSTALL_SH")"
# shellcheck disable=SC2016
assert_eq "CACHE_DIR falls back to HOME/.cache" "/home/u/.cache/agent-context" \
    "$(env -u XDG_CACHE_HOME HOME=/home/u bash -c 'source "$1"; echo "$CACHE_DIR"' _ "$INSTALL_SH")"
# shellcheck disable=SC2016
assert_eq "no XDG_CACHE_HOME and no HOME: no cache" "" \
    "$(env -u XDG_CACHE_HOME -u HOME bash -c 'source "$1"; echo "$CACHE_DIR"' _ "$INSTALL_SH")"

# get_latest_version: the cache dir is private and a cached value is validated before use.
t=$(mk_tmp)
(
    CACHE_DIR="$t/cache" CACHE_FILE="$t/cache/latest-version"
    curl() { echo '{"tag_name": "2.0.0"}'; }
    get_latest_version
    assert_eq "fresh lookup returns the API tag" "2.0.0" "$LATEST_VERSION"
    assert_eq "cache dir is created mode 700" "drwx------" "$(ls -ld "$CACHE_DIR" | cut -c1-10)"
    printf '1.0.0;evil\n' > "$CACHE_FILE"
    get_latest_version
    assert_eq "an invalid fresh cache value is ignored" "2.0.0" "$LATEST_VERSION"
    curl() { return 22; }
    printf '1.0.0;evil\n' > "$CACHE_FILE"
    touch -t 200001010000 "$CACHE_FILE"
    get_latest_version 2>/dev/null
    assert_eq "an invalid stale cache value is ignored" "" "$LATEST_VERSION"
    CACHE_DIR="" CACHE_FILE=""
    curl() { echo '{"tag_name": "3.0.0"}'; }
    get_latest_version
    assert_eq "no cache dir: the lookup still works" "3.0.0" "$LATEST_VERSION"
    printf '%s\n' "$PASS $FAIL" > "$t/counts"
)
read -r PASS FAIL < "$t/counts"

# new_session_id: only a v4 UUID is used (lowercased); anything else yields no session id.
assert_eq "v4 UUID is lowercased" "abcdef01-2345-4678-89ab-0123456789ab" \
    "$(uuidgen() { echo ABCDEF01-2345-4678-89AB-0123456789AB; }; new_session_id)"
assert_eq "non-UUID yields no session id" "" "$(uuidgen() { echo unknown; }; new_session_id)"
assert_eq "non-v4 UUID yields no session id" "" \
    "$(uuidgen() { echo 12345678-1234-1234-1234-123456789012; }; new_session_id)"
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
assert_eq ".claude/CLAUDE.md overwritten with the importer-relative pointer" "@../AGENTS.md" "$(cat "$t/.claude/CLAUDE.md")"
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
    touch "$dir/.agent-context/knowledge-map.md"
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

t=$(mk_tmp)
_mk_complete_install "$t"
rm "$t/.agent-context/knowledge-map.md"
if ! (cd "$t" && check_critical_templates); then
    pass "missing knowledge-map.md → returns 1"
else
    fail "missing knowledge-map.md → returns 1" "returned 0"
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
# update_claude_md never writes through a symlink (CLAUDE.md -> AGENTS.md is a common setup)
# ---------------------------------------------------------------------------
t=$(mk_tmp)
printf '# Agents\nreal rules\n' > "$t/AGENTS.md"
ln -s AGENTS.md "$t/CLAUDE.md"
out="$(cd "$t" && update_claude_md)"
assert_eq "symlinked CLAUDE.md does not overwrite its target" "$(printf '# Agents\nreal rules')" "$(cat "$t/AGENTS.md")"
assert_eq "symlinked CLAUDE.md stays a symlink" "AGENTS.md" "$(readlink "$t/CLAUDE.md")"
case "$out" in *"symlink"*) pass "skipped symlink is reported" ;; *) fail "skipped symlink is reported" "output: $out" ;; esac

# ---------------------------------------------------------------------------
# hooks.local.conf: ignored by git, and committed executable hook keys are flagged
# ---------------------------------------------------------------------------
t=$(mk_tmp)
mkdir -p "$t/.agent-context"
printf 'node_modules/\n' > "$t/.gitignore"
(cd "$t" && ensure_hooks_local_conf_ignored >/dev/null)
(cd "$t" && ensure_hooks_local_conf_ignored >/dev/null)
assert_eq "hooks.local.conf is ignored exactly once" "1" "$(grep -cxF '/.agent-context/hooks.local.conf' "$t/.gitignore")"
assert_eq "existing .gitignore lines are kept" "node_modules/" "$(head -1 "$t/.gitignore")"

t=$(mk_tmp)
(cd "$t" && ensure_hooks_local_conf_ignored >/dev/null)
[ -e "$t/.gitignore" ] && fail "no .gitignore written without an install" "created" || pass "no .gitignore written without an install"

t=$(mk_tmp)
mkdir -p "$t/.agent-context"
printf 'HOOKS_ENABLED=1\nTEST_CMD="npm test"\n' > "$t/.agent-context/hooks.conf"
out="$(cd "$t" && warn_committed_hook_keys 2>&1)"
case "$out" in *hooks.local.conf*) pass "committed executable hook keys are flagged" ;; *) fail "committed hook keys flagged" "output: $out" ;; esac
printf 'HOOKS_ENABLED=1\n' > "$t/.agent-context/hooks.local.conf"
out="$(cd "$t" && warn_committed_hook_keys 2>&1)"
assert_eq "no warning once hooks.local.conf exists" "" "$out"
t=$(mk_tmp)
mkdir -p "$t/.agent-context"
printf 'HOOKS_ENABLED=0\nTEST_CMD=""\nFORMAT_CMD=""\n' > "$t/.agent-context/hooks.conf"
assert_eq "no warning for the shipped defaults" "" "$(cd "$t" && warn_committed_hook_keys 2>&1)"

# ---------------------------------------------------------------------------
# Claude Code resolves @imports relative to the importing file
# ---------------------------------------------------------------------------
echo ""
echo "--- importer-relative pointers + migration ---"

t=$(mk_tmp)
printf '@../AGENTS.md\n' > "$t/test.md"
if is_bootstrap_only "$t/test.md"; then
    pass "@../AGENTS.md-only file is bootstrap-only"
else
    fail "@../AGENTS.md-only file is bootstrap-only" "returned false"
fi

t=$(mk_tmp)
mkdir -p "$t/.claude" "$t/.agent-context"
printf '# Project Instructions\n\n@AGENTS.md\n' > "$t/.claude/CLAUDE.md"
printf '@AGENTS.md\n' > "$t/CLAUDE.md"
printf '## Principles\n\n@.agent-context/base-principles.md\n\n@docs/custom.md\n' > "$t/.agent-context/layer2-project-core.md"
printf '@.agent-context/knowledge-map.md\r\n\n@.agent-context/skills/index.md\n' > "$t/.agent-context/layer3-guidebook.md"
(cd "$t" && migrate_import_paths >/dev/null)
assert_eq ".claude/CLAUDE.md pointer migrated, heading kept" "$(printf '# Project Instructions\n\n@../AGENTS.md')" "$(cat "$t/.claude/CLAUDE.md")"
assert_eq "root CLAUDE.md pointer left alone" "@AGENTS.md" "$(cat "$t/CLAUDE.md")"
assert_eq "layer2 default import migrated, custom import kept" \
    "$(printf '## Principles\n\n@base-principles.md\n\n@docs/custom.md')" "$(cat "$t/.agent-context/layer2-project-core.md")"
assert_eq "layer3 imports migrated, CRLF preserved" \
    "$(printf '@knowledge-map.md\r\n\n@skills/index.md')" "$(cat "$t/.agent-context/layer3-guidebook.md")"
before="$(cat "$t/.claude/CLAUDE.md" "$t/.agent-context/"*.md)"
out="$(cd "$t" && migrate_import_paths)"
assert_eq "migration is idempotent" "$before" "$(cat "$t/.claude/CLAUDE.md" "$t/.agent-context/"*.md)"
assert_eq "second run reports nothing" "" "$out"

t=$(mk_tmp)
mkdir -p "$t/.agent-context"
# shellcheck disable=SC2016  # the backticks are literal test input, not a command substitution
printf '%s\n' '> Shared base: @.agent-context/base-principles.md' \
    'See `@.agent-context/x.md` in code.' '```' '@.agent-context/fenced.md' '```' \
    'mail@.agent-context/not-an-import' '- (@.agent-context/skills/a.md) and @.agent-context/b.md' \
    > "$t/.agent-context/layer2-project-core.md"
(cd "$t" && migrate_import_paths >/dev/null)
# shellcheck disable=SC2016  # literal backticks, see above
assert_eq "inline and non-default nested imports migrated; code, fences and non-imports kept" \
    "$(printf '%s\n' '> Shared base: @base-principles.md' 'See `@.agent-context/x.md` in code.' '```' \
        '@.agent-context/fenced.md' '```' 'mail@.agent-context/not-an-import' '- (@skills/a.md) and @b.md')" \
    "$(cat "$t/.agent-context/layer2-project-core.md")"

t=$(mk_tmp)
mkdir -p "$t/.agent-context" "$t/elsewhere"
printf '@.agent-context/base-principles.md\n' > "$t/elsewhere/layer2.md"
ln -s "$t/elsewhere/layer2.md" "$t/.agent-context/layer2-project-core.md"
(cd "$t" && migrate_import_paths >/dev/null)
assert_eq "symlinked layer file is not written through" "@.agent-context/base-principles.md" "$(cat "$t/elsewhere/layer2.md")"

# ---------------------------------------------------------------------------
# resolve_release_url: only a valid release tag resolves; no fallback to a mutable branch
# ---------------------------------------------------------------------------
ARCHIVE="https://github.com/lx-wnk/Agent-Context/archive/refs/tags"
assert_eq "resolve_release_url pins a release tag" "$ARCHIVE/0.9.0.tar.gz" "$(resolve_release_url "0.9.0")"
assert_eq "resolve_release_url keeps a v-prefixed tag" "$ARCHIVE/v1.2.3.tar.gz" "$(resolve_release_url "v1.2.3")"
resolve_release_url "" >/dev/null && fail "resolve_release_url rejects a failed lookup" "resolved" \
    || pass "resolve_release_url rejects a failed lookup"
resolve_release_url "../evil" >/dev/null && fail "resolve_release_url rejects a malformed version" "resolved" \
    || pass "resolve_release_url rejects a malformed version"

# ---------------------------------------------------------------------------
# changelog_version: first released heading, [Unreleased] skipped
# ---------------------------------------------------------------------------
t=$(mk_tmp)
printf '# Changelog\n\n## [Unreleased]\n\n## [1.4.2] - 2026-01-01\n\n## [1.4.1] - 2025-12-01\n' > "$t/CHANGELOG.md"
assert_eq "changelog_version skips [Unreleased]" "1.4.2" "$(changelog_version "$t")"
t=$(mk_tmp)
printf '## [Unreleased]\n' > "$t/CHANGELOG.md"
assert_eq "changelog_version is empty without a release" "" "$(changelog_version "$t")"

# ---------------------------------------------------------------------------
# register_hooks without jq or python3: warn, leave settings.json alone, do not fail the install
# ---------------------------------------------------------------------------
t=$(mk_tmp)
mkdir -p "$t/root/templates/.claude" "$t/proj/.claude" "$t/bin"
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"x/stop-test-gate.sh"}]}]}}\n' > "$t/root/templates/.claude/settings.json"
printf '{"permissions":{}}\n' > "$t/proj/.claude/settings.json"
for c in mkdir cp grep mktemp cat rm; do ln -s "$(command -v "$c")" "$t/bin/$c"; done
out="$(cd "$t/proj" && PATH="$t/bin" register_hooks "$t/root" 2>&1; echo "rc=$? unverifiable=${HOOKS_UNVERIFIABLE:-0}")"
case "$out" in *"by hand"*"rc=0 unverifiable=1"*) pass "no jq/python3: hook merge skipped with a hint, install not failed" ;;
    *) fail "no jq/python3 hook merge" "output: $out" ;; esac
assert_eq "no jq/python3: settings.json left unchanged" '{"permissions":{}}' "$(cat "$t/proj/.claude/settings.json")"

# ---------------------------------------------------------------------------
# version_gt: numeric semver comparison, optional leading v
# ---------------------------------------------------------------------------
version_gt 0.10.0 0.9.1 && pass "0.10.0 > 0.9.1" || fail "0.10.0 > 0.9.1" "returned false"
version_gt v1.0.0 0.99.99 && pass "v1.0.0 > 0.99.99" || fail "v1.0.0 > 0.99.99" "returned false"
version_gt 0.9.1 0.9.1 && fail "0.9.1 > 0.9.1" "returned true" || pass "equal versions are not greater"
version_gt 0.9.0 0.9.1 && fail "0.9.0 > 0.9.1" "returned true" || pass "older is not greater"

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
