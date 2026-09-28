#!/usr/bin/env bash
# SubagentStop — scope check. Verifies a subagent only wrote files within allowed paths.
#
# Parses the subagent's own transcript (agent_transcript_path; transcript_path is the main
# session) for every file_path it wrote (Write/Edit/MultiEdit) and matches each, relative to
# the project root, against ALLOWED_SUBAGENT_PATHS globs (hooks.conf). A write outside the
# project is always a violation. If the allow-list is empty the check is a no-op.
#
# SUBAGENT_SCOPE modes: off | warn (systemMessage) | block ({"decision":"block"} payload).
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib.sh"

hooks_enabled || exit 0
case "${SUBAGENT_SCOPE:-off}" in
    off) exit 0 ;;
esac
[ -n "${ALLOWED_SUBAGENT_PATHS:-}" ] || exit 0
[ "$(hook_field '.stop_hook_active' 'stop_hook_active')" = "true" ] && exit 0

transcript="$(hook_field '.agent_transcript_path' 'agent_transcript_path')"
transcript="${transcript/#\~/$HOME}"
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0

# Collect only the paths the subagent WROTE — Write/Edit/MultiEdit tool calls. A plain
# file_path scan would also catch Read/Grep events and raise false scope violations.
# jq walks the tool_use blocks correctly; the grep fallback narrows to lines that name a
# write tool before pulling file_path.
if command -v jq >/dev/null 2>&1; then
    touched="$(jq -r 'recurse | objects
        | select(.type? == "tool_use" and ((.name?) == "Write" or (.name?) == "Edit" or (.name?) == "MultiEdit"))
        | .input.file_path // empty' "$transcript" 2>/dev/null | sort -u)"
else
    touched="$(grep -E '"name"[[:space:]]*:[[:space:]]*"(Write|Edit|MultiEdit)"' "$transcript" 2>/dev/null \
        | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | sort -u)"
fi
[ -n "$touched" ] || exit 0

violations=""
while IFS= read -r f; do
    [ -n "$f" ] || continue
    if ! rel="$(project_relpath "$f")" || ! matches_any_glob "$rel" "$ALLOWED_SUBAGENT_PATHS"; then
        violations="${violations}  - $f"$'\n'
    fi
done <<EOF
$touched
EOF

[ -n "$violations" ] || exit 0

if [ "${SUBAGENT_SCOPE:-off}" = "block" ]; then
    emit_block_decision "Subagent wrote outside ALLOWED_SUBAGENT_PATHS: ${violations} Allowed: ${ALLOWED_SUBAGENT_PATHS}"
    exit 0
fi

emit_system_message "agent-context scope check: subagent wrote outside allowed paths (SUBAGENT_SCOPE=warn):"$'\n'"$violations"
exit 0
