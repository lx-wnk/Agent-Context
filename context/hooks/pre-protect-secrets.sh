#!/usr/bin/env bash
# PreToolUse(Write|Edit|MultiEdit) — block writes to secret/credential files. Reads are not covered.
# Exit 2 blocks the tool call; stderr is shown to the agent as the reason.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib.sh"

hooks_enabled || exit 0
[ "${PROTECT_SECRETS:-1}" = "1" ] || exit 0

file="$(hook_field '.tool_input.file_path' 'file_path')"
[ -n "$file" ] || exit 0

is_protected() {
    case "$(basename "$1")" in *.example | *.dist | *.sample) return 1 ;; esac
    matches_any_glob "$1" "$PROTECTED_GLOBS"
}

if is_protected "$file" || is_protected "$(resolve_link "$file")"; then
    echo "Blocked by agent-context: '$file' matches a protected secret pattern (PROTECTED_GLOBS in hooks.conf)." >&2
    echo "This hook guards writes only. If the file must change, ask the user to make the edit." >&2
    exit 2
fi
exit 0
