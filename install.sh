#!/usr/bin/env bash
set -euo pipefail

if ! command -v curl &>/dev/null; then
    echo "Error: curl not found. Install curl and try again." >&2
    exit 1
fi

PROMPT_URL="https://raw.githubusercontent.com/lx-wnk/Agent-Context/main/.prompts/setup-prompt.md"
ALLOWED_TOOLS="Edit,Write,Read,Bash,Glob,Grep,WebFetch,WebSearch,Agent"
LOG=".agent-context/setup.log"

# --local <path>: use a local prompt file instead of the remote URL (for testing)
# --ai-dirs=<dirs>: comma-separated extra AI-doc dirs to treat as migratable (e.g. --ai-dirs=".cursor,.ai-custom")
# --force: skip the up-to-date short-circuit and run the full update flow
PROMPT_INSTRUCTION="Fetch $PROMPT_URL and follow its instructions exactly."
if [ "${1:-}" = "--local" ]; then
    AGENT_CONTEXT_PROMPT="${2:-}"
fi
if [ -n "${AGENT_CONTEXT_PROMPT:-}" ]; then
    if [ ! -f "$AGENT_CONTEXT_PROMPT" ]; then
        echo "Error: AGENT_CONTEXT_PROMPT file not found: $AGENT_CONTEXT_PROMPT" >&2
        exit 1
    fi
    PROMPT_INSTRUCTION="Read $(realpath "$AGENT_CONTEXT_PROMPT") and follow its instructions exactly."
fi

FORCE=0
AI_DIRS=""
for arg in "$@"; do
    case "$arg" in
        --ai-dirs=*) AI_DIRS="${arg#--ai-dirs=}" ;;
        --force) FORCE=1 ;;
    esac
done

if [ -n "$AI_DIRS" ]; then
    PROMPT_INSTRUCTION="$PROMPT_INSTRUCTION Additional AI directories to treat as migratable (extends built-in defaults): $AI_DIRS"
fi

if [ "$FORCE" -eq 1 ]; then
    # COUPLING: the exact sentinel string "Force flag is set" is matched verbatim
    # in setup-prompt.md Step 1. If you rename this sentinel, update that check too.
    PROMPT_INSTRUCTION="$PROMPT_INSTRUCTION Force flag is set: skip any up-to-date version checks and perform a full update regardless of current version."
fi

update_claude_md() {
    local updated=0
    for loc in ".claude/CLAUDE.md" "CLAUDE.md"; do
        [ -f "$loc" ] || continue
        # Skip only if the file is already bootstrap-only: every non-blank line
        # must consist solely of the @AGENTS.md pointer — no other content.
        # This matches the guard in setup-prompt.md Step 4.5a exactly; a looser
        # check (e.g. line count alone) would incorrectly skip files that contain
        # real conventions alongside the pointer.
        # Fix 5: use awk 'END{print NR}' instead of wc -l to correctly count lines
        # in files without a trailing newline (wc -l undercounts by 1 in that case).
        if grep -q "@AGENTS.md" "$loc" && [ "$(awk 'END{print NR}' "$loc")" -le 5 ] && \
           [ "$(grep -cve '^[[:space:]]*$' "$loc")" -eq "$(grep -cxe '[[:space:]]*@AGENTS\.md[[:space:]]*' "$loc")" ]; then
            continue
        fi
        printf '@AGENTS.md\n' > "$loc"
        echo "Updated $loc → @AGENTS.md"
        updated=1
    done
    if [ "$updated" -eq 0 ] && [ ! -f ".claude/CLAUDE.md" ] && [ ! -f "CLAUDE.md" ]; then
        mkdir -p .claude
        printf '@AGENTS.md\n' > .claude/CLAUDE.md
        echo "Created .claude/CLAUDE.md → @AGENTS.md"
    fi
}

# Validate that the cache base is an absolute path before using it.
# XDG_CACHE_HOME or HOME may be relative/empty on hardened/CI systems;
# an untrusted value could enable path injection. Fall back to /tmp when unsure.
_raw_cache_base="${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}"
case "$_raw_cache_base" in
    /*)
        # Fix 8: also reject paths containing '..' segments to fully close path-injection vector
        case "$_raw_cache_base" in
            */..*) CACHE_DIR="/tmp/agent-context" ;;
            *)     CACHE_DIR="$_raw_cache_base/agent-context" ;;
        esac
        ;;
    *)  CACHE_DIR="/tmp/agent-context" ;;
esac
CACHE_FILE="$CACHE_DIR/latest-version"
CACHE_TTL=3600

# Fix 7: declare CACHE_STALE as a global before get_latest_version is defined.
# get_latest_version sets this to 1 (without local) when it falls back to stale cache.
CACHE_STALE=0

get_latest_version() {
    # Use cache unless FORCE=1 or cache is stale/missing
    if [ "$FORCE" -ne 1 ] && [ -f "$CACHE_FILE" ]; then
        local now mtime cache_age
        now=$(date +%s)
        # BSD stat (macOS): stat -f %m; GNU stat (Linux): stat -c %Y.
        # date -r <file> is not portable: macOS date -r expects a numeric timestamp.
        mtime=$(stat -f %m "$CACHE_FILE" 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
        cache_age=$(( now - mtime ))
        # Guard against clock-skew: cache_age can be negative if the system clock
        # jumped backward since the cache was written. Treat negative age as stale
        # (force a fresh fetch) rather than treating it as valid forever.
        if [ "$cache_age" -ge 0 ] && [ "$cache_age" -lt "$CACHE_TTL" ]; then
            cat "$CACHE_FILE"
            return
        fi
    fi
    local api_response version
    api_response=$(curl -fsSL --max-time 10 \
        "https://api.github.com/repos/lx-wnk/Agent-Context/releases/latest" 2>/dev/null) || true
    version=$(echo "$api_response" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(d.get('tag_name',''))" 2>/dev/null) || true
    # Fix 3: wrap cache write in guards so failure degrades gracefully to no-cache
    # rather than killing the script under set -e (e.g. /tmp owned by another UID).
    # Validate version looks like semver before caching — guards against GitHub returning
    # a malformed tag_name (e.g. on API errors that still return HTTP 200).
    if [ -n "$version" ] && [[ "$version" =~ ^v?[0-9]+\.[0-9] ]]; then
        if mkdir -p "$CACHE_DIR" 2>/dev/null; then
            local tmp_cache
            if tmp_cache=$(mktemp "$CACHE_DIR/latest-version.XXXXXX" 2>/dev/null); then
                echo "$version" > "$tmp_cache" && mv "$tmp_cache" "$CACHE_FILE" || rm -f "$tmp_cache"
            fi
        fi
    elif [ -f "$CACHE_FILE" ]; then
        # API failed — fall back to stale cache rather than returning empty.
        # Warn on stderr so the user knows the version check may be outdated.
        echo "Warning: GitHub API request failed; using stale cached version." >&2
        # Fix 7: set global flag (intentional global side-effect, no 'local') so
        # the fast-path can warn the user that the "up to date" verdict may be stale.
        CACHE_STALE=1
        version=$(cat "$CACHE_FILE")
    fi
    echo "$version"
}

# Fix 1 & 2 & 7: expanded fast-path with CLAUDE.md content guard and template file guard.
# Fix 7: CACHE_STALE is declared above (before get_latest_version) and set inside it.

# Fast-path: skip Claude spawn if already up-to-date
if [ "$FORCE" -ne 1 ] && [ -f ".agent-context/.agent-context-version" ]; then
    INSTALLED_VERSION=$(tr -d '[:space:]' < ".agent-context/.agent-context-version")
    LATEST_VERSION=$(get_latest_version | tr -d '[:space:]')
    # An empty INSTALLED_VERSION (e.g. truncated or blank version file) intentionally
    # falls through this guard: the equality check is false, so the full update
    # flow runs as expected rather than silently claiming "up to date".
    if [ -n "$LATEST_VERSION" ] && [ "$INSTALLED_VERSION" = "$LATEST_VERSION" ]; then
        # Fix 1: Guard: if any CLAUDE.md has real content, the agent must run first
        # to migrate it before the bootstrap pointer can safely overwrite the file.
        _needs_agent=0
        for _loc in ".claude/CLAUDE.md" "CLAUDE.md"; do
            [ -f "$_loc" ] || continue
            if ! { grep -q "@AGENTS.md" "$_loc" && \
                   [ "$(awk 'END{print NR}' "$_loc")" -le 5 ] && \
                   [ "$(grep -cve '^[[:space:]]*$' "$_loc")" -eq \
                     "$(grep -cxe '[[:space:]]*@AGENTS\.md[[:space:]]*' "$_loc")" ]; }; then
                _needs_agent=1
                break
            fi
        done
        # Fix 2: Guard: if critical template files are missing, agent must run to restore them.
        # Version match alone is not proof of a complete installation — a user may have
        # deleted a project-owned template, or a patch release added templates without
        # changing the version number stored locally. We check all known critical
        # project-owned template files here; adding a new template to templates/ must
        # also add a corresponding entry to this list.
        if [ "$_needs_agent" -eq 0 ]; then
            for _tmpl in "AGENTS.md" \
                         ".agent-context/layer1-bootstrap.md" \
                         ".agent-context/layer2-project-core.md" \
                         ".agent-context/layer3-guidebook.md" \
                         ".agent-context/skills/index.md"; do
                [ -f "$_tmpl" ] || { _needs_agent=1; break; }
            done
        fi
        if [ "$_needs_agent" -eq 0 ]; then
            # Fix 7: warn when the "up to date" verdict is based on stale cached data.
            if [ "$CACHE_STALE" -eq 1 ]; then
                echo "Warning: version check based on stale cached data — run with --force to verify." >&2
            fi
            echo "agent-context is already up to date ($INSTALLED_VERSION). Nothing to do."
            # This call only matters when neither CLAUDE.md nor .claude/CLAUDE.md exists yet
            # (fresh install with matching version). In all other cases the bootstrap-only
            # guard above already proved nothing needs rewriting.
            update_claude_md
            exit 0
        fi
        # Fall through: CLAUDE.md has real content to migrate, or template files are missing.
    fi
fi

SESSION_ID=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || echo "unknown")
export CLAUDE_SESSION_ID="$SESSION_ID"

if ! command -v claude &>/dev/null; then
    echo "Error: claude CLI not found. Install it from https://claude.ai/code" >&2
    exit 1
fi

mkdir -p .agent-context
> "$LOG"

# Fix 6: write file-based force sentinel so setup-prompt.md can detect force mode
# deterministically, without relying on the natural-language sentinel string in the prompt.
# Cleaned up via trap below — survives agent crashes without manual intervention (one extra
# full-update on the next run, which is the safe fallback).
if [ "$FORCE" -eq 1 ]; then
    mkdir -p .agent-context
    touch .agent-context/.force
fi
trap 'rm -f .agent-context/.force' EXIT

echo "Starting agent-context setup in $(pwd)..."
if [ "$SESSION_ID" != "unknown" ]; then
  echo "Session ID: $SESSION_ID  (run 'claude --resume $SESSION_ID' to resume if needed)"
fi

AGENT_CONTEXT_SETUP=1 claude -p "$PROMPT_INSTRUCTION" \
    --allowedTools "$ALLOWED_TOOLS" \
    --output-format text \
    --dangerously-skip-permissions \
    --session-id "$SESSION_ID" \
    < /dev/null > /dev/null &
CLAUDE_PID=$!

show_progress() {
    local last=0
    local on_dot_line=0

    while kill -0 "$CLAUDE_PID" 2>/dev/null; do
        # wc -l is correct here: setup.log is always written with printf '%s\n',
        # so it always has a trailing newline. (update_claude_md uses awk because
        # CLAUDE.md may lack a trailing newline — a different case.)
        current=$(wc -l < "$LOG" 2>/dev/null || echo 0)
        if [ "$current" -gt "$last" ]; then
            [ "$on_dot_line" -eq 1 ] && printf "\n"
            new_lines=$(tail -n +"$((last + 1))" "$LOG" | head -n "$((current - last))")
            printf "%s\n" "$new_lines"
            last=$current
            on_dot_line=0
            grep -q "^\[agent-context\] Done\." "$LOG" 2>/dev/null && break
        else
            printf "."
            on_dot_line=1
            sleep 5
        fi
    done

    # Flush remaining lines written after process exits
    current=$(wc -l < "$LOG" 2>/dev/null || echo 0)
    if [ "$current" -gt "$last" ]; then
        [ "$on_dot_line" -eq 1 ] && printf "\n"
        tail -n +"$((last + 1))" "$LOG"
    elif [ "$on_dot_line" -eq 1 ]; then
        printf "\n"
    fi
}

show_progress
wait "$CLAUDE_PID"
EXIT_CODE=$?

# Fix 4: only run update_claude_md when the agent succeeded. If the agent failed
# mid-migration, CLAUDE.md content may not yet be routed to layer files — overwriting
# it here would destroy that content.
[ "$EXIT_CODE" -eq 0 ] && update_claude_md

if ! grep -q "^\[agent-context\]" "$LOG" 2>/dev/null; then
    echo "Warning: no progress was logged — Claude may have exited early or encountered an error."
    echo "Set AGENT_CONTEXT_PROMPT to a local prompt file, or check that 'claude' is authenticated."
fi

rm -f "$LOG"
exit $EXIT_CODE
