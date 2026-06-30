#!/usr/bin/env bash
# tests/check-map-budget-unit.sh — unit tests for the discovery-map cap validator.
#
# Verifies the deterministic caps (total bytes, node count, longest line) and the
# conf-driven path. No JSON parser is used — caps are byte/line/count proxies.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="$REPO_ROOT/context/bin/check-map-budget.sh"

PASS=0
FAIL=0
TMP_ROOTS=()
cleanup() { for d in "${TMP_ROOTS[@]:-}"; do [ -d "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT
mk_tmp() { mktemp -d "${TMPDIR:-/tmp}/mapbudget.XXXXXX"; }
pass() { printf "  PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL  %s\n    => %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

# Write a conf with generous caps unless overridden by args: write_conf DIR [TOTAL] [NODES] [LINE]
write_conf() {
    local d="$1" total="${2:-100000}" nodes="${3:-100}" line="${4:-100000}"
    cat > "$d/budget.conf" <<EOF
MAP_FILE="$d/map.json"
MAP_MAX_TOTAL_BYTES=$total
MAP_MAX_NODES=$nodes
MAP_MAX_NODE_LINE_BYTES=$line
EOF
}

# A valid 2-node map, one node per line.
write_map() {
    local d="$1"
    cat > "$d/map.json" <<'EOF'
{
  "generated": "2026-06-24",
  "nodes": [
    {"id":"auth","label":"Auth","globs":["src/auth/**"],"note":"memory/auth.md","watermark":"abc","stale":false},
    {"id":"billing","label":"Billing","globs":["src/billing/**"],"note":"memory/billing.md","watermark":"def","stale":false}
  ],
  "edges": [
    {"from":"billing","to":"auth","rel":"depends-on","why":"shared user ctx"}
  ]
}
EOF
}

echo "=== map-budget validator unit tests ==="
echo ""

# 1. Valid map within all caps → exit 0.
t=$(mk_tmp); TMP_ROOTS+=("$t"); write_conf "$t"; write_map "$t"
if bash "$ENGINE" --conf "$t/budget.conf" --quiet >/dev/null 2>&1; then pass "valid map within caps exits 0"; else fail "valid map within caps exits 0" "exited non-zero"; fi

# 2. Node count over cap → exit 1.
t=$(mk_tmp); TMP_ROOTS+=("$t"); write_conf "$t" 100000 1 100000; write_map "$t"
code=0; bash "$ENGINE" --conf "$t/budget.conf" --quiet >/dev/null 2>&1 || code=$?
[ "$code" -eq 1 ] && pass "node-count over cap exits 1" || fail "node-count over cap exits 1" "got exit $code"

# 3. Total bytes over cap → exit 1.
t=$(mk_tmp); TMP_ROOTS+=("$t"); write_conf "$t" 10 100 100000; write_map "$t"
code=0; bash "$ENGINE" --conf "$t/budget.conf" --quiet >/dev/null 2>&1 || code=$?
[ "$code" -eq 1 ] && pass "total-bytes over cap exits 1" || fail "total-bytes over cap exits 1" "got exit $code"

# 4. Longest line over cap → exit 1.
t=$(mk_tmp); TMP_ROOTS+=("$t"); write_conf "$t" 100000 100 50; write_map "$t"
code=0; bash "$ENGINE" --conf "$t/budget.conf" --quiet >/dev/null 2>&1 || code=$?
[ "$code" -eq 1 ] && pass "longest-line over cap exits 1" || fail "longest-line over cap exits 1" "got exit $code"

# 5. Missing map file → usage/config error exit 2.
t=$(mk_tmp); TMP_ROOTS+=("$t"); write_conf "$t"
code=0; bash "$ENGINE" --conf "$t/budget.conf" --quiet >/dev/null 2>&1 || code=$?
[ "$code" -eq 2 ] && pass "missing map file exits 2" || fail "missing map file exits 2" "got exit $code"

# 6. Explicit --map arg overrides conf MAP_FILE.
t=$(mk_tmp); TMP_ROOTS+=("$t"); write_conf "$t" 100000 100 100000; write_map "$t"
mv "$t/map.json" "$t/other.json"
if bash "$ENGINE" --conf "$t/budget.conf" --map "$t/other.json" --quiet >/dev/null 2>&1; then pass "--map overrides conf MAP_FILE"; else fail "--map overrides conf MAP_FILE" "exited non-zero"; fi

# 7. Non-integer cap in conf → exit 2.
t=$(mk_tmp); TMP_ROOTS+=("$t"); write_map "$t"
cat > "$t/budget.conf" <<EOF
MAP_FILE="$t/map.json"
MAP_MAX_TOTAL_BYTES=100000
MAP_MAX_NODES=notanumber
MAP_MAX_NODE_LINE_BYTES=100000
EOF
code=0; bash "$ENGINE" --conf "$t/budget.conf" --quiet >/dev/null 2>&1 || code=$?
[ "$code" -eq 2 ] && pass "non-integer cap exits 2" || fail "non-integer cap exits 2" "got exit $code"

# 7. A long globs array is EXEMPT from the longest-line cap (globs must never be truncated by it).
t=$(mk_tmp); TMP_ROOTS+=("$t")
cat > "$t/budget.conf" <<EOF
MAP_FILE="$t/map.json"
MAP_MAX_TOTAL_BYTES=100000
MAP_MAX_NODES=100
MAP_MAX_NODE_LINE_BYTES=120
EOF
cat > "$t/map.json" <<'EOF'
{
  "generated": "2026-06-30",
  "nodes": [
    {"id":"big","label":"Big","globs":["a/**","b/**","c/**","d/**","e/**","f/**","g/**","h/**","i/**","j/**","k/**","l/**","m/**","n/**"],"note":"memory/big.md","watermark":"abc","stale":false}
  ],
  "edges": []
}
EOF
if bash "$ENGINE" --conf "$t/budget.conf" --quiet >/dev/null 2>&1; then pass "long globs array is exempt from the line cap"; else fail "globs exempt from line cap" "long globs tripped the per-line cap"; fi

# 8. A long LABEL (prose bloat) still trips the line cap.
cat > "$t/map-label.json" <<'EOF'
{
  "generated": "2026-06-30",
  "nodes": [
    {"id":"big","label":"This is a deliberately very very very very very very very very very long label that exceeds the small per-node line cap on its own","globs":["a/**"],"note":"memory/big.md","watermark":"abc","stale":false}
  ],
  "edges": []
}
EOF
if bash "$ENGINE" --conf "$t/budget.conf" --map "$t/map-label.json" --quiet >/dev/null 2>&1; then fail "long label still trips the line cap" "long label passed the cap"; else pass "long label still trips the line cap"; fi

echo ""
echo "================================================"
TOTAL=$((PASS + FAIL))
printf "Results: %d/%d passed\n" "$PASS" "$TOTAL"
[ "$FAIL" -eq 0 ] && { echo "ALL PASSED"; exit 0; } || { echo "FAILED"; exit 1; }
