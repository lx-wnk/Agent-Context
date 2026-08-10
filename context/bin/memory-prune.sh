#!/usr/bin/env bash
set -euo pipefail

# Memory rotation / decay: archive expired dated memory entries.
#
# Scans memory/ recursively, so expanded domains (memory/<domain>/*.md) are covered too.
# Symlinked files and symlinked sub-directories are followed as long as they resolve INSIDE the
# scanned directory; a link out of the tree is reported and skipped. Skips the archive/ directory
# itself, and index.md/todo.md at any depth.
#
# Reads the dated-entry metadata the workflow already requires on every lesson:
#   - **[scope]** Some lesson (2026-01-15) ttl:90d source:discovered conf:med
# An entry expires when today > entry-date + ttl days. `ttl:infinite` never expires.
# Expired entries are MOVED (never deleted) into memory/archive/<ISO-week>.md.
#
# Dry-run by default — prints what WOULD move and changes nothing.
# Pass --apply to actually rewrite the source files and write the archive.
#
# Usage:
#   memory-prune.sh [--apply] [--dir PATH] [--archive PATH] [--conf PATH]
#
# Defaults: --dir .agent-context/memory   --archive .agent-context/memory/archive
#           --conf .agent-context/budget.conf
#
# TTL resolution per entry, first match wins:
#   1. an explicit ttl: on the line          3. the shared table below
#   2. MEMORY_TTL_DEFAULTS from the conf     4. no default -> the line is kept forever
# A line without a (YYYY-MM-DD) date is never expired, regardless of defaults.
# Defaults resolve by BASENAME only, at any depth: memory/<domain>/lessons.md inherits the
# same default as the top-level lessons.md. Intended — a name means the same thing anywhere.
#
# Exit codes: 0 = success, 2 = usage/config error or a failed rewrite. No other code.
#
# Portability: handles both GNU date (-d) and BSD/macOS date (-j -f), same approach
# install.sh uses for stat. No non-POSIX tools beyond awk/grep/date.

APPLY=0
MEM_DIR=".agent-context/memory"
ARCHIVE_DIR=""
CONF=".agent-context/budget.conf"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --apply) APPLY=1; shift ;;
        --dir) MEM_DIR="${2:-}"; shift 2 ;;
        --dir=*) MEM_DIR="${1#--dir=}"; shift ;;
        --archive) ARCHIVE_DIR="${2:-}"; shift 2 ;;
        --archive=*) ARCHIVE_DIR="${1#--archive=}"; shift ;;
        --conf) CONF="${2:-}"; shift 2 ;;
        --conf=*) CONF="${1#--conf=}"; shift ;;
        -h|--help)
            ## Only single-hash comments ("#" alone, or "# text") are usage text; "##" marks
            ## internal-only rationale that stays in the source but is excluded from --help.
            grep -E '^#($| )' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "Error: unknown argument: $1" >&2; exit 2 ;;
    esac
done

## `find` normalizes its own start argument, so an un-normalized ARCHIVE_DIR ("memory/archive"
## against a "-dir memory/" scan) makes the -path exclusion miss — the archive is then scanned
## as a source file and its own rewrite wipes what earlier weeks put there.
## Walks up to the first existing ancestor, so a not-yet-created archive still canonicalizes.
## Returns 2 when the ancestor cannot be entered — a swallowed `cd` silently substituted the
## empty string, which turned --dir into a no-op scan and relocated --archive to the root.
normalize_dir() {
    local d="$1" tail="" parent leaf abs
    while [ "${d%/}" != "$d" ] && [ "$d" != "/" ]; do d="${d%/}"; done
    [ -n "$d" ] || { printf '%s' "$1"; return 0; }
    while [ ! -d "$d" ]; do
        parent=$(dirname "$d")
        leaf=$(basename "$d")
        [ "$parent" = "$d" ] && { printf '%s' "$1"; return 0; }
        tail="/$leaf$tail"
        d="$parent"
    done
    abs=$(cd "$d" 2>/dev/null && pwd -P) || {
        if [ "$d" = "$1" ]; then
            echo "Error: cannot resolve '$d' — the directory is not searchable." >&2
        else
            echo "Error: cannot resolve '$1' — its existing parent '$d' is not searchable." >&2
        fi
        return 2
    }
    printf '%s%s' "$abs" "$tail"
}

if [ ! -d "$MEM_DIR" ]; then
    echo "Error: memory directory not found: $MEM_DIR" >&2
    exit 2
fi

MEM_DIR=$(normalize_dir "$MEM_DIR") || exit 2
[ -z "$ARCHIVE_DIR" ] && ARCHIVE_DIR="$MEM_DIR/archive"
ARCHIVE_DIR=$(normalize_dir "$ARCHIVE_DIR") || exit 2

## Per-file TTL defaults, applied ONLY to dated entries that carry no ttl: of their own.
## This table ships no `*` catch-all: a file nobody classified stays immortal until a project
## opts in via MEMORY_TTL_DEFAULTS, which may use `*`. resolve_ttl still probes `*` in both
## tables so the precedence order stays uniform across them.
SHARED_TTL_DEFAULTS="
lessons.md=90d
preferences.md=infinite
people.md=infinite
user.md=infinite
"

## The conf is project-owned DATA that can arrive via `git pull` from a repository the developer
## does not control. It is parsed, never executed: conf_get copies out the one key named below,
## literally, with no shell semantics at all. So a conf carries no commands, cannot flip APPLY,
## cannot redirect MEM_DIR/ARCHIVE_DIR past their validation and cannot blank SHARED_TTL_DEFAULTS.
## The other keys in budget.conf (MAX_EFFECTIVE_LINES, INCLUDE_FILES, MAP_FILE, …) belong to other
## scripts; asking for one key by name is what makes that a whitelist rather than a convention.
BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ ! -r "$BIN_DIR/conf-read.sh" ]; then
    echo "Error: $BIN_DIR/conf-read.sh is missing — re-run the Agent-Context update to restore it." >&2
    exit 2
fi
#shellcheck source=conf-read.sh
. "$BIN_DIR/conf-read.sh"

MEMORY_TTL_DEFAULTS=""
CONF_STATUS="missing"
if [ -f "$CONF" ]; then
    if conf_get_into MEMORY_TTL_DEFAULTS "$CONF" MEMORY_TTL_DEFAULTS; then
        CONF_STATUS="loaded"
    else
        MEMORY_TTL_DEFAULTS=""
        ## conf_get_into returns 1 both when the key is simply absent (a normal, silent no-op) and
        ## when it is present but malformed (e.g. an unclosed quote). Only the second is worth a
        ## warning — grep for the key literally to tell the two apart without re-parsing the file.
        if grep -qE '^[[:space:]]*(export[[:space:]]+)?MEMORY_TTL_DEFAULTS=' "$CONF" 2>/dev/null; then
            CONF_STATUS="parse-failed"
            echo "Warning: $CONF sets MEMORY_TTL_DEFAULTS but it could not be parsed (unclosed quote?) — using built-in defaults only." >&2
        else
            CONF_STATUS="no-entry"
        fi
    fi
fi

## Converts YYYY-MM-DD to a Unix epoch. Empty output on parse failure.
date_to_epoch() {
    local d="$1"
    date -j -f "%Y-%m-%d" "$d" +%s 2>/dev/null \
        || date -d "$d" +%s 2>/dev/null \
        || echo ""
}

## Rejects a malformed map before any file is touched — a partial rewrite is worse than
## a hard stop. Word splitting on the map is intentional, as with INCLUDE_FILES; pathname
## expansion is not, or a `*` key would be reported as an unrelated filename.
validate_ttl_map() {
    local label="$1" map="$2" token key value
    set -f
    #shellcheck disable=SC2086
    for token in $map; do
        case "$token" in
            *=*) ;;
            *) set +f; echo "Error: $label entry '$token' is not key=value." >&2; exit 2 ;;
        esac
        key="${token%%=*}"
        value="${token#*=}"
        [ -n "$key" ] || { set +f; echo "Error: $label entry '$token' has an empty key." >&2; exit 2; }
        case "$key" in
            */*) set +f; echo "Error: $label key '$key' must be a file basename, not a path." >&2; exit 2 ;;
        esac
        ## No leading zero: `$(( ))` reads one as octal, and 08/09 are not octal at all — an
        ## invalid one raised a fatal expansion error mid-scan while the run still exited 0.
        if [ "$value" != "infinite" ] && ! printf '%s' "$value" | grep -qE '^([1-9][0-9]*|0)d$'; then
            set +f
            echo "Error: $label value for '$key' must be <N>d or infinite, got '$value'." >&2
            exit 2
        fi
    done
    set +f
}

## Both lookups hand their hit back through TTL_MATCH rather than stdout: a command substitution
## forks a subshell per call, and resolve_ttl probes up to four tables for every dated entry.
TTL_MATCH=""

lookup_ttl_map() {
    local map="$1" want="$2" token
    set -f
    #shellcheck disable=SC2086
    for token in $map; do
        if [ "${token%%=*}" = "$want" ]; then
            set +f
            TTL_MATCH="${token#*=}"
            return 0
        fi
    done
    set +f
    return 1
}

## Exact basename beats catch-all; within each, the conf beats the shared table.
resolve_ttl() {
    local base="$1"
    if lookup_ttl_map "$MEMORY_TTL_DEFAULTS" "$base"; then return 0; fi
    if lookup_ttl_map "$SHARED_TTL_DEFAULTS" "$base"; then return 0; fi
    if lookup_ttl_map "$MEMORY_TTL_DEFAULTS" '*'; then return 0; fi
    if lookup_ttl_map "$SHARED_TTL_DEFAULTS" '*'; then return 0; fi
    TTL_MATCH=""
    return 1
}

validate_ttl_map "MEMORY_TTL_DEFAULTS" "$MEMORY_TTL_DEFAULTS"
validate_ttl_map "SHARED_TTL_DEFAULTS" "$SHARED_TTL_DEFAULTS"

NOW_EPOCH=$(date +%s)
## ISO week of the run (e.g. 2026-W03) — one archive file per prune run/week.
ARCHIVE_WEEK=$(date +%G-W%V)
ARCHIVE_FILE="$ARCHIVE_DIR/${ARCHIVE_WEEK}.md"
TODAY=$(date +%Y-%m-%d)

expired_count=0
scanned_files=0

## Per-file temp files, promoted to script scope (not `local` to process_file) so the trap below
## can reach whichever ones are live at the moment of a signal. A SIGINT mid-scan otherwise left
## them behind under their random mktemp names, holding memory content until TMPDIR was cleared.
tmp=""
keep_tmp=""
dest_tmp=""
cleanup_temp_files() {
    rm -f "${tmp:-}" "${keep_tmp:-}" "${dest_tmp:-}" 2>/dev/null || true
}
## A signal-only cleanup ("trap cleanup_temp_files INT ...", no exit) does NOT stop the script —
## bash resumes the interrupted loop right after the trap returns. The loop's `>> "$keep_tmp"`
## calls then recreate the file the trap just removed, silently DROPPING every line buffered
## before the signal. Resetting the trap and re-sending the signal to ourselves makes the
## process actually die from it (standard 128+signal exit), which is what stops the loop.
die_on_signal() {
    cleanup_temp_files
    trap - "$1"
    kill -s "$1" "$$"
}
trap cleanup_temp_files EXIT
trap 'die_on_signal INT' INT
trap 'die_on_signal TERM' TERM
trap 'die_on_signal HUP' HUP

## Resolves a symlinked memory file to its physical target. A rewrite has to replace the
## TARGET's content — mv over the link would swap a deliberately shared file for a private copy.
resolve_link() {
    local f="$1" dir leaf target hops=0
    dir=$(cd "$(dirname "$f")" 2>/dev/null && pwd -P) || { printf '%s' "$f"; return 0; }
    leaf=$(basename "$f")
    while [ -L "$dir/$leaf" ] && [ "$hops" -lt 32 ]; do
        target=$(readlink "$dir/$leaf")
        case "$target" in
            /*) ;;
            *) target="$dir/$target" ;;
        esac
        dir=$(cd "$(dirname "$target")" 2>/dev/null && pwd -P) || break
        leaf=$(basename "$target")
        hops=$((hops + 1))
    done
    printf '%s/%s' "$dir" "$leaf"
}

## Per-line metadata patterns. Held in variables because bash 3.2 treats a quoted regex on the
## right of =~ as a literal string; an unquoted variable is the form that works across versions.
## All three match leftmost, which is the `grep -oE … | head -1` semantics they replaced.
ENTRY_DATE_RE='\((20[0-9]{2}-[0-9]{2}-[0-9]{2})\)'
TTL_DAYS_RE='ttl:([0-9]+)d'
TTL_TOKEN_RE='ttl:[A-Za-z0-9]+'

## Collected per file: lines to archive, written only in --apply mode.
process_file() {
    local file="$1"
    local base dest
    base=$(basename "$file")
    case "$base" in
        index.md|todo.md) return 0 ;;
    esac

    dest=$(resolve_link "$file")
    ## resolve_link follows the link to its physical target on purpose, which is also a read and
    ## write primitive for anything outside the tree: a repository shipping nothing but
    ## `memory/lessons.md -> ~/private-notes.md` otherwise reaches every file the developer can
    ## write, and the archive lives inside the repository, so the next push carries it out.
    ## Same containment shape as the archive guard below — the quoted variable matches literally.
    case "$dest" in
        "$MEM_DIR"/*) ;;
        *)
            echo "Warning: skipping $file — it resolves to $dest, outside the memory directory $MEM_DIR." >&2
            return 0 ;;
    esac
    ## Independent of the find-level exclusion: whatever route the scan took to get here, a file
    ## inside the archive is never a source. Rewriting one would erase the append just made to it.
    case "$file" in "$ARCHIVE_DIR"/*) return 0 ;; esac
    case "$dest" in "$ARCHIVE_DIR"/*) return 0 ;; esac
    [ "$file" = "$ARCHIVE_FILE" ] && return 0
    [ "$dest" = "$ARCHIVE_FILE" ] && return 0

    if [ ! -r "$file" ]; then
        echo "Warning: skipping unreadable file: $file" >&2
        return 0
    fi

    local had_expired=0
    tmp=$(mktemp "${TMPDIR:-/tmp}/memprune.arch.XXXXXX" 2>/dev/null) || tmp=""
    keep_tmp=$(mktemp "${TMPDIR:-/tmp}/memprune.keep.XXXXXX" 2>/dev/null) || keep_tmp=""
    if [ -z "$tmp" ] || [ -z "$keep_tmp" ]; then
        ## The EXIT trap cleans up whichever of the two mktemp calls succeeded.
        echo "Error: cannot create a temp file in ${TMPDIR:-/tmp} — $file was left unchanged." >&2
        exit 2
    fi

    while IFS= read -r line || [ -n "$line" ]; do
        local entry_date="" ttl_days="" ttl_token="" expiry mark
        if [[ $line =~ $ENTRY_DATE_RE ]]; then entry_date="${BASH_REMATCH[1]}"; fi

        if [ -z "$entry_date" ]; then
            printf '%s\n' "$line" >> "$keep_tmp"
            continue
        fi

        if [[ $line =~ $TTL_DAYS_RE ]]; then ttl_days="${BASH_REMATCH[1]}"; fi

        mark=""
        if [ -z "$ttl_days" ]; then
            ## ttl_token additionally catches ttl:infinite and any other self-declared TTL, so a
            ## file default never overrides an explicit one. Only computed here, where it is read.
            if [[ $line =~ $TTL_TOKEN_RE ]]; then ttl_token="${BASH_REMATCH[0]}"; fi
            if [ -n "$ttl_token" ]; then
                if [ "$ttl_token" != "ttl:infinite" ]; then
                    ## Matches ttl:[A-Za-z0-9]+ but not the numeric ttl:Nd form above and not
                    ## ttl:infinite either — a typo like ttl:90 or ttl:infinitee. Warn rather than
                    ## silently treating a broken token as a deliberate immortal entry.
                    echo "Warning: $file — malformed ttl token '$ttl_token' on a dated entry; kept, not archived: $line" >&2
                fi
                ## Self-declared (ttl:infinite, or the malformed token warned above) — keep the line.
                printf '%s\n' "$line" >> "$keep_tmp"
                continue
            fi
            local default_ttl=""
            if resolve_ttl "$base"; then default_ttl="$TTL_MATCH"; fi
            if [ -z "$default_ttl" ] || [ "$default_ttl" = "infinite" ]; then
                printf '%s\n' "$line" >> "$keep_tmp"
                continue
            fi
            ttl_days="${default_ttl%d}"
            mark="default $default_ttl"
        fi

        local entry_epoch
        entry_epoch=$(date_to_epoch "$entry_date")
        if [ -z "$entry_epoch" ]; then
            printf '%s\n' "$line" >> "$keep_tmp"
            continue
        fi

        ## 10# forces base ten: an entry-declared ttl:09d is a leading zero the arithmetic would
        ## otherwise read as octal, and 08/09 are invalid octal — a fatal expansion error that
        ## terminated the read loop and left every later entry in the file unscanned.
        expiry=$((entry_epoch + 10#$ttl_days * 86400))
        if [ "$NOW_EPOCH" -gt "$expiry" ]; then
            printf '%s\t%s\n' "$mark" "$line" >> "$tmp"
            had_expired=1
            expired_count=$((expired_count + 1))
        else
            printf '%s\n' "$line" >> "$keep_tmp"
        fi
    done < "$file"

    if [ "$had_expired" -eq 1 ]; then
        echo "  $base:"
        ## Field 1 is the marker; everything after the FIRST tab is the entry — a memory line may
        ## itself contain tabs, and the preview is the safety net before --apply, so never truncate.
        awk -F'\t' '{ rest = $0; sub(/^[^\t]*\t/, "", rest);
                      if ($1 == "") printf "    EXPIRED → %s\n", rest;
                      else printf "    EXPIRED (%s) → %s\n", $1, rest }' "$tmp"
        if [ "$APPLY" -eq 1 ]; then
            ## Both writes precede the source rewrite, so a failure here costs nothing — but it has
            ## to leave through the declared exit 2, not a set -e death at exit 1. The leading
            ## 2>/dev/null is applied before the append, so a failing >> reports through the message
            ## below instead of a raw "Permission denied".
            mkdir -p "$ARCHIVE_DIR" 2>/dev/null || {
                echo "Error: cannot create the archive directory $ARCHIVE_DIR — $dest was left unchanged." >&2
                exit 2
            }
            {
                printf '## From %s (archived %s)\n\n' "$base" "$TODAY"
                cut -f2- "$tmp"
                printf '\n'
            } 2>/dev/null >> "$ARCHIVE_FILE" || {
                echo "Error: cannot write the archive $ARCHIVE_FILE — $dest was left unchanged." >&2
                exit 2
            }
            ## Atomic replace: rename within the same directory so an interrupt can never
            ## leave the project-owned memory file truncated. The archive append above already
            ## happened, so any failure here leaves a DUPLICATE — say so and stop at exit 2
            ## rather than letting set -e kill the run with an undeclared exit 1.
            dest_tmp=$(mktemp "$(dirname "$dest")/.memprune.XXXXXX" 2>/dev/null) || {
                echo "Error: cannot create a temp file next to $dest — it was not rewritten." >&2
                echo "       The expired entr(ies) are now BOTH in $ARCHIVE_FILE and still in $dest." >&2
                echo "       Fix the issue first, then remove the duplicate entr(ies) from $ARCHIVE_FILE before re-running --apply." >&2
                exit 2
            }
            ## dest was resolved before the file was read and before the archive was appended.
            ## Re-assert containment here, at the moment the write lands, so a link repointed
            ## during that window cannot redirect the rewrite out of the tree.
            local dest_now
            dest_now=$(resolve_link "$file")
            case "$dest_now" in "$MEM_DIR"/*) ;; *) dest_now="" ;; esac
            if [ "$dest_now" != "$dest" ]; then
                echo "Error: $file changed where it points while it was processed — $dest was not rewritten." >&2
                echo "       The expired entr(ies) are now BOTH in $ARCHIVE_FILE and still in $dest." >&2
                echo "       Fix the issue first, then remove the duplicate entr(ies) from $ARCHIVE_FILE before re-running --apply." >&2
                exit 2
            fi
            cp "$keep_tmp" "$dest_tmp" && mv "$dest_tmp" "$dest" || {
                echo "Error: failed to rewrite $dest." >&2
                echo "       The expired entr(ies) are now BOTH in $ARCHIVE_FILE and still in $dest." >&2
                echo "       Fix the issue first, then remove the duplicate entr(ies) from $ARCHIVE_FILE before re-running --apply." >&2
                exit 2
            }
        fi
    fi

    rm -f "$tmp" "$keep_tmp"
}

echo "Memory decay scan — $MEM_DIR (today: $TODAY)"
case "$CONF_STATUS" in
    loaded) echo "Config: $CONF (MEMORY_TTL_DEFAULTS loaded)" ;;
    no-entry) echo "Config: $CONF found, no MEMORY_TTL_DEFAULTS entry — built-in defaults only" ;;
    parse-failed) echo "Config: $CONF found, MEMORY_TTL_DEFAULTS could not be parsed — built-in defaults only" ;;
    missing) echo "Config: $CONF not found — built-in defaults only" ;;
esac
[ "$APPLY" -eq 1 ] && echo "Mode: APPLY (files will be rewritten)" || echo "Mode: dry-run (no changes; pass --apply to archive)"
echo ""

## BSD sort gained -z on macOS 12. Without it the scan keeps find's own order, which is stable
## for a given tree and only reorders the per-file blocks of the report.
sort_paths() {
    if printf '\0' | sort -z >/dev/null 2>&1; then sort -z; else cat; fi
}

## Recursive: expanded domains live in memory/<domain>/*.md. -not -path excludes the archive as
## a first pass, but -path treats *, ?, [ in ARCHIVE_DIR as wildcards, so a directory name
## containing one can make the exclusion miss. The case guards in process_file (the ARCHIVE_DIR
## and ARCHIVE_FILE checks right after resolve_link) are what actually keep the archive out of
## the rewrite; this find exclusion only saves the wasted read when it matches.
## -L follows symlinks: a project may symlink its memory dir. Targets outside the tree are
## rejected per file in process_file.
## NUL-delimited: a newline is legal in a directory name, and git stores one, so a
## newline-separated scan splits a single path into two — the second fragment being an
## independent path outside the tree that the loop would then read and rewrite.
## Process substitution, not a pipe — a pipe would run the loop in a subshell and discard
## expired_count and scanned_files.
while IFS= read -r -d '' f; do
    [ -e "$f" ] || continue
    scanned_files=$((scanned_files + 1))
    process_file "$f"
done < <(find -L "$MEM_DIR" -type f -name '*.md' -not -path "$ARCHIVE_DIR/*" -print0 2>/dev/null | sort_paths)

if [ "$scanned_files" -eq 0 ] && [ -n "$(ls -A "$MEM_DIR" 2>/dev/null)" ]; then
    echo "Warning: $MEM_DIR is not empty but no .md file was readable — broken symlink?" >&2
fi

echo ""
if [ "$expired_count" -eq 0 ]; then
    echo "No expired entries across $scanned_files file(s). Nothing to archive."
elif [ "$APPLY" -eq 1 ]; then
    echo "Archived $expired_count expired entr(ies) → $ARCHIVE_FILE"
else
    echo "$expired_count expired entr(ies) would be archived → $ARCHIVE_FILE"
    echo "Re-run with --apply to perform the move."
fi
