#!/usr/bin/env bash
# tests/check-setup-steps-unit.sh — unit tests for context/bin/setup-steps.sh
#
# Verifies legacy detection, recoverable-only removal, the idempotent gitignore block, and that the
# installer allowlists the script the prompt calls in the steps a headless run executes.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STEPS="$REPO_ROOT/context/bin/setup-steps.sh"
PROMPT="$REPO_ROOT/.prompts/setup-prompt.md"

PASS=0
FAIL=0
# shellcheck source=tests/lib.sh
source "$REPO_ROOT/tests/lib.sh"
pass() { printf "  PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL  %s\n    => %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }
assert_line() { printf '%s\n' "$2" | grep -qxF -- "$3" && pass "$1" || fail "$1" "no line equal to '$3'"; }
assert_no_line() { printf '%s\n' "$2" | grep -qxF -- "$3" && fail "$1" "unexpected line '$3'" || pass "$1"; }

new_repo() {
    local d
    d=$(mk_tmp)
    ( cd "$d" && git init -q && mkdir -p .agent-context && : > .agent-context/setup.log )
    printf '%s' "$d"
}
commit_all() { ( cd "$1" && git add -A && git -c user.email=t@t -c user.name=t commit -qm fixture ); }

echo "=== setup-steps unit tests ==="
echo ""

# --- detect-legacy ---
t=$(new_repo)
mkdir -p "$t/.ai" "$t/.cursor/rules" "$t/custom"
printf 'rule\n' > "$t/GEMINI.md"
printf '@AGENTS.md\n' > "$t/CLAUDE.md"
out=$( cd "$t" && bash "$STEPS" detect-legacy "custom,missing" )
assert_line "detects .ai" "$out" "FOUND: .ai"
assert_line "detects .cursor/rules" "$out" "FOUND: .cursor/rules"
assert_line "detects GEMINI.md" "$out" "FOUND: GEMINI.md"
assert_line "detects an extra dir" "$out" "FOUND: custom"
assert_no_line "skips a missing extra dir" "$out" "FOUND: missing"
assert_no_line "skips a bootstrap-only CLAUDE.md" "$out" "FOUND: CLAUDE.md"
printf '@AGENTS.md\nOwn rule\n' > "$t/CLAUDE.md"
out=$( cd "$t" && AI_DIRS="custom" bash "$STEPS" detect-legacy )
assert_line "reports a CLAUDE.md with own content" "$out" "FOUND: CLAUDE.md"
assert_line "reads extra dirs from AI_DIRS" "$out" "FOUND: custom"

# --- remove-legacy ---
t=$(new_repo)
mkdir -p "$t/.ai" "$t/dirty"
printf 'a\n' > "$t/.ai/a.md"
printf 'b\n' > "$t/dirty/b.md"
commit_all "$t"
printf 'changed\n' >> "$t/dirty/b.md"
( cd "$t" && bash "$STEPS" remove-legacy .ai dirty absent ) >/dev/null
[ ! -e "$t/.ai" ] && pass "removes a committed, unmodified path" || fail "removes a committed, unmodified path" ".ai still present"
[ -f "$t/dirty/b.md" ] && pass "keeps a modified path" || fail "keeps a modified path" "dirty/b.md gone"
log=$(cat "$t/.agent-context/setup.log")
assert_line "logs the kept path as UNRESOLVED" "$log" "[agent-context] UNRESOLVED: dirty"
assert_line "logs MIGRATION_CLEANUP after a removal" "$log" "[agent-context] MIGRATION_CLEANUP: ran"

t=$(new_repo)
mkdir -p "$t/.ai"
printf 'untracked\n' > "$t/.ai/u.md"
( cd "$t" && bash "$STEPS" remove-legacy .ai ) >/dev/null
[ -f "$t/.ai/u.md" ] && pass "keeps an untracked path" || fail "keeps an untracked path" ".ai/u.md gone"
assert_no_line "no MIGRATION_CLEANUP without a removal" "$(cat "$t/.agent-context/setup.log")" "[agent-context] MIGRATION_CLEANUP: ran"

# --- ensure-gitignore ---
t=$(new_repo)
printf 'node_modules/' > "$t/.gitignore"
( cd "$t" && bash "$STEPS" ensure-gitignore && bash "$STEPS" ensure-gitignore ) >/dev/null
gi=$(cat "$t/.gitignore")
assert_line "keeps the existing last line intact" "$gi" "node_modules/"
[ "$(grep -c '^###> agent-context (transient working state) ###$' "$t/.gitignore")" -eq 1 ] \
    && pass "adds the block exactly once" || fail "adds the block exactly once" "$gi"
assert_line "ignores todo.md" "$gi" "/.agent-context/memory/todo.md"

# --- usage ---
( bash "$STEPS" bogus ) >/dev/null 2>&1
[ $? -eq 2 ] && pass "unknown subcommand exits 2" || fail "unknown subcommand exits 2" "rc=$?"
( bash "$STEPS" remove-legacy ) >/dev/null 2>&1
[ $? -eq 2 ] && pass "remove-legacy without a path exits 2" || fail "remove-legacy without a path exits 2" "rc=$?"

# --- wiring: the headless allowlist covers what the prompt calls ---
grep -qF 'Bash(bash *.agent-context/bin/setup-steps.sh*)' "$REPO_ROOT/install.sh" \
    && pass "installer allowlists setup-steps.sh" || fail "installer allowlists setup-steps.sh" "no allowlist entry"
for sub in detect-legacy remove-legacy ensure-gitignore; do
    grep -qF "bash .agent-context/bin/setup-steps.sh $sub" "$PROMPT" \
        && pass "prompt calls setup-steps.sh $sub" || fail "prompt calls setup-steps.sh $sub" "no call in the prompt"
done
grep -qF 'GITIGNORE_MARKER=' "$PROMPT" \
    && fail "prompt has no inline gitignore block" "GITIGNORE_MARKER still inline" \
    || pass "prompt has no inline gitignore block"

echo ""
echo "================================================"
echo "Results: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
