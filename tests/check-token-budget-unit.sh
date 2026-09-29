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
# shellcheck source=tests/lib.sh
source "$REPO_ROOT/tests/lib.sh"
pass() { printf "  PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL  %s\n    => %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }
assert_eq() { [ "$2" = "$3" ] && pass "$1" || fail "$1" "expected '$2', got '$3'"; }
run_in() { local d="$1"; shift; (cd "$d" && bash "$ENGINE" "$@"); }

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
bash "$ENGINE" --max 2 --quiet "$t/f.md" >/dev/null 2>&1
assert_eq "over-budget exits 1" "1" "$?"

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
if run_in "$t" --conf "$t/budget.conf" --quiet >/dev/null 2>&1; then
    pass "conf-driven run within budget exits 0"
else
    fail "conf-driven run within budget exits 0" "exited non-zero"
fi

# 10. Conf max can be overridden by --max.
run_in "$t" --conf "$t/budget.conf" --max 1 --quiet >/dev/null 2>&1
assert_eq "--max overrides conf (exits 1 at max 1)" "1" "$?"

# 11. Soft/hard caps: a 5-line file between a soft cap of 3 and a hard cap of 10 WARNS but passes.
t=$(mk_tmp)
printf 'a\nb\nc\nd\ne\n' > "$t/f.md"
cat > "$t/soft.conf" <<EOF
MAX_EFFECTIVE_LINES=3
MAX_EFFECTIVE_LINES_HARD=10
INCLUDE_FILES="$t/f.md"
EOF
err=$(run_in "$t" --conf "$t/soft.conf" --quiet 2>&1 >/dev/null); code=$?
{ [ "$code" -eq 0 ] && printf '%s' "$err" | grep -q "WARN"; } \
    && pass "over soft but under hard → WARN + exit 0" || fail "soft warn band" "code=$code err=$err"

# 12. Over the hard cap → exit 1.
cat > "$t/hard.conf" <<EOF
MAX_EFFECTIVE_LINES=2
MAX_EFFECTIVE_LINES_HARD=4
INCLUDE_FILES="$t/f.md"
EOF
run_in "$t" --conf "$t/hard.conf" --quiet >/dev/null 2>&1
assert_eq "over hard cap → exit 1" "1" "$?"

# 13. No hard cap in the conf → hard defaults to 250, not to the soft cap (old project confs).
cat > "$t/nohard.conf" <<EOF
MAX_EFFECTIVE_LINES=4
INCLUDE_FILES="$t/f.md"
EOF
err=$(run_in "$t" --conf "$t/nohard.conf" --quiet 2>&1 >/dev/null); code=$?
{ [ "$code" -eq 0 ] && printf '%s' "$err" | grep -q "WARN"; } \
    && pass "no hard cap → over soft only warns" || fail "no hard cap warn band" "code=$code err=$err"
js=$(run_in "$t" --conf "$t/nohard.conf" --json 2>/dev/null)
assert_eq "no hard cap → hard_cap defaults to 250" "250" "$(sed -n 's/.*"hard_cap": \([0-9]*\).*/\1/p' <<<"$js")"
awk 'BEGIN { for (i = 1; i <= 251; i++) print "rule " i }' > "$t/big.md"
cat > "$t/nohard-big.conf" <<EOF
MAX_EFFECTIVE_LINES=200
INCLUDE_FILES="$t/big.md"
EOF
run_in "$t" --conf "$t/nohard-big.conf" --quiet >/dev/null 2>&1
assert_eq "no hard cap → 251 lines fails" "1" "$?"

# 14. The conf is DATA, not a script. It is parsed for the keys this gate needs and never
# executed, so a budget.conf arriving via `git pull` from an untrusted repository cannot run a
# command on the developer's machine.
t=$(mk_tmp)
printf 'a\nb\nc\n' > "$t/layer.md"
canary="$t/PAYLOAD_RAN"
cat > "$t/payload.conf" <<EOF
MAX_EFFECTIVE_LINES=10
INCLUDE_FILES="$t/layer.md"
touch $canary
EOF
run_in "$t" --conf "$t/payload.conf" --quiet >/dev/null 2>&1
[ -e "$canary" ] && fail "conf payload is never executed" "the conf command ran" \
    || pass "conf payload is never executed"
if run_in "$t" --conf "$t/payload.conf" --quiet >/dev/null 2>&1; then
    pass "the parsed keys still apply while the payload is ignored"
else
    fail "the parsed keys still apply while the payload is ignored" "exited non-zero"
fi

# 15. --list resolves the closure without counting it — the file set is a separate question
# from the file size, and measure-baseline.sh needs the answer before it can measure.
t=$(mk_tmp)
printf 'a\n' > "$t/one.md"
printf 'b\n' > "$t/two.md"
cat > "$t/list.conf" <<EOF
MAX_EFFECTIVE_LINES=1
INCLUDE_FILES="
$t/one.md
$t/two.md
"
EOF
listed=$(run_in "$t" --list --conf "$t/list.conf" 2>/dev/null | wc -l | tr -d '[:space:]')
assert_eq "--list prints one path per resolved file" "2" "$listed"
if run_in "$t" --list --conf "$t/list.conf" >/dev/null 2>&1; then
    pass "--list exits 0 even when the set is over budget"
else
    fail "--list exits 0 even when the set is over budget" "exited non-zero"
fi

# 16. --json carries totals and per-file rows, and keeps the gate's verdict.
t=$(mk_tmp)
printf 'a\nb\nc\n' > "$t/f.md"
js=$(bash "$ENGINE" --json --max 99999 "$t/f.md" 2>/dev/null)
assert_eq "--json reports effective lines" "3" "$(sed -n 's/.*"total_effective_lines": \([0-9]*\).*/\1/p' <<<"$js")"
assert_eq "--json reports bytes" "6" "$(sed -n 's/.*"total_bytes": \([0-9]*\).*/\1/p' <<<"$js")"
assert_eq "--json estimates tokens as ceil(bytes/4)" "2" "$(sed -n 's/.*"total_est_tokens": \([0-9]*\).*/\1/p' <<<"$js")"
assert_eq "--json status passes within budget" "pass" "$(sed -n 's/.*"status": "\([a-z]*\)".*/\1/p' <<<"$js")"

js=$(bash "$ENGINE" --json --max 1 "$t/f.md" 2>/dev/null)
assert_eq "--json status fails over the hard cap" "fail" "$(sed -n 's/.*"status": "\([a-z]*\)".*/\1/p' <<<"$js")"

# 17. A missing file is reported as absent rather than silently dropped from the array.
t=$(mk_tmp)
printf 'a\n' > "$t/f.md"
js=$(bash "$ENGINE" --json --max 99999 "$t/f.md" "$t/gone.md" 2>/dev/null)
assert_eq "--json lists the missing file too" "2" "$(grep -c '"path"' <<<"$js")"
assert_eq "--json marks it absent" "1" "$(grep -c '"present": false' <<<"$js")"

# 18. FP-74: comment removal is shortest-match, and an unclosed comment does not hide lines.
t=$(mk_tmp)
printf '<!-- a --> keep <!-- b -->\n' > "$t/f.md"
assert_eq "text between two comments on one line counted" "1" "$(count_total "$t/f.md")"
printf '<!-- a --> <!-- b -->\n' > "$t/f.md"
assert_eq "two comments only on one line not counted" "0" "$(count_total "$t/f.md")"
printf 'a\n<!--\nb\nc\nd\n' > "$t/f.md"
assert_eq "unclosed comment: every loaded line counted" "5" "$(count_total "$t/f.md")"
printf 'a\n<!-- note\nb\n-->\nc\n' > "$t/f.md"
assert_eq "closed multi-line comment still skipped" "2" "$(count_total "$t/f.md")"
# shellcheck disable=SC2016
printf 'use `<!--` for notes\nrule two\nrule three\n' > "$t/f.md"
assert_eq "<!-- inside a code span is not a comment start" "3" "$(count_total "$t/f.md")"

# 19. Import walk: the set is what Claude Code loads — @imports resolved relative to the importing
# file, starting at .claude/CLAUDE.md (and root CLAUDE.md if present).
mk_proj() {
    local d
    d=$(mk_tmp)
    mkdir -p "$d/.claude" "$d/.agent-context"
    printf '# P\n\n@../AGENTS.md\n' > "$d/.claude/CLAUDE.md"
    # shellcheck disable=SC2016
    printf 'a\n@.agent-context/layer2.md\n| x | @.agent-context/tbl.md |\nsee `@code-span.md` here\n```\n@fenced.md\n```\n' > "$d/AGENTS.md"
    printf 'l2\n@base-principles.md\n' > "$d/.agent-context/layer2.md"
    printf 'bp\n' > "$d/.agent-context/base-principles.md"
    printf 't\n' > "$d/.agent-context/tbl.md"
    printf 'decoy\n' > "$d/base-principles.md"
    printf 'x\n' > "$d/code-span.md"
    printf 'x\n' > "$d/fenced.md"
    printf 'extra one\nextra two\n' > "$d/extra.md"
    printf 'MAX_EFFECTIVE_LINES=100\n' > "$d/budget.conf"
    echo "$d"
}
json_total() { sed -n 's/.*"total_effective_lines": \([0-9]*\).*/\1/p'; }
P=$(mk_proj)
listed=$(run_in "$P" --list --conf budget.conf 2>/dev/null | sort | tr '\n' ' ')
assert_eq "walk resolves imports relative to the importing file" \
    ".agent-context/base-principles.md .agent-context/layer2.md .agent-context/tbl.md .claude/CLAUDE.md AGENTS.md " "$listed"
assert_eq "walked set is counted (2+7+2+1+1)" "13" "$(run_in "$P" --json --conf budget.conf 2>/dev/null | json_total)"
assert_eq "imports in code spans and fences are ignored" "0" \
    "$(run_in "$P" --list --conf budget.conf 2>/dev/null | grep -c -e 'code-span.md' -e 'fenced.md')"

P=$(mk_proj)
printf 'root rule\n' > "$P/CLAUDE.md"
assert_eq "root CLAUDE.md is walked when present" "1" "$(run_in "$P" --list --conf budget.conf 2>/dev/null | grep -cx 'CLAUDE.md')"

# 20. INCLUDE_FILES is optional and additive: a file nobody imports counts only when listed there.
P=$(mk_proj)
assert_eq "unimported file not counted without INCLUDE_FILES" "0" "$(run_in "$P" --list --conf budget.conf 2>/dev/null | grep -cx 'extra.md')"
printf 'MAX_EFFECTIVE_LINES=100\nINCLUDE_FILES="\nextra.md\nAGENTS.md\n"\n' > "$P/budget.conf"
assert_eq "INCLUDE_FILES adds an unimported file" "1" "$(run_in "$P" --list --conf budget.conf 2>/dev/null | grep -cx 'extra.md')"
assert_eq "INCLUDE_FILES and walk are deduplicated" "1" "$(run_in "$P" --list --conf budget.conf 2>/dev/null | grep -cx 'AGENTS.md')"
assert_eq "INCLUDE_FILES lines added to the walked total" "15" "$(run_in "$P" --json --conf budget.conf 2>/dev/null | json_total)"
err=$(run_in "$P" --conf budget.conf --quiet 2>&1 >/dev/null)
assert_eq "unimported INCLUDE_FILES entry is noted" "1" \
    "$(printf '%s\n' "$err" | grep -cx 'note: extra.md is counted from INCLUDE_FILES but not @-imported')"
assert_eq "INCLUDE_FILES entry the walk reaches is deduplicated silently" "0" "$(printf '%s\n' "$err" | grep -c 'AGENTS.md')"

# 20b. SESSION_START_FILES: deliberate session-start reads without an import — counted, never noted.
P=$(mk_proj)
printf 'MAX_EFFECTIVE_LINES=100\nSESSION_START_FILES="\nextra.md\nAGENTS.md\n"\n' > "$P/budget.conf"
assert_eq "SESSION_START_FILES adds an unimported file" "1" "$(run_in "$P" --list --conf budget.conf 2>/dev/null | grep -cx 'extra.md')"
assert_eq "SESSION_START_FILES and walk are deduplicated" "1" "$(run_in "$P" --list --conf budget.conf 2>/dev/null | grep -cx 'AGENTS.md')"
assert_eq "SESSION_START_FILES lines added to the walked total" "15" "$(run_in "$P" --json --conf budget.conf 2>/dev/null | json_total)"
assert_eq "SESSION_START_FILES prints no note" "0" "$(run_in "$P" --conf budget.conf --quiet 2>&1 >/dev/null | grep -c 'note:')"

# 20c. The shipped template conf in an install-shaped tree prints no note at all.
P=$(mk_proj)
mkdir -p "$P/.agent-context/memory"
printf 'lesson\n' > "$P/.agent-context/memory/lessons.md"
printf 'pref\n' > "$P/.agent-context/memory/preferences.md"
cp "$REPO_ROOT/templates/.agent-context/budget.conf" "$P/budget.conf"
err=$(run_in "$P" --conf budget.conf --quiet 2>&1 >/dev/null)
assert_eq "template conf run prints no note" "0" "$(printf '%s\n' "$err" | grep -c 'note:')"
assert_eq "template conf counts the session-start reads" "2" \
    "$(run_in "$P" --list --conf budget.conf 2>/dev/null | grep -c -e 'memory/lessons.md' -e 'memory/preferences.md')"

# 21. A dangling import warns but does not fail the gate.
P=$(mk_proj)
printf 'l2\n@base-principles.md\n@gone.md\n' > "$P/.agent-context/layer2.md"
err=$(run_in "$P" --conf budget.conf --quiet 2>&1 >/dev/null); code=$?
assert_eq "dangling import exits 0" "0" "$code"
assert_eq "dangling import is reported" "1" "$(printf '%s\n' "$err" | grep -c 'gone.md')"

# 22. Usage and config errors exit 2, never 1 — 1 means over budget.
t=$(mk_tmp)
printf 'a\n' > "$t/f.md"
bash "$ENGINE" "$t/f.md" --max >/dev/null 2>&1
assert_eq "--max without a value exits 2" "2" "$?"
bash "$ENGINE" "$t/f.md" --conf >/dev/null 2>&1
assert_eq "--conf without a value exits 2" "2" "$?"
bash "$ENGINE" --bogus "$t/f.md" >/dev/null 2>&1
assert_eq "unknown option exits 2" "2" "$?"
bash "$ENGINE" --max abc "$t/f.md" >/dev/null 2>&1
assert_eq "non-integer --max exits 2" "2" "$?"
printf 'MAX_EFFECTIVE_LINES=ten\n' > "$t/bad.conf"
bash "$ENGINE" --conf "$t/bad.conf" "$t/f.md" >/dev/null 2>&1
assert_eq "non-integer cap in the conf exits 2" "2" "$?"
t=$(mk_tmp)
printf 'MAX_EFFECTIVE_LINES=10\n' > "$t/budget.conf"
err=$(run_in "$t" --conf "$t/budget.conf" --quiet 2>&1 >/dev/null); code=$?
{ [ "$code" -eq 2 ] && printf '%s' "$err" | grep -q "no files to check"; } \
    && pass "no files to check exits 2" || fail "no files to check exits 2" "code=$code err=$err"

# 23. Paths are data: backslashes are printed verbatim and JSON-escaped, never interpreted.
t=$(mk_tmp)
bs_name='a\nb\tc.md'
tab_name="$(printf 'tab\there.md')"
printf 'x\n' > "$t/$bs_name"
printf 'y\n' > "$t/$tab_name"
out=$(bash "$ENGINE" --max 99 "$t/$bs_name" 2>/dev/null)
assert_eq "table prints a backslash path verbatim" "1" "$(grep -cF "$t/$bs_name" <<<"$out")"
js=$(bash "$ENGINE" --json --max 99 "$t/$bs_name" "$t/$tab_name" 2>/dev/null)
assert_eq "json escapes backslashes in a path" "1" "$(grep -cF '/a\\nb\\tc.md"' <<<"$js")"
assert_eq "json escapes a control character in a path" "1" "$(grep -cF 'tab\u0009here.md"' <<<"$js")"
assert_eq "json keeps one line per file" "2" "$(grep -c '"path"' <<<"$js")"

# 24. INCLUDE_FILES entries are paths, not globs.
t=$(mk_tmp)
printf 'a\n' > "$t/one.md"
printf 'b\n' > "$t/two.md"
printf 'INCLUDE_FILES="*.md"\n' > "$t/glob.conf"
assert_eq "INCLUDE_FILES glob is not expanded" "*.md" "$(run_in "$t" --list --conf glob.conf 2>/dev/null)"

echo ""
echo "================================================"
TOTAL=$((PASS + FAIL))
printf "Results: %d/%d passed\n" "$PASS" "$TOTAL"
[ "$FAIL" -eq 0 ] && { echo "ALL PASSED"; exit 0; } || { echo "FAILED"; exit 1; }
