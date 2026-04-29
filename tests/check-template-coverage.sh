#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATES_DIR="$REPO_ROOT/templates"
INSTALL_SH="$REPO_ROOT/install.sh"

# ---------------------------------------------------------------------------
# 1. Parse the critical list from install.sh
# ---------------------------------------------------------------------------
# The for-loop looks like:
#   for _tmpl in "AGENTS.md" \
#                ".agent-context/layer1-bootstrap.md" \
#                ...
#                ".agent-context/skills/index.md"; do
# We extract it by reading only the continuation lines (ending with \ or ";"):
# - the header line: for _tmpl in "..."  \
# - subsequent lines: spaces + "..." \ or "..."; do
# mapfile is Bash 4+ only; use a portable read-loop instead.
CRITICAL_LIST=()
while IFS= read -r line; do
  CRITICAL_LIST+=("$line")
done < <(
  awk '/for _tmpl in /{
    do {
      line = $0
      while (match(line, /"[^"]+"/) > 0) {
        token = substr(line, RSTART+1, RLENGTH-2)
        if (token !~ /[ $]/) print token
        line = substr(line, RSTART+RLENGTH)
      }
      if ($0 !~ /\\[[:space:]]*$/) break
    } while ((getline) > 0)
  }' "$INSTALL_SH"
)

if [ "${#CRITICAL_LIST[@]}" -eq 0 ]; then
  echo "FAIL: could not parse the critical template list from install.sh" >&2
  exit 1
fi

echo "Critical list parsed from install.sh (${#CRITICAL_LIST[@]} entries):"
for entry in "${CRITICAL_LIST[@]}"; do
  echo "  $entry"
done
echo

# ---------------------------------------------------------------------------
# 2. Verify every critical entry actually exists under templates/
# ---------------------------------------------------------------------------
missing_files=0
for entry in "${CRITICAL_LIST[@]}"; do
  target="$TEMPLATES_DIR/$entry"
  if [ ! -f "$target" ]; then
    echo "FAIL: critical entry '$entry' listed in install.sh has no corresponding file at templates/$entry"
    missing_files=1
  fi
done

if [ "$missing_files" -eq 1 ]; then
  exit 1
fi
echo "PASS: all critical entries exist under templates/"
echo

# ---------------------------------------------------------------------------
# 3. Scan templates/ for "core" files not covered by the critical list
# ---------------------------------------------------------------------------
# Core files are defined as:
#   - templates/AGENTS.md
#   - templates/.agent-context/layer*.md   (direct children only, not memory/)
#   - templates/.agent-context/skills/index.md
#
# decisions.json, knowledge-map.md, and memory/* are intentionally excluded.

uncovered=0

check_coverage() {
  local rel_path="$1"   # relative to templates/, e.g. "AGENTS.md"
  local found=0
  for entry in "${CRITICAL_LIST[@]}"; do
    if [ "$entry" = "$rel_path" ]; then
      found=1
      break
    fi
  done
  if [ "$found" -eq 0 ]; then
    echo "WARN: templates/$rel_path is a core file but is NOT in the critical list in install.sh"
    uncovered=1
  fi
}

# Root-level AGENTS.md
[ -f "$TEMPLATES_DIR/AGENTS.md" ] && check_coverage "AGENTS.md"

# .agent-context/layer*.md (direct children only)
# Use plain find | sort — no -print0/sort -z to stay Bash 3.2 / BSD portable.
# layer*.md filenames never contain spaces, so word-splitting is safe here.
while IFS= read -r f; do
  rel="${f#"$TEMPLATES_DIR/"}"
  check_coverage "$rel"
done < <(find "$TEMPLATES_DIR/.agent-context" -maxdepth 1 -name "layer*.md" | sort)

# .agent-context/skills/index.md
[ -f "$TEMPLATES_DIR/.agent-context/skills/index.md" ] && check_coverage ".agent-context/skills/index.md"

if [ "$uncovered" -eq 1 ]; then
  echo
  echo "FAIL: one or more core template files are not covered by the critical list in install.sh."
  echo "      Add the missing entries to the for-loop around line 168 of install.sh."
  exit 1
fi

echo "PASS: all core template files are covered by the critical list in install.sh."
