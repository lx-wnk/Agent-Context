#!/usr/bin/env bash
set -euo pipefail

# Baseline measurement — what layering keeps OUT of every session.
#
# Three sets:
#   layered    the always-on closure: INCLUDE_FILES from budget.conf, read at every start
#   on-demand  project knowledge pulled only when a task's keywords match it
#   flat       layered + on-demand — one file holding everything, the pre-layering shape
#
# Reported per set: effective instruction lines, file bytes, and ceil(bytes/4) as a token
# estimate. Counting is delegated to check-token-budget.sh so one engine defines both the
# gate and the measurement.
#
# What the delta IS: the always-on load a flat setup pays on every session and a layered one
# does not. What it is NOT: a total-session-token claim. A task that pulls two skills pays
# for those two skills, so the delta is an upper bound, reached only by a task that needs
# none of the on-demand set. Nothing here models file reads the agent "would have done".
#
# Usage:
#   measure-baseline.sh [--dir PATH] [--conf PATH] [--json]
#
# Exit codes: 0 = measured, 2 = usage/config error.

ROOT="."
CONF=""
JSON=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dir) ROOT="${2:-}"; shift 2 ;;
        --dir=*) ROOT="${1#--dir=}"; shift ;;
        --conf) CONF="${2:-}"; shift 2 ;;
        --conf=*) CONF="${1#--conf=}"; shift ;;
        --json) JSON=1; shift ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ENGINE="$BIN_DIR/check-token-budget.sh"
if [ ! -r "$ENGINE" ]; then
    echo "Error: $ENGINE is missing — re-run the Agent-Context update to restore it." >&2
    exit 2
fi

if [ ! -d "$ROOT" ]; then
    echo "Error: --dir '$ROOT' is not a directory." >&2
    exit 2
fi
ROOT="$(cd "$ROOT" && pwd)"
cd "$ROOT"

AC=".agent-context"
[ -n "$CONF" ] || CONF="$AC/budget.conf"
if [ ! -r "$CONF" ]; then
    echo "Error: budget conf '$CONF' not found under $ROOT — is Agent-Context installed here?" >&2
    exit 2
fi

# The layered set is whatever the gate already considers always-on — never a second list.
layered=()
while IFS= read -r line; do
    [ -n "$line" ] && layered+=("${line#./}")
done < <(bash "$ENGINE" --list --conf "$CONF")

if [ "${#layered[@]}" -eq 0 ]; then
    echo "Error: INCLUDE_FILES in $CONF resolved to no files." >&2
    exit 2
fi

# On-demand: the knowledge a flat setup would have to load up front and a layered one does
# not. memory/archive/ is excluded — archived entries are history, not live context.
candidates=()
collect() {
    [ -d "$1" ] || return 0
    while IFS= read -r -d '' f; do
        candidates+=("${f#./}")
    done < <(find "$1" -path "$AC/memory/archive" -prune -o -type f \( -name '*.md' -o -name 'map.json' \) -print0)
}
collect "$AC/memory"
collect "$AC/skills"
for f in "$AC/agent-delegation.md" "$AC/memory-maintenance.md" "$AC/map.json"; do
    [ -f "$f" ] && candidates+=("$f")
done

# A file that already loads at startup is not "on demand", however it was discovered.
ondemand=()
for c in $(printf '%s\n' "${candidates[@]:-}" | sort -u); do
    [ -n "$c" ] || continue
    dup=0
    for l in "${layered[@]}"; do
        [ "$c" = "$l" ] && { dup=1; break; }
    done
    [ "$dup" -eq 0 ] && ondemand+=("$c")
done

# Both sets go through the same counter. /dev/null as the conf plus a cap far above any
# real total keeps the gate from firing — this run measures, it does not judge.
measure() {
    bash "$ENGINE" --json --conf /dev/null --max 999999999 -- "$@" | awk '
        /"total_effective_lines"/ { l = $2 }
        /"total_bytes"/           { b = $2 }
        /"total_est_tokens"/      { t = $2 }
        END { gsub(/,/, "", l); gsub(/,/, "", b); gsub(/,/, "", t); print l, b, t }
    '
}

read -r L_LINES L_BYTES L_TOKENS <<<"$(measure "${layered[@]}")"
# An empty array must not expand to one empty argument — that would be counted as a
# missing file instead of as nothing at all.
if [ "${#ondemand[@]}" -eq 0 ]; then
    O_LINES=0; O_BYTES=0; O_TOKENS=0
else
    read -r O_LINES O_BYTES O_TOKENS <<<"$(measure "${ondemand[@]}")"
fi

F_LINES=$((L_LINES + O_LINES))
F_BYTES=$((L_BYTES + O_BYTES))
F_TOKENS=$((L_TOKENS + O_TOKENS))
L_COUNT="${#layered[@]}"
O_COUNT="${#ondemand[@]}"
F_COUNT=$((L_COUNT + O_COUNT))

pct() { awk -v a="$1" -v b="$2" 'BEGIN { if (b == 0) print "0.0"; else printf "%.1f", (a * 100) / b }'; }
PCT_LINES="$(pct "$O_LINES" "$F_LINES")"
PCT_TOKENS="$(pct "$O_TOKENS" "$F_TOKENS")"

if [ "$JSON" -eq 1 ]; then
    cat <<JSON
{
  "root": "$ROOT",
  "layered":   { "files": $L_COUNT, "effective_lines": $L_LINES, "bytes": $L_BYTES, "est_tokens": $L_TOKENS },
  "on_demand": { "files": $O_COUNT, "effective_lines": $O_LINES, "bytes": $O_BYTES, "est_tokens": $O_TOKENS },
  "flat":      { "files": $F_COUNT, "effective_lines": $F_LINES, "bytes": $F_BYTES, "est_tokens": $F_TOKENS },
  "kept_out_pct_of_flat": { "effective_lines": $PCT_LINES, "est_tokens": $PCT_TOKENS }
}
JSON
    exit 0
fi

echo "Always-on baseline vs. flat equivalent  ($ROOT)"
echo ""
printf '  %-24s %6s %11s %10s %9s\n' "set" "files" "eff.lines" "bytes" "~tokens"
printf '  %-24s %6d %11d %10d %9d\n' "layered (always-on)" "$L_COUNT" "$L_LINES" "$L_BYTES" "$L_TOKENS"
printf '  %-24s %6d %11d %10d %9d\n' "on-demand (lazy)" "$O_COUNT" "$O_LINES" "$O_BYTES" "$O_TOKENS"
echo "  -----"
printf '  %-24s %6d %11d %10d %9d\n' "flat (everything)" "$F_COUNT" "$F_LINES" "$F_BYTES" "$F_TOKENS"
echo ""
echo "  Kept out of every session: $O_LINES effective lines · $O_BYTES bytes · ~$O_TOKENS tokens"
echo "  That is $PCT_LINES% of the flat baseline by line, $PCT_TOKENS% by estimated token."
echo ""
echo "  ~tokens = ceil(bytes/4), a byte heuristic, not a tokenizer."
echo "  Upper bound: a task that pulls on-demand files pays for exactly those files."
exit 0
