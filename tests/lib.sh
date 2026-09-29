# shellcheck shell=bash
# Sourced by tests/*.sh. mk_tmp runs inside $(...), so it can only create under a root owned by the sourcing shell.

if ! TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-context-test.XXXXXX") || [ ! -d "$TMP_ROOT" ]; then
    echo "Error: cannot create a temp root under ${TMPDIR:-/tmp}" >&2
    exit 1
fi
trap 'rm -rf "$TMP_ROOT"' EXIT

mk_tmp() { mktemp -d "$TMP_ROOT/XXXXXX"; }

SKIP=0
skip() { printf "  SKIP  %s (%s)\n" "$1" "$2"; SKIP=$((SKIP + 1)); }
