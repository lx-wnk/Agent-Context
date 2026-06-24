#!/usr/bin/env bash
set -euo pipefail

# Discovery-map cap gate. Keeps the on-demand map.json tiny so it never floods context.
#
# Deterministic caps (no JSON parser — byte/line/count proxies, same philosophy as
# check-token-budget.sh): total file bytes, node count ("id": occurrences), and the
# longest line (one node per line → per-node size proxy).
#
# Usage:
#   check-map-budget.sh [--conf PATH] [--map PATH] [--quiet]
#
# Resolution: --map overrides conf MAP_FILE; caps come from the conf.
# Exit codes: 0 = within caps, 1 = over a cap, 2 = usage/config error.

CONF=".agent-context/budget.conf"
MAP_OVERRIDE=""
QUIET=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --conf) CONF="${2:-}"; shift 2 ;;
        --conf=*) CONF="${1#--conf=}"; shift ;;
        --map) MAP_OVERRIDE="${2:-}"; shift 2 ;;
        --map=*) MAP_OVERRIDE="${1#--map=}"; shift ;;
        --quiet) QUIET=1; shift ;;
        -*) echo "Unknown option: $1" >&2; exit 2 ;;
        *) echo "Unexpected argument: $1" >&2; exit 2 ;;
    esac
done

MAP_FILE=".agent-context/map.json"
MAP_MAX_TOTAL_BYTES=16384
MAP_MAX_NODES=60
MAP_MAX_NODE_LINE_BYTES=400
if [ -f "$CONF" ]; then
    # shellcheck disable=SC1090
    . "$CONF"
fi
[ -n "$MAP_OVERRIDE" ] && MAP_FILE="$MAP_OVERRIDE"

for v in MAP_MAX_TOTAL_BYTES MAP_MAX_NODES MAP_MAX_NODE_LINE_BYTES; do
    eval "val=\${$v}"
    if ! [[ "$val" =~ ^[0-9]+$ ]]; then
        echo "Error: $v must be an integer, got '$val'." >&2
        exit 2
    fi
done

if [ ! -f "$MAP_FILE" ]; then
    echo "Error: map file not found: $MAP_FILE (run the discovery-map skill first)." >&2
    exit 2
fi

total_bytes=$(wc -c < "$MAP_FILE" | tr -d ' ')
node_count=$(grep -c '"id"[[:space:]]*:' "$MAP_FILE" || true)
max_line=$(awk '{ if (length($0) > m) m = length($0) } END { print m+0 }' "$MAP_FILE")

over=0
report=""
check() { # name actual limit
    local name="$1" actual="$2" limit="$3" status="ok"
    if [ "$actual" -gt "$limit" ]; then status="OVER"; over=1; fi
    report="${report}$(printf '  %-22s %8d  (limit %d)  %s' "$name" "$actual" "$limit" "$status")\n"
}
check "total bytes" "$total_bytes" "$MAP_MAX_TOTAL_BYTES"
check "node count" "$node_count" "$MAP_MAX_NODES"
check "longest line bytes" "$max_line" "$MAP_MAX_NODE_LINE_BYTES"

if [ "$QUIET" -ne 1 ]; then
    echo "Discovery-map cap audit ($MAP_FILE):"
    printf '%b' "$report"
fi

if [ "$over" -eq 1 ]; then
    echo "FAIL: discovery map exceeds a cap. Split coarse areas into memory/<area>/map.json" >&2
    echo "      (hierarchy), or trim node lines. The top index must stay flat." >&2
    exit 1
fi

[ "$QUIET" -ne 1 ] && echo "PASS: discovery map within caps."
exit 0
