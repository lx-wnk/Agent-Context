#!/usr/bin/env bash
set -uo pipefail

# Discovery digest — a cheap, deterministic project inventory for the setup/update agent.
#
# Purpose: simplify discovery WITHOUT restricting it. This is a read-only orientation map
# the agent reads FIRST so no doc/manifest/service is missed and the LLM subagents spend
# their budget on judgement (what matters, what's non-obvious) instead of re-greping the tree.
# Subagents still free-scan beyond this digest — it is an accelerator, not a whitelist.
#
# Output: Markdown on stdout. No writes. Safe to run anytime:
#   bash .agent-context/bin/discovery-digest.sh
#
# Only considers git-tracked + untracked-but-not-ignored files (the Global Constraint set),
# and never descends into agent-managed or build dirs.

ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { echo "discovery-digest: cannot cd to $ROOT" >&2; exit 2; }

# File set: respect .gitignore. Fall back to find if not a git repo.
list_files() {
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git ls-files --cached --others --exclude-standard
    else
        find . -type f -not -path './.git/*' | sed 's|^\./||'
    fi
}

# Skip agent-managed infrastructure (.agent-context, .claude) and build/dependency dirs —
# the digest is about PROJECT knowledge, not the agent's own files.
EXCLUDE_RE='^(\.agent-context/|\.claude/|node_modules/|vendor/|bin/|obj/|\.deno/|dist/|build/|\.git/)'

ALL="$(list_files | grep -Ev "$EXCLUDE_RE" || true)"

section() { printf '\n## %s\n\n' "$1"; }

echo "# Discovery Digest"
printf '\n> Deterministic project inventory (read-only). Read this first, then scan deeper.\n'

# --- Manifests / stack signals ---
section "Manifests detected"
found_manifest=0
while IFS= read -r m; do
    [ -n "$m" ] || continue
    case "$m" in
        package.json|*/package.json) label="Node/JS" ;;
        composer.json|*/composer.json) label="PHP" ;;
        go.mod) label="Go" ;;
        Cargo.toml|*/Cargo.toml) label="Rust" ;;
        pyproject.toml|requirements.txt|*/pyproject.toml) label="Python" ;;
        pubspec.yaml) label="Dart/Flutter" ;;
        deno.json|deno.jsonc|*/deno.json|*/deno.jsonc) label="Deno" ;;
        *.csproj) label=".NET/C#" ;;
        *.sln) label=".NET solution" ;;
        *) label="manifest" ;;
    esac
    printf -- '- `%s` (%s)\n' "$m" "$label"
    found_manifest=1
done <<EOF
$(printf '%s\n' "$ALL" | grep -Ei '(^|/)(package\.json|composer\.json|go\.mod|Cargo\.toml|pyproject\.toml|requirements\.txt|pubspec\.yaml|deno\.jsonc?)$|\.csproj$|\.sln$' | sort)
EOF
[ "$found_manifest" -eq 0 ] && echo "_none detected_"

# --- Top-level code/service directories ---
section "Top-level directories"
printf '%s\n' "$ALL" | awk -F/ 'NF>1{print $1}' | sort -u | sed 's/^/- /' | head -40

# --- Docker compose services ---
section "Docker / Compose"
compose="$(printf '%s\n' "$ALL" | grep -Ei '(^|/)(docker-)?compose([.-][a-z]+)?\.ya?ml$' | head -3)"
if [ -n "$compose" ]; then
    while IFS= read -r cf; do
        [ -n "$cf" ] || continue
        printf -- '- `%s` services: ' "$cf"
        # service names = 2-space-indented keys under a `services:` block
        awk '
            /^services:/{inb=1; next}
            inb && /^[a-zA-Z]/{inb=0}
            inb && /^  [a-zA-Z0-9._-]+:/{gsub(/[: ]/,""); printf "%s ", $0}
        ' "$cf"
        printf '\n'
    done <<EOF
$compose
EOF
else
    echo "_no compose file_"
fi

# --- Task runners ---
section "Task entry points"
if [ -f Makefile ]; then
    echo "Makefile targets:"
    grep -E '^[a-zA-Z0-9][a-zA-Z0-9_-]*:' Makefile | sed -E 's/:.*//' | sort -u | sed 's/^/  - /' | head -30
fi
if printf '%s\n' "$ALL" | grep -q '^package.json$' && command -v sed >/dev/null; then
    echo "package.json scripts:"
    sed -n '/"scripts"[[:space:]]*:/,/}/p' package.json | grep -oE '"[a-zA-Z0-9:_-]+"[[:space:]]*:' | sed -E 's/"([^"]+)".*/  - \1/' | grep -v scripts | head -30
fi

# --- Documentation inventory (the high-value, often-missed set) ---
section "Documentation inventory"
echo "| Doc | Lines | First heading | Headings |"
echo "| --- | ----- | ------------- | -------- |"
printf '%s\n' "$ALL" | grep -Ei '\.(md|mdx|adoc|rst)$' | sort | while IFS= read -r d; do
    [ -f "$d" ] || continue
    lines=$(awk 'END{print NR}' "$d")
    h1=$(grep -m1 -E '^#[^#]' "$d" | sed -E 's/^#+[[:space:]]*//; s/\|/\\|/g' | cut -c1-60)
    headings=$(grep -cE '^#{1,3}[[:space:]]' "$d")
    [ -z "$h1" ] && h1="—"
    printf '| `%s` | %s | %s | %s |\n' "$d" "$lines" "$h1" "$headings"
done

# --- Heavy / structured docs (distillation candidates) ---
section "Distillation candidates (≥100 lines or many headings — extract gotchas/decisions, don't just link)"
printf '%s\n' "$ALL" | grep -Ei '\.(md|mdx|adoc|rst)$' | sort | while IFS= read -r d; do
    [ -f "$d" ] || continue
    lines=$(awk 'END{print NR}' "$d")
    headings=$(grep -cE '^#{1,3}[[:space:]]' "$d")
    if [ "$lines" -ge 100 ] || [ "$headings" -ge 8 ]; then
        printf -- '- `%s` (%s lines, %s headings)\n' "$d" "$lines" "$headings"
    fi
done

printf '\n_Generated by discovery-digest.sh — orientation only; scan deeper for non-obvious facts._\n'
