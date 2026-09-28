#!/usr/bin/env bash
# tests/check-discovery-digest-unit.sh — unit tests for context/bin/discovery-digest.sh
#
# Verifies the digest detects manifests, inventories docs with line counts, flags heavy docs
# as distillation candidates, excludes agent-managed dirs, and works without git.

# shellcheck disable=SC2016  # the backticks are literal digest output, not a command substitution

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIGEST="$REPO_ROOT/context/bin/discovery-digest.sh"

PASS=0
FAIL=0
# shellcheck source=tests/lib.sh
source "$REPO_ROOT/tests/lib.sh"
pass() { printf "  PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL  %s\n    => %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }
assert_has() { printf '%s' "$2" | grep -qF "$3" && pass "$1" || fail "$1" "missing '$3'"; }
assert_hasnt() { printf '%s' "$2" | grep -qF "$3" && fail "$1" "unexpected '$3'" || pass "$1"; }
assert_line() { printf '%s\n' "$2" | grep -qxF -- "$3" && pass "$1" || fail "$1" "no line equal to '$3'"; }
assert_no_line() { printf '%s\n' "$2" | grep -qxF -- "$3" && fail "$1" "unexpected line '$3'" || pass "$1"; }

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

assert_line "detects package.json manifest" "$OUT" '- `package.json` (Node/JS)'
assert_line "reports package.json scripts" "$OUT" '  - test'
assert_has "inventories docs/small.md" "$OUT" 'docs/small.md'
assert_has "inventories docs/big.md" "$OUT" 'docs/big.md'
assert_has "flags heavy doc as distillation candidate" "$OUT" 'Distillation candidates'
# big.md (120 lines) must appear under candidates; small.md must not be a candidate line.
cand="$(printf '%s' "$OUT" | sed -n '/Distillation candidates/,$p')"
assert_has "big.md is a distillation candidate" "$cand" 'docs/big.md'
assert_hasnt "small.md is NOT a distillation candidate" "$cand" 'docs/small.md'
assert_hasnt "excludes .agent-context from inventory" "$OUT" '.agent-context/internal.md'
assert_hasnt "excludes node_modules from inventory" "$OUT" 'node_modules/dep.md'

# Git fixture: exercises the ls-files path (ignore rules, non-ASCII names, bin/, Makefile, compose).
g=$(mk_tmp)
git -C "$g" init -q
mkdir -p "$g/docs" "$g/bin"
printf '{"name":"x"}\n' > "$g/package.json"
printf 'ignored.md\n' > "$g/.gitignore"
printf '# Ignored\n' > "$g/ignored.md"
UMLAUT_DOC="$(printf 'docs/\303\274ber.md')"
printf '# Umlaut\n' > "$g/$UMLAUT_DOC"
printf '#!/usr/bin/env php\n' > "$g/bin/console"
printf '# Seven\n## a\n## b\n## c\n## d\n## e\n## f\n' > "$g/docs/seven.md"
printf '# Eight\n## a\n## b\n## c\n## d\n## e\n## f\n## g\n' > "$g/docs/eight.md"
printf 'FOO:=1\nBAR ?= 2\nBAZ::=3\nQUX := 4\nbuild: deps\n\t@echo build\ncheck :\n\t@echo check\n' > "$g/Makefile"
printf 'services:\n  web:\n    image: nginx\n  db:\n    image: postgres\nvolumes:\n  data:\n' > "$g/docker-compose.yml"
git -C "$g" add package.json .gitignore Makefile "$UMLAUT_DOC"
GOUT="$(bash "$DIGEST" "$g" 2>/dev/null)"

assert_hasnt "git: .gitignored file excluded" "$GOUT" 'ignored.md'
assert_has "git: untracked, not-ignored doc listed" "$GOUT" '`docs/seven.md`'
assert_has "git: non-ASCII file name inventoried" "$GOUT" "\`$UMLAUT_DOC\`"
assert_hasnt "git: no quoted octal file name" "$GOUT" '\303'
assert_line "git: top-level bin/ is listed" "$GOUT" '- bin'
assert_line "Makefile target build" "$GOUT" '  - build'
assert_line "Makefile target with space before colon" "$GOUT" '  - check'
assert_no_line "Makefile FOO:= is not a target" "$GOUT" '  - FOO'
assert_no_line "Makefile BAZ::= is not a target" "$GOUT" '  - BAZ'
assert_no_line "Makefile QUX := is not a target" "$GOUT" '  - QUX'
assert_line "compose services listed" "$GOUT" '- `docker-compose.yml` services: web db '
gcand="$(printf '%s' "$GOUT" | sed -n '/Distillation candidates/,$p')"
assert_has "8 headings is a distillation candidate" "$gcand" '`docs/eight.md` (8 lines, 8 headings)'
assert_hasnt "7 headings is NOT a distillation candidate" "$gcand" 'docs/seven.md'
assert_has "doc table row has lines, heading, count" "$GOUT" '| `docs/eight.md` | 8 | Eight | 8 |'

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
