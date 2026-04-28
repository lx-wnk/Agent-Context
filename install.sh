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

update_claude_md() {
    local updated=0
    for loc in ".claude/CLAUDE.md" "CLAUDE.md"; do
        [ -f "$loc" ] || continue
        if grep -q "@AGENTS.md" "$loc" && [ "$(wc -l < "$loc")" -le 5 ]; then
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

CACHE_FILE="/tmp/.agent-context-latest-version"
CACHE_TTL=3600

get_latest_version() {
    # Use cache unless FORCE=1 or cache is stale/missing
    if [ "${FORCE:-0}" -ne 1 ] && [ -f "$CACHE_FILE" ]; then
        local cache_age
        cache_age=$(( $(date +%s) - $(date -r "$CACHE_FILE" +%s 2>/dev/null || echo 0) ))
        if [ "$cache_age" -lt "$CACHE_TTL" ]; then
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
        echo "$version" > "$CACHE_FILE"
    fi
    echo "$version"
}

# Fast-path: skip Claude spawn if already up-to-date
if [ "${FORCE:-0}" -ne 1 ] && [ -f ".agent-context/.agent-context-version" ]; then
    INSTALLED_VERSION=$(cat ".agent-context/.agent-context-version" | tr -d '[:space:]')
    LATEST_VERSION=$(get_latest_version)
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
