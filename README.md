# Agent Context Architecture

A project-based setup and memory-handling system for Claude Code. Optimized for structuring project knowledge so that Claude always has the right context at the right time — without bloating the context window.

Instead of dumping everything into a single `CLAUDE.md`, Agent Context provides a layered architecture: all layers (0-3) are loaded at startup via `@`-includes in `AGENTS.md`, keeping the baseline at ~200-250 lines. Detailed reference (skills, memory files) is pulled in on-demand based on the task at hand. Auto-updates keep shared infrastructure current across all your projects.

## The Problem

Claude Code loads project instructions into its context window every conversation. Most projects dump everything into a single `CLAUDE.md`, resulting in:

- **Context bloat:** 500-1000+ lines loaded for every task, even a one-line CSS fix
- **Duplication:** Same information in `CLAUDE.md`, `README.md`, `.claude/rules/`, and memory files
- **Noise:** Entity schemas, route tables, and file trees that Claude can discover by reading the code
- **No structure:** Flat files with no way to load context progressively based on the task

## The Solution

A layered architecture where all layers load at startup via `@`-includes in `AGENTS.md`:

```
CLAUDE.md                          (3 lines — bootstrap pointer)
AGENTS.md                          (~35 lines — identity, quick rules)
.agent-context/
  layer0-agent-workflow.md         (~35 lines — universal agent patterns)
  layer1-bootstrap.md              (~25 lines — tech stack, project identity)
  layer2-project-core.md           (~25 lines — dev principles, conventions)
  layer3-guidebook.md              (~45 lines — task → file routing table)
  memory/                          (stubs, ~10 lines each)
  skills/                          (full reference, loaded on-demand)
```

**Baseline:** ~200-250 lines (AGENTS.md + all layers). Full reference (skills, memory): loaded only when trigger keywords match.

Auto-updates are built in: the agent fetches the setup prompt from remote, which auto-detects UPDATE mode, checks for new releases via the GitHub Releases API, and updates shared files. Project-owned files are never overwritten.

## Architecture

```
agent-context Repo (source)              Project / User (target)
─────────────────────────────            ──────────────────────────
context/agent-startup.md          →──    .agent-context/agent-startup.md (overwritable)
context/layer0-agent-workflow.md  →──    .agent-context/layer0-agent-workflow.md (overwritable)
context/base-principles.md        →──    .agent-context/base-principles.md (overwritable)
plugins.json                      →──    .agent-context/plugins.json (overwritable)
templates/*                       →──    AGENTS.md, layer1-3, memory/ (project-owned)
```

**Overwritable** files are updated on every release. **Project-owned** files are created once and never overwritten. The installed version is tracked in `.agent-context/.agent-context-version` — written by the agent from the release tag.

### Layer System

| Layer   | Location                                  | Content                           | Ownership        |
| ------- | ----------------------------------------- | --------------------------------- | ---------------- |
| Startup | `.agent-context/agent-startup.md`         | Version check, update info        | Shared (updated) |
| 0       | `.agent-context/layer0-agent-workflow.md` | Universal agent workflow          | Shared (updated) |
| Base    | `.agent-context/base-principles.md`       | Dev principles                    | Shared (updated) |
| 1       | `.agent-context/layer1-bootstrap.md`      | Project identity, Docker, domains | Project          |
| 2       | `.agent-context/layer2-project-core.md`   | Dev rules + `@` ref to base       | Project          |
| 3       | `.agent-context/layer3-guidebook.md`      | Task routing, skills, memory      | Project          |

## Why `.agent-context/` instead of `.claude/rules/`?

|                     | `.claude/rules/`            | `.agent-context/`                   |
| ------------------- | --------------------------- | ----------------------------------- |
| **Loading**         | Always loaded (all files)   | Layers at startup, skills on-demand |
| **Path globs**      | Yes (Claude Code native)    | No (agent reads guidebook)          |
| **Discoverability** | Hidden directory convention | Explicit, self-documenting          |

The guidebook pattern (layer 3) replaces path-based auto-loading with task-based routing. `.claude/CLAUDE.md` serves as a minimal bootstrap pointer to `AGENTS.md`.

## How It Works

### Initial Setup (one-time)

Paste [`.prompts/setup-prompt.md`](.prompts/setup-prompt.md) into Claude Code. It:

1. Downloads the latest release from the GitHub Releases API
2. Copies **shared files** from `context/` → `.agent-context/` (overwritable)
3. Creates **project-owned files** from `templates/` → `AGENTS.md`, layers 1-3, memory stubs (never overwritten)
4. Writes the release version to `.agent-context/.agent-context-version`
5. Discovers your tech stack and fills in the TODO placeholders

### Every Session (automatic)

Updates can be triggered manually by fetching the setup prompt from remote and following its instructions:

1. Reads `.agent-context/.agent-context-version` (local) and fetches the latest release tag from the GitHub API (remote, cached for 1 hour)
2. **If already up-to-date and templates intact:** exits immediately — no Claude spawn needed
3. **If versions differ:** spawns Claude, which downloads shared files in parallel, writes the new version
4. **If API fails:** falls back to the cached version; warns if the cache is stale
5. Syncs plugins from `plugins.json` into `.claude/settings.json`

### What the agent sees at runtime

```
AGENTS.md                               ← Agent reads this first
  @.agent-context/agent-startup.md      ← Version check, update info
  @.agent-context/layer0-agent-workflow  ← Memory routing, skill lookup
  @.agent-context/layer1-bootstrap      ← Tech stack, Docker, domains
  @.agent-context/layer2-project-core   ← Your conventions + critical rules
  @.agent-context/layer3-guidebook      ← Task routing → memory/skills on-demand
```

Total baseline: ~200-250 lines. Heavy reference (skills, memory) is loaded only when the task matches.

## Installation

### Quick Start

Run this one-liner from your project root:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/lx-wnk/Agent-Context/main/install.sh)"
```

The script checks whether your project is already up-to-date (TTL-cached, 1 hour). If an update is needed, it spawns Claude headlessly, shows live progress in your terminal, and exits cleanly when done:

```
Starting agent-context setup in /your/project...
...............
[agent-context] Mode: UPDATE (0.3.0 → 0.5.0)
[agent-context] Step 1/5: Checking version...
....
[agent-context] Step 2/5: Installing shared files...
...
[agent-context] Done.
```

Claude analyzes existing documentation, applies quality filters, discovers your tech stack, and creates the architecture. Restart your session afterwards — the new configuration takes effect on the next start.

Pass `--force` to skip the version cache and run a full update regardless of the installed version.

**Requires:** [Claude Code CLI](https://claude.ai/code) installed and authenticated.

### Alternative: paste into a session

Paste the contents of [`.prompts/setup-prompt.md`](.prompts/setup-prompt.md) directly into a Claude Code session if you prefer to confirm each step interactively.

### What Gets Created

```
your-project/
├── AGENTS.md                              ← Entry point
├── .claude/CLAUDE.md                      ← Bootstrap pointer → @AGENTS.md
├── .claude/settings.json                  ← Settings file (created if missing, never overwritten)
└── .agent-context/
    ├── agent-startup.md                   ← Startup info (shared)
    ├── layer0-agent-workflow.md            ← Universal agent workflow (shared)
    ├── base-principles.md                 ← Dev principles (shared)
    ├── layer1-bootstrap.md                ← Project identity, Docker, domains
    ├── layer2-project-core.md             ← Dev principles + critical rules
    ├── layer3-guidebook.md                ← Task routing, skills, memory
    ├── .agent-context-version              ← Installed version (written by setup/update)
    ├── plugins.json                       ← Plugin configuration (shared)
    ├── decisions.json                     ← Architectural decisions (structured)
    ├── knowledge-map.md                   ← Universal knowledge pointer index (auto-maintained)
    ├── setup-decisions.json               ← Decision manifest for idempotent re-runs
    ├── memory-review-prompt.md            ← Memory review prompt (shared)
    ├── decision-review-prompt.md          ← Decision review prompt (shared)
    ├── skills/
    │   └── index.md                       ← Skill registry (on-demand)
    └── memory/
        ├── decisions.md                   ← Legacy stub (migrated to decisions.json)
        ├── lessons.md                     ← Hard-won lessons
        ├── people.md                      ← Team members & stakeholders
        ├── preferences.md                 ← Agent behavior preferences
        ├── todo.md                        ← Current task plan
        ├── user.md                        ← Primary user profile
        ├── log.md                         ← Chronological activity log
        └── index.md                       ← Memory file catalog
```

## Repository Structure

```
agent-context/
├── context/           # Shared agent context (copied to .agent-context/)
├── templates/         # Project setup templates (copied once, never overwritten)
├── tests/             # Pure-bash tests (unit tests + template coverage check)
├── plugins.json       # Base plugin set for Claude Code
├── example.md         # Annotated example (Shopware 6 project)
├── install.sh         # Installer script (curl one-liner entry point)
├── .prompts/          # Prompt files for Claude (setup + review instructions)
└── README.md
```

## Development & Contributing

To test local changes to `.prompts/setup-prompt.md` without creating a release, set `AGENT_CONTEXT_PROMPT` to your local clone's prompt file. The installer script will use it instead of fetching from GitHub.

```bash
# Set once for your shell session
export AGENT_CONTEXT_PROMPT=/path/to/your/Agent-Context/.prompts/setup-prompt.md

# Then run the installer in any target project
/bin/bash -c /path/to/your/Agent-Context/install.sh

# Or inline
AGENT_CONTEXT_PROMPT=/path/to/your/Agent-Context/.prompts/setup-prompt.md \
    /bin/bash -c /path/to/your/Agent-Context/install.sh
```

Replace `/path/to/your/Agent-Context` with the path to your local clone. No changes to release logic required.

## Agents

Specialist agents (`ac-*`) are distributed as the [`agents@lx-wnk`](https://github.com/lx-wnk/agents) plugin — installed automatically via `plugins.json`. See the plugin repo for the full agent list and documentation.

## Example

See [`example.md`](example.md) for a complete annotated walkthrough of a Shopware 6 project. Each file is described in prose — shared files link back to `context/`, project-owned files explain what they contain and why.

## Key Principles

### 1. "Can the agent discover this by reading the code?"

Based on the [ETH Zurich study (2026)](https://arxiv.org/abs/2602.11988): auto-generated context files tend to **reduce** task success rates while increasing token cost by over 20%. Only include information that is **not discoverable** from source code.

**Keep:** Gotchas, non-linter conventions, architecture decisions, external system references, CI workflows. **Remove:** Directory trees, entity fields, route tables, service registrations, dependency lists.

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

Memory files are lightweight stubs (~10 lines) with quick facts. Full reference lives in skills, loaded only when trigger keywords match. This achieves near-zero baseline cost for heavy documentation.

### 4. Full knowledge re-sync on every update

Updates are not file patches. Every `setup-prompt.md` run (SETUP or UPDATE) performs a full knowledge re-synchronization: scan all knowledge sources (agent-context, source code, docs, architecture files), build a consolidated fact inventory, route facts to optimal targets, and verify global integrity. No fact is lost — it may move, but it must be traceable somewhere.

### 5. Self-maintaining knowledge map

`knowledge-map.md` is the single routing index for all project knowledge — both internal (agent-context) and external (docs, architecture files, API specs). Agents update it immediately when sources change, following the same non-negotiable rule as `lessons.md` updates. The map always reflects current project reality.

## Updates

After creating a [GitHub Release](https://github.com/lx-wnk/Agent-Context/releases), projects update by re-running the `install.sh` one-liner. The script compares the installed version against the latest release (GitHub Releases API, TTL-cached for 1 hour) — if already up-to-date, it exits immediately without spawning Claude. If a new version is available, Claude downloads the shared files in parallel, overwrites them, and runs a full knowledge re-synchronization: scanning all project knowledge sources, routing new facts to optimal targets, and verifying nothing was lost. Project-owned files receive improvements additively; content is never deleted. If the API is unreachable, the installer falls back to the cached version.

## Research & References

### Core Papers

- [ETH Zurich: Evaluating AGENTS.md (arxiv 2602.11988)](https://arxiv.org/abs/2602.11988) — Empirical evaluation of context files across coding agents; finds auto-generated context tends to reduce task success rates while increasing token cost by 20%+
- [Empirical Study of CLAUDE.md Files (arxiv 2509.14744)](https://arxiv.org/abs/2509.14744) — Analysis of 253 CLAUDE.md files across 242 repositories; validates layered hierarchy design; identifies dominant content categories (Build/Run, Implementation Details, Architecture)
- [Lost in the Middle: How LLMs Use Long Contexts (arxiv 2307.03172)](https://arxiv.org/abs/2307.03172) — Foundational paper on U-shaped position bias; explains why critical constraints belong at the top of context files, not the middle
- [Agentic Context Engineering (arxiv 2510.04618)](https://arxiv.org/abs/2510.04618) — Treats context as an evolving playbook refined through generation, reflection, and curation; directly relevant to the memory self-improvement loop
- [Tokalator: Measuring Token Cost of Instruction Files (arxiv 2604.08290)](https://arxiv.org/abs/2604.08290) — Finds 21.2% of context tokens come from unintentionally-included files; a single instruction file adds ~4,200 tokens per prompt silently
- [On the Impact of AGENTS.md Files (arxiv 2601.20404)](https://arxiv.org/abs/2601.20404) — Empirical measurement: AGENTS.md presence yields 16.58% median runtime reduction and ~20% output-token reduction when content is lean
- [SSGM: Structured Memory Governance (arxiv 2603.11768)](https://arxiv.org/abs/2603.11768) — TTL-tiered memory with semantic relevance × time-decay scoring; basis for the TTL metadata system
- [MemoryGraft: Persistent Memory Poisoning (arxiv 2512.16962)](https://arxiv.org/abs/2512.16962) — Poisoned skill/memory files can corrupt 87% of downstream agent decisions within 4 hours; motivates source attribution and trust scoring
- [A-MemGuard: Consensus Validation Defense (OpenReview)](https://openreview.net/forum?id=fVxfCEv8xG) — Dual-memory + consensus validation cuts poisoning attack success by 95%+

### Engineering & Best Practices

- [Addy Osmani: Stop Using /init for AGENTS.md](https://addyosmani.com/blog/agents-md/) — The "discoverable?" filter for what belongs in context files
- [Anthropic: Effective Context Engineering for AI Agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) — Authoritative guide on context design for agentic systems
- [Anthropic: How We Built Our Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system) — Orchestrator/subagent patterns; multi-agent outperformed single-agent Claude Opus 4 by 90%+ on internal evals
- [Anthropic: Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) — Structured environments for multi-session tasks; relevant to setup/update prompt design
- [Context Engineering for Coding Agents — Thoughtworks](https://martinfowler.com/articles/exploring-gen-ai/context-engineering-coding-agents.html) — Practical framing of context engineering for coding workflows (Birgitta Böckeler, published on martinfowler.com)
- [Want better AI outputs? Try context engineering — GitHub Blog](https://github.blog/ai-and-ml/generative-ai/want-better-ai-outputs-try-context-engineering/) — Accessible overview of context engineering concepts
- [llms.txt standard](https://llmstxt.org/) — Curated pointer-index file for LLM navigation of large doc sets without modification; basis for the knowledge-map.md pattern
- [Terraform plan/apply](https://developer.hashicorp.com/terraform/cli/commands/plan) — Plan-before-execute UX pattern; basis for setup-plan.md and Ack/Nack flow
- [Nx migrations.json](https://nx.dev/docs/reference/nx/migrations) — Persisted decision manifest for idempotent re-runs; basis for setup-decisions.json
- [Copier: Template Updating](https://copier.readthedocs.io/en/stable/updating/) — Three-way merge approach for project-owned files (evaluated and adapted — conflict markers replaced with additive-only + integrity check)

### Standards & Docs

- [AGENTS.md specification](https://agents.md/) — Open standard for agent instructions, stewarded by the Agentic AI Foundation (Linux Foundation)
- [Claude Code: Best Practices](https://code.claude.com/docs/en/best-practices)
- [Claude Code: Skills](https://code.claude.com/docs/en/skills)
- [Agent Creation Best Practices](docs/best-practices-agent-creation.md) — Comprehensive guide for creating custom agent configurations (German)

## License

MIT
