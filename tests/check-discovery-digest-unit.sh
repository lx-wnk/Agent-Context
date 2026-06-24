#!/usr/bin/env bash
# tests/check-discovery-digest-unit.sh — unit tests for context/bin/discovery-digest.sh
#
# Verifies the digest detects manifests, inventories docs with line counts, flags heavy docs
# as distillation candidates, excludes agent-managed dirs, and works without git.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIGEST="$REPO_ROOT/context/bin/discovery-digest.sh"

PASS=0
FAIL=0
TMP_ROOTS=()
cleanup() { for d in "${TMP_ROOTS[@]:-}"; do [ -d "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT
mk_tmp() { local d; d=$(mktemp -d "${TMPDIR:-/tmp}/digest-test.XXXXXX"); TMP_ROOTS+=("$d"); echo "$d"; }
pass() { printf "  PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL  %s\n    => %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }
assert_has() { printf '%s' "$2" | grep -qF "$3" && pass "$1" || fail "$1" "missing '$3'"; }
assert_hasnt() { printf '%s' "$2" | grep -qF "$3" && fail "$1" "unexpected '$3'" || pass "$1"; }

echo "=== discovery-digest unit tests ==="
echo ""

# Build a fixture project (non-git is fine — exercises the find fallback).
t=$(mk_tmp)
mkdir -p "$t/docs" "$t/.agent-context" "$t/node_modules"
printf '{"name":"x","scripts":{"test":"y"}}\n' > "$t/package.json"
printf 'short doc\n' > "$t/docs/small.md"
# A heavy doc: 120 lines.
{ echo "# Big Spec"; for i in $(seq 1 119); do echo "line $i"; done; } > "$t/docs/big.md"
printf 'agent infra noise\n' > "$t/.agent-context/internal.md"
printf 'dep\n' > "$t/node_modules/dep.md"

OUT="$(bash "$DIGEST" "$t" 2>/dev/null)"

assert_has "detects package.json manifest" "$OUT" 'package.json'
assert_has "reports package.json scripts" "$OUT" 'test'
assert_has "inventories docs/small.md" "$OUT" 'docs/small.md'
assert_has "inventories docs/big.md" "$OUT" 'docs/big.md'
assert_has "flags heavy doc as distillation candidate" "$OUT" 'Distillation candidates'
# big.md (120 lines) must appear under candidates; small.md must not be a candidate line.
cand="$(printf '%s' "$OUT" | sed -n '/Distillation candidates/,$p')"
assert_has "big.md is a distillation candidate" "$cand" 'docs/big.md'
assert_hasnt "small.md is NOT a distillation candidate" "$cand" 'docs/small.md'
assert_hasnt "excludes .agent-context from inventory" "$OUT" '.agent-context/internal.md'
assert_hasnt "excludes node_modules from inventory" "$OUT" 'node_modules/dep.md'

# Empty project: no manifests, still produces a digest without erroring.
t2=$(mk_tmp)
OUT2="$(bash "$DIGEST" "$t2" 2>/dev/null)"; RC=$?
{ [ "$RC" -eq 0 ] && printf '%s' "$OUT2" | grep -q 'Discovery Digest'; } \
    && pass "empty project produces a digest, exit 0" || fail "empty project" "rc=$RC"

echo ""
echo "================================================"
TOTAL=$((PASS + FAIL))
printf "Results: %d/%d passed\n" "$PASS" "$TOTAL"
[ "$FAIL" -eq 0 ] && { echo "ALL PASSED"; exit 0; } || { echo "FAILED"; exit 1; }
