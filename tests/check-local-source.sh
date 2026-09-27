#!/usr/bin/env bash
# tests/check-local-source.sh — integration test for install.sh --local-source / AGENT_CONTEXT_SOURCE.
#
# Uses `claude` and `curl` stubs (no real CLI, no network) to assert install.sh: bypasses the up-to-date
# short-circuit, points the agent at the LOCAL prompt, and injects the LOCAL SOURCE MODE directive
# so the agent copies files from the local clone instead of downloading.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL="$REPO_ROOT/install.sh"

PASS=0
FAIL=0
# mk_tmp runs inside $(...), so it can only create under a root owned by this shell.
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/localsrc.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT
mk_tmp() { mktemp -d "$TMP_ROOT/XXXXXX"; }
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

# curl stub: the releases API always answers 2.0.0, so no run touches the network.
cat > "$STUB/curl" <<'EOF'
#!/usr/bin/env bash
echo '{"tag_name": "2.0.0"}'
EOF
chmod +x "$STUB/curl"
export XDG_CACHE_HOME
XDG_CACHE_HOME=$(mk_tmp)
VERSION_CACHE="$XDG_CACHE_HOME/agent-context/latest-version"
mkdir -p "$(dirname "$VERSION_CACHE")"

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

# 5. --force injects the full-rediscovery directive and bypasses a fresh version cache (1.0.0 → API 2.0.0).
TGT=$(mk_tmp)
echo "1.0.0" > "$VERSION_CACHE"
run_install "$TGT" --force
printf '%s' "$CAP" | grep -q "FULL REDISCOVERY" \
    && pass "--force injects the FULL REDISCOVERY directive" || fail "--force directive" "not in prompt"
printf '%s' "$CAP" | grep -q "TARGET VERSION: 2.0.0" \
    && pass "--force bypasses the version cache" || fail "--force cache bypass" "prompt not pinned to the API tag"
printf '%s' "$CAP" | grep -q "Fetch https://raw.githubusercontent.com/lx-wnk/Agent-Context/2.0.0/.prompts/setup-prompt.md" \
    && pass "prompt is fetched from the pinned release tag" || fail "pinned prompt URL" "not in prompt"

# 6. --discover does NOT build headless — it hands off to the interactive /discover when no map exists.
#    Also exercises the cache-hit path (fresh 1.0.0 cache, no --force) that reads the cache mtime via stat.
TGT=$(mk_tmp)
echo "1.0.0" > "$VERSION_CACHE"
cap6="$(mk_tmp)/cap"
out6="$( cd "$TGT" && CAPTURE="$cap6" PATH="$STUB:$PATH" bash "$INSTALL" --discover 2>&1 )"
printf '%s' "$out6" | grep -q "No discovery map was built" \
    && pass "--discover hands off to interactive /discover (no fake build)" || fail "--discover hand-off" "no hand-off message in output"
{ [ -f "$cap6" ] && tr '\0' '\n' < "$cap6" | grep -q "TARGET VERSION: 1.0.0"; } \
    && pass "a fresh version cache pins the target" || fail "cache-hit target" "prompt not pinned to the cached tag"

echo ""
echo "================================================"
TOTAL=$((PASS + FAIL))
printf "Results: %d/%d passed\n" "$PASS" "$TOTAL"
[ "$FAIL" -eq 0 ] && { echo "ALL PASSED"; exit 0; } || { echo "FAILED"; exit 1; }
