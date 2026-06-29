# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Agent-Context is a layered, agent-agnostic context architecture for AI coding agents. All layers (0-3) load at startup via `@`-includes in `AGENTS.md`, keeping the always-on baseline at ~150-200 effective instruction lines (enforced by `tests/check-token-budget.sh`). Detailed reference (skills, memory files, delegation/memory-maintenance procedures) is pulled on-demand based on task keywords.

This repository contains the framework itself: shared context files, templates, setup/update prompts, and documentation. It is **not** a runtime application — it's a template system installed into other projects via `.prompts/setup-prompt.md`.

## Commands

```bash
# Format all files
npm run prettier:fix

# Check formatting (CI-style)
npm run prettier

# Run all tests
npm test
```

## Architecture

### File Ownership Model

Two categories of files, critical to understand before editing:

- **Shared files** (`context/`, incl. `context/bin/`, `context/hooks/`, `context/skills/`, and `context/commands/`): Overwritten on every auto-update in target projects. Changes here propagate to all installations. Includes the `discovery-map` skill, the `check-map-budget.sh` cap validator, and the `discover` Claude Code slash command (`context/commands/discover.md` → `.claude/commands/discover.md`).
- **Template files** (`templates/`): Copied once during setup, never overwritten. These become project-owned files (incl. `hooks.conf`, `budget.conf`).
- **Test files** (`tests/`): CI tests verifying `install.sh` behavior, template coverage, token budget, memory-prune, hooks, and an offline install smoke test (`check-install-smoke.sh`, derived from the setup-prompt download table). Not installed into target projects.

When adding a new **shared** file, wire it into `.prompts/setup-prompt.md` Step 2 (download list + parallel curl block). When adding a new **core template**, update `check_critical_templates()` in `install.sh`. Both are guarded by `tests/`.

### Layer System

Entry point is `AGENTS.md` → all layers load at startup via `@`-includes:

| Layer   | Source                                            | Purpose                                                 |
| ------- | ------------------------------------------------- | ------------------------------------------------------- |
| Startup | `context/agent-startup.md`                        | Version check, update info                              |
| 0       | `context/layer0-agent-workflow.md`                | Universal agent workflow, memory routing, skill lookup  |
| Base    | `context/base-principles.md`                      | Dev principles (only non-obvious ones)                  |
| 1       | `templates/.agent-context/layer1-bootstrap.md`    | Tech stack, Docker, domains (project-owned)             |
| 2       | `templates/.agent-context/layer2-project-core.md` | Dev rules, testing, conventions (project-owned)         |
| 3       | `templates/.agent-context/layer3-guidebook.md`    | Task routing table, skills/memory index (project-owned) |

### Setup & Update Flow

- **Setup & Update**: `.prompts/setup-prompt.md` — single prompt that auto-detects mode. SETUP: full installation with discovery. UPDATE: version check, shared file sync.

## Definition of Done

Before declaring any task complete, verify `README.md` is still accurate: installation steps, example output, repository structure, and behavior descriptions must reflect the current code. Update it if anything has drifted.

## Key Conventions

- **Formatting**: Prettier with `printWidth: 120`, 2-space indent, `proseWrap: preserve`
- **Context minimization**: Only include information not discoverable from source code. Based on ETH Zurich (2026) research showing auto-generated context reduces agent performance ~3%.
- **Memory routing**: General convention → layer 2, domain fact → `memory/<domain>.md`, heavy reference (>30 lines) → `skills/`, gotcha → `memory/lessons.md`, decision → `decisions.json`
- **Discovery map**: the `discovery-map` skill builds an on-demand `map.json` + `memory/<node>.md` notes; pulled lazily, never `@`-included; size-capped by `check-map-budget.sh` (caps in `budget.conf`). Invoke via the `/discover` slash command (Claude Code) or a natural-language trigger ("discover the project") for other agents — both run interactively, where fan-out works. The headless installer never builds the map.
- **Install flags**: `install.sh --force` = full from-scratch rediscovery (re-scan at SETUP depth, merge non-destructively); `--discover` = after the run, check for a map and hand off to interactive `/discover` if absent (does not build it headlessly); `--local-source <path>` (env `AGENT_CONTEXT_SOURCE`) = install from a local clone instead of downloading.
- **PR template**: `.github/pull_request_template.md` — Summary, Changes, Notes sections
- **Documentation language**: `docs/best-practices-agent-creation.md` is in German
