#!/usr/bin/env bash
# tests/check-measure-baseline-unit.sh — unit tests for the baseline measurement script.
#
# Verifies the set split (layered vs on-demand), that memory/archive is excluded, that a file
# which is already always-on is never also counted as on-demand, that flat is the exact sum,
# and the JSON shape. Counting itself is covered by check-token-budget-unit.sh.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_BIN="$REPO_ROOT/context/bin"

PASS=0
FAIL=0
# shellcheck source=tests/lib.sh
source "$REPO_ROOT/tests/lib.sh"

pass() { printf "  PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL  %s\n    => %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }
assert_eq() { [ "$2" = "$3" ] && pass "$1" || fail "$1" "expected '$2', got '$3'"; }

# Builds a minimal installed tree: the ten @-imported files plus the two INCLUDE_FILES
# session-start reads, 2 effective lines each, plus whatever on-demand content the caller adds.
mk_project() {
    local d
    d=$(mk_tmp)
    mkdir -p "$d/.agent-context/bin" "$d/.agent-context/memory" "$d/.agent-context/skills" "$d/.claude"
    cp "$SRC_BIN/check-token-budget.sh" "$SRC_BIN/conf-read.sh" "$SRC_BIN/measure-baseline.sh" "$d/.agent-context/bin/"
    cp "$REPO_ROOT/templates/.agent-context/budget.conf" "$d/.agent-context/budget.conf"
    printf 'line one\n@../AGENTS.md\n' > "$d/.claude/CLAUDE.md"
    printf 'line one\n@.agent-context/agent-startup.md\n' > "$d/AGENTS.md"
    local prev=agent-startup.md f
    for f in layer0-agent-workflow.md layer1-bootstrap.md layer2-project-core.md \
        layer3-guidebook.md base-principles.md knowledge-map.md skills/index.md; do
        printf 'line one\n@%s\n' "$f" > "$d/.agent-context/$prev"
        prev="$f"
    done
    printf 'line one\n\nline two\n' > "$d/.agent-context/skills/index.md"
    printf 'line one\n\nline two\n' > "$d/.agent-context/memory/lessons.md"
    printf 'line one\n\nline two\n' > "$d/.agent-context/memory/preferences.md"
    echo "$d"
}

run_measure() { bash "$1/.agent-context/bin/measure-baseline.sh" --dir "$1" 2>&1; }

# Pulls one column out of a table row. Anchored at line start so the prose below the table —
# which also mentions "on-demand" and "flat" — cannot match. Column 3 = files, 4 = eff. lines.
row_field() { awk -v want="$1" -v col="$2" '$0 ~ ("^  " want) { print $col }' <<<"$3"; }

echo "=== measure-baseline unit tests ==="
echo ""

# 1. A bare install has twelve always-on files at 2 effective lines each and nothing on demand.
P=$(mk_project)
out=$(run_measure "$P")
assert_eq "bare install: 12 layered files" "12" "$(row_field 'layered' 3 "$out")"
assert_eq "bare install: 24 layered effective lines" "24" "$(row_field 'layered' 4 "$out")"
assert_eq "bare install: nothing on demand" "0" "$(row_field 'on-demand' 3 "$out")"
assert_eq "bare install: flat equals layered" "24" "$(row_field 'flat' 4 "$out")"

# 2. Memory, nested memory, skills, and the shared on-demand docs all land in the lazy set.
P=$(mk_project)
mkdir -p "$P/.agent-context/memory/billing" "$P/.agent-context/skills/foo"
printf 'a\nb\nc\n' > "$P/.agent-context/memory/people.md"
printf 'a\nb\nc\n' > "$P/.agent-context/memory/billing/notes.md"
printf 'a\nb\nc\n' > "$P/.agent-context/skills/foo/SKILL.md"
printf 'a\nb\nc\n' > "$P/.agent-context/agent-delegation.md"
printf 'a\nb\nc\n' > "$P/.agent-context/memory-maintenance.md"
printf '{"nodes":[]}\n' > "$P/.agent-context/map.json"
out=$(run_measure "$P")
assert_eq "on-demand picks up all six sources" "6" "$(row_field 'on-demand' 3 "$out")"
assert_eq "on-demand lines: 5 docs x 3 + map.json" "16" "$(row_field 'on-demand' 4 "$out")"
assert_eq "flat is the exact sum" "40" "$(row_field 'flat' 4 "$out")"

# 3. Archived memory is history, not context — it must not inflate the on-demand set.
P=$(mk_project)
mkdir -p "$P/.agent-context/memory/archive"
printf 'a\nb\nc\n' > "$P/.agent-context/memory/people.md"
printf 'x\ny\nz\nq\nw\ne\n' > "$P/.agent-context/memory/archive/2026-W01.md"
out=$(run_measure "$P")
assert_eq "memory/archive excluded from on-demand" "1" "$(row_field 'on-demand' 3 "$out")"
assert_eq "archive lines not counted" "3" "$(row_field 'on-demand' 4 "$out")"

# 4. skills/index.md is always-on; discovering it under skills/ must not double-count it.
P=$(mk_project)
out=$(run_measure "$P")
assert_eq "always-on skills/index.md not counted twice" "0" "$(row_field 'on-demand' 3 "$out")"

# 5. JSON mode reports the same split.
P=$(mk_project)
printf 'a\nb\nc\n' > "$P/.agent-context/memory/people.md"
js=$(bash "$P/.agent-context/bin/measure-baseline.sh" --dir "$P" --json 2>&1)
get_json() { awk -v k="\"$1\"" '$0 ~ k { print }' <<<"$js" | sed -e 's/.*"effective_lines": \([0-9]*\).*/\1/'; }
assert_eq "json: layered lines" "24" "$(get_json layered)"
assert_eq "json: on_demand lines" "3" "$(get_json on_demand)"
assert_eq "json: flat lines" "27" "$(get_json flat)"

# 6. A directory that is not a project fails loudly rather than reporting zeros.
P=$(mk_project)
rm -f "$P/.agent-context/budget.conf"
bash "$SRC_BIN/measure-baseline.sh" --dir "$P" >/dev/null 2>&1
assert_eq "missing budget.conf exits 2" "2" "$?"

bash "$SRC_BIN/measure-baseline.sh" --dir "/nonexistent/path/for/test" >/dev/null 2>&1
assert_eq "missing --dir exits 2" "2" "$?"

bash "$SRC_BIN/measure-baseline.sh" --bogus >/dev/null 2>&1
assert_eq "unknown option exits 2" "2" "$?"

echo ""
echo "================================================"
echo "Results: $PASS/$((PASS + FAIL)) passed"
if [ "$FAIL" -gt 0 ]; then
    echo "FAILED"
    exit 1
fi
echo "ALL PASSED"
