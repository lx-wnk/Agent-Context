#!/usr/bin/env bash
set -euo pipefail

# Token-budget gate for the always-on context closure.
#
# Counts "effective instruction lines" — non-blank, non-comment, non-divider lines —
# across the files that load on every session, and fails if the total exceeds a limit.
# Lines are a deliberate proxy for tokens: cheap, deterministic, and good enough to stop
# the always-on baseline from silently bloating. It is a guardrail, not an exact tokenizer.
#
# Usage:
#   check-token-budget.sh [--conf PATH] [--max N] [--quiet] [FILE...]
#
# Resolution order for the file set and limit:
#   1. Explicit FILE arguments override the conf's INCLUDE_FILES.
#   2. --max overrides the conf's MAX_EFFECTIVE_LINES.
#   3. Otherwise both come from the conf (default: .agent-context/budget.conf).
#
# Exit codes: 0 = within budget, 1 = over budget, 2 = usage/config error.

CONF=".agent-context/budget.conf"
MAX_OVERRIDE=""
QUIET=0
FILES=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --conf) CONF="${2:-}"; shift 2 ;;
        --conf=*) CONF="${1#--conf=}"; shift ;;
        --max) MAX_OVERRIDE="${2:-}"; shift 2 ;;
        --max=*) MAX_OVERRIDE="${1#--max=}"; shift ;;
        --quiet) QUIET=1; shift ;;
        --) shift; while [ "$#" -gt 0 ]; do FILES+=("$1"); shift; done ;;
        -*) echo "Unknown option: $1" >&2; exit 2 ;;
        *) FILES+=("$1"); shift ;;
    esac
done

MAX_EFFECTIVE_LINES=200
MAX_EFFECTIVE_LINES_HARD=""
INCLUDE_FILES=""
if [ -f "$CONF" ]; then
    # shellcheck disable=SC1090
    . "$CONF"
fi

[ -n "$MAX_OVERRIDE" ] && MAX_EFFECTIVE_LINES="$MAX_OVERRIDE"
# Hard cap defaults to the soft cap → backward compatible (fail exactly at the soft limit).
# When the conf sets a higher hard cap, the soft limit becomes a warn-only target and the
# gate fails only past the hard cap — real projects fill layers legitimately.
[ -n "$MAX_EFFECTIVE_LINES_HARD" ] || MAX_EFFECTIVE_LINES_HARD="$MAX_EFFECTIVE_LINES"

if [ "${#FILES[@]}" -eq 0 ]; then
    # INCLUDE_FILES is a newline/space separated list from the conf.
    # shellcheck disable=SC2206
    FILES=($INCLUDE_FILES)
fi

if [ "${#FILES[@]}" -eq 0 ]; then
    echo "Error: no files to check. Provide FILE args or set INCLUDE_FILES in $CONF." >&2
    exit 2
fi

for _cap in MAX_EFFECTIVE_LINES MAX_EFFECTIVE_LINES_HARD; do
    eval "_v=\${$_cap}"
    if ! [[ "$_v" =~ ^[0-9]+$ ]]; then
        echo "Error: $_cap must be an integer, got '$_v'." >&2
        exit 2
    fi
done

# Counts effective instruction lines in one file via an awk state machine.
# Skips: blank lines, HTML comment lines (single- and multi-line <!-- ... -->),
# markdown table separators (| --- | :-: |), and horizontal-rule dividers (---, ===, ***).
count_effective() {
    awk '
        BEGIN { in_comment = 0; n = 0 }
        {
            line = $0
            # Strip a comment that opens and closes on the same line.
            gsub(/<!--.*-->/, "", line)
            if (in_comment) {
                if (line ~ /-->/) { sub(/.*-->/, "", line); in_comment = 0 }
                else next
            }
            if (line ~ /<!--/) { sub(/<!--.*/, "", line); in_comment = 1 }
            # Trim whitespace.
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            if (line == "") next
            # Markdown table separator row, e.g. | --- | :--: |
            if (line ~ /^\|?[[:space:]]*:?-+:?[[:space:]]*(\|[[:space:]]*:?-+:?[[:space:]]*)+\|?$/) next
            # Horizontal rule dividers.
            if (line ~ /^(-{3,}|={3,}|\*{3,})$/) next
            n++
        }
        END { print n }
    ' "$1"
}

total=0
missing=0
rows=""
for f in "${FILES[@]}"; do
    if [ ! -f "$f" ]; then
        rows="${rows}  MISSING  ${f}\n"
        missing=1
        continue
    fi
    c=$(count_effective "$f")
    total=$((total + c))
    rows="${rows}$(printf '  %5d  %s' "$c" "$f")\n"
done

if [ "$QUIET" -ne 1 ]; then
    echo "Token-budget audit (effective instruction lines, always-on closure):"
    printf '%b' "$rows"
    echo "  -----"
    printf '  %5d  TOTAL (soft: %d · hard: %d)\n' "$total" "$MAX_EFFECTIVE_LINES" "$MAX_EFFECTIVE_LINES_HARD"
fi

if [ "$missing" -eq 1 ]; then
    echo "Warning: one or more always-on files are missing — counted as 0." >&2
fi

if [ "$total" -gt "$MAX_EFFECTIVE_LINES_HARD" ]; then
    echo "FAIL: always-on baseline is $total effective lines, over the hard cap of $MAX_EFFECTIVE_LINES_HARD." >&2
    echo "      Move optional content behind task-routing (memory/ or skills/) to reduce it." >&2
    exit 1
fi

if [ "$total" -gt "$MAX_EFFECTIVE_LINES" ]; then
    echo "WARN: always-on baseline is $total effective lines, over the soft target of $MAX_EFFECTIVE_LINES (hard cap $MAX_EFFECTIVE_LINES_HARD)." >&2
    echo "      Consider moving optional content behind task-routing (memory/ or skills/)." >&2
    [ "$QUIET" -ne 1 ] && echo "PASS: within the hard cap (soft target exceeded)."
    exit 0
fi

[ "$QUIET" -ne 1 ] && echo "PASS: always-on baseline within budget."
exit 0
