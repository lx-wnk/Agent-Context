#!/usr/bin/env bash
set -euo pipefail

# Memory rotation / decay: archive expired dated memory entries.
#
# Scans memory/ recursively, so expanded domains (memory/<domain>/*.md) are covered too.
# Symlinked files and symlinked sub-directories are followed. Skips the archive/ directory
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
            grep '^#' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

# `find` normalizes its own start argument, so an un-normalized ARCHIVE_DIR ("memory/archive"
# against a "-dir memory/" scan) makes the -path exclusion miss — the archive is then scanned
# as a source file and its own rewrite wipes what earlier weeks put there.
# Walks up to the first existing ancestor, so a not-yet-created archive still canonicalizes.
normalize_dir() {
    local d="$1" tail="" parent leaf
    while [ "${d%/}" != "$d" ] && [ "$d" != "/" ]; do d="${d%/}"; done
    [ -n "$d" ] || { printf '%s' "$1"; return 0; }
    while [ ! -d "$d" ]; do
        parent=$(dirname "$d")
        leaf=$(basename "$d")
        [ "$parent" = "$d" ] && { printf '%s' "$1"; return 0; }
        tail="/$leaf$tail"
        d="$parent"
    done
    printf '%s%s' "$(cd "$d" && pwd -P)" "$tail"
}

if [ ! -d "$MEM_DIR" ]; then
    echo "Error: memory directory not found: $MEM_DIR" >&2
    exit 2
fi

MEM_DIR=$(normalize_dir "$MEM_DIR")
[ -z "$ARCHIVE_DIR" ] && ARCHIVE_DIR="$MEM_DIR/archive"
ARCHIVE_DIR=$(normalize_dir "$ARCHIVE_DIR")

# Per-file TTL defaults, applied ONLY to dated entries that carry no ttl: of their own.
# Deliberately no `*` catch-all: a file nobody classified stays immortal until a project
# opts in via MEMORY_TTL_DEFAULTS.
SHARED_TTL_DEFAULTS="
lessons.md=90d
preferences.md=infinite
people.md=infinite
user.md=infinite
"

# The conf may set MEMORY_TTL_DEFAULTS — and nothing else this script relies on. It is sourced
# in a SUBSHELL and only that one key is read back, so a conf cannot flip APPLY, redirect
# MEM_DIR/ARCHIVE_DIR past their validation, or blank out SHARED_TTL_DEFAULTS. The other keys
# in budget.conf (MAX_EFFECTIVE_LINES, INCLUDE_FILES, MAP_FILE, …) belong to other scripts and
# are simply ignored here.
MEMORY_TTL_DEFAULTS=""
if [ -f "$CONF" ]; then
    MEMORY_TTL_DEFAULTS=$(
        set +e
        # shellcheck disable=SC1090
        . "$CONF" >/dev/null 2>&1
        printf '%s' "${MEMORY_TTL_DEFAULTS:-}"
    ) || MEMORY_TTL_DEFAULTS=""
fi

# Converts YYYY-MM-DD to a Unix epoch. Empty output on parse failure.
date_to_epoch() {
    local d="$1"
    date -j -f "%Y-%m-%d" "$d" +%s 2>/dev/null \
        || date -d "$d" +%s 2>/dev/null \
        || echo ""
}

# Rejects a malformed map before any file is touched — a partial rewrite is worse than
# a hard stop. Word splitting on the map is intentional, as with INCLUDE_FILES.
validate_ttl_map() {
    local label="$1" map="$2" token key value
    # shellcheck disable=SC2086
    for token in $map; do
        case "$token" in
            *=*) ;;
            *) echo "Error: $label entry '$token' is not key=value." >&2; exit 2 ;;
        esac
        key="${token%%=*}"
        value="${token#*=}"
        [ -n "$key" ] || { echo "Error: $label entry '$token' has an empty key." >&2; exit 2; }
        case "$key" in
            */*) echo "Error: $label key '$key' must be a file basename, not a path." >&2; exit 2 ;;
        esac
        if [ "$value" != "infinite" ] && ! printf '%s' "$value" | grep -qE '^[0-9]+d$'; then
            echo "Error: $label value for '$key' must be <N>d or infinite, got '$value'." >&2
            exit 2
        fi
    done
}

lookup_ttl_map() {
    local map="$1" want="$2" token
    # shellcheck disable=SC2086
    for token in $map; do
        [ "${token%%=*}" = "$want" ] && { printf '%s' "${token#*=}"; return 0; }
    done
    return 1
}

# Exact basename beats catch-all; within each, the conf beats the shared table.
resolve_ttl() {
    local base="$1" v
    if v=$(lookup_ttl_map "$MEMORY_TTL_DEFAULTS" "$base"); then printf '%s' "$v"; return 0; fi
    if v=$(lookup_ttl_map "$SHARED_TTL_DEFAULTS" "$base"); then printf '%s' "$v"; return 0; fi
    if v=$(lookup_ttl_map "$MEMORY_TTL_DEFAULTS" '*'); then printf '%s' "$v"; return 0; fi
    if v=$(lookup_ttl_map "$SHARED_TTL_DEFAULTS" '*'); then printf '%s' "$v"; return 0; fi
    return 1
}

validate_ttl_map "MEMORY_TTL_DEFAULTS" "$MEMORY_TTL_DEFAULTS"
validate_ttl_map "SHARED_TTL_DEFAULTS" "$SHARED_TTL_DEFAULTS"

NOW_EPOCH=$(date +%s)
# ISO week of the run (e.g. 2026-W03) — one archive file per prune run/week.
ARCHIVE_WEEK=$(date +%G-W%V)
ARCHIVE_FILE="$ARCHIVE_DIR/${ARCHIVE_WEEK}.md"
TODAY=$(date +%Y-%m-%d)

expired_count=0
scanned_files=0

# Resolves a symlinked memory file to its physical target. A rewrite has to replace the
# TARGET's content — mv over the link would swap a deliberately shared file for a private copy.
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

# Collected per file: lines to archive, written only in --apply mode.
process_file() {
    local file="$1"
    local base dest
    base=$(basename "$file")
    case "$base" in
        index.md|todo.md) return 0 ;;
    esac

    dest=$(resolve_link "$file")
    # Independent of the find-level exclusion: whatever route the scan took to get here, a file
    # inside the archive is never a source. Rewriting one would erase the append just made to it.
    case "$file" in "$ARCHIVE_DIR"/*) return 0 ;; esac
    case "$dest" in "$ARCHIVE_DIR"/*) return 0 ;; esac
    [ "$file" = "$ARCHIVE_FILE" ] && return 0
    [ "$dest" = "$ARCHIVE_FILE" ] && return 0

    if [ ! -r "$file" ]; then
        echo "Warning: skipping unreadable file: $file" >&2
        return 0
    fi

    local tmp keep_tmp had_expired=0
    tmp=$(mktemp "${TMPDIR:-/tmp}/memprune.arch.XXXXXX")
    keep_tmp=$(mktemp "${TMPDIR:-/tmp}/memprune.keep.XXXXXX")

    while IFS= read -r line || [ -n "$line" ]; do
        local entry_date ttl_days ttl_token expiry mark
        # Extract (YYYY-MM-DD) and ttl:Nd. ttl_token additionally catches ttl:infinite and
        # any other self-declared TTL, so a file default never overrides an explicit one.
        entry_date=$(printf '%s\n' "$line" | grep -oE '\(20[0-9]{2}-[0-9]{2}-[0-9]{2}\)' | head -1 | tr -d '()' || true)
        ttl_days=$(printf '%s\n' "$line" | grep -oE 'ttl:[0-9]+d' | head -1 | grep -oE '[0-9]+' || true)
        ttl_token=$(printf '%s\n' "$line" | grep -oE 'ttl:[A-Za-z0-9]+' | head -1 || true)

        if [ -z "$entry_date" ]; then
            printf '%s\n' "$line" >> "$keep_tmp"
            continue
        fi

        mark=""
        if [ -z "$ttl_days" ]; then
            if [ -n "$ttl_token" ]; then
                # Self-declared but non-numeric (ttl:infinite) — honour it, keep the line.
                printf '%s\n' "$line" >> "$keep_tmp"
                continue
            fi
            local default_ttl=""
            default_ttl=$(resolve_ttl "$base") || default_ttl=""
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

        expiry=$((entry_epoch + ttl_days * 86400))
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
        awk -F'\t' '{ if ($1 == "") printf "    EXPIRED → %s\n", $2; else printf "    EXPIRED (%s) → %s\n", $1, $2 }' "$tmp"
        if [ "$APPLY" -eq 1 ]; then
            mkdir -p "$ARCHIVE_DIR"
            {
                printf '## From %s (archived %s)\n\n' "$base" "$TODAY"
                cut -f2- "$tmp"
                printf '\n'
            } >> "$ARCHIVE_FILE"
            # Atomic replace: rename within the same directory so an interrupt can never
            # leave the project-owned memory file truncated. The archive append above already
            # happened, so any failure here leaves a DUPLICATE — say so and stop at exit 2
            # rather than letting set -e kill the run with an undeclared exit 1.
            local dest_tmp
            dest_tmp=$(mktemp "$(dirname "$dest")/.memprune.XXXXXX" 2>/dev/null) || {
                rm -f "$tmp" "$keep_tmp"
                echo "Error: cannot create a temp file next to $dest — it was not rewritten." >&2
                echo "       The expired entr(ies) are now BOTH in $ARCHIVE_FILE and still in $dest." >&2
                exit 2
            }
            cp "$keep_tmp" "$dest_tmp" && mv "$dest_tmp" "$dest" || {
                rm -f "$dest_tmp" "$tmp" "$keep_tmp"
                echo "Error: failed to rewrite $dest." >&2
                echo "       The expired entr(ies) are now BOTH in $ARCHIVE_FILE and still in $dest." >&2
                exit 2
            }
        fi
    fi

    rm -f "$tmp" "$keep_tmp"
}

echo "Memory decay scan — $MEM_DIR (today: $TODAY)"
[ "$APPLY" -eq 1 ] && echo "Mode: APPLY (files will be rewritten)" || echo "Mode: dry-run (no changes; pass --apply to archive)"
echo ""

# Recursive: expanded domains live in memory/<domain>/*.md. The archive is excluded, or
# every run would re-scan and re-archive what the previous run moved there.
# -L follows symlinks: a project may symlink its memory dir or share a single lessons.md.
# Process substitution, not a pipe — a pipe would run the loop in a subshell and discard
# expired_count and scanned_files.
while IFS= read -r f; do
    [ -e "$f" ] || continue
    scanned_files=$((scanned_files + 1))
    process_file "$f"
done < <(find -L "$MEM_DIR" -type f -name '*.md' -not -path "$ARCHIVE_DIR/*" 2>/dev/null | sort)

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
