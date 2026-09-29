#!/usr/bin/env bash
set -uo pipefail

# Deterministic setup/update steps as subcommands, so the setup agent runs each as one
# allowlisted command — the headless installer denies inline multi-line shell.
#
#   bash .agent-context/bin/setup-steps.sh detect-legacy [<comma-separated extra dirs>]   # Step 4.5a
#   bash .agent-context/bin/setup-steps.sh remove-legacy <path>...                         # Step 4.5c
#   bash .agent-context/bin/setup-steps.sh ensure-gitignore                                # Step 4.6c / S5
#
# Run from the project root. Exit 2 on a usage error.

LOG=".agent-context/setup.log"

detect_legacy() {
    local extra_dirs="${1:-${AI_DIRS:-}}" dir f extra old_ifs
    for dir in .ai .cursor/rules; do [ -d "$dir" ] && echo "FOUND: $dir"; done
    for f in CLAUDE.md GEMINI.md .cursorrules .github/copilot-instructions.md; do
        [ -f "$f" ] || continue
        # A root CLAUDE.md of at most 5 lines whose non-blank lines are all the @AGENTS.md pointer is ours.
        if [ "$f" = "CLAUDE.md" ] && [ "$(awk 'END{print NR}' "$f")" -le 5 ] && grep -q "@AGENTS.md" "$f" \
            && [ "$(grep -cve '^[[:space:]]*$' "$f")" -eq "$(grep -cxe '[[:space:]]*@AGENTS\.md[[:space:]]*' "$f")" ]; then
            continue
        fi
        echo "FOUND: $f"
    done
    old_ifs="$IFS"
    IFS=','
    for extra in $extra_dirs; do
        IFS="$old_ifs"
        [ -n "$extra" ] && [ -e "$extra" ] && echo "FOUND: $extra"
        IFS=','
    done
    IFS="$old_ifs"
}

# Removes a path only when git can restore it: tracked, committed, unmodified, nothing ignored inside.
remove_legacy() {
    local removed=0 p
    [ "$#" -gt 0 ] || { echo "setup-steps: remove-legacy needs at least one path" >&2; exit 2; }
    for p in "$@"; do
        [ -e "$p" ] || continue
        if [ -n "$(git ls-files -- "$p")" ] && [ -z "$(git status --porcelain --ignored -- "$p")" ]; then
            git rm -r -q -- "$p" && removed=1 && echo "Removed $p (recoverable from git history)"
        else
            echo "[agent-context] UNRESOLVED: $p" >> "$LOG"
            echo "Kept $p (not recoverable from git history) — logged as UNRESOLVED"
        fi
    done
    if [ "$removed" -eq 1 ]; then echo "[agent-context] MIGRATION_CLEANUP: ran" >> "$LOG"; fi
}

ensure_gitignore() {
    if [ -f .gitignore ] && grep -qF "###> agent-context (transient working state) ###" .gitignore; then
        echo "gitignore block present"
        return
    fi
    # The marker must start on its own line.
    if [ -s .gitignore ] && [ "$(tail -c 1 .gitignore | wc -l)" -eq 0 ]; then
        printf '\n' >> .gitignore
    fi
    cat >> .gitignore <<'EOF'
###> agent-context (transient working state) ###
# Per-session task plan, kept locally to avoid merge conflicts across branches.
/.agent-context/memory/todo.md
###< agent-context ###
EOF
    echo "gitignore block added"
}

case "${1:-}" in
    detect-legacy) shift; detect_legacy "$@" ;;
    remove-legacy) shift; remove_legacy "$@" ;;
    ensure-gitignore) ensure_gitignore ;;
    *)
        echo "Usage: bash setup-steps.sh detect-legacy [<dirs>] | remove-legacy <path>... | ensure-gitignore" >&2
        exit 2
        ;;
esac
