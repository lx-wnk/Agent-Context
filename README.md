# Agent Context Architecture

A project-based setup and memory-handling system for Claude Code. Optimized for structuring project knowledge so that
Claude always has the right context at the right time — without bloating the context window.

Instead of dumping everything into a single `CLAUDE.md`, Agent Context provides a layered architecture with progressive
disclosure: a minimal baseline (~60-80 lines) is always loaded, while detailed reference (skills, memory files) is
pulled in on-demand based on the task at hand. Auto-updates keep shared infrastructure current across all your projects.

## The Problem

Claude Code loads project instructions into its context window every conversation. Most projects dump everything into a
single `CLAUDE.md`, resulting in:

- **Context bloat:** 500-1000+ lines loaded for every task, even a one-line CSS fix
- **Duplication:** Same information in `CLAUDE.md`, `README.md`, `.claude/rules/`, and memory files
- **Noise:** Entity schemas, route tables, and file trees that Claude can discover by reading the code
- **No structure:** Flat files with no way to load context progressively based on the task
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

Auto-updates are built in: on every session start, a SessionStart agent hook checks for new releases via the GitHub
Releases API and updates shared files automatically. Project-owned files are never overwritten.

## Architecture

```
agent-context Repo (source)              Project (committed files)
─────────────────────────────            ──────────────────────────
context/agent-startup.md          →──    .agent-context/agent-startup.md (overwritable)
context/layer0-agent-workflow.md  →──    .agent-context/layer0-agent-workflow.md (overwritable)
context/base-principles.md        →──    .agent-context/base-principles.md (overwritable)
.prompts/update-prompt.md          →──    .agent-context/update-prompt.md (overwritable)
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

## Why `.agent-context/` instead of `.claude/rules/`?

|                     | `.claude/rules/`            | `.agent-context/`              |
| ------------------- | --------------------------- | ------------------------------ |
| **Loading**         | Always loaded (all files)   | Layer-based, on-demand         |
| **Path globs**      | Yes (Claude Code native)    | No (agent reads guidebook)     |
| **Discoverability** | Hidden directory convention | Explicit, self-documenting     |

The guidebook pattern (layer 3) replaces path-based auto-loading with task-based routing. `.claude/CLAUDE.md` serves as
a minimal bootstrap pointer to `AGENTS.md`.

## How It Works

### Initial Setup (one-time)

Paste [`.prompts/SETUP-PROMPT.md`](.prompts/SETUP-PROMPT.md) into Claude Code. It:

1. Downloads the latest release from the GitHub Releases API
2. Copies **shared files** from `context/` → `.agent-context/` (overwritable)
3. Creates **project-owned files** from `templates/` → `AGENTS.md`, layers 1-3, memory stubs (never overwritten)
4. Writes the release version to `.agent-context/.agent-context-version`
5. Discovers your tech stack and fills in the TODO placeholders

### Every Session (automatic)

A **SessionStart agent hook** in `.claude/settings.json` spawns a subagent that reads
`.agent-context/update-prompt.md` and performs the update:

1. Reads `.agent-context/.agent-context-version` (local) and fetches the latest release tag from the GitHub API (remote)
2. **If versions differ:** downloads the tarball, overwrites shared files (including the update prompt itself), writes
   the new version
3. **If versions match or API fails:** continues silently — never blocks the session
4. Syncs plugins from `plugins.json` into `.claude/settings.json`

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

Run this in your project directory:

```bash
claude -p "Fetch https://raw.githubusercontent.com/lx-wnk/Agent-Context/main/.prompts/SETUP-PROMPT.md and follow its instructions exactly."
```

Or paste the contents of [`.prompts/SETUP-PROMPT.md`](.prompts/SETUP-PROMPT.md) manually into a Claude Code session.

Claude analyzes existing documentation, applies quality filters, discovers your tech stack, creates the architecture,
and sets up the auto-update hook. Restart your session afterwards — the new configuration takes effect on the next
start.

### What Gets Created

```
your-project/
├── AGENTS.md                              ← Entry point
├── .claude/CLAUDE.md                      ← Bootstrap pointer → @AGENTS.md
├── .claude/settings.json                  ← SessionStart agent hook (merged, not overwritten)
└── .agent-context/
    ├── agent-startup.md                   ← Startup info (shared)
    ├── layer0-agent-workflow.md            ← Universal agent workflow (shared)
    ├── base-principles.md                 ← Dev principles (shared)
    ├── update-prompt.md                   ← Auto-update agent instructions (shared)
    ├── layer1-bootstrap.md                ← Project identity, Docker, domains
    ├── layer2-project-core.md             ← Dev principles + critical rules
    ├── layer3-guidebook.md                ← Task routing, skills, memory
    ├── .agent-context-version              ← Installed version (written by hook)
    ├── plugins.json                       ← Plugin configuration (shared)
    ├── skills/                            ← Skills (on-demand reference)
    └── memory/
        ├── decisions.md                   ← Architectural decisions
        ├── lessons.md                     ← Hard-won lessons
        └── todo.md                        ← Current task plan
```

## Repository Structure

```
agent-context/
├── context/           # Shared context files (copied to .agent-context/)
├── templates/         # Project setup templates (copied once, never overwritten)
├── plugins.json       # Base plugin set for Claude Code
├── example.md         # Annotated example (Shopware 6 project)
├── .prompts/          # Prompt files (setup + auto-update agent instructions)
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
the next session start, the agent hook reads `update-prompt.md`, checks the Releases API, detects the version
difference, downloads the release, and overwrites the 🔒 shared files. Project-owned files are never touched. If the API
is unreachable, the agent continues silently.

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
