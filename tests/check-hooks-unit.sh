#!/usr/bin/env bash
# tests/check-hooks-unit.sh — unit tests for context/hooks/*.sh
#
# Drives each hook with a realistic stdin JSON payload and a temp hooks.conf (via
# AGENT_CONTEXT_HOOKS_CONF) and asserts: master off = no-op, secret-block exits 2,
# format runs the command, the Stop gate warns vs blocks, and the subagent scope check fires.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS="$REPO_ROOT/context/hooks"

PASS=0
FAIL=0
TMP_ROOTS=()
cleanup() { for d in "${TMP_ROOTS[@]:-}"; do [ -d "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT
mk_tmp() { local d; d=$(mktemp -d "${TMPDIR:-/tmp}/hooks-test.XXXXXX"); TMP_ROOTS+=("$d"); echo "$d"; }
pass() { printf "  PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL  %s\n    => %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

# run_hook <script> <conf> <stdin-json> -> sets RC, OUT (stdout), ERR (stderr)
run_hook() {
    local script="$1" conf="$2" json="$3" outf errf
    outf=$(mktemp); errf=$(mktemp)
    AGENT_CONTEXT_HOOKS_CONF="$conf" printf '%s' "$json" \
        | AGENT_CONTEXT_HOOKS_CONF="$conf" bash "$script" >"$outf" 2>"$errf"
    RC=$?
    OUT="$(cat "$outf")"; ERR="$(cat "$errf")"
    rm -f "$outf" "$errf"
}

echo "=== hooks unit tests ==="
echo ""

# --- pre-protect-secrets ---
echo "--- pre-protect-secrets (PreToolUse) ---"
t=$(mk_tmp)
printf 'HOOKS_ENABLED=1\nPROTECT_SECRETS=1\nPROTECTED_GLOBS=".env .env.* *.key"\n' > "$t/on.conf"
printf 'HOOKS_ENABLED=0\n' > "$t/off.conf"

run_hook "$HOOKS/pre-protect-secrets.sh" "$t/on.conf" '{"tool_name":"Write","tool_input":{"file_path":".env"}}'
[ "$RC" -eq 2 ] && pass "writing .env exits 2 (blocked)" || fail "writing .env exits 2" "rc=$RC"

run_hook "$HOOKS/pre-protect-secrets.sh" "$t/on.conf" '{"tool_name":"Write","tool_input":{"file_path":"config/app.key"}}'
[ "$RC" -eq 2 ] && pass "writing *.key exits 2 (blocked)" || fail "writing *.key exits 2" "rc=$RC"

run_hook "$HOOKS/pre-protect-secrets.sh" "$t/on.conf" '{"tool_name":"Write","tool_input":{"file_path":"src/app.js"}}'
[ "$RC" -eq 0 ] && pass "writing normal file exits 0 (allowed)" || fail "writing normal file exits 0" "rc=$RC"

run_hook "$HOOKS/pre-protect-secrets.sh" "$t/off.conf" '{"tool_name":"Write","tool_input":{"file_path":".env"}}'
[ "$RC" -eq 0 ] && pass "master off → .env write not blocked" || fail "master off → not blocked" "rc=$RC"

# --- post-format ---
echo "--- post-format (PostToolUse) ---"
t=$(mk_tmp)
target="$t/file.txt"; marker="$t/formatted.marker"
printf 'content\n' > "$target"
printf 'HOOKS_ENABLED=1\nFORMAT_ON_EDIT=1\nFORMAT_CMD="cp {} %s"\n' "$marker" > "$t/fmt.conf"
run_hook "$HOOKS/post-format.sh" "$t/fmt.conf" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$target\"}}"
[ -f "$marker" ] && pass "FORMAT_CMD runs on edited file" || fail "FORMAT_CMD runs on edited file" "marker not created"

printf 'HOOKS_ENABLED=1\nFORMAT_ON_EDIT=0\nFORMAT_CMD="cp {} %s.off"\n' "$marker" > "$t/fmtoff.conf"
run_hook "$HOOKS/post-format.sh" "$t/fmtoff.conf" "{\"tool_input\":{\"file_path\":\"$target\"}}"
[ ! -f "$marker.off" ] && pass "FORMAT_ON_EDIT=0 → no formatting" || fail "FORMAT_ON_EDIT=0 → no formatting" "ran anyway"

# --- stop-test-gate ---
echo "--- stop-test-gate (Stop) ---"
t=$(mk_tmp)
printf 'HOOKS_ENABLED=1\nSTOP_GATE="warn"\nTEST_CMD="false"\n' > "$t/warn.conf"
run_hook "$HOOKS/stop-test-gate.sh" "$t/warn.conf" '{"hook_event_name":"Stop"}'
{ [ "$RC" -eq 0 ] && printf '%s' "$ERR" | grep -q "test gate"; } \
    && pass "warn mode: failing tests → exit 0 + stderr warning" || fail "warn mode" "rc=$RC err=$ERR"

printf 'HOOKS_ENABLED=1\nSTOP_GATE="block"\nTEST_CMD="false"\n' > "$t/block.conf"
run_hook "$HOOKS/stop-test-gate.sh" "$t/block.conf" '{"hook_event_name":"Stop","stop_hook_active":false}'
{ [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '"decision":"block"'; } \
    && pass "block mode: failing tests → decision:block payload" || fail "block mode" "rc=$RC out=$OUT"

run_hook "$HOOKS/stop-test-gate.sh" "$t/block.conf" '{"hook_event_name":"Stop","stop_hook_active":true}'
{ [ "$RC" -eq 0 ] && ! printf '%s' "$OUT" | grep -q '"decision":"block"'; } \
    && pass "block mode: stop_hook_active=true → no re-block (loop guard)" || fail "loop guard" "out=$OUT"

# Loop guard must hold WITHOUT jq too — stop_hook_active is a JSON boolean the sed
# fallback must read. Build a jq-free sandbox bin with only the tools the hook needs.
sandbox="$(mk_tmp)/bin"; mkdir -p "$sandbox"
for b in bash sh cat sed grep head tail tr rm mktemp false true awk dirname basename; do
    p="$(command -v "$b" 2>/dev/null)" && ln -sf "$p" "$sandbox/$b"
done
if PATH="$sandbox" command -v jq >/dev/null 2>&1; then
    echo "  SKIP  no-jq loop guard (could not isolate jq)"
else
    outf=$(mktemp)
    PATH="$sandbox" AGENT_CONTEXT_HOOKS_CONF="$t/block.conf" "$sandbox/bash" "$HOOKS/stop-test-gate.sh" \
        <<<'{"hook_event_name":"Stop","stop_hook_active":true}' >"$outf" 2>/dev/null
    grep -q '"decision":"block"' "$outf" \
        && fail "no-jq: loop guard holds (stop_hook_active=true → no re-block)" "re-blocked without jq" \
        || pass "no-jq: loop guard holds (stop_hook_active=true → no re-block)"
    # And block mode WITHOUT jq still emits valid block JSON when it should (sed fallback path).
    PATH="$sandbox" AGENT_CONTEXT_HOOKS_CONF="$t/block.conf" "$sandbox/bash" "$HOOKS/stop-test-gate.sh" \
        <<<'{"hook_event_name":"Stop","stop_hook_active":false}' >"$outf" 2>/dev/null
    grep -q '"decision":"block"' "$outf" \
        && pass "no-jq: block mode still emits decision payload" \
        || fail "no-jq: block mode still emits decision payload" "no payload without jq"
    rm -f "$outf"
fi

printf 'HOOKS_ENABLED=1\nSTOP_GATE="block"\nTEST_CMD="true"\n' > "$t/pass.conf"
run_hook "$HOOKS/stop-test-gate.sh" "$t/pass.conf" '{"hook_event_name":"Stop"}'
{ [ "$RC" -eq 0 ] && [ -z "$OUT" ]; } && pass "passing tests → exit 0, no payload" || fail "passing tests" "rc=$RC out=$OUT"

# --- subagent-scope ---
echo "--- subagent-scope (SubagentStop) ---"
t=$(mk_tmp)
tr="$t/transcript.jsonl"
cat > "$tr" <<'JSONL'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"src/ok.js","content":"x"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"config/secret.yml"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"config/reads-are-fine.yml"}}]}}
JSONL
printf 'HOOKS_ENABLED=1\nSUBAGENT_SCOPE="warn"\nALLOWED_SUBAGENT_PATHS="src/*"\n' > "$t/scope-warn.conf"
run_hook "$HOOKS/subagent-scope.sh" "$t/scope-warn.conf" "{\"transcript_path\":\"$tr\"}"
{ [ "$RC" -eq 0 ] && printf '%s' "$ERR" | grep -q "config/secret.yml" \
    && ! printf '%s' "$ERR" | grep -q "reads-are-fine.yml"; } \
    && pass "warn: out-of-scope WRITE flagged, READ ignored" || fail "scope warn" "rc=$RC err=$ERR"

printf 'HOOKS_ENABLED=1\nSUBAGENT_SCOPE="block"\nALLOWED_SUBAGENT_PATHS="src/*"\n' > "$t/scope-block.conf"
run_hook "$HOOKS/subagent-scope.sh" "$t/scope-block.conf" "{\"transcript_path\":\"$tr\"}"
printf '%s' "$OUT" | grep -q '"decision":"block"' && pass "block mode: out-of-scope → decision:block" || fail "scope block" "out=$OUT"

printf 'HOOKS_ENABLED=1\nSUBAGENT_SCOPE="warn"\nALLOWED_SUBAGENT_PATHS="src/* config/*"\n' > "$t/scope-ok.conf"
run_hook "$HOOKS/subagent-scope.sh" "$t/scope-ok.conf" "{\"transcript_path\":\"$tr\"}"
{ [ "$RC" -eq 0 ] && [ -z "$ERR" ]; } && pass "all writes in scope → silent exit 0" || fail "scope ok" "rc=$RC err=$ERR"

echo ""
echo "================================================"
TOTAL=$((PASS + FAIL))
printf "Results: %d/%d passed\n" "$PASS" "$TOTAL"
[ "$FAIL" -eq 0 ] && { echo "ALL PASSED"; exit 0; } || { echo "FAILED"; exit 1; }
