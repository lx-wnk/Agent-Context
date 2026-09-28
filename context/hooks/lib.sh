#!/usr/bin/env bash
# Shared helpers for Agent-Context hooks. Sourced by every hook script.
#
# Responsibilities:
#   - load the committed hooks.conf (toggles) and the user-local hooks.local.conf (opt-in + commands)
#   - read the hook's stdin JSON once and expose field extraction (jq if present, else sed)
#   - gate on the master + per-hook enable flags
#
# No hard dependency on jq — extraction degrades to sed so hooks run in minimal environments.

# Resolve the hooks directory (where this lib lives) and the project root.
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$HOOK_DIR/../.." && pwd)}"
CONF_FILE="${AGENT_CONTEXT_HOOKS_CONF:-$HOOK_DIR/../hooks.conf}"
LOCAL_CONF_FILE="${AGENT_CONTEXT_HOOKS_LOCAL_CONF:-$HOOK_DIR/../hooks.local.conf}"

# Defaults — overridden by hooks.conf / hooks.local.conf. Conservative: everything off until opted in.
HOOKS_ENABLED=0
PROTECT_SECRETS=1
PROTECTED_GLOBS=".env .env.* *.pem *.key id_rsa secrets.* *.secret"
FORMAT_ON_EDIT=1
FORMAT_CMD=""
STOP_GATE="warn"
TEST_CMD=""
SUBAGENT_SCOPE="off"
ALLOWED_SUBAGENT_PATHS=""

# Both confs are parsed, never sourced. hooks.conf is committed and can arrive via `git pull`,
# so the keys that switch hooks on or name a command to run (HOOKS_ENABLED, TEST_CMD, FORMAT_CMD)
# are read only from the gitignored, user-local hooks.local.conf — their values ARE executed.
# hooks.local.conf may override every other key as well. A missing reader leaves the defaults
# above in place (master switch off) rather than failing the hook, which would block the session.
CONF_READER="$HOOK_DIR/../bin/conf-read.sh"
if [ -r "$CONF_READER" ]; then
    # shellcheck source=../bin/conf-read.sh
    . "$CONF_READER"
    conf_load "$CONF_FILE" PROTECT_SECRETS PROTECTED_GLOBS FORMAT_ON_EDIT STOP_GATE SUBAGENT_SCOPE \
        ALLOWED_SUBAGENT_PATHS
    conf_load "$LOCAL_CONF_FILE" HOOKS_ENABLED PROTECT_SECRETS PROTECTED_GLOBS FORMAT_ON_EDIT FORMAT_CMD \
        STOP_GATE TEST_CMD SUBAGENT_SCOPE ALLOWED_SUBAGENT_PATHS
elif [ -f "$CONF_FILE" ] || [ -f "$LOCAL_CONF_FILE" ]; then
    echo "agent-context hooks: $CONF_READER is missing — hooks stay disabled. Re-run the update." >&2
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

# Terminal escape sequences and control characters (all but newline and tab) are removed, so
# test-runner colour codes neither break the no-jq JSON nor reach Claude as raw bytes.
sanitize_text() {
    printf '%s' "$1" | LC_ALL=C sed "s/$(printf '\033')\[[0-9;?]*[A-Za-z]//g" | LC_ALL=C tr -d '\000-\010\013-\037\177'
}

json_string() {
    if command -v jq >/dev/null 2>&1; then
        sanitize_text "$1" | jq -Rs .
    else
        sanitize_text "$1" | tr '\t' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g' \
            | awk 'BEGIN { printf "\"" } { printf "%s%s", (NR > 1 ? "\\n" : ""), $0 } END { printf "\"" }'
    fi
}

emit_block_decision() { printf '{"decision":"block","reason":%s}\n' "$(json_string "$1")"; }

# Stderr on exit 0 lands in the debug log only; systemMessage is what the user sees.
emit_system_message() { printf '{"systemMessage":%s}\n' "$(json_string "$1")"; }

resolve_link() {
    local p="$1" n=0 l
    while [ -L "$p" ] && [ "$n" -lt 40 ]; do
        l="$(readlink "$p")"
        case "$l" in /*) p="$l" ;; *) p="$(dirname "$p")/$l" ;; esac
        n=$((n + 1))
    done
    printf '%s' "$p"
}

# Prints <path> relative to PROJECT_DIR; returns 1 when it lies outside. A missing parent
# directory (deleted since the write) falls back to a textual prefix check.
project_relpath() {
    local path="$1" dir root rel
    case "$path" in /*) ;; *) path="$PROJECT_DIR/$path" ;; esac
    if ! { dir="$(cd "$(dirname "$path")" 2>/dev/null && pwd -P)" && root="$(cd "$PROJECT_DIR" 2>/dev/null && pwd -P)"; }; then
        case "$path" in */../* | */./*) return 1 ;; esac
        dir="$(dirname "$path")"
        root="${PROJECT_DIR%/}"
    fi
    case "$dir/" in "$root"/*) ;; *) return 1 ;; esac
    rel="${dir#"$root"}/$(basename "$path")"
    printf '%s' "${rel#/}"
}

# Glob match: returns 0 if <basename-or-path> matches any space-separated pattern in $2.
# `read -a` splits without pathname expansion: an unquoted `for p in $patterns` would expand
# `*.pem` against the cwd (the project root), so an existing a.pem would stop protecting b.pem.
# Case-insensitive, because .ENV is the same file as .env on APFS and NTFS.
matches_any_glob() {
    local subject="$1" base p matched=1 reset_case=0
    local -a pats
    base="$(basename "$subject")"
    read -r -a pats <<< "$2"
    shopt -q nocasematch || { shopt -s nocasematch; reset_case=1; }
    for p in ${pats[@]+"${pats[@]}"}; do
        # shellcheck disable=SC2254
        case "$base" in $p) matched=0; break ;; esac
        # shellcheck disable=SC2254
        case "$subject" in $p) matched=0; break ;; esac
    done
    [ "$reset_case" -eq 1 ] && shopt -u nocasematch
    return "$matched"
}
