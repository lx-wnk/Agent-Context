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
# Build argv by word-splitting FORMAT_CMD; a {} token becomes the file path as a SINGLE
# argument (so paths with spaces survive), otherwise the path is appended. No eval — the
# raw path is never re-parsed by the shell.
read -ra _fmt_parts <<< "$FORMAT_CMD"
_argv=()
_has_placeholder=0
for _p in "${_fmt_parts[@]}"; do
    if [ "$_p" = "{}" ]; then _argv+=("$file"); _has_placeholder=1; else _argv+=("$_p"); fi
done
[ "$_has_placeholder" -eq 1 ] || _argv+=("$file")
"${_argv[@]}" >/dev/null 2>&1 || echo "agent-context: format command failed on $file (non-blocking)." >&2
exit 0
