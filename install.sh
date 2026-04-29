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
    _abs_prompt=$(realpath "$AGENT_CONTEXT_PROMPT" 2>/dev/null \
        || python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$AGENT_CONTEXT_PROMPT" 2>/dev/null \
        || echo "$AGENT_CONTEXT_PROMPT")
    PROMPT_INSTRUCTION="Read $_abs_prompt and follow its instructions exactly."
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
    PROMPT_INSTRUCTION="$PROMPT_INSTRUCTION Force flag is set: skip any up-to-date version checks and perform a full update regardless of current version."
fi

# Returns 0 if the file contains only the @AGENTS.md bootstrap pointer (no real content).
# Uses awk for line count to correctly handle files without a trailing newline.
is_bootstrap_only() {
    local file="$1"
    [ -f "$file" ] || return 1
    grep -q "@AGENTS.md" "$file" && \
        [ "$(awk 'END{print NR}' "$file")" -le 5 ] && \
        [ "$(grep -cve '^[[:space:]]*$' "$file")" -eq \
          "$(grep -cxe '[[:space:]]*@AGENTS\.md[[:space:]]*' "$file")" ]
}

# Returns 0 if all critical project-owned template files are present.
# Adding a new template to templates/ requires a matching entry here.
# tests/check-template-coverage.sh auto-reads this list — no changes needed there.
check_critical_templates() {
    for _tmpl in "AGENTS.md" \
                 ".agent-context/layer1-bootstrap.md" \
                 ".agent-context/layer2-project-core.md" \
                 ".agent-context/layer3-guidebook.md" \
                 ".agent-context/skills/index.md"; do
        [ -f "$_tmpl" ] || return 1
    done
}

update_claude_md() {
    local updated=0
    for loc in ".claude/CLAUDE.md" "CLAUDE.md"; do
        [ -f "$loc" ] || continue
        if is_bootstrap_only "$loc"; then
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

# XDG_CACHE_HOME or HOME may be relative/empty on hardened/CI systems — fall back to /tmp.
_raw_cache_base="${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}"
case "$_raw_cache_base" in
    /*)
        case "$_raw_cache_base" in
            */..*) CACHE_DIR="/tmp/agent-context" ;;
            *)     CACHE_DIR="$_raw_cache_base/agent-context" ;;
        esac
        ;;
    *) CACHE_DIR="/tmp/agent-context" ;;
esac
CACHE_FILE="$CACHE_DIR/latest-version"
CACHE_TTL=3600

# Declared before get_latest_version; set inside it when falling back to stale cache.
CACHE_STALE=0

get_latest_version() {
    if [ "$FORCE" -ne 1 ] && [ -f "$CACHE_FILE" ]; then
        local now mtime cache_age
        now=$(date +%s)
        # BSD stat (macOS): stat -f %m; GNU stat (Linux): stat -c %Y.
        mtime=$(stat -f %m "$CACHE_FILE" 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
        cache_age=$(( now - mtime ))
        # Negative cache_age means the system clock jumped backward — treat as stale.
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
    if [ -n "$version" ] && [[ "$version" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        if mkdir -p "$CACHE_DIR" 2>/dev/null; then
            local tmp_cache
            if tmp_cache=$(mktemp "$CACHE_DIR/latest-version.XXXXXX" 2>/dev/null); then
                echo "$version" > "$tmp_cache" && mv "$tmp_cache" "$CACHE_FILE" || rm -f "$tmp_cache"
            fi
        fi
    elif [ -f "$CACHE_FILE" ]; then
        echo "Warning: GitHub API request failed; using stale cached version." >&2
        CACHE_STALE=1
        version=$(cat "$CACHE_FILE")
    fi
    echo "$version"
}

# Fast-path: skip Claude spawn if already up-to-date.
# Guards: version match alone is not proof of a complete installation — a CLAUDE.md with
# real content still needs migration, and missing templates need restoration.
if [ "$FORCE" -ne 1 ] && [ -f ".agent-context/.agent-context-version" ]; then
    INSTALLED_VERSION=$(tr -d '[:space:]' < ".agent-context/.agent-context-version")
    LATEST_VERSION=$(get_latest_version | tr -d '[:space:]')
    # Strip optional leading 'v' so "v0.5.3" and "0.5.3" compare as equal.
    # An empty INSTALLED_VERSION (e.g. blank version file) intentionally falls through:
    # the equality check is false, so the full update flow runs.
    if [ -n "$LATEST_VERSION" ] && [ "${INSTALLED_VERSION#v}" = "${LATEST_VERSION#v}" ]; then
        _needs_agent=0
        for _loc in ".claude/CLAUDE.md" "CLAUDE.md"; do
            if [ -f "$_loc" ] && ! is_bootstrap_only "$_loc"; then
                _needs_agent=1
                break
            fi
        done
        if [ "$_needs_agent" -eq 0 ] && ! check_critical_templates; then
            _needs_agent=1
        fi
        if [ "$_needs_agent" -eq 0 ]; then
            if [ "$CACHE_STALE" -eq 1 ]; then
                echo "Warning: version check based on stale cached data — run with --force to verify." >&2
            fi
            echo "agent-context is already up to date ($INSTALLED_VERSION). Nothing to do."
            # Creates .claude/CLAUDE.md only when neither location exists yet (fresh install).
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

# Only run when agent succeeded — a failed mid-migration must not overwrite CLAUDE.md content
# that hasn't yet been routed to layer files.
[ "$EXIT_CODE" -eq 0 ] && update_claude_md

if ! grep -q "^\[agent-context\]" "$LOG" 2>/dev/null; then
    echo "Warning: no progress was logged — Claude may have exited early or encountered an error."
    echo "Set AGENT_CONTEXT_PROMPT to a local prompt file, or check that 'claude' is authenticated."
fi

rm -f "$LOG"
exit $EXIT_CODE
