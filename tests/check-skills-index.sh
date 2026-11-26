#!/usr/bin/env bash
# Every shared skill reaches skills/index.md: the template lists it (SETUP), and the UPDATE
# skills-index sync runs outside the change-gated 5a–5d (an update never overwrites the index).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROMPT="$REPO_ROOT/.prompts/setup-prompt.md"
INDEX="$REPO_ROOT/templates/.agent-context/skills/index.md"
SYNC='### 5e.0: Skills Index Sync'

fail=0
check() {
    if [ "$1" = ok ]; then
        printf "  PASS  %s\n" "$2"
    else
        printf "  FAIL  %s\n" "$2"
        fail=1
    fi
}

skill_names() {
    local f
    for f in "$1"/*.md "$1"/*/SKILL.md; do
        [ -f "$f" ] || continue
        [ "$(basename "$f")" = index.md ] && continue
        sed -n 's/^name:[[:space:]]*//p' "$f" | head -n 1
    done
}

# Captured, never piped into grep -q: an early grep exit would SIGPIPE awk under pipefail.
section() { awk -v h="$1" '$0 == h { on = 1; next } on && /^###? / { exit } on' "$PROMPT"; }
line_of() { awk -v h="$1" '$0 == h { print NR; exit }' "$PROMPT"; }
has() { case "$1" in *"$2"*) echo ok ;; *) echo no ;; esac; }

shared=$(skill_names "$REPO_ROOT/context/skills")
[ -n "$shared" ] && r=ok || r=no
check "$r" "shared skills found under context/skills/"
for name in $shared; do
    grep -q "^| \`$name\` " "$INDEX" && r=ok || r=no
    check "$r" "template skills/index.md lists shared skill $name"
done

sync=$(section "$SYNC")
check "$(has "$sync" 'Step 5e.0: Skills index')" "setup-prompt has the 5e.0 skills index sync step with its log line"
check "$(has "$sync" 'insert one row after the last table row')" "5e.0 inserts rows inside the table"

gate=$(section '### 5.0: Change gate')
check "$(has "$gate" 'run only 5e.0 and 5e')" "change gate keeps 5e.0 when it skips 5a–5d"

d=$(section '### 5d: knowledge-map.md Update')
[ "$(has "$d" 'skills/index.md')" = no ] && r=ok || r=no
check "$r" "5d no longer owns the skills index rebuild (single owner: 5e.0)"

l2=$(line_of '## Step 2: Install Shared Files')
l5b=$(line_of '### 5b: Routing & Restructuring (additive-only)')
lsync=$(line_of "$SYNC")
l5e=$(line_of '### 5e: Token Budget Audit')
[ -n "$l2" ] && [ -n "$l5b" ] && [ -n "$lsync" ] && [ -n "$l5e" ] &&
    [ "$l2" -lt "$l5b" ] && [ "$l5b" -lt "$lsync" ] && [ "$lsync" -lt "$l5e" ] && r=ok || r=no
check "$r" "5e.0 runs after Step 2 and 5b, before the 5e budget audit"

exit "$fail"
