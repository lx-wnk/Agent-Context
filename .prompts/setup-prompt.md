# Agent Context — Setup & Update

> **Usage:** This prompt is fetched remotely from the latest release tag — it is NOT deployed locally to target projects.
> It auto-detects SETUP vs. UPDATE mode and handles both flows.

## Mode Detection

1. If `.agent-context/.agent-context-version` exists → **UPDATE** mode
2. Otherwise → **SETUP** mode

Announce the detected mode to the user before proceeding.

---

## Step 1: Version Selection

1. Read `.agent-context/.agent-context-version` (default `0.0.0` if missing)
2. Fetch the release list from `https://api.github.com/repos/lx-wnk/Agent-Context/releases`
3. If the fetch fails or returns no releases:
   - **SETUP:** abort with an informative message — version selection is required
   - **UPDATE:** inform the user that releases could not be checked, skip to Step 5
4. **UPDATE only:** If the current version already matches the latest stable release → inform the user and skip to Step 5
5. Present the available versions to the user (mark which is current, which is latest stable, and label pre-releases as
   `(pre-release)`)
6. Ask the user which version to install — default is `latest stable`
7. If the user declines → skip to Step 5
8. Fetch the selected release from `https://api.github.com/repos/lx-wnk/Agent-Context/releases/tags/v<version>` and use
   its `tarball_url`

## Step 2: Install Shared Files

1. Download the tarball from `tarball_url` and extract it to a temp directory
2. Copy these files from the extracted archive into `.agent-context/`:

| Source (in archive)                  | Destination                                |
| ------------------------------------ | ------------------------------------------ |
| `context/agent-startup.md`           | `.agent-context/agent-startup.md`          |
| `context/layer0-agent-workflow.md`   | `.agent-context/layer0-agent-workflow.md`  |
| `context/base-principles.md`         | `.agent-context/base-principles.md`        |
| `plugins.json`                       | `.agent-context/plugins.json`              |
| `.prompts/decision-review-prompt.md` | `.agent-context/decision-review-prompt.md` |
| `.prompts/memory-review-prompt.md`   | `.agent-context/memory-review-prompt.md`   |

3. Write the new version to `.agent-context/.agent-context-version`
4. Clean up the temp directory

## Step 3: Template Files

For each file in the archive's `templates/` directory:

- If the destination file does **NOT** exist → create it from the template
- If the destination file already exists → skip (project-owned, never overwrite)

This ensures both first-time setup and updates receive new template files introduced in later versions.

## Step 4: Agent Sync

Update shared agents (prefixed `ac-`) in both global and project-local locations. Only update locations where `ac-*`
agents already exist — do NOT install agents into a location that has none.

1. Check if the archive contains an `agents/` directory with `ac-*.md` files. If not, skip this step.
2. Check **both** agent locations for existing `ac-*` files:
   - `~/.claude/agents/` (global)
   - `.claude/agents/` (project-local)
3. For each location that **already contains at least one `ac-*` file**:
   - Overwrite all existing `ac-*` files with versions from the archive
   - Add any new `ac-*` files not yet present
   - Never touch files without the `ac-` prefix (those are user-owned)
4. If neither location has `ac-*` files, skip — agents are opt-in via setup.

## Step 5: Plugin Sync

1. Read `.agent-context/plugins.json` (skip if missing)
2. Read `.claude/settings.json` (create with `{}` if missing)
3. For each plugin not already in `enabledPlugins`: add it with value `true`
4. Never remove existing plugins

## Step 6: Compatibility Check

After updating shared files, check project-owned files for known outdated patterns:

| Pattern found in project-owned file     | Suggested update                                            |
| --------------------------------------- | ----------------------------------------------------------- |
| `memory/decisions.md` as routing target | Change to `decisions.json` (structured format since v0.2.0) |

If any patterns are found, include them in the response as suggestions — never auto-fix project-owned files.

---

## UPDATE Mode: Done

If in UPDATE mode, skip all remaining phases. Return `ok: true` with a brief summary (e.g. "Updated 0.1.1 → 0.1.2,
synced 3 agents, synced 2 plugins" or "Already up to date" or "User declined update"). Always return `ok: true` — even
on failure.

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
  plugins.json                           🔒 SHARED — do NOT modify (auto-updated)
  .agent-context-version                 🔒 SHARED — written by setup/update
  memory-review-prompt.md               🔒 SHARED — do NOT modify (auto-updated)
  decision-review-prompt.md              🔒 SHARED — do NOT modify (auto-updated)
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

Launch **6 parallel subagents** to scan the project. All subagents are **mandatory** — every one MUST execute, none may
be skipped. Running them in parallel maximizes speed.

#### Subagent 1: Documentation Scanner

Scan for existing documentation files and summarize their content:

- `CLAUDE.md`, `AGENTS.md`, `README.md`, `CONTRIBUTING.md`
- `.claude/rules/*.md`
- `skills-lock.json`

Output: list of files found with summary of content per file.

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

#### Subagent 6: Skills & Plugins

Check for existing skills infrastructure:

- `skills-lock.json` — locked skill definitions
- `.claude/skills/`, `.agents/skills/` — existing project skills

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

> This phase is the safety net. Shared files (layer0, base-principles) define a **generic** workflow. Projects often
> have **project-specific** workflow rules that lived in the same files before migration. If you overwrite a shared file
> or remove "general" content, you MUST verify nothing project-specific was lost.

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

After all relocations, go through the checklist and confirm every item has a ✓. If any item is unchecked, it's a gap —
fix it before proceeding.

**Common traps to watch for:**

- The new shared `layer0` is much shorter than the old one — it only covers Skill Lookup, Memory Rules, and
  Self-Improvement. Old layer0 content like Plan-First, Subagent Strategy, Task Management, Verification must move to
  `layer2-project-core.md`
- `base-principles.md` says "present concrete options" but your project might have said "present up to 5 options" — keep
  the project-specific detail
- External skill installation commands (`npx skills experimental_install`) are project-specific, not covered by the
  shared layer0's "Skill Lookup" section
- "Unit tests for all new implementations" is a project policy, not general LLM knowledge

### Phase S4: Fill Layers & Migrate Content

Replace `TODO` placeholders with discovered + user-provided information:

- **`AGENTS.md`**: Project name, tech stack, Docker container, 3-5 quick rules
- **`layer1-bootstrap.md`**: Identity, Docker exec pattern, domains, excluded dirs
- **`layer2-project-core.md`**: Non-linter conventions, critical rules, testing strategy, commit convention, **workflow
  rules rescued from Phase S3.5**
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

**Important:** Do NOT create memory files for general programming principles (KISS, YAGNI, DRY, SOLID, Clean Code). LLMs
already know these — adding them wastes context budget and reduces performance. Only store knowledge that is **specific
to this project** and **not discoverable from the code**.

### Phase S5: Project Skills Discovery

Analyze the project for recurring patterns that benefit from dedicated skills:

- Custom build/deploy scripts, CI workflows
- Testing patterns specific to this project
- Domain-specific business logic patterns
- Common code generation tasks

For each pattern, create a skill in `.claude/skills/<skill-name>/SKILL.md` with YAML frontmatter.

If `skills-lock.json` exists in the project root:

1. Run `npx skills experimental_install` to install locked skills — this is **mandatory**, not optional
2. Add `.agents/skills/` to `.gitignore`
3. Keep `skills-lock.json` committed

### Phase S6: Agent Installation (Claude Code only, optional)

If the release archive contains an `agents/` directory with `ac-*.md` files, offer to install them. All shared agents
use the `ac-` prefix (agent-context) and are designed to work with any project — they auto-detect tech stacks and use
MCP tools only when available.

1. List available `ac-*` agents and describe each one briefly (based on their `description` frontmatter)
2. Ask the user which agents they want to install and where:
   - `~/.claude/agents/` — available in all projects (global, recommended)
   - `.claude/agents/` — available only in this project (project-specific)
3. Copy selected agent files to the chosen location
4. If the user wants project-specific customization: copy to `.claude/agents/` and suggest editing the system prompt to
   match project conventions (e.g., add Shopware-specific rules to `ac-backend.md`). Follow the patterns documented in
   `docs/best-practices-agent-creation.md` — especially: descriptions with "Use when..." triggers, minimal tool lists,
   and the Role → Core Principle → Workflow → Output Format → Rules section order.
5. For creating entirely new project-specific agents, reference `docs/best-practices-agent-creation.md` for the full
   checklist (frontmatter design, prompt structure, anti-patterns).

**Do NOT overwrite** existing agent files with the same name unless the user explicitly confirms. New agents (not yet
present) are added without confirmation.

### Phase S7: Cleanup & Verification

**Cleanup:**

- Delete or empty migrated source files (`.claude/rules/*.md`, etc.)
- Verify `.agent-context/` is NOT in `.gitignore`

**Verification:**

1. `AGENTS.md` exists with identity and layer references
2. No `TODO` placeholders remain (except intentional ones)
3. `wc -l AGENTS.md` < 45 lines
4. `wc -l .agent-context/layer*.md` — each < 50 lines
5. Check `.agent-context/memory/*.md` line counts — domain stubs < 15 lines each (skip `index.md` and `log.md`)
6. No duplicated content across files
7. `.claude/CLAUDE.md` points to `@AGENTS.md`
8. **Migration audit checklist from Phase S3.5 is 100% checked off**
9. `.agent-context/memory/log.md` and `.agent-context/memory/index.md` exist
10. `.agent-context/memory-review-prompt.md` exists

**Summary:**

| Metric                 | Before | After |
| ---------------------- | ------ | ----- |
| Always-loaded lines    | X      | Y     |
| On-demand lines        | 0      | Z     |
| Number of source files | X      | —     |
| Number of target files | —      | Y     |
| Migration audit items  | N      | N ✓   |

Inform the user to restart their agent session for the new configuration to take effect.

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
- **Audit before overwrite:** Always run Phase S3.5 before overwriting shared files in existing projects — the new shared
  files are generic and will silently drop project-specific workflow rules
