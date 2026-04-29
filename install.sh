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
        if grep -q "@AGENTS.md" "$loc" && [ "$(wc -l < "$loc")" -le 5 ] && \
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
_raw_cache_base="${XDG_CACHE_HOME:-$HOME/.cache}"
case "$_raw_cache_base" in
    /*) CACHE_DIR="$_raw_cache_base/agent-context" ;;
    *)  CACHE_DIR="/tmp/agent-context" ;;
esac
CACHE_FILE="$CACHE_DIR/latest-version"
CACHE_TTL=3600

get_latest_version() {
    # Use cache unless FORCE=1 or cache is stale/missing
    if [ "$FORCE" -ne 1 ] && [ -f "$CACHE_FILE" ]; then
        local now mtime cache_age
        now=$(date +%s)
        mtime=$(date -r "$CACHE_FILE" +%s 2>/dev/null || echo 0)
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
    if [ -n "$version" ]; then
        mkdir -p "$CACHE_DIR"
        local tmp_cache
        tmp_cache=$(mktemp "$CACHE_DIR/latest-version.XXXXXX")
        echo "$version" > "$tmp_cache"
        mv "$tmp_cache" "$CACHE_FILE"
    elif [ -f "$CACHE_FILE" ]; then
        # API failed — fall back to stale cache rather than returning empty.
        # Warn on stderr so the user knows the version check may be outdated.
        echo "Warning: GitHub API request failed; using stale cached version." >&2
        version=$(cat "$CACHE_FILE")
    fi
    echo "$version"
}

# Fast-path: skip Claude spawn if already up-to-date
if [ "$FORCE" -ne 1 ] && [ -f ".agent-context/.agent-context-version" ]; then
    INSTALLED_VERSION=$(tr -d '[:space:]' < ".agent-context/.agent-context-version")
    LATEST_VERSION=$(get_latest_version | tr -d '[:space:]')
    # An empty INSTALLED_VERSION (e.g. truncated or blank version file) intentionally
    # falls through this guard: the equality check is false, so the full update
    # flow runs as expected rather than silently claiming "up to date".
    if [ -n "$LATEST_VERSION" ] && [ "$INSTALLED_VERSION" = "$LATEST_VERSION" ]; then
        echo "agent-context is already up to date ($INSTALLED_VERSION). Nothing to do."
        update_claude_md
        exit 0
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
update_claude_md

if ! grep -q "^\[agent-context\]" "$LOG" 2>/dev/null; then
    echo "Warning: no progress was logged — Claude may have exited early or encountered an error."
    echo "Set AGENT_CONTEXT_PROMPT to a local prompt file, or check that 'claude' is authenticated."
fi

rm -f "$LOG"
exit $EXIT_CODE
