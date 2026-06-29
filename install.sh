#!/usr/bin/env bash
set -euo pipefail

FORCE=0

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

validate_version_string() {
    [[ "$1" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# XDG_CACHE_HOME or HOME may be relative/empty on hardened/CI systems — fall back to /tmp.
resolve_cache_dir() {
    local raw
    if [ "${1+set}" = "set" ]; then
        raw="$1"
    else
        raw="${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}"
    fi
    case "$raw" in
        /*)
            case "$raw" in
                */..*) echo "/tmp/agent-context" ;;
                *)     echo "$raw/agent-context" ;;
            esac
            ;;
        *) echo "/tmp/agent-context" ;;
    esac
}

CACHE_DIR=$(resolve_cache_dir)
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
    version=$(printf '%s\n' "$api_response" | awk -F'"' '/"tag_name"/{for(i=1;i<=NF;i++) if($i=="tag_name"){print $(i+2); exit}}') || true
    if validate_version_string "$version"; then
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

main() {
    if ! command -v curl &>/dev/null; then
        echo "Error: curl not found. Install curl and try again." >&2
        exit 1
    fi

    PROMPT_URL="https://raw.githubusercontent.com/lx-wnk/Agent-Context/main/.prompts/setup-prompt.md"
    ALLOWED_TOOLS="Edit,Write,Read,Bash,Glob,Grep,WebFetch,WebSearch,Agent"
    LOG=".agent-context/setup.log"

    # --local-source <path> (or env AGENT_CONTEXT_SOURCE): install every shared file and template from
    #   a local clone instead of downloading from GitHub. Implies a forced run. For local dev/testing.
    # --ai-dirs=<dirs>: comma-separated extra AI-doc dirs to treat as migratable (e.g. --ai-dirs=".cursor,.ai-custom")
    # --force: full from-scratch rediscovery — re-scan the whole codebase at SETUP depth even on an
    #   existing install, merging into existing knowledge without deleting still-valid facts
    # --discover: after install, run the discovery-map skill to build map.json + per-node notes
    PROMPT_INSTRUCTION="Fetch $PROMPT_URL and follow its instructions exactly."
    LOCAL_PROMPT=""
    if [ "${1:-}" = "--local-source" ]; then
        AGENT_CONTEXT_SOURCE="${2:-}"
    fi

    # Local-source mode: validate the clone, force a run, and read its prompt locally.
    if [ -n "${AGENT_CONTEXT_SOURCE:-}" ]; then
        if [ ! -d "$AGENT_CONTEXT_SOURCE" ]; then
            echo "Error: AGENT_CONTEXT_SOURCE directory not found: $AGENT_CONTEXT_SOURCE" >&2
            exit 1
        fi
        _abs_source=$(realpath "$AGENT_CONTEXT_SOURCE" 2>/dev/null || (cd "$AGENT_CONTEXT_SOURCE" && pwd))
        if [ ! -f "$_abs_source/.prompts/setup-prompt.md" ]; then
            echo "Error: not an Agent-Context clone (no .prompts/setup-prompt.md): $_abs_source" >&2
            exit 1
        fi
        LOCAL_PROMPT="$_abs_source/.prompts/setup-prompt.md"
        FORCE=1
    fi

    if [ -n "$LOCAL_PROMPT" ]; then
        PROMPT_INSTRUCTION="Read $LOCAL_PROMPT and follow its instructions exactly."
    fi

    # Tell the agent to source everything locally instead of downloading.
    if [ -n "${AGENT_CONTEXT_SOURCE:-}" ]; then
        PROMPT_INSTRUCTION="$PROMPT_INSTRUCTION LOCAL SOURCE MODE: do NOT download from GitHub. Install every shared file (Step 2) and every template (Step 3) by copying from the local clone at $_abs_source using the same relative paths (e.g. copy $_abs_source/context/bin/check-map-budget.sh to .agent-context/bin/check-map-budget.sh). Skip the remote version lookup and all <tag> URL building; take the target version from $_abs_source/CHANGELOG.md (latest entry)."
    fi

    AI_DIRS=""
    DISCOVER=0
    for arg in "$@"; do
        case "$arg" in
            --ai-dirs=*) AI_DIRS="${arg#--ai-dirs=}" ;;
            --force) FORCE=1 ;;
            --discover) DISCOVER=1 ;;
        esac
    done

    if [ -n "$AI_DIRS" ]; then
        PROMPT_INSTRUCTION="$PROMPT_INSTRUCTION Additional AI directories to treat as migratable (extends built-in defaults): $AI_DIRS"
    fi

    if [ "$FORCE" -eq 1 ]; then
        PROMPT_INSTRUCTION="$PROMPT_INSTRUCTION FORCE / FULL REDISCOVERY: skip all up-to-date checks and, even on an existing install, run a complete from-scratch discovery — re-scan the entire codebase and rebuild the knowledge inventory at SETUP depth, do not merely reconcile deltas. Merge into the existing memory/decisions/knowledge-map; never delete a still-valid fact (move it, don't lose it)."
    fi

    if [ "$DISCOVER" -eq 1 ]; then
        PROMPT_INSTRUCTION="$PROMPT_INSTRUCTION BUILD DISCOVERY MAP: after the install/update completes, run the discovery-map skill (.agent-context/skills/discovery-map.md) to build .agent-context/map.json and the per-node memory/<node>.md notes, then run .agent-context/bin/check-map-budget.sh to confirm the caps."
    fi

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

    SESSION_ID=$(uuidgen 2>/dev/null \
        || cat /proc/sys/kernel/random/uuid 2>/dev/null \
        || od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' | awk '{print substr($0,1,8)"-"substr($0,9,4)"-"substr($0,13,4)"-"substr($0,17,4)"-"substr($0,21,12)}' \
        || echo "unknown")
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
        echo "Use --local-source <clone> for a local install, or check that 'claude' is authenticated."
    fi

    rm -f "$LOG"
    exit $EXIT_CODE
}

if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then main "$@"; fi
