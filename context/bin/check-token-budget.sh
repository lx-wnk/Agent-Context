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
#   check-token-budget.sh [--conf PATH] [--max N] [--quiet|--json] [--list] [FILE...]
#
# --json  prints one machine-readable object instead of the table (totals first, then a
#         per-file array) and keeps the same exit codes, so a gate and a measurement can
#         share one run. --list prints the resolved file set, one path per line, and stops
#         before counting — it answers "which files is the closure" without answering
#         "how big is it". Both are what measure-baseline.sh consumes.
#
# The file set is what Claude Code actually loads: the @-import closure walked from
# .claude/CLAUDE.md (and ./CLAUDE.md if present), relative to the current directory. Each import
# resolves relative to the importing file. Imports inside code spans or fenced blocks are
# ignored; an import that resolves to no file is warned about, never counted, never fatal.
#
# Resolution order for the file set and limit:
#   1. Explicit FILE arguments are the whole set — no walk, no conf lists.
#   2. Otherwise the walked closure plus the conf's optional SESSION_START_FILES (files read at
#      session start without an @-import) plus the legacy INCLUDE_FILES, deduplicated. An
#      INCLUDE_FILES entry the walk does not reach is counted and printed as a note.
#   3. --max sets both caps to N. Otherwise both come from the conf
#      (default: .agent-context/budget.conf); a missing hard cap defaults to 250.
#
# Exit codes: 0 = within budget, 1 = over budget, 2 = usage/config error.

CONF=".agent-context/budget.conf"
MAX_OVERRIDE=""
QUIET=0
JSON=0
LIST=0
FILES=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --conf) [ "$#" -ge 2 ] || { echo "Error: --conf requires an argument" >&2; exit 2; }; CONF="$2"; shift 2 ;;
        --conf=*) CONF="${1#--conf=}"; shift ;;
        --max) [ "$#" -ge 2 ] || { echo "Error: --max requires an argument" >&2; exit 2; }; MAX_OVERRIDE="$2"; shift 2 ;;
        --max=*) MAX_OVERRIDE="${1#--max=}"; shift ;;
        --quiet) QUIET=1; shift ;;
        --json) JSON=1; QUIET=1; shift ;;
        --list) LIST=1; shift ;;
        --) shift; while [ "$#" -gt 0 ]; do FILES+=("$1"); shift; done ;;
        -*) echo "Unknown option: $1" >&2; exit 2 ;;
        *) FILES+=("$1"); shift ;;
    esac
done

MAX_EFFECTIVE_LINES=200
MAX_EFFECTIVE_LINES_HARD=""
SESSION_START_FILES=""
INCLUDE_FILES=""

# The conf is project-owned DATA that can arrive via `git pull` from a repository the developer
# does not control, so it is parsed rather than sourced — the keys below are copied out
# literally and nothing in the file is ever executed.
BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ ! -r "$BIN_DIR/conf-read.sh" ]; then
    echo "Error: $BIN_DIR/conf-read.sh is missing — re-run the Agent-Context update to restore it." >&2
    exit 2
fi
# shellcheck source=conf-read.sh
. "$BIN_DIR/conf-read.sh"

conf_load "$CONF" MAX_EFFECTIVE_LINES MAX_EFFECTIVE_LINES_HARD SESSION_START_FILES INCLUDE_FILES

if [ -n "$MAX_OVERRIDE" ]; then
    MAX_EFFECTIVE_LINES="$MAX_OVERRIDE"
    MAX_EFFECTIVE_LINES_HARD="$MAX_OVERRIDE"
fi
[ -n "$MAX_EFFECTIVE_LINES_HARD" ] || MAX_EFFECTIVE_LINES_HARD=250

for _cap in MAX_EFFECTIVE_LINES MAX_EFFECTIVE_LINES_HARD; do
    _v="${!_cap}"
    if ! [[ "$_v" =~ ^[0-9]+$ ]]; then
        echo "Error: $_cap must be an integer, got '$_v'." >&2
        exit 2
    fi
done
[ "$MAX_EFFECTIVE_LINES_HARD" -ge "$MAX_EFFECTIVE_LINES" ] || MAX_EFFECTIVE_LINES_HARD="$MAX_EFFECTIVE_LINES"

normalize_path() {
    printf '%s\n' "$1" | awk -F/ '{
        abs = ($0 ~ /^\//); n = 0
        for (i = 1; i <= NF; i++) {
            s = $i
            if (s == "" || s == ".") continue
            if (s == "..") { if (n > 0 && st[n] != "..") n--; else if (!abs) st[++n] = ".."; continue }
            st[++n] = s
        }
        out = ""
        for (i = 1; i <= n; i++) out = out (i > 1 ? "/" : "") st[i]
        if (abs) out = "/" out
        print (out == "" ? "." : out)
    }'
}

# One raw @-import path per line, in file order.
extract_imports() {
    awk '
        /^ ? ? ?(```|~~~)/ { fence = !fence; next }
        fence { next }
        {
            line = $0
            gsub(/`[^`]*`/, "", line)
            while (match(line, /(^|[[:space:](>|])@[^[:space:])|]+/)) {
                tok = substr(line, RSTART, RLENGTH)
                sub(/^[^@]*@/, "", tok)
                print tok
                line = substr(line, RSTART + RLENGTH)
            }
        }
    ' "$1"
}

SEEN=$'\n'
DANGLING=""
add_file() {
    case "$SEEN" in *$'\n'"$1"$'\n'*) return 1 ;; esac
    SEEN="$SEEN$1"$'\n'
    FILES+=("$1")
}

walk_imports() {
    local queue="$1" cur imp target
    while [ -n "$queue" ]; do
        cur="${queue%%$'\n'*}"
        [ "$queue" = "$cur" ] && queue="" || queue="${queue#*$'\n'}"
        add_file "$cur" || continue
        while IFS= read -r imp; do
            imp="${imp%$'\r'}"
            case "$imp" in
                /*) target="$imp" ;;
                \~/*) target="$HOME/${imp#\~/}" ;;
                *) target="$(dirname "$cur")/$imp" ;;
            esac
            target="$(normalize_path "$target")"
            if [ -f "$target" ]; then
                queue="${queue:+$queue$'\n'}$target"
            else
                DANGLING="${DANGLING}  $cur -> @$imp"$'\n'
            fi
        done < <(extract_imports "$cur")
    done
}

if [ "${#FILES[@]}" -eq 0 ]; then
    for _root in .claude/CLAUDE.md CLAUDE.md; do
        [ -f "$_root" ] && walk_imports "$_root"
    done
    # Both lists are newline/space separated paths, never globs.
    set -f
    # shellcheck disable=SC2206
    _session=($SESSION_START_FILES)
    for _f in ${_session[@]+"${_session[@]}"}; do
        add_file "$(normalize_path "$_f")" || true
    done
    # shellcheck disable=SC2206
    _extra=($INCLUDE_FILES)
    set +f
    for _f in ${_extra[@]+"${_extra[@]}"}; do
        _f="$(normalize_path "$_f")"
        if add_file "$_f" && [ "$LIST" -ne 1 ]; then
            echo "note: $_f is counted from INCLUDE_FILES but not @-imported" >&2
        fi
    done
fi

if [ -n "$DANGLING" ]; then
    echo "Warning: @-imports that resolve to no file (not counted):" >&2
    printf '%s' "$DANGLING" >&2
fi

if [ "${#FILES[@]}" -eq 0 ]; then
    echo "Error: no files to check. No .claude/CLAUDE.md or CLAUDE.md to walk, and no SESSION_START_FILES or INCLUDE_FILES in $CONF." >&2
    exit 2
fi

if [ "$LIST" -eq 1 ]; then
    printf '%s\n' "${FILES[@]}"
    exit 0
fi

# Counts effective instruction lines in one file via an awk state machine.
# Skips: blank lines, HTML comments (shortest match, several per line, multi-line),
# markdown table separators (| --- | :-: |), and horizontal-rule dividers (---, ===, ***).
# `<!--` inside a code span is text. A comment never closed hides nothing — the agent still
# loads those lines, so they count.
count_effective() {
    awk '
        function effective(s) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
            if (s == "") return 0
            if (s ~ /^\|?[[:space:]]*:?-+:?[[:space:]]*(\|[[:space:]]*:?-+:?[[:space:]]*)+\|?$/) return 0
            if (s ~ /^(-{3,}|={3,}|\*{3,})$/) return 0
            return 1
        }
        function comment_start(s,    masked, span) {
            masked = s
            while (match(masked, /`[^`]*`/)) {
                span = sprintf("%" RLENGTH "s", "")
                masked = substr(masked, 1, RSTART - 1) span substr(masked, RSTART + RLENGTH)
            }
            return index(masked, "<!--")
        }
        BEGIN { in_comment = 0; n = 0; pending = 0 }
        {
            rest = $0; out = ""; closed = 0; touched = in_comment
            while (rest != "") {
                if (in_comment) {
                    p = index(rest, "-->")
                    if (p == 0) break
                    rest = substr(rest, p + 3); in_comment = 0; closed = 1
                } else {
                    p = comment_start(rest)
                    if (p == 0) { out = out rest; break }
                    out = out substr(rest, 1, p - 1)
                    rest = substr(rest, p + 4); in_comment = 1; touched = 1
                }
            }
            visible = effective(out)
            n += visible
            if (in_comment) {
                if (closed) pending = 0
                if (!visible && effective($0)) pending++
            } else if (touched) {
                pending = 0
            }
        }
        END { if (in_comment) n += pending; print n }
    ' "$1"
}

# Byte counts feed the token estimate. A file enters the context window verbatim —
# comments and blank lines included — so bytes, not effective lines, are what a tokenizer
# would see. The two numbers answer different questions and are both reported.
count_bytes() { wc -c < "$1" | tr -d '[:space:]'; }

json_escape() {
    printf '%s\n' "$1" | LC_ALL=C awk '
        BEGIN { for (i = 1; i < 32; i++) if (i != 10) esc[sprintf("%c", i)] = sprintf("\\u%04x", i) }
        {
            out = ""
            for (i = 1; i <= length($0); i++) {
                c = substr($0, i, 1)
                if (c == "\\" || c == "\"") out = out "\\" c
                else if (c in esc) out = out esc[c]
                else out = out c
            }
            printf "%s%s", (NR > 1 ? "\\n" : ""), out
        }'
}

total=0
total_bytes=0
missing=0
rows=""
json_files=""
for f in "${FILES[@]}"; do
    if [ ! -f "$f" ]; then
        rows="${rows}  MISSING  ${f}"$'\n'
        missing=1
        json_files="${json_files:+$json_files,$'\n'}    { \"path\": \"$(json_escape "$f")\", \"present\": false, \"effective_lines\": 0, \"bytes\": 0 }"
        continue
    fi
    c=$(count_effective "$f")
    b=$(count_bytes "$f")
    total=$((total + c))
    total_bytes=$((total_bytes + b))
    rows="${rows}$(printf '  %5d  %s' "$c" "$f")"$'\n'
    json_files="${json_files:+$json_files,$'\n'}    { \"path\": \"$(json_escape "$f")\", \"present\": true, \"effective_lines\": ${c}, \"bytes\": ${b} }"
done

# ceil(bytes/4) — the byte heuristic every provider-agnostic estimate uses. Not a tokenizer.
est_tokens=$(( (total_bytes + 3) / 4 ))

if [ "$JSON" -eq 1 ]; then
    if [ "$total" -gt "$MAX_EFFECTIVE_LINES_HARD" ]; then status="fail"
    elif [ "$total" -gt "$MAX_EFFECTIVE_LINES" ]; then status="warn"
    else status="pass"
    fi
    echo "{"
    echo "  \"total_effective_lines\": ${total},"
    echo "  \"total_bytes\": ${total_bytes},"
    echo "  \"total_est_tokens\": ${est_tokens},"
    echo "  \"soft_cap\": ${MAX_EFFECTIVE_LINES},"
    echo "  \"hard_cap\": ${MAX_EFFECTIVE_LINES_HARD},"
    echo "  \"missing_files\": ${missing},"
    echo "  \"status\": \"${status}\","
    echo "  \"files\": ["
    printf '%s\n' "$json_files"
    echo "  ]"
    echo "}"
fi

if [ "$QUIET" -ne 1 ]; then
    echo "Token-budget audit (effective instruction lines, always-on closure):"
    printf '%s' "$rows"
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
