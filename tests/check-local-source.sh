#!/usr/bin/env bash
# tests/check-local-source.sh — integration test for install.sh --local-source / AGENT_CONTEXT_SOURCE.
#
# Uses a `claude` stub (no real CLI, no network) to assert install.sh: bypasses the up-to-date
# short-circuit, points the agent at the LOCAL prompt, and injects the LOCAL SOURCE MODE directive
# so the agent copies files from the local clone instead of downloading.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL="$REPO_ROOT/install.sh"

PASS=0
FAIL=0
TMP_ROOTS=()
cleanup() { for d in "${TMP_ROOTS[@]:-}"; do [ -d "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT
mk_tmp() { local d; d=$(mktemp -d "${TMPDIR:-/tmp}/localsrc.XXXXXX"); TMP_ROOTS+=("$d"); echo "$d"; }
pass() { printf "  PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL  %s\n    => %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

echo "=== install.sh local-source integration ==="
echo ""

# Fake local clone (source): minimal — only needs .prompts/setup-prompt.md + CHANGELOG.md.
SRC=$(mk_tmp)
mkdir -p "$SRC/.prompts"
printf '# setup prompt\n' > "$SRC/.prompts/setup-prompt.md"
printf '# Changelog\n\n## 9.9.9\n' > "$SRC/CHANGELOG.md"
# install.sh canonicalizes the source via realpath; on macOS /tmp -> /private/tmp, so assert
# against the resolved path, not the symlinked mktemp path.
SRC_ABS="$(cd "$SRC" && pwd -P)"

# claude stub: record args (NUL-delimited) to $CAPTURE and exit 0 immediately.
STUB="$(mk_tmp)/bin"
mkdir -p "$STUB"
cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
[ -n "${CAPTURE:-}" ] && printf '%s\0' "$@" > "$CAPTURE"
exit 0
EOF
chmod +x "$STUB/claude"

# run_install <target-dir> <args...> -> sets CAP (captured prompt args, newline-joined) and RC.
run_install() {
    local tgt="$1"
    shift
    local cap
    cap="$(mk_tmp)/cap"
    ( cd "$tgt" && CAPTURE="$cap" PATH="$STUB:$PATH" bash "$INSTALL" "$@" >/dev/null 2>&1 )
    RC=$?
    CAP=""
    [ -f "$cap" ] && CAP="$(tr '\0' '\n' < "$cap")"
}

# 1. --local-source bypasses the up-to-date short-circuit (version present) and reaches the agent.
TGT=$(mk_tmp)
mkdir -p "$TGT/.agent-context"
printf '0.6.1\n' > "$TGT/.agent-context/.agent-context-version"
printf 'pointer\n' > "$TGT/CLAUDE.md"
run_install "$TGT" --local-source "$SRC"
[ -n "$CAP" ] && pass "claude invoked (up-to-date short-circuit bypassed)" \
    || fail "claude invoked" "no capture — short-circuit was not bypassed"
printf '%s' "$CAP" | grep -q "LOCAL SOURCE MODE" \
    && pass "prompt carries the LOCAL SOURCE MODE directive" || fail "LOCAL SOURCE MODE present" "not in prompt"
printf '%s' "$CAP" | grep -q "$SRC_ABS" \
    && pass "prompt references the local source path" || fail "source path present" "not in prompt"
printf '%s' "$CAP" | grep -q "Read $SRC_ABS/.prompts/setup-prompt.md" \
    && pass "agent pointed at the local prompt" || fail "local prompt path" "not in prompt"

# 2. Env form AGENT_CONTEXT_SOURCE triggers the same behavior (no flag).
TGT=$(mk_tmp)
cap2="$(mk_tmp)/cap"
( cd "$TGT" && CAPTURE="$cap2" AGENT_CONTEXT_SOURCE="$SRC" PATH="$STUB:$PATH" bash "$INSTALL" >/dev/null 2>&1 )
{ [ -f "$cap2" ] && tr '\0' '\n' < "$cap2" | grep -q "LOCAL SOURCE MODE"; } \
    && pass "AGENT_CONTEXT_SOURCE env triggers local-source" || fail "env form" "directive not injected"

# 3. Nonexistent source dir → exit 1.
TGT=$(mk_tmp)
( cd "$TGT" && PATH="$STUB:$PATH" bash "$INSTALL" --local-source "/no/such/dir" >/dev/null 2>&1 )
rc=$?
[ "$rc" -eq 1 ] && pass "missing source dir exits 1" || fail "missing source dir exits 1" "got $rc"

# 4. A dir that is not an Agent-Context clone (no setup-prompt) → exit 1.
NOCLONE=$(mk_tmp)
TGT=$(mk_tmp)
( cd "$TGT" && PATH="$STUB:$PATH" bash "$INSTALL" --local-source "$NOCLONE" >/dev/null 2>&1 )
rc=$?
[ "$rc" -eq 1 ] && pass "non-clone source exits 1" || fail "non-clone source exits 1" "got $rc"

# 5. --force injects the full-rediscovery directive (offline: --force skips the short-circuit).
TGT=$(mk_tmp)
cap5="$(mk_tmp)/cap"
( cd "$TGT" && CAPTURE="$cap5" PATH="$STUB:$PATH" bash "$INSTALL" --force >/dev/null 2>&1 )
{ [ -f "$cap5" ] && tr '\0' '\n' < "$cap5" | grep -q "FULL REDISCOVERY"; } \
    && pass "--force injects the FULL REDISCOVERY directive" || fail "--force directive" "not in prompt"

# 6. --discover does NOT build headless — it hands off to the interactive /discover when no map exists.
TGT=$(mk_tmp)
out6="$( cd "$TGT" && PATH="$STUB:$PATH" bash "$INSTALL" --discover 2>&1 )"
printf '%s' "$out6" | grep -q "No discovery map was built" \
    && pass "--discover hands off to interactive /discover (no fake build)" || fail "--discover hand-off" "no hand-off message in output"

echo ""
echo "================================================"
TOTAL=$((PASS + FAIL))
printf "Results: %d/%d passed\n" "$PASS" "$TOTAL"
[ "$FAIL" -eq 0 ] && { echo "ALL PASSED"; exit 0; } || { echo "FAILED"; exit 1; }
