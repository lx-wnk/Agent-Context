# Agent Context Architecture

A reusable prompt for setting up layered, agent-agnostic context architecture in any software project. Reduces baseline context by 5-7x while keeping full reference accessible on-demand.

## The Problem

AI coding agents (Claude Code, Cursor, Gemini CLI, Copilot, Codex) load project instructions into their context window every conversation. Most projects dump everything into a single file (`CLAUDE.md`, `.cursorrules`), resulting in:

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

**Baseline:** ~100 lines (AGENTS.md + layers 0-2). Full reference: loaded only when trigger keywords match.

## Why `.agent-context/` instead of `.claude/`?

| | `.claude/rules/` | `.agent-context/` |
|-|-------------------|-------------------|
| **Works with** | Claude Code only | Any AI agent |
| **Loading** | Always loaded (all files) | Layer-based, on-demand |
| **Path globs** | Yes (Claude Code native) | No (agent reads guidebook) |
| **Discoverability** | Hidden directory convention | Explicit, self-documenting |
| **Skills** | `.claude/skills/` (Claude-specific) | `.agent-context/skills/` (universal) |

`.claude/rules/` is a Claude Code feature — other agents ignore it. `.agent-context/` is a plain directory any agent can read. The guidebook pattern (layer 3) replaces path-based auto-loading with task-based routing that works regardless of the agent.

**Compatibility:** You can keep a minimal `CLAUDE.md` as a bootstrap pointer to `AGENTS.md`. Similarly for `.cursorrules` or other tool-specific files.

## Usage

1. Copy the contents of [`PROMPT.md`](PROMPT.md) as a prompt into any AI coding agent
2. The agent analyzes existing documentation, applies quality filters, and creates the architecture
3. Review the result and iterate

The prompt works with Claude Code, Cursor, Gemini CLI, GitHub Copilot, Codex, and any other agent that can read and write files.

## Example

The [`example/`](example/) directory shows a complete setup for a Shopware 6 project (based on [shopware/shopware](https://github.com/shopware/shopware)):

```
example/
  AGENTS.md                            # Entry point
  .agent-context/
    layer0-agent-workflow.md           # Workflow, verification, routing
    layer1-bootstrap.md                # Tech stack, core domains
    layer2-project-core.md             # Principles, conventions, testing
    layer3-guidebook.md                # Task routing, skill index
    memory/
      architecture.md                  # Non-obvious architectural details
      dal-conventions.md               # DAL quick facts (stub → skill)
      decisions.md                     # Architecture decisions
      infrastructure.md                # Docker, CI, build quick facts (stub → skill)
      lessons.md                       # Gotchas and hard-won knowledge
    skills/
      dal-reference.md                 # Full DAL reference (on-demand)
      infrastructure.md                # Full commands & CI reference (on-demand)
```

## Key Principles

### 1. "Can the agent discover this by reading the code?"

Based on the [ETH Zurich study (2026)](https://arxiv.org/abs/2602.11988): auto-generated context files reduce agent performance by ~3%. Only include information that is **not discoverable** from source code.

**Keep:** Gotchas, non-linter conventions, architecture decisions, external system references, CI workflows.
**Remove:** Directory trees, entity fields, route tables, service registrations, dependency lists.

### 2. Narrowest fitting scope

Route information to the most specific level possible:

| Scope | Target |
|-------|--------|
| General philosophy | `layer2-project-core.md` |
| Domain convention | `memory/<domain>.md` |
| Heavy reference (>30 lines) | `skills/<reference>.md` |
| Gotcha / lesson | `memory/lessons.md` |

A PHP convention loaded during a CSS fix is wasted context.

### 3. Stubs + Skills pattern

Memory files are lightweight stubs (~10 lines) with quick facts. Full reference lives in skills, loaded only when trigger keywords match. This achieves near-zero baseline cost for heavy documentation.

## Research & References

- [ETH Zurich: Evaluating AGENTS.md (arxiv 2602.11988)](https://arxiv.org/abs/2602.11988) — Empirical evaluation of context files across coding agents
- [Addy Osmani: Stop Using /init for AGENTS.md](https://addyosmani.com/blog/agents-md/) — The "discoverable?" filter
- [Context Engineering for AI Agents — Anthropic](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- [Context Engineering for Coding Agents — Martin Fowler](https://martinfowler.com/articles/exploring-gen-ai/context-engineering-coding-agents.html)
- [Want better AI outputs? Try context engineering — GitHub Blog](https://github.blog/ai-and-ml/generative-ai/want-better-ai-outputs-try-context-engineering/)
- [AGENTS.md specification](https://agents.md/) — Open standard for agent instructions
- [Claude Code: Best Practices](https://code.claude.com/docs/en/best-practices)
- [Claude Code: Skills](https://code.claude.com/docs/en/skills)

## License

MIT
