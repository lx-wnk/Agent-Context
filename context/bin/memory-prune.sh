#!/usr/bin/env bash
set -euo pipefail

# Memory rotation / decay: archive expired dated memory entries.
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
#   memory-prune.sh [--apply] [--dir PATH] [--archive PATH]
#
# Defaults: --dir .agent-context/memory   --archive .agent-context/memory/archive
#
# Portability: handles both GNU date (-d) and BSD/macOS date (-j -f), same approach
# install.sh uses for stat. No non-POSIX tools beyond awk/grep/date.

APPLY=0
MEM_DIR=".agent-context/memory"
ARCHIVE_DIR=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --apply) APPLY=1; shift ;;
        --dir) MEM_DIR="${2:-}"; shift 2 ;;
        --dir=*) MEM_DIR="${1#--dir=}"; shift ;;
        --archive) ARCHIVE_DIR="${2:-}"; shift 2 ;;
        --archive=*) ARCHIVE_DIR="${1#--archive=}"; shift ;;
        -h|--help)
            grep '^#' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

[ -z "$ARCHIVE_DIR" ] && ARCHIVE_DIR="$MEM_DIR/archive"

if [ ! -d "$MEM_DIR" ]; then
    echo "Error: memory directory not found: $MEM_DIR" >&2
    exit 2
fi

# Converts YYYY-MM-DD to a Unix epoch. Empty output on parse failure.
date_to_epoch() {
    local d="$1"
    date -j -f "%Y-%m-%d" "$d" +%s 2>/dev/null \
        || date -d "$d" +%s 2>/dev/null \
        || echo ""
}

NOW_EPOCH=$(date +%s)
# ISO week of the run (e.g. 2026-W03) — one archive file per prune run/week.
ARCHIVE_WEEK=$(date +%G-W%V)
ARCHIVE_FILE="$ARCHIVE_DIR/${ARCHIVE_WEEK}.md"
TODAY=$(date +%Y-%m-%d)

expired_count=0
scanned_files=0

# Collected per file: lines to archive, written only in --apply mode.
process_file() {
    local file="$1"
    local base
    base=$(basename "$file")
    case "$base" in
        index.md|todo.md) return 0 ;;
    esac

    local tmp keep_tmp had_expired=0
    tmp=$(mktemp "${TMPDIR:-/tmp}/memprune.arch.XXXXXX")
    keep_tmp=$(mktemp "${TMPDIR:-/tmp}/memprune.keep.XXXXXX")

    while IFS= read -r line || [ -n "$line" ]; do
        local entry_date ttl_days expiry
        # Extract (YYYY-MM-DD) and ttl:Nd. Lines without both are kept as-is.
        entry_date=$(printf '%s\n' "$line" | grep -oE '\(20[0-9]{2}-[0-9]{2}-[0-9]{2}\)' | head -1 | tr -d '()' || true)
        ttl_days=$(printf '%s\n' "$line" | grep -oE 'ttl:[0-9]+d' | head -1 | grep -oE '[0-9]+' || true)

        if [ -z "$entry_date" ] || [ -z "$ttl_days" ]; then
            printf '%s\n' "$line" >> "$keep_tmp"
            continue
        fi

        local entry_epoch
        entry_epoch=$(date_to_epoch "$entry_date")
        if [ -z "$entry_epoch" ]; then
            printf '%s\n' "$line" >> "$keep_tmp"
            continue
        fi

        expiry=$((entry_epoch + ttl_days * 86400))
        if [ "$NOW_EPOCH" -gt "$expiry" ]; then
            printf '%s\n' "$line" >> "$tmp"
            had_expired=1
            expired_count=$((expired_count + 1))
        else
            printf '%s\n' "$line" >> "$keep_tmp"
        fi
    done < "$file"

    if [ "$had_expired" -eq 1 ]; then
        echo "  $base:"
        sed 's/^/    EXPIRED → /' "$tmp"
        if [ "$APPLY" -eq 1 ]; then
            mkdir -p "$ARCHIVE_DIR"
            {
                printf '## From %s (archived %s)\n\n' "$base" "$TODAY"
                cat "$tmp"
                printf '\n'
            } >> "$ARCHIVE_FILE"
            # Atomic replace: rename within the same directory so an interrupt can never
            # leave the project-owned memory file truncated.
            local dest_tmp
            dest_tmp="$(mktemp "$(dirname "$file")/.memprune.XXXXXX")"
            cp "$keep_tmp" "$dest_tmp" && mv "$dest_tmp" "$file" || { rm -f "$dest_tmp"; echo "Error: failed to rewrite $file" >&2; }
        fi
    fi

    rm -f "$tmp" "$keep_tmp"
}

echo "Memory decay scan — $MEM_DIR (today: $TODAY)"
[ "$APPLY" -eq 1 ] && echo "Mode: APPLY (files will be rewritten)" || echo "Mode: dry-run (no changes; pass --apply to archive)"
echo ""

for f in "$MEM_DIR"/*.md; do
    [ -f "$f" ] || continue
    scanned_files=$((scanned_files + 1))
    process_file "$f"
done

echo ""
if [ "$expired_count" -eq 0 ]; then
    echo "No expired entries across $scanned_files file(s). Nothing to archive."
elif [ "$APPLY" -eq 1 ]; then
    echo "Archived $expired_count expired entr(ies) → $ARCHIVE_FILE"
else
    echo "$expired_count expired entr(ies) would be archived → $ARCHIVE_FILE"
    echo "Re-run with --apply to perform the move."
fi
