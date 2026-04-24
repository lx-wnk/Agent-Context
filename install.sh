#!/usr/bin/env bash
set -euo pipefail

PROMPT_URL="https://raw.githubusercontent.com/lx-wnk/Agent-Context/main/.prompts/setup-prompt.md"
ALLOWED_TOOLS="Edit,Write,Read,Bash,Glob,Grep,WebFetch,WebSearch,Agent"
LOG=".agent-context/setup.log"

# --local <path>: use a local prompt file instead of the remote URL (for testing)
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

if ! command -v claude &>/dev/null; then
    echo "Error: claude CLI not found. Install it from https://claude.ai/code" >&2
    exit 1
fi

mkdir -p .agent-context
> "$LOG"

echo "Starting agent-context setup in $(pwd)..."

AGENT_CONTEXT_SETUP=1 claude -p "$PROMPT_INSTRUCTION" \
    --allowedTools "$ALLOWED_TOOLS" \
    --output-format text \
    --dangerously-skip-permissions \
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
