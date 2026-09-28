#!/usr/bin/env bash
# tests/check-hooks-unit.sh — unit tests for context/hooks/*.sh
#
# Drives each hook with a realistic stdin JSON payload and a temp hooks.local.conf (via
# AGENT_CONTEXT_HOOKS_LOCAL_CONF), optionally beside a committed hooks.conf (AGENT_CONTEXT_HOOKS_CONF),
# and asserts: master off = no-op, secret-block exits 2, format runs the command, the Stop gate
# warns vs blocks, the subagent scope check fires, and executable keys are honoured only locally.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS="$REPO_ROOT/context/hooks"

PASS=0
FAIL=0
# shellcheck source=tests/lib.sh
source "$REPO_ROOT/tests/lib.sh"
pass() { printf "  PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL  %s\n    => %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

NO_CONF="$(mk_tmp)/absent.conf"

# run_hook <script> <local-conf> <stdin-json> [<committed-conf>] -> sets RC, OUT (stdout), ERR (stderr)
run_hook() {
    local script="$1" local_conf="$2" json="$3" conf="${4:-$NO_CONF}" outf errf
    outf=$(mktemp); errf=$(mktemp)
    printf '%s' "$json" \
        | AGENT_CONTEXT_HOOKS_CONF="$conf" AGENT_CONTEXT_HOOKS_LOCAL_CONF="$local_conf" \
            bash "$script" >"$outf" 2>"$errf"
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

# Patterns are matched literally, never glob-expanded against the hook's cwd (the project root),
# and case-insensitively: a.pem / .env.local on disk must not narrow `*.pem` / `.env.*`, and .ENV
# is the same file as .env on a case-insensitive filesystem.
t2=$(mk_tmp)
touch "$t2/a.pem" "$t2/.env.local"
printf 'HOOKS_ENABLED=1\nPROTECT_SECRETS=1\nPROTECTED_GLOBS=".env .env.* *.pem"\n' > "$t2/on.conf"
for f in b.pem .env.production .ENV; do
    rc=0
    ( cd "$t2" && printf '{"tool_name":"Write","tool_input":{"file_path":"%s/%s"}}' "$t2" "$f" \
        | AGENT_CONTEXT_HOOKS_CONF="$NO_CONF" AGENT_CONTEXT_HOOKS_LOCAL_CONF="$t2/on.conf" bash "$HOOKS/pre-protect-secrets.sh" >/dev/null 2>&1 ) || rc=$?
    [ "$rc" -eq 2 ] && pass "$f blocked although matching files exist in cwd" || fail "$f blocked" "rc=$rc"
done

# A CRLF hooks.conf (Windows checkout) must not silently switch every hook off.
printf 'HOOKS_ENABLED=1\r\nPROTECT_SECRETS=1\r\nPROTECTED_GLOBS=".env"\r\n' > "$t/crlf.conf"
run_hook "$HOOKS/pre-protect-secrets.sh" "$t/crlf.conf" '{"tool_name":"Write","tool_input":{"file_path":".env"}}'
[ "$RC" -eq 2 ] && pass "CRLF hooks.conf still blocks .env" || fail "CRLF hooks.conf still blocks .env" "rc=$RC"

# An escaped quote inside a double-quoted value is not supported; truncating at it would turn
# TEST_CMD="echo \"hi\" && false" into `echo \`, a gate that always passes. Refuse the key instead.
printf 'TEST_CMD="echo \\"hi\\" && false"\n' > "$t/esc.conf"
esc_err="$( bash -c '. "$1"; conf_get "$2" TEST_CMD; echo "[${_conf_v_TEST_CMD-unset}]"' _ \
    "$REPO_ROOT/context/bin/conf-read.sh" "$t/esc.conf" 2>&1 >/dev/null )"
esc_out="$( bash -c '. "$1"; if conf_get "$2" TEST_CMD >/dev/null 2>&1; then echo set; else echo unset; fi' _ \
    "$REPO_ROOT/context/bin/conf-read.sh" "$t/esc.conf" )"
[ "$esc_out" = "unset" ] && pass "escaped quote leaves the key unset" || fail "escaped quote leaves the key unset" "got $esc_out"
printf '%s' "$esc_err" | grep -q "escaped quote" && pass "escaped quote is reported on stderr" \
    || fail "escaped quote is reported" "stderr: $esc_err"

# --- post-format ---
echo "--- post-format (PostToolUse) ---"
t=$(mk_tmp)
target="$t/file.txt"; marker="$t/formatted.marker"
printf 'content\n' > "$target"
printf 'HOOKS_ENABLED=1\nFORMAT_ON_EDIT=1\nFORMAT_CMD="cp {} %s"\n' "$marker" > "$t/fmt.conf"
run_hook "$HOOKS/post-format.sh" "$t/fmt.conf" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$target\"}}"
[ -f "$marker" ] && pass "FORMAT_CMD runs on edited file" || fail "FORMAT_CMD runs on edited file" "marker not created"

target_sp="$t/has space.txt"; marker_sp="$t/fmt-spaced.marker"
printf 'content\n' > "$target_sp"
printf 'HOOKS_ENABLED=1\nFORMAT_ON_EDIT=1\nFORMAT_CMD="cp {} %s"\n' "$marker_sp" > "$t/fmt-spaced.conf"
run_hook "$HOOKS/post-format.sh" "$t/fmt-spaced.conf" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$target_sp\"}}"
[ -f "$marker_sp" ] && pass "format handles path with spaces (no eval breakage)" || fail "spaced path format" "marker not created"

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
    PATH="$sandbox" AGENT_CONTEXT_HOOKS_CONF="$NO_CONF" AGENT_CONTEXT_HOOKS_LOCAL_CONF="$t/block.conf" "$sandbox/bash" "$HOOKS/stop-test-gate.sh" \
        <<<'{"hook_event_name":"Stop","stop_hook_active":true}' >"$outf" 2>/dev/null
    grep -q '"decision":"block"' "$outf" \
        && fail "no-jq: loop guard holds (stop_hook_active=true → no re-block)" "re-blocked without jq" \
        || pass "no-jq: loop guard holds (stop_hook_active=true → no re-block)"
    # And block mode WITHOUT jq still emits valid block JSON when it should (sed fallback path).
    PATH="$sandbox" AGENT_CONTEXT_HOOKS_CONF="$NO_CONF" AGENT_CONTEXT_HOOKS_LOCAL_CONF="$t/block.conf" "$sandbox/bash" "$HOOKS/stop-test-gate.sh" \
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

# --- committed hooks.conf vs. user-local hooks.local.conf ---
echo "--- hooks.conf / hooks.local.conf split ---"
t=$(mk_tmp)
printf 'HOOKS_ENABLED=1\nSTOP_GATE="block"\nTEST_CMD="touch %s/pulled.marker"\n' "$t" > "$t/pulled.conf"
run_hook "$HOOKS/stop-test-gate.sh" "$NO_CONF" '{"hook_event_name":"Stop"}' "$t/pulled.conf"
{ [ ! -f "$t/pulled.marker" ] && [ -z "$OUT" ]; } && pass "committed HOOKS_ENABLED=1 + TEST_CMD → nothing runs" \
    || fail "committed HOOKS_ENABLED=1 + TEST_CMD → nothing runs" "TEST_CMD executed or out=$OUT"

printf 'HOOKS_ENABLED=1\n' > "$t/local-on.conf"
run_hook "$HOOKS/stop-test-gate.sh" "$t/local-on.conf" '{"hook_event_name":"Stop"}' "$t/pulled.conf"
[ ! -f "$t/pulled.marker" ] && pass "local HOOKS_ENABLED=1 does not adopt a committed TEST_CMD" \
    || fail "local HOOKS_ENABLED=1 does not adopt a committed TEST_CMD" "committed TEST_CMD was executed"

printf 'HOOKS_ENABLED=1\nTEST_CMD="touch %s/local.marker"\n' "$t" > "$t/local-test.conf"
run_hook "$HOOKS/stop-test-gate.sh" "$t/local-test.conf" '{"hook_event_name":"Stop"}' "$t/pulled.conf"
[ -f "$t/local.marker" ] && pass "TEST_CMD from hooks.local.conf runs" || fail "TEST_CMD from hooks.local.conf runs" "marker missing"

target="$t/file.txt"
printf 'content\n' > "$target"
printf 'HOOKS_ENABLED=1\nFORMAT_CMD="cp {} %s/pulled-fmt.marker"\n' "$t" > "$t/pulled-fmt.conf"
run_hook "$HOOKS/post-format.sh" "$t/local-on.conf" "{\"tool_input\":{\"file_path\":\"$target\"}}" "$t/pulled-fmt.conf"
[ ! -f "$t/pulled-fmt.marker" ] && pass "committed FORMAT_CMD is ignored" || fail "committed FORMAT_CMD is ignored" "FORMAT_CMD was executed"

printf 'PROTECT_SECRETS=1\nPROTECTED_GLOBS="*.custom"\n' > "$t/globs.conf"
run_hook "$HOOKS/pre-protect-secrets.sh" "$t/local-on.conf" '{"tool_input":{"file_path":"a.custom"}}' "$t/globs.conf"
[ "$RC" -eq 2 ] && pass "PROTECTED_GLOBS from hooks.conf apply once enabled locally" \
    || fail "PROTECTED_GLOBS from hooks.conf apply once enabled locally" "rc=$RC"

printf 'HOOKS_ENABLED=1\nPROTECT_SECRETS=0\n' > "$t/local-nosecrets.conf"
run_hook "$HOOKS/pre-protect-secrets.sh" "$t/local-nosecrets.conf" '{"tool_input":{"file_path":"a.custom"}}' "$t/globs.conf"
[ "$RC" -eq 0 ] && pass "hooks.local.conf overrides a hooks.conf key" || fail "hooks.local.conf overrides a hooks.conf key" "rc=$RC"

echo ""
echo "================================================"
TOTAL=$((PASS + FAIL))
printf "Results: %d/%d passed\n" "$PASS" "$TOTAL"
[ "$FAIL" -eq 0 ] && { echo "ALL PASSED"; exit 0; } || { echo "FAILED"; exit 1; }
