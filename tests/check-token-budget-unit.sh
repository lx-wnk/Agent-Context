#!/usr/bin/env bash
# tests/check-token-budget-unit.sh — unit tests for the token-budget counting engine.
#
# Verifies the effective-line heuristic: blank lines, HTML comments (single- and multi-line),
# markdown table separators, and horizontal rules are NOT counted; real instruction lines are.
# Also checks the over-budget exit code and the conf-driven path.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="$REPO_ROOT/context/bin/check-token-budget.sh"

PASS=0
FAIL=0
TMP_ROOTS=()

cleanup() { for d in "${TMP_ROOTS[@]:-}"; do [ -d "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

mk_tmp() { local d; d=$(mktemp -d "${TMPDIR:-/tmp}/budget.XXXXXX"); TMP_ROOTS+=("$d"); echo "$d"; }
pass() { printf "  PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL  %s\n    => %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }
assert_eq() { [ "$2" = "$3" ] && pass "$1" || fail "$1" "expected '$2', got '$3'"; }

echo "=== token-budget engine unit tests ==="
echo ""

# Effective-line count is reported on the TOTAL line; extract it with --quiet off.
count_total() {
    bash "$ENGINE" --max 99999 "$1" 2>/dev/null | awk '/TOTAL/{print $1}'
}

# 1. Plain instruction lines are counted.
t=$(mk_tmp)
printf 'rule one\nrule two\nrule three\n' > "$t/f.md"
assert_eq "3 plain lines counted as 3" "3" "$(count_total "$t/f.md")"

# 2. Blank lines are ignored.
t=$(mk_tmp)
printf 'rule one\n\n\nrule two\n' > "$t/f.md"
assert_eq "blank lines not counted" "2" "$(count_total "$t/f.md")"

# 3. Single-line HTML comments are ignored.
t=$(mk_tmp)
printf '<!-- a comment -->\nrule one\n' > "$t/f.md"
assert_eq "single-line HTML comment skipped" "1" "$(count_total "$t/f.md")"

# 4. Multi-line HTML comments are ignored.
t=$(mk_tmp)
printf '<!--\nblock comment line\nstill comment\n-->\nrule one\n' > "$t/f.md"
assert_eq "multi-line HTML comment skipped" "1" "$(count_total "$t/f.md")"

# 5. Markdown table separator rows are ignored, but header/data rows count.
t=$(mk_tmp)
printf '| Col A | Col B |\n| ----- | ----- |\n| x | y |\n' > "$t/f.md"
assert_eq "table separator skipped, header+data counted" "2" "$(count_total "$t/f.md")"

# 6. Horizontal-rule dividers are ignored.
t=$(mk_tmp)
printf 'rule one\n---\n===\n***\nrule two\n' > "$t/f.md"
assert_eq "horizontal rules skipped" "2" "$(count_total "$t/f.md")"

# 7. Over-budget input exits 1.
t=$(mk_tmp)
printf 'a\nb\nc\nd\n' > "$t/f.md"
if bash "$ENGINE" --max 2 --quiet "$t/f.md" >/dev/null 2>&1; then
    fail "over-budget exits non-zero" "exited 0"
else
    pass "over-budget exits non-zero"
fi

# 8. Within-budget input exits 0.
t=$(mk_tmp)
printf 'a\nb\n' > "$t/f.md"
if bash "$ENGINE" --max 5 --quiet "$t/f.md" >/dev/null 2>&1; then
    pass "within-budget exits 0"
else
    fail "within-budget exits 0" "exited non-zero"
fi

# 9. Conf-driven path: INCLUDE_FILES + MAX_EFFECTIVE_LINES read from conf.
t=$(mk_tmp)
printf 'a\nb\nc\n' > "$t/layer.md"
cat > "$t/budget.conf" <<EOF
MAX_EFFECTIVE_LINES=10
INCLUDE_FILES="$t/layer.md"
EOF
if bash "$ENGINE" --conf "$t/budget.conf" --quiet >/dev/null 2>&1; then
    pass "conf-driven run within budget exits 0"
else
    fail "conf-driven run within budget exits 0" "exited non-zero"
fi

# 10. Conf max can be overridden by --max.
if bash "$ENGINE" --conf "$t/budget.conf" --max 1 --quiet >/dev/null 2>&1; then
    fail "--max overrides conf (should fail at max 1)" "exited 0"
else
    pass "--max overrides conf (fails at max 1)"
fi

echo ""
echo "================================================"
TOTAL=$((PASS + FAIL))
printf "Results: %d/%d passed\n" "$PASS" "$TOTAL"
[ "$FAIL" -eq 0 ] && { echo "ALL PASSED"; exit 0; } || { echo "FAILED"; exit 1; }
