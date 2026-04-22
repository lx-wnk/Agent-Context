# Agent-Context Optimizations — Design Spec

**Date:** 2026-04-22
**Status:** Approved — pending implementation plan
**Goal:** Bring every project installation to "optimum" on every update — with zero knowledge loss, live context synchronization, and self-maintaining routing.

---

## Background & Research

This design is grounded in five parallel research investigations conducted 2026-04-22. Key findings that shaped the decisions:

### Token Efficiency

- **Tokalator (arxiv 2604.08290):** Instruction files silently add ~4,200 tokens per prompt. 21.2% of context tokens in real sessions come from unintentionally-included files. Layers above 500 lines must be flagged.
- **arxiv 2601.20404:** AGENTS.md presence yields 16.58% median runtime reduction and ~20% output-token reduction — but only when content is lean and targeted.
- Progressive 3-level disclosure (metadata → runtime → extended refs) yields ~70% token reduction with accuracy climbing from 60-70% to 85-95%.

### Context Engineering

- **Anthropic engineering blog (2025):** Subagents should explore with 10,000+ tokens but return 1,000-2,000 token condensed summaries. Lead agent never sees raw exploration output.
- **Lost in the Middle (arxiv 2307.03172):** U-shaped position bias — critical constraints must appear at the top of context files, not the middle.
- **Agentic Context Engineering (arxiv 2510.04618):** Context as an evolving playbook refined through generation, reflection, and curation — directly relevant to the self-improvement loop.

### Memory Lifecycle

- **SSGM Framework (arxiv 2603.11768):** Assign semantic-category-based TTL — immutable facts (architecture decisions) infinite; transient notes 7-30 days. Composite scoring: semantic relevance × exponential time-decay penalty.
- **Memory in the Age of AI Agents (arxiv 2512.13564):** Budget-aware bounded forgetting preserves narrative coherence.

### Security

- **MemoryGraft (arxiv 2512.16962):** Poisoned README/skill files can hijack agents weeks later via semantic triggers. A single compromise poisons 87% of downstream decisions within 4 hours.
- **A-MemGuard (OpenReview):** Consensus validation across multiple memory paths cuts attack success by 95%+ with minimal utility cost.
- **Practical mitigation:** Trust-scoring on memory entries (source attribution + confidence), temporal decay, and pattern-based filtering.

### Update Safety

- **Copier / Cruft / Flexlate:** Three-way merge (base = old template, ours = user file, theirs = new template) is the safest approach for project-owned files — but conflict markers (`<<<<<<<`) break AI agents reading context files. Decision: use Inventory → Restructure → Global Integrity Check instead.
- **Terraform plan/apply model:** Batch review before execution. Persisted plan file guarantees "what you approved is what gets applied."
- **Nx migrations.json model:** Persisted decision manifest enables idempotent re-runs — only changed/new elements require user input.

### Docs-as-Context

- **llms.txt standard:** Curated markdown pointer file — one-line descriptions + paths to actual content. Anthropic, Mintlify, Cursor have adopted it.
- **AGENTS.md / Cursor Rules:** Pointer-file precedent across agents — "point only to documentation relevant for execution."
- **SHA-256 change detection (memweave):** Per-file hashes detect doc changes without modifying source files.

### Setup UX

- **Terraform:** Plan/apply with saved plan guarantees alignment between approval and execution.
- **Nx:** Commit decision file, re-run freely, comment out or reorder entries — translates directly to markdown-based systems.
- **Smart defaults:** Auto-decide when confidence >0.8, escalate only genuine ambiguity.

---

## Design

### Section 1: Smart Update Engine

#### Current State

Updates only patch shared files (`context/`, `plugins.json`). Project-owned files (`layer1-3`, `memory/`) never receive framework improvements except by manual intervention.

#### New Update Philosophy

Every update is a **full knowledge re-synchronization**, not a file patch. The update scans all knowledge sources — existing agent-context, source code, and all project documentation — builds a unified fact inventory, restructures into the optimal form, and validates completeness on a global (not per-file) basis.

#### Knowledge Sources (scanned on every Setup + Update)

```
Existing agent-context         → all layers, memory/, decisions.json, skills/
Source code                    → dependencies, conventions visible in code, new patterns
Structured knowledge folders   → docs/, architecture/, wiki/, api/, specs/, *.md (root)
                                 (any folder with structured written knowledge)
```

#### Three-Step Update Flow

**Step 1 — Consolidated Fact Inventory**

Before any file is touched, the agent extracts every fact, rule, and decision from all knowledge sources. Output: a flat list of facts with origin, topic, and estimated scope.

**Step 2 — Routing & Restructuring**

Each fact is routed to the most specific, appropriate target in the new framework structure:

| Fact Type                   | Target                   |
| --------------------------- | ------------------------ |
| Project-wide convention     | `layer2-project-core.md` |
| Domain-specific fact        | `memory/<domain>.md`     |
| Heavy reference (>30 lines) | `skills/<reference>.md`  |
| Gotcha / lesson             | `memory/lessons.md`      |
| Architecture decision       | `decisions.json`         |
| External knowledge pointer  | `knowledge-map.md`       |

**Step 3 — Global Integrity Check**

After restructuring, every fact from Step 1 must be traceable in the new structure. The check is on **total knowledge**, not per file. A fact may move from `layer2` to `memory/auth.md` — as long as it exists somewhere, the check passes. Missing facts are reported as errors before any files are committed.

---

### Section 2: Setup/Update UX + Ack/Nack

#### Discovery Output Format

Each of the 6 discovery subagents emits structured findings:

```json
{
  "source": "docs/architecture.md",
  "size_lines": 287,
  "topic": "System Architecture",
  "category_guess": "reference",
  "confidence": 0.91,
  "recommended_action": "reference"
}
```

#### Confidence-Based Auto-Decision

| Signal                                                     | Auto-Decision                         |
| ---------------------------------------------------------- | ------------------------------------- |
| Confidence >0.8 AND size <30 lines AND single layer target | Auto-route, no user input             |
| Confidence >0.8 AND size >100 lines OR has TOC             | Auto → `knowledge-map.md` reference   |
| Confidence ≤0.8 OR spans multiple layer categories         | → Ack/Nack                            |
| Two sources contradict each other                          | → Ack/Nack with both options          |
| Structured knowledge folder first discovered               | → Ack/Nack: consolidate vs. reference |

#### Interactive Mode (Claude Code)

Ambiguous decisions surface as direct questions in the conversation. Multiple independent decisions are batched:

```
Ich habe folgende Entscheidungen — bitte bestätigen:
1. docs/architecture.md → referenzieren (287 Zeilen, structured)   [Ack/Nack]
2. docs/api-guide.md    → referenzieren (412 Zeilen, has TOC)       [Ack/Nack]
3. CONTRIBUTING.md      → konsolidieren (18 Zeilen, conventions)    [Ack/Nack]
```

High-confidence decisions execute silently and are listed in the summary only.

#### Interactive Mode Detection

Claude Code is detected via the presence of `.claude/settings.json`. If detected and a session is active (not headless/CI), interactive Ack/Nack mode is used. Otherwise: plan-file mode.

#### Plan-File Mode (other agents / CI / headless)

A `.agent-context/setup-plan.md` is generated before any execution:

```markdown
# .agent-context/setup-plan.md — 2026-04-22

| #   | Source                       | Action      | Confidence | Status    |
| --- | ---------------------------- | ----------- | ---------- | --------- |
| 1   | docs/architecture.md         | reference   | 0.91       | ✅ auto   |
| 2   | CONTRIBUTING.md              | consolidate | 0.85       | ✅ auto   |
| 3   | layer2: conflict rule A vs B | keep rule A | 0.55       | ⏳ review |
```

User edits the Status column, re-runs prompt → agent reads plan and executes.

#### Decision Manifest (Re-Run Idempotency)

All decisions are persisted to `.agent-context/setup-decisions.json`:

```json
{
  "docs/architecture.md": {
    "action": "reference",
    "sha256": "a3f...",
    "decided_at": "2026-04-22",
    "source": "user-ack"
  }
}
```

On re-run: SHA-256 comparison. Unchanged sources → decision reused silently. Changed sources → ask again.

---

### Section 3: Knowledge Map & Task-Based Routing

#### Concept

`.agent-context/knowledge-map.md` is a universal pointer index for all structured knowledge in the project. It replaces and extends the Layer 3 routing table by covering both internal (agent-context) and external (any project folder) knowledge sources.

No source file is ever modified. The map is agent-system-owned and agent-maintained.

#### Structure

```markdown
# Knowledge Map

## Task Routing

| Working on...    | Agent-Context                     | External Knowledge           |
| ---------------- | --------------------------------- | ---------------------------- |
| Auth / Login     | `memory/auth.md`                  | `docs/auth-flow.md`          |
| API Endpoints    | `memory/api.md`, `decisions.json` | `api/openapi.yaml`           |
| DB Schema        | `memory/db.md`                    | `architecture/data-model.md` |
| Frontend Styling | `memory/design-tokens.md`         | `docs/design-system.md`      |

## Knowledge Sources

| Source                       | Topic               | Format   | SHA256 | Last Verified |
| ---------------------------- | ------------------- | -------- | ------ | ------------- |
| `docs/auth-flow.md`          | Auth & Sessions     | Markdown | a3f... | 2026-04-22    |
| `architecture/data-model.md` | DB Schema Decisions | Markdown | b7c... | 2026-04-22    |
| `api/openapi.yaml`           | API Surface         | YAML     | d2e... | 2026-04-22    |
```

#### Self-Updating: Layer 0 Integration

`knowledge-map.md` is a first-class citizen of the Self-Improvement Loop — same non-negotiable trigger rules as `lessons.md` and `decisions.json`:

| Event                                           | Immediate Action                                   |
| ----------------------------------------------- | -------------------------------------------------- |
| External file changed (SHA256 mismatch)         | Update SHA256 + Last Verified in Knowledge Sources |
| New structured knowledge file/folder discovered | Add entry to Knowledge Sources + Task Routing      |
| Task type used but routing row missing          | Add routing row based on current task type         |
| Source no longer exists                         | Remove entry from map                              |

**Non-negotiable:** These updates happen as the very next action after discovery, before continuing other work. The map always reflects the current project knowledge state.

#### Layer 3 Relationship

Layer 3 (`layer3-guidebook.md`) retains its internal routing table (agent-context only). External sources are exclusively managed in the knowledge map. Layer 3 includes a single pointer:

```markdown
@.agent-context/knowledge-map.md
```

---

### Section 4: Memory & Security Hardening

#### TTL Metadata

Every memory entry carries an inline TTL marker enabling automated staleness detection by the Memory Review Prompt:

```markdown
<!-- Format: - **[scope]** Lesson (YYYY-MM-DD) ttl:VALUE source:SOURCE conf:LEVEL -->

- **[auth]** JWT tokens must be invalidated server-side (2026-04-22) ttl:infinite source:user conf:high
- **[docker]** Port 8080 internal only (2026-04-01) ttl:90d source:discovered conf:med
- **[sprint]** API v2 migration runs until end of April (2026-04-10) ttl:30d source:user conf:high
```

**TTL Categories:**

| Category                                     | Value          | Example                                   |
| -------------------------------------------- | -------------- | ----------------------------------------- |
| Architecture decisions, security constraints | `ttl:infinite` | Technology choices, forbidden patterns    |
| Gotchas, API quirks, hard-won lessons        | `ttl:90d`      | Unexpected behavior, workarounds          |
| Sprint/task-scoped, temporary                | `ttl:30d`      | Active migrations, temporary restrictions |

#### Trust Scoring (Context Poisoning Defense)

Source attribution and confidence scores on every memory entry:

| Field     | Values                           | Meaning                |
| --------- | -------------------------------- | ---------------------- |
| `source:` | `user`, `discovered`, `external` | Who produced this fact |
| `conf:`   | `high`, `med`, `low`             | Confidence level       |

On contradiction between two entries: higher `conf` wins. Equal confidence → agent flags for user resolution, never overwrites autonomously.

Research basis: MemoryGraft (arxiv 2512.16962) showed poisoned skill/memory files can corrupt 87% of downstream agent decisions within 4 hours. Source attribution + temporal decay cuts attack success by 95%+ (A-MemGuard, OpenReview).

#### Token Budget Audit

Automated check in the update prompt after every sync:

```
Token Budget Audit:
  layer0-agent-workflow.md  → 125 lines  ✅
  layer1-bootstrap.md       →  28 lines  ✅
  layer2-project-core.md    →  31 lines  ✅
  layer3-guidebook.md       →  48 lines  ✅
  knowledge-map.md          →  67 lines  ✅
  memory/lessons.md         →  19 lines  ✅
  [WARN] memory/api.md      → 521 lines  ⚠️ → Skill graduation recommended
```

Files above threshold are never auto-modified — reported as graduation candidates only. Threshold: 500 lines for `memory/` stubs.

---

## Architectural Decision Record

### ADR-001: Claude Code Native Extension Deferred

**Decision:** The Claude Code Native Extension (`.claude/rules/*.md` with `paths:` frontmatter, `SessionStart` hooks, skill `paths:` for glob-triggered auto-activation) is explicitly deferred and not included in this design.

**Context:**

Claude Code offers native features that overlap with patterns this framework implements manually:

- `.claude/rules/*.md` with `paths:` frontmatter provides native path-scoped lazy loading (replaces Layer 3 routing)
- `SessionStart` hook enables dynamic context injection without static layer files
- Skill `paths:` frontmatter enables automatic glob-triggered activation

These features would yield meaningful performance gains within Claude Code.

**Reason for Deferral:**

The Agent-Context framework is deliberately agent-agnostic. It works in Claude Code, Cursor, GitHub Copilot, Gemini CLI, and any other agent that reads AGENTS.md or CLAUDE.md. Plugin-installed agents (`agents@lx-wnk`) cannot use hooks or `mcpServers` — meaning the native extension would create two divergent behavior paths: one for the main Claude agent and one for all plugin agents within Claude Code itself.

Introducing Claude-native features at the framework level would:

1. Break compatibility for all non-Claude agents
2. Create inconsistent behavior between main agent and plugin agents within Claude Code itself
3. Undermine the agent-agnostic design principle that allows this framework to work across tools

**Future Consideration:**

If the framework ever introduces a Claude-specific opt-in overlay layer, the Native Extension can be revisited. At that point: `.claude/rules/*.md` should mirror Layer 3 routing (not replace it), and hooks should be additive enhancements only.

**References:**

- Claude Code docs: `code.claude.com/docs/en/hooks`, `code.claude.com/docs/en/skills`
- Plugin agents cannot use `hooks`, `mcpServers`, or `permissionMode` (Claude Code docs, 2026-04-22)

---

## Implementation Summary

| Area               | Change                                                                                    |
| ------------------ | ----------------------------------------------------------------------------------------- |
| Update Engine      | Full knowledge re-sync (inventory → restructure → global integrity check) on every update |
| Knowledge Sources  | Setup + Update scan code, docs, AND all structured knowledge folders                      |
| Setup UX           | Terraform plan/apply: batch Ack/Nack in Claude, plan-file for other agents                |
| Re-Run Idempotency | `setup-decisions.json` manifest with SHA-256 per source                                   |
| Knowledge Map      | `knowledge-map.md`: universal pointer index, self-updating via Self-Improvement Loop      |
| Task Routing       | Layer 3 covers internal agent-context; knowledge-map covers external sources              |
| Memory TTL         | Inline `ttl:` + `source:` + `conf:` metadata on every memory entry                        |
| Security           | Trust-scoring, source attribution, contradiction resolution without autonomous override   |
| Token Audit        | Automated line-count check in update prompt, graduation candidates reported               |
| README             | Updated to reflect new capabilities + new Research & References entries                   |
| Claude Native      | Deferred — see ADR-001                                                                    |

### README Updates

`README.md` is updated as part of this implementation to reflect:

- New update philosophy (full knowledge re-sync vs. file patch)
- `knowledge-map.md` and `setup-decisions.json` added to the installed file structure
- Extended "Key Principles" covering knowledge integrity and self-maintaining routing
- New "Research & References" entries for all sources informing this design:
  - Tokalator (arxiv 2604.08290) — silent token overhead of instruction files
  - arxiv 2601.20404 — empirical AGENTS.md runtime/token impact
  - SSGM Framework (arxiv 2603.11768) — memory lifecycle governance and TTL
  - MemoryGraft (arxiv 2512.16962) — context poisoning via memory/skill files
  - A-MemGuard (OpenReview) — consensus validation as poisoning defense
  - llms.txt standard — pointer-index pattern for docs-as-context
  - Terraform / Nx — plan/apply and persisted decision manifest patterns
