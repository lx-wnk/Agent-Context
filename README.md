# Agent Context Architecture

A reusable prompt for setting up layered, agent-agnostic context architecture in any software project. Reduces baseline
context by 5-7x while keeping full reference accessible on-demand.

## The Problem

AI coding agents (Claude Code, Cursor, Gemini CLI, Copilot, Codex) load project instructions into their context window
every conversation. Most projects dump everything into a single file (`CLAUDE.md`, `.cursorrules`), resulting in:

- **Context bloat:** 500-1000+ lines loaded for every task, even a one-line CSS fix
- **Duplication:** Same information in `CLAUDE.md`, `README.md`, `.claude/rules/`, and memory files
- **Noise:** Entity schemas, route tables, and file trees that agents can discover by reading the code
- **Vendor lock-in:** Tool-specific files that don't work across agents

## The Solution

A layered architecture with progressive disclosure:

```
CLAUDE.md                          (3 lines — bootstrap pointer)
AGENTS.md                          (~35 lines — identity, quick rules)
.agent-context/
  layer0-agent-workflow.md         (~25 lines — universal agent patterns)
  layer1-bootstrap.md              (~20 lines — tech stack, project identity)
  layer2-project-core.md           (~35 lines — dev principles, conventions)
  layer3-guidebook.md              (~30 lines — task → file routing table)
  memory/                          (stubs, ~10 lines each)
  skills/                          (full reference, loaded on-demand)
```

**Baseline:** ~60-80 lines (AGENTS.md + layers 0-2). Full reference: loaded only when trigger keywords match.

Auto-updates are built in: on every session start, the agent checks for new releases via the GitHub Releases API and
updates shared files automatically. Project-owned files are never overwritten.

## Architecture

```
agent-context Repo (source)              Project (committed files)
─────────────────────────────            ──────────────────────────
context/agent-startup.md          →──    .agent-context/agent-startup.md (overwritable)
context/layer0-agent-workflow.md  →──    .agent-context/layer0-agent-workflow.md (overwritable)
context/base-principles.md        →──    .agent-context/base-principles.md (overwritable)
plugins.json                      →──    .agent-context/plugins.json (overwritable)
templates/*                       →──    AGENTS.md, layer1-3, memory/ (project-owned)
```

**Overwritable** files are updated on every release. **Project-owned** files are created once and never overwritten. The
installed version is tracked in `.agent-context/.agent-context-version` — written by the agent from the release tag.

### Layer System

| Layer | Location                                  | Content                           | Ownership        |
| ----- | ----------------------------------------- | --------------------------------- | ---------------- |
| 0     | `.agent-context/layer0-agent-workflow.md` | Universal agent workflow          | Shared (updated) |
| Base  | `.agent-context/base-principles.md`       | Dev principles                    | Shared (updated) |
| 1     | `.agent-context/layer1-bootstrap.md`      | Project identity, Docker, domains | Project          |
| 2     | `.agent-context/layer2-project-core.md`   | Dev rules + `@` ref to base       | Project          |
| 3     | `.agent-context/layer3-guidebook.md`      | Task routing, skills, memory      | Project          |

## Why `.agent-context/` instead of `.claude/`?

|                     | `.claude/rules/`                    | `.agent-context/`                    |
| ------------------- | ----------------------------------- | ------------------------------------ |
| **Works with**      | Claude Code only                    | Any AI agent                         |
| **Loading**         | Always loaded (all files)           | Layer-based, on-demand               |
| **Path globs**      | Yes (Claude Code native)            | No (agent reads guidebook)           |
| **Discoverability** | Hidden directory convention         | Explicit, self-documenting           |
| **Skills**          | `.claude/skills/` (Claude-specific) | `.agent-context/skills/` (universal) |

`.claude/rules/` is a Claude Code feature — other agents ignore it. `.agent-context/` is a plain directory any agent can
read. The guidebook pattern (layer 3) replaces path-based auto-loading with task-based routing that works regardless of
the agent.

**Compatibility:** You can keep a minimal `CLAUDE.md` as a bootstrap pointer to `AGENTS.md`. Similarly for
`.cursorrules` or other tool-specific files.

## How It Works

### Initial Setup (one-time)

You paste [`PROMPT.md`](PROMPT.md) into any AI coding agent. The agent:

1. Downloads the latest release from the GitHub Releases API
2. Copies **shared files** from `context/` → `.agent-context/` (overwritable)
3. Creates **project-owned files** from `templates/` → `AGENTS.md`, layers 1-3, memory stubs (never overwritten)
4. Writes the release version to `.agent-context/.agent-context-version`
5. Discovers your tech stack and fills in the TODO placeholders

### Every Session (automatic, Claude Code)

A **SessionStart hook** in `.claude/settings.json` runs `.agent-context/scripts/agent-context-update.sh` before the
agent starts. The script:

1. Reads `.agent-context/.agent-context-version` (local) and fetches the latest release tag from the GitHub API (remote)
2. **If versions differ:** downloads the tarball, overwrites shared files (including the script itself), writes the new
   version
3. **If versions match or API fails:** continues silently — never blocks the session
4. Syncs plugins from `plugins.json` into `.claude/settings.json`

This is **deterministic** — no LLM interpretation involved, runs in ~1-2 seconds, costs zero tokens.

For non-Claude-Code agents, `agent-startup.md` contains fallback instructions for manual version checking.

### What the agent sees at runtime

```
AGENTS.md                               ← Agent reads this first
  @.agent-context/agent-startup.md      ← Update info (hook already ran)
  @.agent-context/layer0-agent-workflow  ← Memory routing, skill lookup
  @.agent-context/layer1-bootstrap      ← Tech stack, Docker, domains
  @.agent-context/layer2-project-core   ← Your conventions + critical rules
  @.agent-context/layer3-guidebook      ← Task routing → memory/skills on-demand
```

Total baseline: ~60-80 lines. Heavy reference (skills, memory) is loaded only when the task matches.

## Installation

### Quick Start

1. Copy the contents of [`PROMPT.md`](PROMPT.md) as a prompt into any AI coding agent
2. The agent analyzes existing documentation, applies quality filters, discovers your tech stack, and creates the
   architecture
3. Restart your agent session — the new configuration takes effect on the next start

The prompt works with Claude Code, Cursor, Gemini CLI, GitHub Copilot, Codex, and any other agent that can read and
write files.

### What Gets Created

```
your-project/
├── AGENTS.md                              ← Agent entry point
├── .claude/CLAUDE.md                      ← Claude Code integration
├── .claude/settings.json                  ← SessionStart hook (merged, not overwritten)
├── .github/copilot-instructions.md        ← GitHub Copilot integration
├── .junie/guidelines.md                   ← Junie integration
└── .agent-context/
    ├── agent-startup.md                   ← Startup check, auto-update (shared)
    ├── layer0-agent-workflow.md            ← Universal agent workflow (shared)
    ├── base-principles.md                 ← Dev principles (shared)
    ├── layer1-bootstrap.md                ← Project identity, Docker, domains
    ├── layer2-project-core.md             ← Dev principles + critical rules
    ├── layer3-guidebook.md                ← Task routing, skills, memory
    ├── .agent-context-version              ← Installed version (written by hook)
    ├── plugins.json                       ← Plugin configuration
    ├── scripts/agent-context-update.sh           ← Auto-update hook script (shared)
    ├── skills/                            ← Skills (on-demand reference)
    └── memory/
        ├── decisions.md                   ← Architectural decisions
        ├── lessons.md                     ← Hard-won lessons
        └── todo.md                        ← Current task plan
```

## Repository Structure

```
agent-context/
├── context/           # Shared agent context (copied to .agent-context/)
├── scripts/           # Hook scripts (copied to .agent-context/scripts/)
├── templates/         # Project setup templates (copied once, never overwritten)
├── plugins.json       # Base plugin set for Claude Code
├── example.md         # Annotated example (Shopware 6 project)
├── PROMPT.md          # Setup prompt (paste into any agent)
└── README.md
```

## Example

See [`example.md`](example.md) for a complete annotated walkthrough of a Shopware 6 project. Each file is described in
prose — shared files link back to `context/`, project-owned files explain what they contain and why.

## Key Principles

### 1. "Can the agent discover this by reading the code?"

Based on the [ETH Zurich study (2026)](https://arxiv.org/abs/2602.11988): auto-generated context files reduce agent
performance by ~3%. Only include information that is **not discoverable** from source code.

**Keep:** Gotchas, non-linter conventions, architecture decisions, external system references, CI workflows. **Remove:**
Directory trees, entity fields, route tables, service registrations, dependency lists.

### 2. Narrowest fitting scope

Route information to the most specific level possible:

| Scope                       | Target                   |
| --------------------------- | ------------------------ |
| General philosophy          | `layer2-project-core.md` |
| Domain convention           | `memory/<domain>.md`     |
| Heavy reference (>30 lines) | `skills/<reference>.md`  |
| Gotcha / lesson             | `memory/lessons.md`      |

A PHP convention loaded during a CSS fix is wasted context.

### 3. Stubs + Skills pattern

Memory files are lightweight stubs (~10 lines) with quick facts. Full reference lives in skills, loaded only when
trigger keywords match. This achieves near-zero baseline cost for heavy documentation.

## Updates

After creating a [GitHub Release](https://github.com/lx-wnk/Agent-Context/releases), projects update automatically: on
the next agent session, `agent-startup.md` checks the Releases API, detects the version difference, downloads the
release, and overwrites the 🔒 shared files. Project-owned files are never touched. If the API is unreachable, the agent
continues silently.

## Research & References

- [ETH Zurich: Evaluating AGENTS.md (arxiv 2602.11988)](https://arxiv.org/abs/2602.11988) — Empirical evaluation of
  context files across coding agents
- [Addy Osmani: Stop Using /init for AGENTS.md](https://addyosmani.com/blog/agents-md/) — The "discoverable?" filter
- [Context Engineering for AI Agents — Anthropic](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- [Context Engineering for Coding Agents — Martin Fowler](https://martinfowler.com/articles/exploring-gen-ai/context-engineering-coding-agents.html)
- [Want better AI outputs? Try context engineering — GitHub Blog](https://github.blog/ai-and-ml/generative-ai/want-better-ai-outputs-try-context-engineering/)
- [AGENTS.md specification](https://agents.md/) — Open standard for agent instructions
- [Claude Code: Best Practices](https://code.claude.com/docs/en/best-practices)
- [Claude Code: Skills](https://code.claude.com/docs/en/skills)

## License

MIT
