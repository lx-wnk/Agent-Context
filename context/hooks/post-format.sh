#!/usr/bin/env bash
# PostToolUse(Write|Edit) — auto-format the file that was just written.
# Non-blocking: formatting failures are reported to the transcript but never fail the run.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib.sh"

hooks_enabled || exit 0
[ "${FORMAT_ON_EDIT:-1}" = "1" ] || exit 0
[ -n "${FORMAT_CMD:-}" ] || exit 0

file="$(hook_field '.tool_input.file_path' 'file_path')"
[ -n "$file" ] || exit 0
[ -f "$file" ] || exit 0

# FORMAT_CMD receives the file path as an argument. {} is substituted if present,
# otherwise the path is appended — supports both "prettier --write {}" and "prettier --write".
if printf '%s' "$FORMAT_CMD" | grep -q '{}'; then
    cmd="${FORMAT_CMD//\{\}/$file}"
    eval "$cmd" >/dev/null 2>&1 || echo "agent-context: format command failed on $file (non-blocking)." >&2
else
    # shellcheck disable=SC2086
    $FORMAT_CMD "$file" >/dev/null 2>&1 || echo "agent-context: format command failed on $file (non-blocking)." >&2
fi
exit 0
