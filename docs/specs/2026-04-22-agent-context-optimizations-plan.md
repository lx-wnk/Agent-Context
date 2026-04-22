# Agent-Context Optimizations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform the Agent-Context framework into a self-maintaining, knowledge-preserving system that synchronizes every project installation to "optimum" on every update.

**Architecture:** Three change layers: (1) shared context files get knowledge-map triggers and TTL/trust metadata; (2) templates get the knowledge-map file and updated memory entry formats; (3) the setup/update prompt gains full knowledge re-synchronization logic with Ack/Nack UX and token budget audit. All changes are markdown/JSON only — no build system, no runtime code.

**Tech Stack:** Markdown, JSON, Prettier (`npm run prettier`), shell (`wc -l`, `grep`, `sha256sum`)

**Spec:** `docs/specs/2026-04-22-agent-context-optimizations-design.md`

---

## File Map

| File                                             | Action     | Responsibility                                                  |
| ------------------------------------------------ | ---------- | --------------------------------------------------------------- |
| `templates/.agent-context/knowledge-map.md`      | **Create** | Universal knowledge pointer index template                      |
| `context/layer0-agent-workflow.md`               | Modify     | Add knowledge-map to Self-Improvement Loop triggers             |
| `templates/.agent-context/layer3-guidebook.md`   | Modify     | Add `@knowledge-map.md` pointer                                 |
| `templates/.agent-context/memory/lessons.md`     | Modify     | Add TTL/source/conf metadata format                             |
| `templates/.agent-context/memory/preferences.md` | Modify     | Add TTL/source/conf metadata format                             |
| `templates/.agent-context/memory/people.md`      | Modify     | Add TTL/source/conf metadata format                             |
| `.prompts/memory-review-prompt.md`               | Modify     | Add TTL-aware staleness check                                   |
| `templates/.agent-context/decisions.json`        | Modify     | Add ADR-001 entry                                               |
| `.prompts/setup-prompt.md`                       | Modify     | Discovery expansion, UPDATE re-sync, Ack/Nack UX, token audit   |
| `README.md`                                      | Modify     | New capabilities, file structure, Key Principles, Research refs |

---

### Task 1: knowledge-map.md Template

**Files:**

- Create: `templates/.agent-context/knowledge-map.md`

- [ ] **Step 1: Verify file does not exist**

Run: `ls templates/.agent-context/knowledge-map.md 2>&1`
Expected: `No such file or directory`

- [ ] **Step 2: Create the file**

Write exactly this content to `templates/.agent-context/knowledge-map.md`:

```markdown
# Knowledge Map

> Universal knowledge index for this project. Maintained automatically — never edit manually.
> Updated immediately when knowledge sources change (see Layer 0 → Self-Improvement Loop).

## Task Routing

| Working on... | Agent-Context | External Knowledge |
| ------------- | ------------- | ------------------ |

<!-- TODO: Populated during setup. Example:
| Auth / Login     | `memory/auth.md`                  | `docs/auth-flow.md`           |
| API Endpoints    | `memory/api.md`, `decisions.json` | `api/openapi.yaml`            |
| DB Schema        | `memory/db.md`                    | `architecture/data-model.md`  |
-->

## Knowledge Sources

| Source | Topic | Format | SHA256 | Last Verified |
| ------ | ----- | ------ | ------ | ------------- |

<!-- TODO: Populated during setup. Example:
| `docs/auth-flow.md`          | Auth & Sessions     | Markdown | a3f... | 2026-04-22 |
| `architecture/data-model.md` | DB Schema Decisions | Markdown | b7c... | 2026-04-22 |
-->
```

- [ ] **Step 3: Verify**

Run: `grep -c "Knowledge Sources" templates/.agent-context/knowledge-map.md`
Expected: `1`

- [ ] **Step 4: Format**

Run: `npm run prettier`
Expected: All files pass

- [ ] **Step 5: Commit**

```bash
git add templates/.agent-context/knowledge-map.md
git commit -m "feat: add knowledge-map.md template for universal knowledge pointer index"
```

---

### Task 2: Layer 0 — Knowledge Map in Self-Improvement Loop

**Files:**

- Modify: `context/layer0-agent-workflow.md`

- [ ] **Step 1: Verify the section to modify**

Run: `grep -n "Lesson Graduation" context/layer0-agent-workflow.md`
Expected: a line number (e.g., `68:## Lesson Graduation`)

- [ ] **Step 2: Insert Knowledge Map Triggers section**

In `context/layer0-agent-workflow.md`, locate the `## Lesson Graduation` section. Insert the following block **immediately before** it (after the empty line that follows the Session Routine section):

```markdown
### Knowledge Map Triggers

Update `.agent-context/knowledge-map.md` immediately when any of the following occurs — same non-negotiable rule as all other triggers (next action after discovery, before continuing):

| Event                                              | Action                                                   |
| -------------------------------------------------- | -------------------------------------------------------- |
| External file changed (SHA256 mismatch detected)   | Update SHA256 + Last Verified in Knowledge Sources table |
| New structured knowledge file or folder discovered | Add entry to Knowledge Sources + add row to Task Routing |
| Task type used but no routing row exists for it    | Add routing row to Task Routing based on current task    |
| Knowledge source no longer exists                  | Remove entry from Knowledge Sources table                |
```

- [ ] **Step 3: Verify insertion**

Run: `grep -n "Knowledge Map Triggers" context/layer0-agent-workflow.md`
Expected: a line number

- [ ] **Step 4: Check line count stays reasonable**

Run: `wc -l context/layer0-agent-workflow.md`
Expected: under 145 lines

- [ ] **Step 5: Format**

Run: `npm run prettier`
Expected: All files pass

- [ ] **Step 6: Commit**

```bash
git add context/layer0-agent-workflow.md
git commit -m "feat: add knowledge-map triggers to layer0 self-improvement loop"
```

---

### Task 3: Layer 3 Template — Knowledge Map Pointer

**Files:**

- Modify: `templates/.agent-context/layer3-guidebook.md`

- [ ] **Step 1: Verify current Skills Index section**

Run: `grep -n "Skills Index" templates/.agent-context/layer3-guidebook.md`
Expected: a line number

- [ ] **Step 2: Insert knowledge-map pointer**

In `templates/.agent-context/layer3-guidebook.md`, find the line:

```markdown
## Skills Index
```

Insert the following block **before** the `## Skills Index` section:

```markdown
## Knowledge Map

External knowledge sources and task-based routing to project docs, architecture files, and other structured knowledge. Updated automatically on every agent run.

@.agent-context/knowledge-map.md
```

- [ ] **Step 3: Verify insertion**

Run: `grep -n "knowledge-map" templates/.agent-context/layer3-guidebook.md`
Expected: a line containing `@.agent-context/knowledge-map.md`

- [ ] **Step 4: Format**

Run: `npm run prettier`
Expected: All files pass

- [ ] **Step 5: Commit**

```bash
git add templates/.agent-context/layer3-guidebook.md
git commit -m "feat: add knowledge-map pointer to layer3-guidebook template"
```

---

### Task 4: Memory Templates — TTL/Source/Conf Format

**Files:**

- Modify: `templates/.agent-context/memory/lessons.md`
- Modify: `templates/.agent-context/memory/preferences.md`
- Modify: `templates/.agent-context/memory/people.md`

- [ ] **Step 1: Check current content of all three files**

Run: `cat templates/.agent-context/memory/lessons.md`
Run: `cat templates/.agent-context/memory/preferences.md`
Run: `cat templates/.agent-context/memory/people.md`

- [ ] **Step 2: Replace lessons.md**

Write exactly this content to `templates/.agent-context/memory/lessons.md`:

```markdown
# Lessons Learned

<!-- Format: - **[scope]** Lesson (YYYY-MM-DD) ttl:VALUE source:SOURCE conf:LEVEL -->
<!-- TTL: infinite (architecture/security) | 90d (gotchas/quirks) | 30d (sprint/temp) -->
<!-- Source: user (user-confirmed) | discovered (agent-found) | external (from docs/code) -->
<!-- Conf: high | med | low — used for contradiction resolution (higher conf wins) -->
```

- [ ] **Step 3: Replace preferences.md**

Write exactly this content to `templates/.agent-context/memory/preferences.md`:

```markdown
# Agent Behavior Preferences

<!-- Format: - **[scope]** Preference (YYYY-MM-DD) ttl:VALUE source:SOURCE conf:LEVEL -->
<!-- TTL: infinite (stable preferences) | 90d (likely to change) -->
<!-- Source: user | discovered | external -->
<!-- Conf: high | med | low -->
```

- [ ] **Step 4: Replace people.md**

Write exactly this content to `templates/.agent-context/memory/people.md`:

```markdown
# Team & Stakeholders

<!-- Format: - **Name** — Role, relevant context (YYYY-MM-DD) ttl:VALUE source:SOURCE conf:LEVEL -->
<!-- TTL: infinite (stable roles) | 90d (roles change) | 30d (sprint-specific) -->
<!-- Source: user | discovered | external -->
<!-- Conf: high | med | low -->
```

- [ ] **Step 5: Verify all three files updated**

Run: `grep -l "ttl:VALUE" templates/.agent-context/memory/lessons.md templates/.agent-context/memory/preferences.md templates/.agent-context/memory/people.md | wc -l`
Expected: `3`

- [ ] **Step 6: Format**

Run: `npm run prettier`
Expected: All files pass

- [ ] **Step 7: Commit**

```bash
git add templates/.agent-context/memory/lessons.md templates/.agent-context/memory/preferences.md templates/.agent-context/memory/people.md
git commit -m "feat: add TTL/source/conf metadata format to memory templates"
```

---

### Task 5: Memory Review Prompt — TTL-Aware Staleness

**Files:**

- Modify: `.prompts/memory-review-prompt.md`

- [ ] **Step 1: Find the Staleness Check section**

Run: `grep -n "Staleness Check" .prompts/memory-review-prompt.md`
Expected: a line number (e.g., `45:## Step 2: Staleness Check`)

- [ ] **Step 2: Replace the Staleness Check section**

Find this block in `.prompts/memory-review-prompt.md`:

```markdown
## Step 2: Staleness Check

For each memory entry that has a date (format `YYYY-MM-DD`):

| Age         | Action                                                        |
| ----------- | ------------------------------------------------------------- |
| < 90 days   | Keep — still fresh                                            |
| 90-180 days | Flag as **stale** — include in summary for user review        |
| > 180 days  | Flag as **archive candidate** — suggest removal or graduation |

Entries without dates: flag as **undated** in summary (suggest adding a date).
```

Replace with:

```markdown
## Step 2: Staleness Check

For each memory entry that has a date (format `YYYY-MM-DD`):

1. Extract inline TTL marker if present (e.g., `ttl:90d`, `ttl:infinite`, `ttl:30d`)
2. Apply TTL rules:

| TTL                        | Rule                                                                                  |
| -------------------------- | ------------------------------------------------------------------------------------- |
| `ttl:infinite`             | Never expires — skip staleness check                                                  |
| `ttl:Nd` (e.g., `ttl:90d`) | Flag as **archive candidate** when (date + N days) < today                            |
| No TTL present             | Apply defaults: <90 days keep, 90-180 days **stale**, >180 days **archive candidate** |

3. Entries without dates: flag as **undated** in summary (suggest adding date + TTL).
4. On contradiction between two entries with conflicting facts: flag as **conflict** — include both in summary. Higher `conf:` value wins; equal conf requires user resolution.
```

- [ ] **Step 3: Verify replacement**

Run: `grep -n "ttl:infinite" .prompts/memory-review-prompt.md`
Expected: a line number

- [ ] **Step 4: Verify SHARED FILE header still present**

Run: `grep -c "SHARED FILE" .prompts/memory-review-prompt.md`
Expected: `1`

- [ ] **Step 5: Format**

Run: `npm run prettier`
Expected: All files pass

- [ ] **Step 6: Commit**

```bash
git add .prompts/memory-review-prompt.md
git commit -m "feat: add TTL-aware staleness check and conflict detection to memory-review-prompt"
```

---

### Task 6: decisions.json — ADR-001

**Files:**

- Modify: `templates/.agent-context/decisions.json`

- [ ] **Step 1: Verify current content**

Run: `cat templates/.agent-context/decisions.json`
Expected: `[]`

- [ ] **Step 2: Write ADR-001**

Write exactly this content to `templates/.agent-context/decisions.json`:

```json
[
  {
    "id": "ADR-001",
    "title": "Claude Code Native Extension Deferred",
    "date": "2026-04-22",
    "status": "decided",
    "context": "Claude Code offers native features that overlap with manual patterns in this framework: .claude/rules/*.md with paths: frontmatter, SessionStart hooks, and skill paths: for glob-triggered auto-activation. These would yield meaningful performance gains within Claude Code.",
    "decision": "The Native Extension is deferred. The Agent-Context framework is deliberately agent-agnostic, working in Claude Code, Cursor, GitHub Copilot, Gemini CLI, and any agent that reads AGENTS.md or CLAUDE.md. Plugin-installed agents (agents@lx-wnk) cannot use hooks or mcpServers, which would create divergent behavior between the main Claude agent and plugin agents within Claude Code itself.",
    "consequences": "No Claude-specific optimizations in the core framework. If a Claude-specific opt-in overlay layer is introduced in the future, revisit this decision. At that point: .claude/rules/*.md should mirror Layer 3 routing (not replace it), and hooks should be additive enhancements only.",
    "references": [
      "code.claude.com/docs/en/hooks",
      "code.claude.com/docs/en/skills",
      "Plugin agents cannot use hooks, mcpServers, or permissionMode (Claude Code docs, 2026-04-22)"
    ]
  }
]
```

- [ ] **Step 3: Verify JSON is valid**

Run: `python3 -c "import json; json.load(open('templates/.agent-context/decisions.json')); print('valid')"`
Expected: `valid`

- [ ] **Step 4: Format**

Run: `npm run prettier`
Expected: All files pass

- [ ] **Step 5: Commit**

```bash
git add templates/.agent-context/decisions.json
git commit -m "docs: add ADR-001 (Claude Code Native Extension deferred) to decisions template"
```

---

### Task 7: Setup-Prompt — All Enhancements

This task modifies `.prompts/setup-prompt.md` in four sequential sub-tasks. Each sub-task adds one independent section or modifies one existing section.

**Files:**

- Modify: `.prompts/setup-prompt.md`

#### Sub-task 7a: Add Knowledge Decision Logic Section

- [ ] **Step 1: Locate the insertion point**

Run: `grep -n "UPDATE Mode: Done" .prompts/setup-prompt.md`
Expected: a line number (e.g., `88:## UPDATE Mode: Done`)

- [ ] **Step 2: Insert Knowledge Decision Logic before "UPDATE Mode: Done"**

Find this line in `.prompts/setup-prompt.md`:

```markdown
## UPDATE Mode: Done
```

Insert the following block **immediately before** it:

```markdown
## Knowledge Decision Logic

Used during Phase S2 (SETUP) and Step 7 (UPDATE) when processing discovered knowledge sources.

### Auto-Decision (no user input required)

Apply automatically when confidence ≥ 0.8:

| Signal                                                     | Action                                        |
| ---------------------------------------------------------- | --------------------------------------------- |
| Size <30 lines AND maps cleanly to one layer               | Auto-route to target layer, no question       |
| Size >100 lines OR file has a table of contents            | Auto → add to `knowledge-map.md` as reference |
| Existing `setup-decisions.json` entry with matching SHA256 | Reuse previous decision silently              |

### Requires Ack/Nack

Ask the user when:

- Confidence <0.8 OR content spans multiple layer categories
- Two sources contain contradicting information about the same topic
- A structured knowledge folder is discovered for the first time
- Size is 30–100 lines AND category is ambiguous

### Claude Code Interactive Mode

Detected when `.claude/settings.json` exists and the session is interactive (not headless/CI).

Batch all pending Ack/Nack decisions into a single message:
```

I found the following — please confirm:

1. docs/architecture.md → reference in knowledge-map (287 lines, structured) [Ack/Nack]
2. docs/api-guide.md → reference in knowledge-map (412 lines, has TOC) [Ack/Nack]
3. CONTRIBUTING.md → consolidate into layer2 (18 lines, conventions) [Ack/Nack]

````

High-confidence auto-decisions are listed in the summary only — not asked.

### Plan-File Mode (other agents / CI / headless)

When not in Claude Code interactive mode, write `.agent-context/setup-plan.md` before executing:

```markdown
# Setup Plan — YYYY-MM-DD

| # | Source | Action | Confidence | Status |
|---|--------|--------|------------|--------|
| 1 | docs/architecture.md | reference | 0.91 | ✅ auto |
| 2 | CONTRIBUTING.md | consolidate | 0.85 | ✅ auto |
| 3 | layer2: conflict rule A vs B | keep rule A | 0.55 | ⏳ review |
````

User edits the Status column and re-runs the prompt to execute.

### Decision Manifest

After all decisions are made, write/update `.agent-context/setup-decisions.json`:

```json
{
  "docs/architecture.md": {
    "action": "reference",
    "sha256": "<sha256-of-file-contents>",
    "decided_at": "YYYY-MM-DD",
    "source": "user-ack"
  }
}
```

Compute SHA256 with `sha256sum <file>` (Linux/Mac) or equivalent. Use today's date for `decided_at`.

````

- [ ] **Step 3: Verify insertion**

Run: `grep -n "Knowledge Decision Logic" .prompts/setup-prompt.md`
Expected: a line number

- [ ] **Step 4: Format**

Run: `npm run prettier`
Expected: All files pass

#### Sub-task 7b: Expand Phase S2 Discovery to All Knowledge Sources

- [ ] **Step 5: Locate Subagent 1 in Phase S2**

Run: `grep -n "Subagent 1: Documentation Scanner" .prompts/setup-prompt.md`
Expected: a line number

- [ ] **Step 6: Replace Subagent 1 scope**

Find this block in `.prompts/setup-prompt.md`:

```markdown
#### Subagent 1: Documentation Scanner

Scan for existing documentation files and summarize their content:

- `CLAUDE.md`, `AGENTS.md`, `README.md`, `CONTRIBUTING.md`
- `.claude/rules/*.md`
- `skills-lock.json`

Output: list of files found with summary of content per file.
````

Replace with:

````markdown
#### Subagent 1: Documentation & Knowledge Scanner

Scan for all existing documentation and structured knowledge sources:

- Root-level markdown files: `CLAUDE.md`, `AGENTS.md`, `README.md`, `CONTRIBUTING.md`, `CHANGELOG.md`
- `.claude/rules/*.md`, `skills-lock.json`
- Any folder containing 3+ markdown or structured-data files (YAML, JSON, OpenAPI):
  `docs/`, `architecture/`, `wiki/`, `api/`, `specs/`, `rfcs/`, `decisions/`, or similarly named directories

For each source found, output one structured finding:

```json
{
  "source": "<relative-path>",
  "size_lines": <line-count>,
  "topic": "<inferred topic>",
  "category_guess": "consolidate|reference|ignore",
  "confidence": <0.0-1.0>,
  "recommended_action": "consolidate|reference|ignore",
  "sha256": "<sha256-of-file>"
}
```
````

Apply Knowledge Decision Logic rules to determine `recommended_action` and `confidence`.

````

- [ ] **Step 7: Verify replacement**

Run: `grep -n "structured-data files" .prompts/setup-prompt.md`
Expected: a line number

#### Sub-task 7c: Add knowledge-map.md Creation to Phase S4

- [ ] **Step 8: Locate Phase S4 insertion point**

Run: `grep -n "Phase S4: Fill Layers" .prompts/setup-prompt.md`
Expected: a line number

- [ ] **Step 9: Add knowledge-map creation step at end of Phase S4**

Find this line in `.prompts/setup-prompt.md`:

```markdown
Each fact in exactly ONE place. No duplicates.
````

Add the following block **after** that line (after the blank line that follows it):

```markdown
#### knowledge-map.md

After filling all layers, create or update `.agent-context/knowledge-map.md`:

1. For every source from Subagent 1 with `recommended_action = "reference"` (after Ack/Nack decisions):
   - Add a row to **Knowledge Sources** table: source path, inferred topic, format, sha256, today's date
   - If a clear task type can be determined: add a row to **Task Routing** table
   - Otherwise: leave Task Routing for the user to fill (add a `<!-- TODO -->` comment)
2. Write/update `.agent-context/setup-decisions.json` with all decisions (auto + user-confirmed)

Do not modify any source file — the map is a pointer index only.
```

- [ ] **Step 10: Verify insertion**

Run: `grep -n "knowledge-map.md" .prompts/setup-prompt.md | head -5`
Expected: multiple lines including the new section

#### Sub-task 7d: Add UPDATE Step 7 — Knowledge Re-Sync

- [ ] **Step 11: Locate "UPDATE Mode: Done" block**

Run: `grep -n "UPDATE mode, skip all remaining" .prompts/setup-prompt.md`
Expected: a line number

- [ ] **Step 12: Insert Step 7 before the UPDATE Done block**

Find this block in `.prompts/setup-prompt.md`:

```markdown
## UPDATE Mode: Done

If in UPDATE mode, skip all remaining phases. Return `ok: true` with a brief summary
```

Insert the following block **immediately before** it:

```markdown
## Step 7: Knowledge Re-Sync (UPDATE mode)

After updating shared files (Steps 1–6), re-synchronize all project knowledge:

### 7a: Consolidated Fact Inventory

Launch parallel subagents (same as SETUP Phase S2) to scan:

- Existing `.agent-context/` (all layers, memory/, decisions.json, skills/)
- All root-level `*.md` files
- Any folder containing 3+ markdown or structured-data files

Check `.agent-context/setup-decisions.json` for existing decisions — skip sources with matching SHA256.

For new or changed sources: apply Knowledge Decision Logic (Ack/Nack or plan-file).

### 7b: Routing & Restructuring (additive-only)

Route facts to their targets — **additive only, never overwrite existing content**:

| Fact Type                   | Target                   | Rule                                    |
| --------------------------- | ------------------------ | --------------------------------------- |
| Project-wide convention     | `layer2-project-core.md` | Append if keyword not already present   |
| Domain-specific fact        | `memory/<domain>.md`     | Append if keyword not already present   |
| Heavy reference (>30 lines) | `skills/<reference>.md`  | Create if skill does not exist          |
| Gotcha / lesson             | `memory/lessons.md`      | Append with today's date + TTL          |
| Architecture decision       | `decisions.json`         | Append to JSON array if id not present  |
| External knowledge pointer  | `knowledge-map.md`       | Append row if source not already listed |

Keyword check: search target file for 2–3 key terms from the fact. If found → skip. If not found → append.

### 7c: Global Integrity Check

For each fact/finding collected in 7a:

1. Search for its 2–3 key terms across all `.agent-context/` files and `knowledge-map.md`
2. If no match found → list as missing
3. If any facts are missing: report them to the user, do NOT commit — ask how to resolve
4. If all facts are accounted for → proceed

### 7d: knowledge-map.md Update

For each source with `action = "reference"`:

- Update SHA256 and Last Verified if the file has changed
- Add any new sources discovered since last run
- Remove entries for sources that no longer exist

Update `.agent-context/setup-decisions.json` with all new decisions.
```

- [ ] **Step 13: Verify insertion**

Run: `grep -n "Step 7: Knowledge Re-Sync" .prompts/setup-prompt.md`
Expected: a line number

#### Sub-task 7e: Add Token Budget Audit to Phase S7

- [ ] **Step 14: Locate Phase S7 Verification section**

Run: `grep -n "wc -l AGENTS.md" .prompts/setup-prompt.md`
Expected: a line number

- [ ] **Step 15: Add token budget audit after existing line-count checks**

Find this block in `.prompts/setup-prompt.md` (existing verification step 4 and 5):

```markdown
4. `wc -l .agent-context/layer*.md` — each < 50 lines
5. Check `.agent-context/memory/*.md` line counts — domain stubs < 15 lines each (skip `index.md` and `log.md`)
```

Replace with:

```markdown
4. `wc -l .agent-context/layer*.md` — each < 50 lines
5. Check `.agent-context/memory/*.md` line counts — domain stubs < 15 lines each (skip `index.md` and `log.md`)
6. **Token Budget Audit** — run `wc -l .agent-context/layer*.md .agent-context/knowledge-map.md .agent-context/memory/*.md` and report:
   - Layer files ≥ 50 lines: flag as bloated
   - `knowledge-map.md` ≥ 100 lines: flag for cleanup
   - Memory files ≥ 500 lines: flag as skill graduation candidate
   - Include the audit table in the summary output (✅ / ⚠️ per file)
```

- [ ] **Step 16: Format**

Run: `npm run prettier`
Expected: All files pass

- [ ] **Step 17: Verify all sub-task changes are present**

```bash
grep -c "Knowledge Decision Logic" .prompts/setup-prompt.md
grep -c "structured-data files" .prompts/setup-prompt.md
grep -c "knowledge-map.md" .prompts/setup-prompt.md
grep -c "Step 7: Knowledge Re-Sync" .prompts/setup-prompt.md
grep -c "Token Budget Audit" .prompts/setup-prompt.md
```

Expected: each command returns `1` or more

- [ ] **Step 18: Commit**

```bash
git add .prompts/setup-prompt.md
git commit -m "feat: enhance setup-prompt with discovery expansion, knowledge re-sync, Ack/Nack UX, and token audit"
```

---

### Task 8: README Update

**Files:**

- Modify: `README.md`

- [ ] **Step 1: Add knowledge-map.md and setup-decisions.json to the installed file structure**

In `README.md`, find the code block showing `.agent-context/` directory structure (the one listing `decisions.json`, `memory-review-prompt.md`, etc.).

Add these two lines after `decisions.json`:

```
    ├── knowledge-map.md                   ← Universal knowledge pointer index (auto-maintained)
    ├── setup-decisions.json               ← Decision manifest for idempotent re-runs
```

- [ ] **Step 2: Update Key Principles section**

In `README.md`, locate the `## Key Principles` section. After the existing three principles (`1. "Can the agent discover this..."`, `2. Narrowest fitting scope`, `3. Stubs + Skills pattern`), add:

```markdown
### 4. Full knowledge re-sync on every update

Updates are not file patches. Every `setup-prompt.md` run (SETUP or UPDATE) performs a full knowledge re-synchronization: scan all knowledge sources (agent-context, source code, docs, architecture files), build a consolidated fact inventory, route facts to optimal targets, and verify global integrity. No fact is lost — it may move, but it must be traceable somewhere.

### 5. Self-maintaining knowledge map

`knowledge-map.md` is the single routing index for all project knowledge — both internal (agent-context) and external (docs, architecture files, API specs). Agents update it immediately when sources change, following the same non-negotiable rule as `lessons.md` updates. The map always reflects current project reality.
```

- [ ] **Step 3: Update the Updates section to reflect new flow**

In `README.md`, locate the `## Updates` section. Find the sentence describing what the update does and replace it with:

```markdown
After creating a [GitHub Release](https://github.com/lx-wnk/Agent-Context/releases), projects update automatically: on the next session start, the agent fetches the setup prompt from remote (UPDATE mode), checks the Releases API, detects the version difference, downloads the release, and overwrites the shared files. The update then performs a full knowledge re-synchronization — scanning all project knowledge sources, routing new facts to optimal targets, and verifying nothing was lost. Project-owned files receive improvements additively; content is never deleted. If the API is unreachable, the agent continues silently.
```

- [ ] **Step 4: Add new Research & References entries**

In `README.md`, locate `### Core Papers` under `## Research & References`. Add these entries:

```markdown
- [Tokalator: Measuring Token Cost of Instruction Files (arxiv 2604.08290)](https://arxiv.org/abs/2604.08290) — Finds 21.2% of context tokens come from unintentionally-included files; a single instruction file adds ~4,200 tokens per prompt silently
- [On the Impact of AGENTS.md Files (arxiv 2601.20404)](https://arxiv.org/abs/2601.20404) — Empirical measurement: AGENTS.md presence yields 16.58% median runtime reduction and ~20% output-token reduction when content is lean
- [SSGM: Structured Memory Governance (arxiv 2603.11768)](https://arxiv.org/abs/2603.11768) — TTL-tiered memory with semantic relevance × time-decay scoring; basis for the TTL metadata system
- [MemoryGraft: Persistent Memory Poisoning (arxiv 2512.16962)](https://arxiv.org/abs/2512.16962) — Poisoned skill/memory files can corrupt 87% of downstream agent decisions within 4 hours; motivates source attribution and trust scoring
- [A-MemGuard: Consensus Validation Defense (OpenReview)](https://openreview.net/forum?id=fVxfCEv8xG) — Dual-memory + consensus validation cuts poisoning attack success by 95%+
```

Under `### Engineering & Best Practices`, add:

```markdown
- [llms.txt standard](https://llmstxt.org/) — Curated pointer-index file for LLM navigation of large doc sets without modification; basis for the knowledge-map.md pattern
- [Terraform plan/apply](https://developer.hashicorp.com/terraform/cli/commands/plan) — Plan-before-execute UX pattern; basis for setup-plan.md and Ack/Nack flow
- [Nx migrations.json](https://nx.dev/docs/reference/nx/migrations) — Persisted decision manifest for idempotent re-runs; basis for setup-decisions.json
- [Copier: Template Updating](https://copier.readthedocs.io/en/stable/updating/) — Three-way merge approach for project-owned files (evaluated and adapted — conflict markers replaced with additive-only + integrity check)
```

- [ ] **Step 5: Verify additions**

```bash
grep -c "knowledge-map.md" README.md
grep -c "setup-decisions.json" README.md
grep -c "Tokalator" README.md
grep -c "MemoryGraft" README.md
grep -c "llms.txt" README.md
```

Expected: each returns `1` or more

- [ ] **Step 6: Format**

Run: `npm run prettier`
Expected: All files pass

- [ ] **Step 7: Commit**

```bash
git add README.md
git commit -m "docs: update README with knowledge-map, new principles, and research references"
```

---

### Task 9: Final Verification

**Files:** Read-only

- [ ] **Step 1: Run Prettier on all files**

Run: `npm run prettier`
Expected: All files pass with zero errors

- [ ] **Step 2: Verify all shared context files have the SHARED FILE header**

Run: `grep -rL "SHARED FILE" context/*.md .prompts/memory-review-prompt.md .prompts/decision-review-prompt.md`
Expected: no output (all shared files have the header; setup-prompt.md is excluded — it is not a shared context file)

- [ ] **Step 3: Verify line counts are within limits**

```bash
wc -l context/layer0-agent-workflow.md
wc -l context/base-principles.md
wc -l templates/.agent-context/layer*.md
wc -l templates/.agent-context/knowledge-map.md
wc -l templates/.agent-context/memory/*.md
```

Expected:

- `context/layer0-agent-workflow.md` < 145 lines
- `context/base-principles.md` < 40 lines
- Each `layer*.md` template < 35 lines
- `knowledge-map.md` template < 30 lines
- Memory templates < 10 lines each

- [ ] **Step 4: Verify new files exist**

```bash
ls templates/.agent-context/knowledge-map.md
grep -c "ADR-001" templates/.agent-context/decisions.json
grep -c "Knowledge Decision Logic" .prompts/setup-prompt.md
grep -c "Step 7: Knowledge Re-Sync" .prompts/setup-prompt.md
grep -c "Knowledge Map Triggers" context/layer0-agent-workflow.md
```

Expected: each returns `1` or more (no errors)

- [ ] **Step 5: Verify no duplicate content across shared files**

Run: `grep -h "Knowledge Map" context/*.md | sort | uniq -d`
Expected: no output (no duplicates)

- [ ] **Step 6: Final commit if any formatting fixes were applied**

```bash
git status
# If any files changed:
git add -A
git commit -m "chore: formatting fixes after agent-context optimizations"
```

- [ ] **Step 7: Push branch**

```bash
git push -u origin feat/agent-context-optimizations
```
