#!/usr/bin/env bash
# Shared helpers for Agent-Context hooks. Sourced by every hook script.
#
# Responsibilities:
#   - locate and load the project-owned hooks.conf (toggles + project toolchain)
#   - read the hook's stdin JSON once and expose field extraction (jq if present, else sed)
#   - gate on the master + per-hook enable flags
#
# No hard dependency on jq — extraction degrades to sed so hooks run in minimal environments.

# Resolve the hooks directory (where this lib lives) and the project root.
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$HOOK_DIR/../.." && pwd)}"
CONF_FILE="${AGENT_CONTEXT_HOOKS_CONF:-$HOOK_DIR/../hooks.conf}"

# Defaults — overridden by hooks.conf. Conservative: everything off until opted in.
HOOKS_ENABLED=0
PROTECT_SECRETS=1
PROTECTED_GLOBS=".env .env.* *.pem *.key id_rsa secrets.* *.secret"
FORMAT_ON_EDIT=1
FORMAT_CMD=""
STOP_GATE="warn"
TEST_CMD=""
SUBAGENT_SCOPE="off"
ALLOWED_SUBAGENT_PATHS=""

if [ -f "$CONF_FILE" ]; then
    # shellcheck disable=SC1090
    . "$CONF_FILE"
fi

# Read all of stdin once into RAW for field extraction.
RAW="$(cat)"

# hook_field <jq-path> <plain-key>
# Returns the first matching string value. Uses jq when available for correctness,
# otherwise a sed fallback that handles the common flat-string case.
hook_field() {
    local jq_path="$1" key="$2" val
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$RAW" | jq -r "$jq_path // empty" 2>/dev/null && return 0
    fi
    # sed fallback 1: quoted string value ("file_path":"/x").
    val="$(printf '%s' "$RAW" | sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    # sed fallback 2: bareword value (booleans/numbers, e.g. "stop_hook_active":true) —
    # without this, JSON booleans read as empty and break callers like the Stop loop guard.
    if [ -z "$val" ]; then
        val="$(printf '%s' "$RAW" | sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*\([A-Za-z0-9._-][A-Za-z0-9._-]*\).*/\1/p' | head -1)"
    fi
    printf '%s' "$val"
}

# True if the master switch is on. Hooks call this first and exit 0 (no-op) if off.
hooks_enabled() { [ "${HOOKS_ENABLED:-0}" = "1" ]; }

# Emit a valid {"decision":"block","reason":...} payload on stdout for Stop/SubagentStop.
# jq guarantees correct escaping; the fallback flattens control characters (newlines, tabs)
# to spaces and escapes backslashes/quotes so the result is always valid JSON.
emit_block_decision() {
    local reason="$1"
    if command -v jq >/dev/null 2>&1; then
        jq -nc --arg r "$reason" '{decision:"block",reason:$r}'
    else
        local flat
        flat="$(printf '%s' "$reason" | tr '\n\r\t' '   ' | sed 's/\\/\\\\/g; s/"/\\"/g')"
        printf '{"decision":"block","reason":"%s"}\n' "$flat"
    fi
}

# Glob match: returns 0 if <basename-or-path> matches any space-separated pattern in $2.
matches_any_glob() {
    local subject="$1" patterns="$2" base p
    base="$(basename "$subject")"
    for p in $patterns; do
        # shellcheck disable=SC2254
        case "$base" in $p) return 0 ;; esac
        # shellcheck disable=SC2254
        case "$subject" in $p) return 0 ;; esac
    done
    return 1
}
