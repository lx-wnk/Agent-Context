#!/usr/bin/env bash
# tests/check-memory-prune-unit.sh — unit tests for context/bin/memory-prune.sh
#
# Verifies decay semantics: expired entries archived, ttl:infinite kept, not-yet-expired
# kept, metadata-less lines kept, dry-run is non-destructive, index.md/todo.md skipped,
# and re-running is idempotent.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PRUNE="$REPO_ROOT/context/bin/memory-prune.sh"

PASS=0
FAIL=0
TMP_ROOTS=()
cleanup() { for d in "${TMP_ROOTS[@]:-}"; do [ -d "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT
mk_tmp() { local d; d=$(mktemp -d "${TMPDIR:-/tmp}/memprune-test.XXXXXX"); TMP_ROOTS+=("$d"); echo "$d"; }
pass() { printf "  PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL  %s\n    => %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }
assert_file_contains() { grep -qF "$3" "$2" 2>/dev/null && pass "$1" || fail "$1" "missing '$3' in $2"; }
assert_file_not_contains() { grep -qF "$3" "$2" 2>/dev/null && fail "$1" "unexpected '$3' in $2" || pass "$1"; }

# A fixture with one of each class. Dates are far in the past / future so the test is
# stable regardless of the run date (no Date.now coupling).
seed() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "$dir/lessons.md" <<'EOF'
# Lessons Learned

- **[old]** Expired gotcha (2020-01-01) ttl:90d source:discovered conf:med
- **[arch]** Permanent rule (2020-01-01) ttl:infinite source:user conf:high
- **[future]** Long-lived (2099-01-01) ttl:30d source:discovered conf:med
- Plain note without metadata.
EOF
    cat > "$dir/index.md" <<'EOF'
# Memory Index
- **[skip]** index entry (2020-01-01) ttl:90d
EOF
}

echo "=== memory-prune unit tests ==="
echo ""

# 1. Dry-run is non-destructive.
t=$(mk_tmp); seed "$t/memory"
bash "$PRUNE" --dir "$t/memory" >/dev/null 2>&1
assert_file_contains "dry-run keeps expired entry in place" "$t/memory/lessons.md" "Expired gotcha"
[ -d "$t/memory/archive" ] && fail "dry-run creates no archive dir" "archive/ exists" || pass "dry-run creates no archive dir"

# 2. Apply archives expired, keeps the rest.
t=$(mk_tmp); seed "$t/memory"
bash "$PRUNE" --dir "$t/memory" --apply >/dev/null 2>&1
assert_file_not_contains "apply removes expired entry from source" "$t/memory/lessons.md" "Expired gotcha"
assert_file_contains "apply keeps ttl:infinite entry" "$t/memory/lessons.md" "Permanent rule"
assert_file_contains "apply keeps not-yet-expired entry" "$t/memory/lessons.md" "Long-lived"
assert_file_contains "apply keeps metadata-less line" "$t/memory/lessons.md" "Plain note without metadata"
arch=$(find "$t/memory/archive" -name '*.md' | head -1)
assert_file_contains "expired entry moved to archive" "$arch" "Expired gotcha"

# 3. index.md is skipped (never pruned).
assert_file_contains "index.md is not pruned" "$t/memory/index.md" "index entry"

# 4. Idempotent: second apply changes nothing more.
before=$(cat "$t/memory/lessons.md")
bash "$PRUNE" --dir "$t/memory" --apply >/dev/null 2>&1
after=$(cat "$t/memory/lessons.md")
[ "$before" = "$after" ] && pass "second apply is idempotent" || fail "second apply is idempotent" "file changed on re-run"

echo ""
echo "================================================"
TOTAL=$((PASS + FAIL))
printf "Results: %d/%d passed\n" "$PASS" "$TOTAL"
[ "$FAIL" -eq 0 ] && { echo "ALL PASSED"; exit 0; } || { echo "FAILED"; exit 1; }
