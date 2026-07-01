#!/usr/bin/env bash
# tests/check-install-smoke.sh — offline install smoke test.
#
# Simulates a real install WITHOUT network, a release tag, or a claude session: it derives the
# shared-file list from the SAME download table the real installer uses (.prompts/setup-prompt.md
# Step 2), copies each source from the working tree into a target dir, lays down the project-owned
# templates, then runs the installed gates. This both proves the installed layout works AND catches
# download-table drift (a new shared file that was never wired into the table fails here).
#
# Usage:
#   bash tests/check-install-smoke.sh [TARGET_DIR]
# With no TARGET_DIR a temp dir is used and removed on exit. Pass a path to keep the tree for
# inspection (e.g. bash tests/check-install-smoke.sh /tmp/ac-install).
#
# Exit: 0 = install layout valid and gates pass, 1 = a problem (missing source, gate failure).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROMPT="$REPO_ROOT/.prompts/setup-prompt.md"

PASS=0
FAIL=0
pass() { printf "  PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL  %s\n    => %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

# Target: explicit arg (kept) or a temp dir (auto-removed).
KEEP=1
TARGET="${1:-}"
if [ -z "$TARGET" ]; then
    TARGET="$(mktemp -d "${TMPDIR:-/tmp}/ac-install.XXXXXX")"
    KEEP=0
fi
cleanup() { [ "$KEEP" -eq 0 ] && [ -d "$TARGET" ] && rm -rf "$TARGET"; }
trap cleanup EXIT
mkdir -p "$TARGET"

echo "=== install smoke test (offline) ==="
echo "  target: $TARGET"
echo ""

# 1. Project-owned scaffold: templates/ maps to the project root (.agent-context, .claude, AGENTS.md).
cp -R "$REPO_ROOT/templates/." "$TARGET/" 2>/dev/null \
    && pass "templates scaffold copied" || fail "templates scaffold copied" "cp failed"

# 2. Shared files: derive (source -> dest) from the setup-prompt Step 2 download table and copy
#    each source from the working tree. A missing source is a hard failure (table drift).
table_rows="$(awk '/^\| *Source path/{t=1;next} t&&/^\| *`/{n=split($0,a,"`"); if(a[2]&&a[4]) print a[2]"\t"a[4]} t&&!/^\|/{t=0}' "$PROMPT")"
row_count="$(printf '%s\n' "$table_rows" | grep -c . || true)"
[ "$row_count" -ge 1 ] && pass "parsed $row_count shared-file rows from download table" \
    || fail "parse download table" "no rows found in $PROMPT"

missing_src=0
copied=0
while IFS="$(printf '\t')" read -r src dst; do
    [ -n "$src" ] || continue
    if [ ! -f "$REPO_ROOT/$src" ]; then
        fail "source exists for $dst" "missing working-tree file: $src"
        missing_src=1
        continue
    fi
    mkdir -p "$TARGET/$(dirname "$dst")"
    cp "$REPO_ROOT/$src" "$TARGET/$dst" || { fail "copy $src" "cp failed"; missing_src=1; continue; }
    copied=$((copied + 1))
done <<EOF
$table_rows
EOF
[ "$missing_src" -eq 0 ] && pass "all $copied shared sources present and copied" \
    || fail "all shared sources present" "one or more download-table sources missing from the tree"

# 3. Make the installed scripts executable, as the real installer's chmod step does.
chmod +x "$TARGET"/.agent-context/bin/*.sh "$TARGET"/.agent-context/hooks/*.sh 2>/dev/null || true

# 4. Every destination from the table must now exist in the target.
missing_dst=0
while IFS="$(printf '\t')" read -r src dst; do
    [ -n "$dst" ] || continue
    [ -f "$TARGET/$dst" ] || { fail "installed file present" "$dst missing in target"; missing_dst=1; }
done <<EOF
$table_rows
EOF
[ "$missing_dst" -eq 0 ] && pass "every download-table destination is present in the target" \
    || fail "all destinations present" "see above"

# 5. Gates run in the installed tree (cwd = target so the conf's project-relative paths resolve).
if ( cd "$TARGET" && bash .agent-context/bin/check-token-budget.sh --quiet ); then
    pass "always-on token-budget gate passes in installed tree"
else
    fail "token-budget gate" "check-token-budget.sh exited non-zero in the installed tree"
fi

# Map gate with no map yet must exit 2 (no map.json) — proves the validator installed and runs.
mc=0
( cd "$TARGET" && bash .agent-context/bin/check-map-budget.sh --quiet >/dev/null 2>&1 ) || mc=$?
[ "$mc" -eq 2 ] && pass "map-budget gate present and reports no-map (exit 2)" \
    || fail "map-budget gate" "expected exit 2 (no map.json), got $mc"

echo ""
echo "================================================"
TOTAL=$((PASS + FAIL))
printf "Results: %d/%d passed\n" "$PASS" "$TOTAL"
[ "$KEEP" -eq 1 ] && echo "(target kept at $TARGET)"
[ "$FAIL" -eq 0 ] && { echo "ALL PASSED"; exit 0; } || { echo "FAILED"; exit 1; }
