#!/usr/bin/env bash
# SubagentStop — scope check. Verifies a subagent only wrote files within allowed paths.
#
# Parses the subagent transcript for every file_path it wrote (Write/Edit/MultiEdit) and
# compares each against ALLOWED_SUBAGENT_PATHS globs (hooks.conf). If the allow-list is empty
# the check is a no-op (nothing to enforce).
#
# SUBAGENT_SCOPE modes: off | warn (stderr, default) | block ({"decision":"block"} payload).
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib.sh"

hooks_enabled || exit 0
case "${SUBAGENT_SCOPE:-off}" in
    off) exit 0 ;;
esac
[ -n "${ALLOWED_SUBAGENT_PATHS:-}" ] || exit 0

transcript="$(hook_field '.transcript_path' 'transcript_path')"
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0

# Collect every file_path the subagent touched. grep is robust enough for the JSONL transcript;
# we only need the set of paths, not full JSON fidelity.
touched="$(grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' "$transcript" 2>/dev/null \
    | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | sort -u)"
[ -n "$touched" ] || exit 0

violations=""
while IFS= read -r f; do
    [ -n "$f" ] || continue
    if ! matches_any_glob "$f" "$ALLOWED_SUBAGENT_PATHS"; then
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

echo "agent-context scope check: subagent wrote outside allowed paths (SUBAGENT_SCOPE=warn):" >&2
printf '%s' "$violations" >&2
exit 0
