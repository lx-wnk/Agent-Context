#!/usr/bin/env bash
set -euo pipefail

# Repo-side token-budget gate: guards the always-on baseline that this framework SHIPS.
#
# Consumers fill layer1-3 with their own content (which they budget via .agent-context/budget.conf);
# this check covers only the files the framework controls — the shared always-on files plus the
# template scaffolding — so a release can never silently bloat what every install is forced to load.
#
# Reuses the same counting engine consumers get (context/bin/check-token-budget.sh) — single
# source of truth for how an "effective instruction line" is defined.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="$REPO_ROOT/context/bin/check-token-budget.sh"

# Effective-line ceiling for the always-on closure the framework ships.
# Target from the project brief: always-on < ~150–200 effective instructions.
# Set to 160 to lock in the progressive-disclosure win (baseline ~141) with headroom —
# a regression that re-bloats a shared layer past this turns CI red. Override via BUDGET_MAX.
MAX="${BUDGET_MAX:-160}"

# Always-on closure mapped to source-of-truth paths in this repo.
# Mirror of the @-include closure rooted at templates/AGENTS.md (see README "What the agent sees").
FILES=(
    "$REPO_ROOT/context/agent-startup.md"
    "$REPO_ROOT/context/layer0-agent-workflow.md"
    "$REPO_ROOT/context/base-principles.md"
    "$REPO_ROOT/templates/AGENTS.md"
    "$REPO_ROOT/templates/.agent-context/layer1-bootstrap.md"
    "$REPO_ROOT/templates/.agent-context/layer2-project-core.md"
    "$REPO_ROOT/templates/.agent-context/layer3-guidebook.md"
    "$REPO_ROOT/templates/.agent-context/knowledge-map.md"
    "$REPO_ROOT/templates/.agent-context/skills/index.md"
    "$REPO_ROOT/templates/.claude/CLAUDE.md"
)

exec bash "$ENGINE" --max "$MAX" "${FILES[@]}"
