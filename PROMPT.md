# Agent Context Architecture — Setup Prompt

> **Usage:** Copy this entire file as a prompt to any AI coding agent (Claude Code, Cursor, Gemini CLI, Copilot, Codex, etc.) in a project that needs context architecture setup. The agent will analyze existing documentation, apply quality filters, and create the layered `.agent-context/` structure.

---

## Your Task

Analyze this project and create a layered `.agent-context/` context architecture. This architecture provides AI agents with the right information at the right time — minimizing baseline context while keeping full reference accessible on-demand.

## Phase 1: Discovery

Scan the project for existing agent/documentation files. Read ALL of these that exist:

- `CLAUDE.md`, `AGENTS.md`, `.cursorrules`, `.windsurfrules`, `GEMINI.md`, `COPILOT.md`
- `.claude/rules/*.md`, `.cursor/rules/*.md`
- `README.md`, `CONTRIBUTING.md`, `docs/`
- `.claude/projects/*/memory/*.md` (user memory files)
- `Makefile`, `package.json`, `composer.json`, `docker-compose.yml` / `compose.yaml`
- `.github/workflows/*.yml`, `.gitlab-ci.yml`, `Jenkinsfile`
- `.env.example`, `.editorconfig`

List what you found and summarize the total content size (approximate line count).

## Phase 2: Content Classification

For every piece of information found, apply the **"Can the agent discover this by reading the code?"** filter (ETH Zurich, 2026):

### KEEP (not discoverable from code):
- Gotchas, quirks, and hard-won lessons learned
- Conventions that no linter enforces (e.g., "no autowiring", "structs over arrays")
- Non-obvious architectural decisions and their rationale
- External system references (API endpoints, IDs, tokens, URLs)
- Docker/infra port mappings and networking conventions
- CI pipeline structure and custom build steps
- Security constraints and forbidden patterns
- Business-specific terminology or domain knowledge
- Pre-commit/pre-merge workflows

### REMOVE (discoverable from code):
- Directory trees and file structure listings
- Entity/model field listings (read the source files)
- Route tables (read annotations/decorators)
- Service registrations (read config files)
- Code style rules enforced by linters/formatters
- Linter/quality tool configuration details (levels, excludes, baselines, suppressed identifiers — read the config files directly: `phpstan.neon`, `.php-cs-fixer.php`, `eslint.config.*`, etc.)
- Function signatures and API surfaces
- Dependency lists (read package manager files)
- README content duplicated into agent context

**Principle:** Every line in context files represents friction the agent cannot resolve alone. If possible, fix the friction in the code instead of documenting it.

## Phase 3: Architecture Creation

Create this directory structure:

```
.agent-context/
  layer0-agent-workflow.md      # Universal agent patterns
  layer1-bootstrap.md           # Project identity & tech stack
  layer2-project-core.md        # Dev principles & conventions
  layer3-guidebook.md           # Task → file routing table
  memory/                       # Lightweight stubs with quick facts
    <domain-files>.md           # One per domain, only non-discoverable content
  skills/                       # Full reference docs, loaded on-demand
    <reference-files>.md        # Heavy docs with YAML trigger frontmatter
```

### Layer Files

**layer0-agent-workflow.md** (~20-30 lines)
- Plan-first approach
- Verification commands (build, test, lint)
- Memory update rules
- Routing table: how to classify and store new user learnings

**layer1-bootstrap.md** (~15-25 lines)
- Tech stack (language, framework, version)
- Infrastructure summary (Docker, cloud, DB)
- Project structure overview (only what's NOT obvious from directory names)
- Plugin/package/module table with dependencies (if applicable)

**layer2-project-core.md** (~25-40 lines)
- Development principles (only those not enforced by tooling)
- Code conventions that linters DON'T catch
- Testing strategy and patterns
- Commit convention
- Any "always apply" rules

**layer3-guidebook.md** (~25-40 lines)
- Task-to-file routing table: for each common task type, list which memory files and skills to load
- Memory file index with one-line descriptions
- Skills index with trigger keywords

### Memory Files (Stubs)

Each memory file should be **under 15 lines** containing:
1. Title
2. Pointer to skill file if a full reference exists
3. 3-5 quick facts that are most frequently needed (IDs, commands, URLs)

Only create memory files for domains that have non-discoverable content.

### Skills (Full Reference)

For content blocks over ~30 lines, create a skill file with YAML frontmatter:

```yaml
---
name: <skill-name>
description: <one-line summary for trigger matching>
triggers:
  - <keyword1>
  - <keyword2>
---

# Full reference content here
```

Skills are loaded ONLY when trigger keywords match the current task. This is the key to keeping baseline context small.

### Entry Points

**CLAUDE.md** (if it exists, replace content):
```markdown
# <Project Name>
All project instructions live in [AGENTS.md](AGENTS.md). Read and follow that file.
```

**AGENTS.md** (create or update, ~30-40 lines):
- One-line project identity
- Context architecture table (layers + always-load flags)
- 3-5 "Quick Rules" that apply to EVERY task
- Compaction preservation instructions

## Phase 4: Content Migration

For each source file found in Phase 1:
1. Classify each section using the Phase 2 filter
2. Route surviving content to the narrowest fitting target:
   - General dev philosophy → `layer2-project-core.md`
   - Domain-specific convention → `memory/<domain>.md`
   - Heavy reference (>30 lines) → `skills/<reference>.md`
   - Gotcha / hard-won lesson → `memory/lessons.md`
   - Architecture decision → `memory/decisions.md`
3. Eliminate all duplicates — each fact lives in exactly ONE place
4. Convert vague rules to actionable instructions

**Routing priority:** Domain-specific > project-wide > global. Narrower scope = less unnecessary context loading.

## Phase 5: Cleanup

- Delete or empty old source files (`.claude/rules/*.md`, etc.)
- Update any references to moved content
- Update user memory (`MEMORY.md`) to point to new architecture
- Verify `.agent-context/` is NOT in `.gitignore`

## Phase 6: Verification

Run these checks:
1. `wc -l AGENTS.md` — should be under 45 lines
2. `wc -l .agent-context/layer*.md` — each under 40 lines
3. `wc -l .agent-context/memory/*.md` — stubs under 15 lines each
4. Grep for key project-specific terms in new files to verify no content was lost
5. `cat CLAUDE.md` — should be 2-3 lines (bootstrap pointer)
6. No duplicated content across files

## Phase 7: Summary

Present a before/after comparison:

| Metric | Before | After |
|--------|--------|-------|
| Always-loaded lines | X | Y |
| On-demand lines | 0 | Z |
| Number of source files | X | — |
| Number of target files | — | Y |

---

## Constraints

- **Agent-agnostic:** No tool-specific instructions in any file. Works with any AI coding assistant.
- **No over-engineering:** Skip skills if total content is under ~200 lines. Skip memory stubs if a domain has less than ~30 lines of content.
- **Preserve all non-discoverable knowledge:** Nothing gets deleted — it gets routed, filtered, or promoted to code.
- **Respect existing conventions:** If the project already has strong documentation patterns, adapt the architecture to fit, don't force a complete rewrite.
