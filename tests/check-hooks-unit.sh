#!/usr/bin/env bash
# tests/check-hooks-unit.sh — unit tests for context/hooks/*.sh
#
# Drives each hook with a realistic stdin JSON payload and a temp hooks.local.conf (via
# AGENT_CONTEXT_HOOKS_LOCAL_CONF), optionally beside a committed hooks.conf (AGENT_CONTEXT_HOOKS_CONF),
# and asserts: master off = no-op, secret-block exits 2, format runs the command, the Stop gate
# warns vs blocks, the subagent scope check fires, and executable keys are honoured only locally.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS="${HOOKS_UNDER_TEST:-$REPO_ROOT/context/hooks}"
JSON_CHECK="${JSON_CHECK-$(command -v jq 2>/dev/null)}"

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
    outf=$(mktemp "$TMP_ROOT/XXXXXX"); errf=$(mktemp "$TMP_ROOT/XXXXXX")
    printf '%s' "$json" \
        | AGENT_CONTEXT_HOOKS_CONF="$conf" AGENT_CONTEXT_HOOKS_LOCAL_CONF="$local_conf" \
            "$BASH" "$script" >"$outf" 2>"$errf"
    RC=$?
    OUT="$(cat "$outf")"; ERR="$(cat "$errf")"
    rm -f "$outf" "$errf"
}

valid_json() { [ -z "$JSON_CHECK" ] || printf '%s' "$1" | "$JSON_CHECK" -e . >/dev/null 2>&1; }
system_message() { printf '%s' "$1" | grep -q '"systemMessage"' && printf '%s' "$1" | grep -q "$2" && valid_json "$1"; }

echo "=== hooks unit tests${HOOKS_TEST_NOJQ:+ (no jq)} ==="
echo ""

# --- pre-protect-secrets ---
echo "--- pre-protect-secrets (PreToolUse) ---"
t=$(mk_tmp)
printf 'HOOKS_ENABLED=1\nPROTECT_SECRETS=1\nPROTECTED_GLOBS=".env .env.* *.key"\n' > "$t/on.conf"
printf 'HOOKS_ENABLED=0\n' > "$t/off.conf"
printf 'HOOKS_ENABLED=1\nPROTECTED_GLOBS=".env .env.* *.pem *.key"\n' > "$t/on2.conf"

run_hook "$HOOKS/pre-protect-secrets.sh" "$t/on.conf" '{"tool_name":"Write","tool_input":{"file_path":".env"}}'
[ "$RC" -eq 2 ] && pass "writing .env exits 2 (blocked)" || fail "writing .env exits 2" "rc=$RC"

run_hook "$HOOKS/pre-protect-secrets.sh" "$t/on.conf" '{"tool_name":"Write","tool_input":{"file_path":"config/app.key"}}'
[ "$RC" -eq 2 ] && pass "writing *.key exits 2 (blocked)" || fail "writing *.key exits 2" "rc=$RC"

run_hook "$HOOKS/pre-protect-secrets.sh" "$t/on.conf" '{"tool_name":"Write","tool_input":{"file_path":"src/app.js"}}'
[ "$RC" -eq 0 ] && pass "writing normal file exits 0 (allowed)" || fail "writing normal file exits 0" "rc=$RC"

run_hook "$HOOKS/pre-protect-secrets.sh" "$t/off.conf" '{"tool_name":"Write","tool_input":{"file_path":".env"}}'
[ "$RC" -eq 2 ] && pass "HOOKS_ENABLED=0 → .env write still blocked" || fail "HOOKS_ENABLED=0 → .env write still blocked" "rc=$RC"

run_hook "$HOOKS/pre-protect-secrets.sh" "$NO_CONF" '{"tool_name":"Write","tool_input":{"file_path":".env"}}'
[ "$RC" -eq 2 ] && pass "no hooks.conf / hooks.local.conf → .env write blocked" \
    || fail "no hooks.conf / hooks.local.conf → .env write blocked" "rc=$RC"

run_hook "$HOOKS/pre-protect-secrets.sh" "$NO_CONF" '{"tool_name":"Write","tool_input":{"file_path":"id_rsa.bak"}}'
[ "$RC" -eq 2 ] && pass "built-in globs cover id_rsa.*" || fail "built-in globs cover id_rsa.*" "rc=$RC"

printf 'PROTECT_SECRETS=0\n' > "$t/nosecrets.conf"
run_hook "$HOOKS/pre-protect-secrets.sh" "$t/nosecrets.conf" '{"tool_name":"Write","tool_input":{"file_path":".env"}}'
[ "$RC" -eq 0 ] && pass "local PROTECT_SECRETS=0 → guard off" || fail "local PROTECT_SECRETS=0 → guard off" "rc=$RC"

run_hook "$HOOKS/pre-protect-secrets.sh" "$NO_CONF" '{"tool_name":"Write","tool_input":{"file_path":".env"}}' "$t/nosecrets.conf"
[ "$RC" -eq 0 ] && pass "committed PROTECT_SECRETS=0 → guard off" || fail "committed PROTECT_SECRETS=0 → guard off" "rc=$RC"

printf 'PROTECT_SECRETS="0\nPROTECTED_GLOBS="*.none\n' > "$t/broken.conf"
run_hook "$HOOKS/pre-protect-secrets.sh" "$t/broken.conf" '{"tool_name":"Write","tool_input":{"file_path":".env"}}'
[ "$RC" -eq 2 ] && pass "unparseable conf → built-in defaults, .env blocked" \
    || fail "unparseable conf → built-in defaults, .env blocked" "rc=$RC"

noreader="$(mk_tmp)"
mkdir -p "$noreader/hooks"
cp "$HOOKS"/*.sh "$noreader/hooks/"
printf 'PROTECT_SECRETS=0\n' > "$noreader/hooks.conf"
printf '{"tool_name":"Write","tool_input":{"file_path":".env"}}' \
    | AGENT_CONTEXT_HOOKS_CONF="$noreader/hooks.conf" AGENT_CONTEXT_HOOKS_LOCAL_CONF="$NO_CONF" \
        "$BASH" "$noreader/hooks/pre-protect-secrets.sh" >/dev/null 2>&1
RC=$?
[ "$RC" -eq 2 ] && pass "conf-read.sh missing → guard fails closed" || fail "conf-read.sh missing → guard fails closed" "rc=$RC"

for f in "$t/.env" "$t/x.pem"; do
    run_hook "$HOOKS/pre-protect-secrets.sh" "$t/on2.conf" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}"
    [ "$RC" -eq 2 ] && pass "absolute $(basename "$f") blocked" || fail "absolute $(basename "$f") blocked" "rc=$RC"
done
{ printf '%s' "$ERR" | grep -q "writes" && ! printf '%s' "$ERR" | grep -q "reading"; } \
    && pass "block message claims writes only" || fail "block message claims writes only" "err=$ERR"

run_hook "$HOOKS/pre-protect-secrets.sh" "$t/on2.conf" "{\"tool_name\":\"MultiEdit\",\"tool_input\":{\"file_path\":\"$t/.env\",\"edits\":[]}}"
[ "$RC" -eq 2 ] && pass "MultiEdit on .env blocked" || fail "MultiEdit on .env blocked" "rc=$RC"

for f in .env.example .env.dist .env.sample; do
    run_hook "$HOOKS/pre-protect-secrets.sh" "$t/on2.conf" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$t/$f\"}}"
    [ "$RC" -eq 0 ] && pass "$f allowed (template suffix)" || fail "$f allowed (template suffix)" "rc=$RC"
done

printf 'X=1\n' > "$t/.env"
ln -s "$t/.env" "$t/innocent.txt"
run_hook "$HOOKS/pre-protect-secrets.sh" "$t/on2.conf" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$t/innocent.txt\"}}"
[ "$RC" -eq 2 ] && pass "symlink to .env blocked" || fail "symlink to .env blocked" "rc=$RC"

# Patterns are matched literally, never glob-expanded against the hook's cwd (the project root),
# and case-insensitively: a.pem / .env.local on disk must not narrow `*.pem` / `.env.*`, and .ENV
# is the same file as .env on a case-insensitive filesystem.
t2=$(mk_tmp)
touch "$t2/a.pem" "$t2/.env.local"
printf 'HOOKS_ENABLED=1\nPROTECT_SECRETS=1\nPROTECTED_GLOBS=".env .env.* *.pem"\n' > "$t2/on.conf"
for f in b.pem .env.production .ENV; do
    rc=0
    ( cd "$t2" && printf '{"tool_name":"Write","tool_input":{"file_path":"%s/%s"}}' "$t2" "$f" \
        | AGENT_CONTEXT_HOOKS_CONF="$NO_CONF" AGENT_CONTEXT_HOOKS_LOCAL_CONF="$t2/on.conf" "$BASH" "$HOOKS/pre-protect-secrets.sh" >/dev/null 2>&1 ) || rc=$?
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
export CLAUDE_PROJECT_DIR="$t"
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

printf 'content\n' > "$t/appended.txt"
printf 'HOOKS_ENABLED=1\nFORMAT_CMD="rm"\n' > "$t/fmt-append.conf"
run_hook "$HOOKS/post-format.sh" "$t/fmt-append.conf" "{\"tool_input\":{\"file_path\":\"$t/appended.txt\"}}"
[ ! -f "$t/appended.txt" ] && pass "FORMAT_CMD without {} gets the path appended" || fail "FORMAT_CMD without {} appends path" "file still there"

printf 'HOOKS_ENABLED=1\nFORMAT_CMD="false"\n' > "$t/fmt-fail.conf"
run_hook "$HOOKS/post-format.sh" "$t/fmt-fail.conf" "{\"tool_input\":{\"file_path\":\"$target\"}}"
{ [ "$RC" -eq 0 ] && system_message "$OUT" "format command failed"; } \
    && pass "format failure → exit 0 + systemMessage" || fail "format failure → systemMessage" "rc=$RC out=$OUT"

outside="$(mk_tmp)/outside.txt"
printf 'content\n' > "$outside"
run_hook "$HOOKS/post-format.sh" "$t/fmt-append.conf" "{\"tool_input\":{\"file_path\":\"$outside\"}}"
[ -f "$outside" ] && pass "file outside CLAUDE_PROJECT_DIR is not formatted" || fail "outside file not formatted" "FORMAT_CMD ran on it"
unset CLAUDE_PROJECT_DIR

# --- stop-test-gate ---
echo "--- stop-test-gate (Stop) ---"
t=$(mk_tmp)
printf 'HOOKS_ENABLED=1\nSTOP_GATE="warn"\nTEST_CMD="false"\n' > "$t/warn.conf"
run_hook "$HOOKS/stop-test-gate.sh" "$t/warn.conf" '{"hook_event_name":"Stop"}'
{ [ "$RC" -eq 0 ] && system_message "$OUT" "test gate"; } \
    && pass "warn mode: failing tests → exit 0 + systemMessage" || fail "warn mode" "rc=$RC out=$OUT"

printf 'HOOKS_ENABLED=1\nSTOP_GATE="off"\nTEST_CMD="touch %s/off.marker"\n' "$t" > "$t/gate-off.conf"
run_hook "$HOOKS/stop-test-gate.sh" "$t/gate-off.conf" '{"hook_event_name":"Stop"}'
[ ! -f "$t/off.marker" ] && pass "STOP_GATE=off → TEST_CMD not run" || fail "STOP_GATE=off" "TEST_CMD ran"

printf 'HOOKS_ENABLED=1\nSTOP_GATE="block"\nTEST_CMD="touch %s/active.marker"\n' "$t" > "$t/active.conf"
run_hook "$HOOKS/stop-test-gate.sh" "$t/active.conf" '{"hook_event_name":"Stop","stop_hook_active":true}'
[ ! -f "$t/active.marker" ] && pass "stop_hook_active=true → suite not re-run" || fail "stop_hook_active skips suite" "TEST_CMD ran"

cat > "$t/noisy.sh" <<'SH'
pad=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
i=0
while [ "$i" -lt 200 ]; do printf '\033[31mFAIL\033[0m line %s %s\n' "$i" "$pad"; i=$((i + 1)); done
exit 1
SH
printf 'HOOKS_ENABLED=1\nSTOP_GATE="block"\nTEST_CMD="bash %s/noisy.sh"\n' "$t" > "$t/noisy.conf"
run_hook "$HOOKS/stop-test-gate.sh" "$t/noisy.conf" '{"hook_event_name":"Stop","stop_hook_active":false}'
esc="$(printf '\033')"
{ printf '%s' "$OUT" | grep -q '"decision":"block"' && valid_json "$OUT" && [ "${#OUT}" -le 5000 ] \
    && printf '%s' "$OUT" | grep -q "Test output" && ! printf '%s' "$OUT" | grep -q "$esc" \
    && ! printf '%s' "$OUT" | grep -qi 'u001b'; } \
    && pass "block reason: valid JSON, no ANSI, capped, labelled" \
    || fail "block reason sanitized" "len=${#OUT} out=$(printf '%s' "$OUT" | head -c 300)"

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
    outf=$(mktemp "$TMP_ROOT/XXXXXX")
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
export CLAUDE_PROJECT_DIR="$t"
tr="$t/agent.jsonl"; main_tr="$t/main.jsonl"
cat > "$tr" <<JSONL
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"$t/src/ok.js","content":"x"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"$t/config/secret.yml"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"$t/config/reads-are-fine.yml"}}]}}
JSONL
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"%s/lib/main.js"}}]}}\n' "$t" > "$main_tr"
payload="{\"transcript_path\":\"$main_tr\",\"agent_transcript_path\":\"$tr\",\"stop_hook_active\":false}"
printf 'HOOKS_ENABLED=1\nSUBAGENT_SCOPE="warn"\nALLOWED_SUBAGENT_PATHS="src/*"\n' > "$t/scope-warn.conf"
run_hook "$HOOKS/subagent-scope.sh" "$t/scope-warn.conf" "$payload"
{ [ "$RC" -eq 0 ] && system_message "$OUT" "config/secret.yml" \
    && ! printf '%s' "$OUT" | grep -q "reads-are-fine.yml" && ! printf '%s' "$OUT" | grep -q "src/ok.js"; } \
    && pass "warn: absolute out-of-scope WRITE flagged via systemMessage, READ ignored" || fail "scope warn" "rc=$RC out=$OUT"

printf 'HOOKS_ENABLED=1\nSUBAGENT_SCOPE="block"\nALLOWED_SUBAGENT_PATHS="src/*"\n' > "$t/scope-block.conf"
run_hook "$HOOKS/subagent-scope.sh" "$t/scope-block.conf" "$payload"
printf '%s' "$OUT" | grep -q '"decision":"block"' && pass "block mode: out-of-scope → decision:block" || fail "scope block" "out=$OUT"

run_hook "$HOOKS/subagent-scope.sh" "$t/scope-block.conf" "{\"agent_transcript_path\":\"$tr\",\"stop_hook_active\":true}"
! printf '%s' "$OUT" | grep -q '"decision":"block"' && pass "block mode: stop_hook_active=true → no re-block" || fail "scope loop guard" "out=$OUT"

printf 'HOOKS_ENABLED=1\nSUBAGENT_SCOPE="warn"\nALLOWED_SUBAGENT_PATHS="src/* config/*"\n' > "$t/scope-ok.conf"
run_hook "$HOOKS/subagent-scope.sh" "$t/scope-ok.conf" "$payload"
{ [ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ]; } && pass "all writes in scope → silent exit 0" || fail "scope ok" "rc=$RC out=$OUT err=$ERR"

run_hook "$HOOKS/subagent-scope.sh" "$t/scope-warn.conf" "{\"transcript_path\":\"$tr\",\"agent_transcript_path\":\"$main_tr\"}"
printf '%s' "$OUT" | grep -q "lib/main.js" && ! printf '%s' "$OUT" | grep -q "secret.yml" \
    && pass "agent_transcript_path is scanned, not transcript_path" || fail "reads agent_transcript_path" "out=$OUT"

printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/elsewhere/notes.md"}}]}}\n' > "$t/out.jsonl"
printf 'HOOKS_ENABLED=1\nSUBAGENT_SCOPE="warn"\nALLOWED_SUBAGENT_PATHS="*.md"\n' > "$t/scope-md.conf"
run_hook "$HOOKS/subagent-scope.sh" "$t/scope-md.conf" "{\"agent_transcript_path\":\"$t/out.jsonl\"}"
printf '%s' "$OUT" | grep -q "/elsewhere/notes.md" && pass "write outside the project is a violation" || fail "outside-project write flagged" "out=$OUT"

printf 'HOOKS_ENABLED=1\nSUBAGENT_SCOPE="off"\nALLOWED_SUBAGENT_PATHS="src/*"\n' > "$t/scope-off.conf"
run_hook "$HOOKS/subagent-scope.sh" "$t/scope-off.conf" "$payload"
{ [ -z "$OUT" ] && [ -z "$ERR" ]; } && pass "SUBAGENT_SCOPE=off → silent" || fail "SUBAGENT_SCOPE=off" "out=$OUT err=$ERR"
unset CLAUDE_PROJECT_DIR

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

t=$(mk_tmp)
export CLAUDE_PROJECT_DIR="$t"
printf 'content\n' > "$t/file.txt"
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/elsewhere/x"}}]}}\n' > "$t/agent.jsonl"
printf 'FORMAT_CMD="touch %s/fmt.marker"\nSTOP_GATE="block"\nTEST_CMD="touch %s/test.marker"\nSUBAGENT_SCOPE="block"\nALLOWED_SUBAGENT_PATHS="src/*"\n' \
    "$t" "$t" > "$t/no-master.conf"
for c in "$NO_CONF" "$t/no-master.conf"; do
    run_hook "$HOOKS/post-format.sh" "$c" "{\"tool_input\":{\"file_path\":\"$t/file.txt\"}}"
    o1="$OUT"
    run_hook "$HOOKS/stop-test-gate.sh" "$c" '{"hook_event_name":"Stop"}'
    o2="$OUT"
    run_hook "$HOOKS/subagent-scope.sh" "$c" "{\"agent_transcript_path\":\"$t/agent.jsonl\"}"
    o3="$OUT"
    { [ ! -f "$t/fmt.marker" ] && [ ! -f "$t/test.marker" ] && [ -z "$o1$o2$o3" ]; } \
        && pass "without HOOKS_ENABLED=1 format/test gate/scope stay off ($(basename "$c"))" \
        || fail "without HOOKS_ENABLED=1 format/test gate/scope stay off ($(basename "$c"))" "out=$o1$o2$o3"
done
unset CLAUDE_PROJECT_DIR

if [ -z "${HOOKS_TEST_NOJQ:-}" ] && ! PATH="$sandbox" command -v jq >/dev/null 2>&1; then
    for b in touch cp mkdir ln readlink chmod wc sort; do
        p="$(command -v "$b" 2>/dev/null)" && ln -sf "$p" "$sandbox/$b"
    done
    ln -sf "$BASH" "$sandbox/bash"
    echo ""
    if PATH="$sandbox" HOOKS_TEST_NOJQ=1 JSON_CHECK="$JSON_CHECK" HOOKS_UNDER_TEST="$HOOKS" "$BASH" "$0"; then
        pass "whole suite passes without jq"
    else
        fail "whole suite passes without jq" "see the (no jq) run above"
    fi
fi

echo ""
echo "================================================"
TOTAL=$((PASS + FAIL))
printf "Results: %d/%d passed\n" "$PASS" "$TOTAL"
[ "$FAIL" -eq 0 ] && { echo "ALL PASSED"; exit 0; } || { echo "FAILED"; exit 1; }
