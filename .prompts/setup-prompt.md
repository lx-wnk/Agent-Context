# Agent Context — Setup & Update

> **Usage:** This prompt is fetched remotely from the latest release tag — it is NOT deployed locally to target projects.
> It auto-detects SETUP vs. UPDATE mode and handles both flows.

## Global Constraint: Knowledge Map Sources

**This rule applies everywhere in this prompt — no exceptions.**

A file may only appear in `knowledge-map.md` if ALL of the following are true:

1. It is tracked or staged by git, or untracked but not gitignored (`git ls-files --cached --others --exclude-standard`)
2. It contains project knowledge — documentation, architecture decisions, conventions, domain facts
3. It is NOT agent-managed infrastructure (skills, agents, rules, plugins, or any tooling the agent self-indexes)

## File Classification: AI Docs vs Real Docs

This classification is used in UPDATE mode (Migration Cleanup step) and SETUP mode (cleanup and verification phases).

### AI Docs (migratable — safe to delete/replace)

Built-in directories and files always treated as AI docs:

- `.ai/`
- `.agent-context/` (only migrate away from it when replacing with a newer structure — never delete the current destination)
- `AGENTS.md`
- `CLAUDE.md` (root)
- `GEMINI.md` (root)
- `.claude/CLAUDE.md`
- `.cursorrules`
- `.cursor/rules/`
- `.github/copilot-instructions.md`

If the prompt was invoked with an `--ai-dirs` argument (injected by `install.sh`), those directories extend this built-in list.

### Real Docs (never modify, move, or delete)

Any file **not** in an AI-managed directory. When a file's classification is uncertain (e.g. a root-level `makefile`, a custom config), default to **Real Doc** (conservative). Add it to the `UNRESOLVED` list in the post-migration report.

---

## Step 0: Interactive Mode Detection (MUST run first, before anything else)

**This is the very first action. Run it immediately before reading or acting on any other step.**

Run this bash command and store the result:

```bash
bash -c '[ -t 0 ] && echo interactive || echo headless'
```

Then check the environment:

```bash
echo "${CI:-unset}"
```

Set `INTERACTIVE_MODE=true` if the bash output was `interactive` AND `CI` is not `true`. Otherwise set `INTERACTIVE_MODE=false`.

In non-interactive mode (`INTERACTIVE_MODE=false`), write progress to `.agent-context/setup.log` at the start of each step via a Bash tool call:

```bash
echo "[agent-context] Step N/7: <description>" >> .agent-context/setup.log
```

Create the log file at the very start (before Step 1) so `tail -f` can attach immediately:

```bash
mkdir -p .agent-context && > .agent-context/setup.log
```

Example log entries:

```
[agent-context] Mode: UPDATE (0.3.0 → 0.5.0)
[agent-context] Step 1/5: Checking version...
[agent-context] Step 2/5: Installing shared files...
[agent-context] Step 3/5: Processing template files...
[agent-context] Step 4/5: Compatibility check...
[agent-context] Step 5/5: Knowledge re-sync...
[agent-context] Done.
```

Write `[agent-context] Done.` as the final log line — not as a numbered step.

---

## Mode Detection

1. If `.agent-context/.agent-context-version` exists → **UPDATE** mode
2. Otherwise → **SETUP** mode

If `INTERACTIVE_MODE=true`, announce the detected mode. In non-interactive mode, do NOT log the mode here — log it in Step 1 once the target version is known.

---

## Step 1: Version Selection

1. Read `.agent-context/.agent-context-version` (default `0.0.0` if missing)
2. Fetch the release list from `https://api.github.com/repos/lx-wnk/Agent-Context/releases`
3. If the fetch fails or returns no releases:
   - **SETUP:** abort with an informative message — version selection is required
   - **UPDATE:** inform the user that releases could not be checked, skip to Step 4
4. **UPDATE only:** If the current version already matches the latest stable release → inform the user and skip to Step 4
5. If `INTERACTIVE_MODE=false`: skip the version prompt entirely, use the latest stable release automatically — do not present a table or ask any question. Then log the mode and target version:
   ```bash
   echo "[agent-context] Mode: UPDATE (0.3.0 → 0.5.0)" >> .agent-context/setup.log
   # or for SETUP:
   echo "[agent-context] Mode: SETUP (installing 0.5.0)" >> .agent-context/setup.log
   ```
6. Present the available versions to the user (mark which is current, which is latest stable, and label pre-releases as `(pre-release)`)
7. Ask the user which version to install — default is `latest stable`
8. If the user declines → skip to Step 4
9. Store the selected version tag (e.g. `v0.5.0`) — it is used to build raw file URLs in Steps 2 and 3.

## Step 2: Install Shared Files

Fetch each shared file directly from GitHub raw content — no tarball or temp directory needed.

Base URL: `https://raw.githubusercontent.com/lx-wnk/Agent-Context/<tag>/`

| Source path                          | Destination                                |
| ------------------------------------ | ------------------------------------------ |
| `context/agent-startup.md`           | `.agent-context/agent-startup.md`          |
| `context/layer0-agent-workflow.md`   | `.agent-context/layer0-agent-workflow.md`  |
| `context/base-principles.md`         | `.agent-context/base-principles.md`        |
| `.prompts/decision-review-prompt.md` | `.agent-context/decision-review-prompt.md` |
| `.prompts/memory-review-prompt.md`   | `.agent-context/memory-review-prompt.md`   |

Fetch each file with:

```bash
curl -fsSL "https://raw.githubusercontent.com/lx-wnk/Agent-Context/<tag>/<source-path>" \
    -o "<destination>"
```

Write the new version to `.agent-context/.agent-context-version`.

## Step 3: Template Files

List the contents of the `templates/` directory via the GitHub Contents API:

```bash
curl -fsSL "https://api.github.com/repos/lx-wnk/Agent-Context/contents/templates?ref=<tag>"
```

This returns a recursive file listing. For each file:

- Fetch it from `https://raw.githubusercontent.com/lx-wnk/Agent-Context/<tag>/templates/<relative-path>`
- If the destination file does **NOT** exist → write it
- If the destination file already exists → skip (project-owned, never overwrite)

This ensures both first-time setup and updates receive new template files introduced in later versions.

## Step 4: Compatibility Check

After updating shared files, check project-owned files for known outdated patterns:

| Pattern found in project-owned file     | Suggested update                                            |
| --------------------------------------- | ----------------------------------------------------------- |
| `memory/decisions.md` as routing target | Change to `decisions.json` (structured format since v0.2.0) |

If any patterns are found, include them in the response as suggestions — never auto-fix project-owned files.

### CLAUDE.md Bootstrap Check (auto-fix exception)

CLAUDE.md is the agent's entry point and must contain **only** the bootstrap pointer. All project knowledge belongs in the layer files — content left in CLAUDE.md bypasses the layer system and causes duplication.

Check both locations:

1. `.claude/CLAUDE.md`
2. `CLAUDE.md` (project root)

**For each found location:**

- **Has content beyond `@AGENTS.md`?** → Extract substantive content (rules, conventions, architecture notes) and apply Knowledge Decision Logic to route each item to the correct layer file (same rules as Step 5). Do NOT attempt to write or overwrite CLAUDE.md — `install.sh` replaces it with the bootstrap pointer after this agent exits.
- **Contains only `@AGENTS.md` (or equivalent)?** → skip, nothing to migrate

---

## Knowledge Decision Logic

Used during Phase S2 (SETUP) and Step 5 (UPDATE) when processing discovered knowledge sources.

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

Detected when `.claude/settings.json` exists **and** neither of the following signals is present: `CI=true` environment variable set, or the prompt was invoked with the `-p` flag (non-interactive / headless mode). If either signal is present, fall back to Plan-File Mode.

Batch all pending Ack/Nack decisions into a single message:

```
I found the following — please confirm:
1. docs/architecture.md → reference in knowledge-map (287 lines, structured)  [Ack/Nack]
2. docs/api-guide.md    → reference in knowledge-map (412 lines, has TOC)     [Ack/Nack]
3. CONTRIBUTING.md      → consolidate into layer2 (18 lines, conventions)     [Ack/Nack]
```

High-confidence auto-decisions are listed in the summary only — not asked.

### Plan-File Mode (other agents / CI / headless)

When not in Claude Code interactive mode, write `.agent-context/setup-plan.md` before executing:

```markdown
# Setup Plan — YYYY-MM-DD

| #   | Source                     | Action      | Confidence | Status    |
| --- | -------------------------- | ----------- | ---------- | --------- |
| 1   | docs/architecture.md       | reference   | 0.91       | ✅ auto   |
| 2   | CONTRIBUTING.md            | consolidate | 0.85       | ✅ auto   |
| 3   | src/: conflict rule A vs B | keep rule A | 0.55       | ⏳ review |
```

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

## Step 4.5: Migration Cleanup (UPDATE mode only)

Run this step unconditionally in UPDATE mode — it self-skips in 4.5a if no old AI directories are found.

### 4.5a: Detect old AI directories

Check whether any built-in AI-doc directories (other than `.agent-context/` itself) exist:

```bash
for dir in .ai .cursor/rules; do [ -d "$dir" ] && echo "FOUND: $dir"; done
for f in AGENTS.md CLAUDE.md GEMINI.md .cursorrules .claude/CLAUDE.md .github/copilot-instructions.md; do [ -f "$f" ] && echo "FOUND: $f"; done
```

If none found → skip to Step 5.

### 4.5b: Classify all files in old AI directories

For each found old directory/file:

1. Apply the **File Classification** rules from the top of this prompt.
2. Any file that cannot be classified confidently → add to `UNRESOLVED` list, do NOT touch it (log command in 4.5d).
3. All confirmed AI-doc files → proceed to deletion.

### 4.5c: Delete old AI directories

Delete only confirmed AI-doc directories and files:

```bash
# Example — adapt to what was found in 4.5a:
rm -rf .ai/          # directory
rm .cursorrules      # flat file
```

Do NOT delete Real Docs. Do NOT carry over any file contents or path references to the new structure.
Do NOT delete `.agent-context/` itself — it is the destination of this migration.

### 4.5d: Mark UNRESOLVED files

If any files could not be classified, store them for the post-migration report:

```bash
# One line per unresolved file:
echo "[agent-context] UNRESOLVED: <path/to/file>" >> .agent-context/setup.log
```

If nothing is unresolved, skip this step.

---

## Step 5: Knowledge Re-Sync (UPDATE mode)

After updating shared files (Steps 1–6), re-synchronize all project knowledge:

### 7a: Consolidated Fact Inventory

Apply the **Global Constraint: Knowledge Map Sources** — run `git ls-files --cached --others --exclude-standard` and only consider files in that output.

Launch parallel subagents (same as SETUP Phase S2 Subagent 1) to scan within that set:

- Existing `.agent-context/` (all layers, memory/, decisions.json, skills/)
- All root-level `*.md` files
- Any folder containing 3+ markdown or structured-data files

Check `.agent-context/setup-decisions.json` for existing decisions — skip sources with matching SHA256.

For new or changed sources: apply Knowledge Decision Logic (Ack/Nack or plan-file).

### 7b: Routing & Restructuring (additive-only)

Route facts to their targets — **additive only, never overwrite existing content**:

| Fact Type                   | Target                   | Rule                                                           |
| --------------------------- | ------------------------ | -------------------------------------------------------------- |
| Project-wide convention     | `layer2-project-core.md` | Append if keyword not already present                          |
| Domain-specific fact        | `memory/<domain>.md`     | Append if keyword not already present                          |
| Heavy reference (>30 lines) | `skills/<reference>.md`  | Create if skill does not exist                                 |
| Gotcha / lesson             | `memory/lessons.md`      | Append with today's date, `ttl:90d source:discovered conf:med` |
| Architecture decision       | `decisions.json`         | Append to JSON array if id not present                         |
| External knowledge pointer  | `knowledge-map.md`       | Append row if source not already listed                        |

Keyword check: search target file for 2–3 key terms from the fact. If found → skip. If not found → append.

### 7c: Global Integrity Check

For each fact/finding collected in 7a:

1. Search for its 2–3 key terms across all `.agent-context/` files and `knowledge-map.md`
2. If no match found → list as missing
3. If any facts are missing: report them to the user, do NOT commit — ask how to resolve
4. If all facts are accounted for → proceed

### 7d: knowledge-map.md Update

**If Migration Cleanup (Step 4.5) deleted any old AI directories:**

Do NOT update the existing `knowledge-map.md` and `setup-decisions.json` incrementally — regenerate them from scratch:

1. Delete (or empty) `.agent-context/knowledge-map.md` and `.agent-context/setup-decisions.json`
2. Scan all Real Docs currently in the repo (apply **Global Constraint: Knowledge Map Sources**)
3. Compute fresh SHA256 for each source: `sha256sum <file>`
4. Rebuild `knowledge-map.md` routing table and Knowledge Sources table from scratch
5. Rebuild `setup-decisions.json` with only currently-existing files and their current SHA256 values
6. Scan `.agent-context/skills/` and rebuild `skills/index.md` from what actually exists there

No old paths. No stale hashes. No entries for files that no longer exist.

**If no Migration Cleanup ran (normal update):**

For each source with `action = "reference"`:

- Update SHA256 and Last Verified if the file has changed
- Add any new sources discovered since last run
- Remove entries for sources that no longer exist

Update `.agent-context/setup-decisions.json` with all new decisions.

### 7e: Token Budget Audit

Run `wc -l .agent-context/layer*.md .agent-context/knowledge-map.md .agent-context/memory/*.md` and report:

- Layer files ≥ 50 lines: flag as bloated
- `knowledge-map.md` ≥ 100 lines: flag for cleanup
- Memory files ≥ 500 lines: flag as skill graduation candidate
- Include the audit table in the summary output (✅ / ⚠️ per file)

## UPDATE Mode: Done

If in UPDATE mode, skip all remaining phases. Return `ok: true` with a brief summary (e.g. "Updated 0.1.1 → 0.1.2" or "Already up to date" or "User declined update"). Always return `ok: true` — even on failure.

Always output the following at the very end of the UPDATE run. Omit the `UNRESOLVED` block if the list is empty:

```
Migration complete.

UNRESOLVED (could not be classified — review manually):
  - <file1>
  - <file2>

If anything didn't go as expected, resume this session with:
  claude --resume $CLAUDE_SESSION_ID
```

`$CLAUDE_SESSION_ID` is available as an environment variable during the agent run.

---

## SETUP Mode: Additional Phases

The following phases run **only** during first-time setup.

### Phase S1: Project Structure

Create the directory structure and Claude Code integration.

#### Directory structure

```
File                                     Ownership
─────────────────────────────────────    ──────────────────────────────────────
AGENTS.md                                PROJECT — customize freely
.claude/CLAUDE.md                        Bootstrap pointer → @AGENTS.md
.claude/settings.json                    Settings file (created if missing, never overwritten)
.agent-context/
  agent-startup.md                       🔒 SHARED — do NOT modify (auto-updated)
  layer0-agent-workflow.md               🔒 SHARED — do NOT modify (auto-updated)
  base-principles.md                     🔒 SHARED — do NOT modify (auto-updated)
  .agent-context-version                 🔒 SHARED — written by setup/update
  memory-review-prompt.md               🔒 SHARED — do NOT modify (auto-updated)
  decision-review-prompt.md              🔒 SHARED — do NOT modify (auto-updated)
  knowledge-map.md                       PROJECT — maintained by agent, never recreate from template
  setup-decisions.json                   PROJECT — maintained by agent, never recreate from template
  decisions.json                         PROJECT — structured decisions (auto-reviewed)
  layer1-bootstrap.md                    PROJECT — customize freely
  layer2-project-core.md                 PROJECT — customize freely
  layer3-guidebook.md                    PROJECT — customize freely
  skills/
    index.md                             PROJECT — skill registry
  memory/                                PROJECT — customize freely
    decisions.md                         Legacy stub (migrated to decisions.json)
    index.md                             Memory file catalog
    lessons.md
    log.md                               Append-only activity log
    people.md
    preferences.md
    todo.md
    user.md
```

#### Ownership rules

**🔒 SHARED files** are overwritten on every auto-update. Never add project-specific content to them — it will be lost.
Put project-specific workflow rules in `layer2-project-core.md`, task routing in `layer3-guidebook.md`.

**PROJECT files** are created once from templates and never overwritten. All project customization goes here.

### Phase S2: Discovery (Parallel Subagent Scan)

Launch **6 parallel subagents** to scan the project. All subagents are **mandatory** — every one MUST execute, none may be skipped. Running them in parallel maximizes speed.

#### Subagent 1: Documentation & Knowledge Scanner

Apply the **Global Constraint: Knowledge Map Sources** — run `git ls-files --cached --others --exclude-standard` and only consider files in that output.

Scan for all existing documentation and structured knowledge sources within that set:

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

Apply Knowledge Decision Logic rules to determine `recommended_action` and `confidence`.

#### Subagent 2: Project Identity & Stack

Determine project name and full tech stack from:

- `package.json`, `composer.json`, `go.mod`, `Cargo.toml`, `requirements.txt`, `pyproject.toml`
- Repo name or directory name as fallback

Output: project name, languages, frameworks, key dependencies.

#### Subagent 3: Infrastructure & Docker

Scan for container and infrastructure configuration:

- `docker-compose.yml` / `compose.yaml` — container names, ports, exec patterns
- `.env`, `.env.example` — `APP_URL`, `BASE_URL`, `SHOP_URL`, other domains

Output: container map, port map, domain list.

#### Subagent 4: CI/CD & Testing

Scan for CI pipelines and test configuration:

- `.github/workflows/`, `.gitlab-ci.yml`, `Jenkinsfile`
- `phpunit.xml`, `vitest.config.*`, `cypress.config.*`, `jest.config.*`

Output: CI platform, pipeline structure, test frameworks, test commands.

#### Subagent 5: Git Conventions

Analyze repository history and conventions:

- `git log --oneline -20` — commit message style
- Branch naming patterns, conventional commit config (`.commitlintrc`, etc.)

Output: commit convention, branch strategy.

#### Subagent 6: Skills

Check for existing skills infrastructure:

- `skills-lock.json` — locked skill definitions
- `.claude/skills/` — existing project skills

Output: whether skills-lock exists, list of existing skills.

#### Merge Results

Collect all subagent outputs. Document each finding with its target layer:

| Finding type             | Document in                       |
| ------------------------ | --------------------------------- |
| Project name, stack      | `layer1-bootstrap.md`             |
| Docker, domains          | `layer1-bootstrap.md`             |
| Conventions, CI, testing | `layer2-project-core.md`          |
| Skills, task routing     | `layer3-guidebook.md`             |
| Existing doc content     | Input for Phase S3 classification |

Only ask the user for values that no subagent could auto-detect.

### Phase S3: Content Classification

For every piece of existing documentation, apply the **"Can the agent discover this by reading the code?"** filter:

#### KEEP (not discoverable):

- Gotchas, quirks, hard-won lessons
- Conventions no linter enforces
- Non-obvious architectural decisions + rationale
- External system references (API endpoints, IDs, URLs)
- Docker/infra networking conventions
- CI pipeline structure, custom build steps
- Security constraints, forbidden patterns
- Business terminology, domain knowledge
- Workflow rules specific to this project (plan-first thresholds, verification requirements, task tracking conventions)
- Tool commands that aren't obvious from the codebase (e.g. `npx skills experimental_install`)

#### REMOVE (discoverable from code):

- Directory trees, file structure
- Entity/model field listings
- Route tables, service registrations
- Linter/formatter config details
- Function signatures, API surfaces
- Dependency lists
- README content duplicated into agent context

**Principle:** "Every line in context files = friction the agent can't resolve alone."

### Phase S3.5: Migration Audit (CRITICAL — prevents silent content loss)

> This phase is the safety net. Shared files (layer0, base-principles) define a **generic** workflow. Projects often have **project-specific** workflow rules that lived in the same files before migration. If you overwrite a shared file or remove "general" content, you MUST verify nothing project-specific was lost.

#### Step 1: Build a "before" inventory

Before overwriting any file, extract every distinct rule/instruction from the existing content. Create a checklist:

```
## Pre-Migration Content Inventory

### From existing layer0 (will be overwritten):
- [ ] Rule: "Enter plan mode for non-trivial tasks (3+ steps)"
- [ ] Rule: "Write plan to memory/todo.md"
- [ ] Rule: "Mark items complete as you go"
- [ ] ...

### From existing AGENTS.md quick rules (will be trimmed):
- [ ] Rule 1: "Pre-commit: make review"
- [ ] Rule 2: "Docker: all PHP in bo__shop"
- [ ] ...

### From sections being removed as "general knowledge":
- [ ] "Unit tests for all new implementations"
- [ ] "npx skills experimental_install when skills-lock.json exists"
- [ ] ...
```

#### Step 2: Classify each item

For each item, determine:

| Classification                                               | Action                                                                           |
| ------------------------------------------------------------ | -------------------------------------------------------------------------------- |
| **Covered by new shared files** (base-principles.md, layer0) | Mark as ✓ migrated — verify by reading the shared file and confirming it's there |
| **General LLM knowledge** (KISS, YAGNI, DRY, SOLID)          | Mark as ✓ removed intentionally                                                  |
| **Project-specific, NOT in shared files**                    | ⚠️ Must be relocated to a PROJECT-owned file                                     |

#### Step 3: Relocate orphaned content

Any item classified as "project-specific, NOT in shared files" must be placed in the appropriate project-owned file:

| Content type                                             | Target                                                  |
| -------------------------------------------------------- | ------------------------------------------------------- |
| Workflow rules (plan-first, verification, task tracking) | `layer2-project-core.md` → new "Workflow Rules" section |
| Tool commands (`npx skills`, custom scripts)             | `layer2-project-core.md` or `memory/commands.md`        |
| Testing requirements (unit test policy)                  | `layer2-project-core.md`                                |
| Domain conventions                                       | `memory/<domain>.md`                                    |

#### Step 4: Verify zero loss

After all relocations, go through the checklist and confirm every item has a ✓. If any item is unchecked, it's a gap — fix it before proceeding.

**Common traps to watch for:**

- The new shared `layer0` is much shorter than the old one — it only covers Skill Lookup, Memory Rules, and Self-Improvement. Old layer0 content like Plan-First, Subagent Strategy, Task Management, Verification must move to `layer2-project-core.md`
- `base-principles.md` says "present concrete options" but your project might have said "present up to 5 options" — keep the project-specific detail
- External skill installation commands (`npx skills experimental_install`) are project-specific, not covered by the shared layer0's "Skill Lookup" section
- "Unit tests for all new implementations" is a project policy, not general LLM knowledge

### Phase S4: Fill Layers & Migrate Content

Replace `TODO` placeholders with discovered + user-provided information:

- **`AGENTS.md`**: Project name, tech stack, Docker container, 3-5 quick rules
- **`layer1-bootstrap.md`**: Identity, Docker exec pattern, domains, excluded dirs
- **`layer2-project-core.md`**: Non-linter conventions, critical rules, testing strategy, commit convention, **workflow rules rescued from Phase S3.5**
- **`layer3-guidebook.md`**: Task-routing table, skills index, memory file index

For existing documentation found in Phase S2, route surviving content:

| Scope                       | Target                                 |
| --------------------------- | -------------------------------------- |
| General dev philosophy      | `layer2-project-core.md`               |
| Domain-specific convention  | `memory/<domain>.md`                   |
| Heavy reference (>30 lines) | `skills/<reference>.md`                |
| Gotcha / lesson             | `memory/lessons.md`                    |
| User/team info              | `memory/user.md` or `memory/people.md` |
| Agent behavior preference   | `memory/preferences.md`                |
| Architecture decision       | `decisions.json`                       |

Each fact in exactly ONE place. No duplicates.

#### CLAUDE.md Reduction

After routing all content from an existing `CLAUDE.md` to layer files, do NOT attempt to overwrite it — `install.sh` replaces it with the bootstrap pointer (`@AGENTS.md`) after this agent exits. The knowledge is already in the layers; the file swap is handled outside the agent.

#### knowledge-map.md

After filling all layers, create or update `.agent-context/knowledge-map.md`. Apply the **Global Constraint: Knowledge Map Sources** — only add entries for sources that satisfy all three conditions.

1. For every source from Subagent 1 with `recommended_action = "reference"` (after Ack/Nack decisions):
   - Add a row to **Knowledge Sources** table: source path, inferred topic, format, sha256, today's date
   - If a clear task type can be determined: add a row to **Task Routing** table
   - Otherwise: add a `<!-- TODO: add task type for this source -->` comment after the row
2. Write/update `.agent-context/setup-decisions.json` with all decisions (auto + user-confirmed)

Do not modify any source file — the map is a pointer index only.

**Important:** Do NOT create memory files for general programming principles (KISS, YAGNI, DRY, SOLID, Clean Code). LLMs already know these — adding them wastes context budget and reduces performance. Only store knowledge that is **specific to this project** and **not discoverable from the code**.

### Phase S5: Cleanup & Verification

**Cleanup:**

- Delete or empty migrated source files (`.claude/rules/*.md`, etc.)
- Verify `.agent-context/` is NOT in `.gitignore`

**Verification:**

1. `AGENTS.md` exists with identity and layer references
2. No `TODO` placeholders remain (except intentional ones)
3. `wc -l AGENTS.md` < 45 lines
4. Check `.agent-context/memory/*.md` line counts — domain stubs < 15 lines each (skip `index.md` and `log.md`)
5. **Token Budget Audit** — run `wc -l .agent-context/layer*.md .agent-context/knowledge-map.md .agent-context/memory/*.md` and report:
   - Layer files ≥ 50 lines: flag as bloated
   - `knowledge-map.md` ≥ 100 lines: flag for cleanup
   - Memory files ≥ 500 lines: flag as skill graduation candidate
   - Include the audit table in the summary output (✅ / ⚠️ per file)
6. No duplicated content across files
7. `.claude/CLAUDE.md` points to `@AGENTS.md`
8. **Migration audit checklist from Phase S3.5 is 100% checked off**
9. `.agent-context/memory/log.md` and `.agent-context/memory/index.md` exist
10. `.agent-context/memory-review-prompt.md` exists

**Summary:**

| Metric                             | Before | After |
| ---------------------------------- | ------ | ----- |
| Always-loaded lines                | X      | Y     |
| On-demand lines                    | 0      | Z     |
| Number of source files             | X      | —     |
| Number of target files (incl. map) | —      | Y     |
| `knowledge-map.md` entries         | —      | N     |
| Migration audit items              | N      | N ✓   |

Inform the user to restart their agent session for the new configuration to take effect.

Output the following at the very end. Omit the `UNRESOLVED` block if the list is empty:

```
Setup complete.

UNRESOLVED (could not be classified — review manually):
  - <file1>
  - <file2>

If anything didn't go as expected, resume this session with:
  claude --resume $CLAUDE_SESSION_ID
```

`$CLAUDE_SESSION_ID` is available as an environment variable during the agent run.

---

## Error Handling

- **Network failure** (API unreachable, tarball download fails):
  - **SETUP:** abort — cannot proceed without release files
  - **UPDATE:** skip update, keep existing files, return `ok: true`
- **Corrupted/incomplete archive**: Do NOT overwrite existing files with partial content. Skip update, return `ok: true`
- **File write failure**: Log which file failed, continue with remaining files
- **UPDATE mode** is best-effort — never block session start. **SETUP mode** should fail fast with clear messages.

## Constraints

- **Non-destructive:** Never overwrite project-owned files that already have content
- **Ask, don't guess:** If information cannot be auto-detected, ask the user
- **One fact, one place:** No duplication across files
- **No over-engineering:** Skip skills if total content < ~200 lines, skip memory stubs if domain < ~30 lines
- **Preserve knowledge:** Nothing gets deleted — it gets routed, filtered, or promoted to code
- **Audit before overwrite:** Always run Phase S3.5 before overwriting shared files in existing projects — the new shared files are generic and will silently drop project-specific workflow rules
