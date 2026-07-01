#!/usr/bin/env bash
# PreToolUse(Write|Edit) — block writes to secret/credential files.
# Exit 2 blocks the tool call; stderr is shown to the agent as the reason.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib.sh"

hooks_enabled || exit 0
[ "${PROTECT_SECRETS:-1}" = "1" ] || exit 0

file="$(hook_field '.tool_input.file_path' 'file_path')"
[ -n "$file" ] || exit 0

if matches_any_glob "$file" "$PROTECTED_GLOBS"; then
    echo "Blocked by agent-context: '$file' matches a protected secret pattern (PROTECTED_GLOBS in hooks.conf)." >&2
    echo "If you need a value from it, ask the user for the specific variable instead of reading or writing the file." >&2
    exit 2
fi
exit 0
