#!/usr/bin/env bash
# Stop — test gate. Runs TEST_CMD before the run is allowed to end.
#
# STOP_GATE modes (hooks.conf):
#   off   — do nothing
#   warn  — run tests, print failures to stderr, but let the run end (default)
#   block — if tests fail, force the agent to continue via the documented
#           {"decision":"block"} stdout protocol (exit 2 is unreliable for Stop)
#
# Guards on stop_hook_active so a failing block-mode gate cannot loop forever.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib.sh"

hooks_enabled || exit 0
case "${STOP_GATE:-warn}" in
    off) exit 0 ;;
esac
[ -n "${TEST_CMD:-}" ] || exit 0

# Avoid re-entrant blocking: if we are already inside a stop-hook continuation, do not block again.
stop_active="$(hook_field '.stop_hook_active' 'stop_hook_active')"

if eval "$TEST_CMD" >/tmp/agent-context-testgate.$$ 2>&1; then
    rm -f "/tmp/agent-context-testgate.$$"
    exit 0
fi

output="$(tail -n 40 "/tmp/agent-context-testgate.$$" 2>/dev/null)"
rm -f "/tmp/agent-context-testgate.$$"

if [ "${STOP_GATE:-warn}" = "block" ] && [ "$stop_active" != "true" ]; then
    emit_block_decision "Test gate failed (TEST_CMD: $TEST_CMD). Fix the failing tests before ending the run. Last output: $output"
    exit 0
fi

echo "agent-context test gate: TEST_CMD failed (STOP_GATE=${STOP_GATE:-warn}, not blocking)." >&2
printf '%s\n' "$output" >&2
exit 0
