# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Agent-Context is a layered, agent-agnostic context architecture for AI coding agents. All layers (0-3) load at startup via `@`-includes in `AGENTS.md`, keeping the baseline at ~150-200 lines. Detailed reference (skills, memory files) is pulled on-demand based on task keywords.

This repository contains the framework itself: shared context files, agent configurations, templates, setup/update prompts, and documentation. It is **not** a runtime application — it's a template system installed into other projects via `.prompts/setup-prompt.md`.

## Commands

```bash
# Format all files
npm run prettier:fix

# Check formatting (CI-style)
npm run prettier
```

There are no build, test, or lint commands beyond Prettier.

## Architecture

### File Ownership Model

Two categories of files, critical to understand before editing:

- **Shared files** (`context/`, `agents/`, `plugins.json`): Overwritten on every auto-update in target projects. Changes here propagate to all installations.
- **Template files** (`templates/`): Copied once during setup, never overwritten. These become project-owned files.

### Layer System

Entry point is `AGENTS.md` → all layers load at startup via `@`-includes:

| Layer | Source                                            | Purpose                                                 |
| ----- | ------------------------------------------------- | ------------------------------------------------------- |
| 0     | `context/layer0-agent-workflow.md`                | Universal agent workflow, memory routing, skill lookup  |
| Base  | `context/base-principles.md`                      | Dev principles (only non-obvious ones)                  |
| 1     | `templates/.agent-context/layer1-bootstrap.md`    | Tech stack, Docker, domains (project-owned)             |
| 2     | `templates/.agent-context/layer2-project-core.md` | Dev rules, testing, conventions (project-owned)         |
| 3     | `templates/.agent-context/layer3-guidebook.md`    | Task routing table, skills/memory index (project-owned) |

### Setup & Update Flow

- **Setup & Update**: `.prompts/setup-prompt.md` — single prompt that auto-detects mode. SETUP: full installation with discovery. UPDATE: version check, shared file sync, agent/plugin sync.

### Agent Configurations (`agents/`)

12 pre-built agents, all prefixed `ac-`. Each is a YAML-frontmatter markdown file defining role, tools, model, and workflow. See `docs/best-practices-agent-creation.md` (German) for conventions:

- One agent = one clear responsibility
- Declare only tools actually used
- MCP tools are always conditional ("if available")
- Every workflow step needs a clear exit condition
- Affirmative instructions over prohibitions

## Key Conventions

- **Formatting**: Prettier with `printWidth: 120`, 2-space indent, `proseWrap: preserve`
- **Context minimization**: Only include information not discoverable from source code. Based on ETH Zurich (2026) research showing auto-generated context reduces agent performance ~3%.
- **Memory routing**: General convention → layer 2, domain fact → `memory/<domain>.md`, heavy reference (>30 lines) → `skills/`, gotcha → `memory/lessons.md`, decision → `decisions.json`
- **PR template**: `.github/pull_request_template.md` — Summary, Changes, Notes sections
- **Documentation language**: `docs/best-practices-agent-creation.md` is in German
