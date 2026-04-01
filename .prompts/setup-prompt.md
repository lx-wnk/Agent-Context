# Agent Context Architecture — Setup Prompt

> **Usage:** Paste this entire file as a prompt into Claude Code to set up the agent-context architecture in your
> project. This is a project-based setup and memory-handling system — it structures your project knowledge into layers
> so Claude always has the right context without bloating the context window.

---

## Your Task

Set up the layered `.agent-context/` context architecture in this project. This gives Claude Code the right information
at the right time — minimal baseline context (~60-80 lines always loaded), full reference on-demand via memory files and
skills.

Follow each phase in order.

## Phase 1: Setup Structure

Create the directory structure and Claude Code integration.

### Directory structure

```
File                                     Ownership
─────────────────────────────────────    ──────────────────────────────────────
AGENTS.md                                PROJECT — customize freely
.claude/CLAUDE.md                        Bootstrap pointer → @AGENTS.md
.claude/settings.json                    SessionStart hook (merged, not overwritten)
.agent-context/
  agent-startup.md                       🔒 SHARED — do NOT modify (auto-updated)
  layer0-agent-workflow.md               🔒 SHARED — do NOT modify (auto-updated)
  base-principles.md                     🔒 SHARED — do NOT modify (auto-updated)
  update-prompt.md                       🔒 SHARED — do NOT modify (auto-updated)
  plugins.json                           🔒 SHARED — do NOT modify (auto-updated)
  .agent-context-version                 🔒 SHARED — written by auto-update
  layer1-bootstrap.md                    PROJECT — customize freely
  layer2-project-core.md                 PROJECT — customize freely
  layer3-guidebook.md                    PROJECT — customize freely
  memory/                                PROJECT — customize freely
    decisions.md
    lessons.md
    todo.md
```

### Ownership rules

**🔒 SHARED files** are overwritten on every auto-update. Never add project-specific content to them — it will be lost.
Put project-specific workflow rules in `layer2-project-core.md`, task routing in `layer3-guidebook.md`.

**PROJECT files** are created once from templates and never overwritten. All project customization goes here.

### Fetching shared files

Fetch the latest release from `https://api.github.com/repos/lx-wnk/Agent-Context/releases/latest`, download the archive
from `tarball_url`, and copy shared files into `.agent-context/`: files from `context/` and
`.prompts/update-prompt.md`. Also copy `plugins.json`. Write the release version (from `tag_name`, without `v` prefix)
to `.agent-context/.agent-context-version`.

For project-owned files, use the templates from `templates/` in the archive — or create them manually with TODO
placeholders. If a project-owned file already exists, do NOT overwrite it.

### SessionStart hook

Set up the auto-update hook. Edit `.claude/settings.json` (create with `{}` if missing). The
`hooks.SessionStart` field is an **array** — other hooks may already exist. **Append** our entry, do NOT replace
existing hooks. Skip if an entry referencing `update-prompt.md` already exists.

The hook uses `type: "agent"` — a subagent reads the update prompt and performs the update using its own tools (no
external dependencies like `curl` or `jq` required).

```json
{
  "type": "agent",
  "prompt": "Read .agent-context/update-prompt.md and follow its instructions exactly. If the file does not exist, return ok:true with reason 'update-prompt.md not found, skipping'.",
  "timeout": 60
}
```

Example with multiple hooks coexisting:

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [{ "type": "command", "command": "bash .other/hook.sh" }] },
      {
        "hooks": [
          {
            "type": "agent",
            "prompt": "Read .agent-context/update-prompt.md and follow its instructions exactly. If the file does not exist, return ok:true with reason 'update-prompt.md not found, skipping'.",
            "timeout": 60
          }
        ]
      }
    ]
  }
}
```

## Phase 2: Discovery

Auto-discover as much as possible before asking the user:

- **Existing docs**: `CLAUDE.md`, `AGENTS.md`, `README.md`, `CONTRIBUTING.md`, `.claude/rules/*.md`,
  `skills-lock.json`
- **Project name**: From `package.json`, `composer.json`, repo name, or directory name
- **Tech stack**: `package.json`, `composer.json`, `go.mod`, `Cargo.toml`, `requirements.txt`
- **Docker**: `docker-compose.yml` / `compose.yaml` for container names, ports, exec patterns
- **Domains**: `.env`, `.env.example` for `APP_URL`, `BASE_URL`, `SHOP_URL`
- **CI**: `.github/workflows/`, `.gitlab-ci.yml`, `Jenkinsfile`
- **Testing**: `phpunit.xml`, `vitest.config.*`, `cypress.config.*`, `jest.config.*`
- **Commit convention**: `git log --oneline -20`

Only ask the user for values that cannot be auto-detected.

## Phase 3: Content Classification

For every piece of existing documentation, apply the **"Can the agent discover this by reading the code?"** filter:

### KEEP (not discoverable):

- Gotchas, quirks, hard-won lessons
- Conventions no linter enforces
- Non-obvious architectural decisions + rationale
- External system references (API endpoints, IDs, URLs)
- Docker/infra networking conventions
- CI pipeline structure, custom build steps
- Security constraints, forbidden patterns
- Business terminology, domain knowledge

### REMOVE (discoverable from code):

- Directory trees, file structure
- Entity/model field listings
- Route tables, service registrations
- Linter/formatter config details
- Function signatures, API surfaces
- Dependency lists
- README content duplicated into agent context

**Principle:** Every line in context files = friction the agent can't resolve alone.

## Phase 4: Fill Layers & Migrate Content

Replace `TODO` placeholders with discovered + user-provided information:

- **`AGENTS.md`**: Project name, tech stack, Docker container, 3-5 quick rules
- **`layer1-bootstrap.md`**: Identity, Docker exec pattern, domains, excluded dirs
- **`layer2-project-core.md`**: Non-linter conventions, critical rules, testing strategy, commit convention
- **`layer3-guidebook.md`**: Task-routing table, skills index, memory file index

For existing documentation found in Phase 2, route surviving content:

| Scope                       | Target                   |
| --------------------------- | ------------------------ |
| General dev philosophy      | `layer2-project-core.md` |
| Domain-specific convention  | `memory/<domain>.md`     |
| Heavy reference (>30 lines) | `skills/<reference>.md`  |
| Gotcha / lesson             | `memory/lessons.md`      |
| Architecture decision       | `memory/decisions.md`    |

Each fact in exactly ONE place. No duplicates.

**Important:** Do NOT create memory files for general programming principles (KISS, YAGNI, DRY, SOLID, Clean Code). LLMs
already know these — adding them wastes context budget and reduces performance. Only store knowledge that is **specific
to this project** and **not discoverable from the code**.

## Phase 5: Project Skills Discovery

Analyze the project for recurring patterns that benefit from dedicated skills:

- Custom build/deploy scripts, CI workflows
- Testing patterns specific to this project
- Domain-specific business logic patterns
- Common code generation tasks

For each pattern, create a skill in `.claude/skills/<skill-name>/SKILL.md` with YAML frontmatter.

If `skills-lock.json` exists: add `.agents/skills/` to `.gitignore`, keep `skills-lock.json` committed.

## Phase 6: Agent Installation (Claude Code only, optional)

If the release archive contains an `agents/` directory with `ac-*.md` files, offer to install them. All shared agents
use the `ac-` prefix (agent-context) and are designed to work with any project — they auto-detect tech stacks and use
MCP tools only when available.

1. List available `ac-*` agents and describe each one briefly (based on their `description` frontmatter)
2. Ask the user which agents they want to install and where:
   - `~/.claude/agents/` — available in all projects (global, recommended)
   - `.claude/agents/` — available only in this project (project-specific)
3. Copy selected agent files to the chosen location
4. If the user wants project-specific customization: copy to `.claude/agents/` and suggest editing the system prompt to
   match project conventions (e.g., add Shopware-specific rules to `ac-backend.md`)

**Do NOT overwrite** existing agent files with the same name unless the user explicitly confirms. New agents (not yet
present) are added without confirmation.

## Phase 7: Cleanup & Verification

**Cleanup:**

- Delete or empty migrated source files (`.claude/rules/*.md`, etc.)
- Verify `.agent-context/` is NOT in `.gitignore`

**Verification:**

1. `AGENTS.md` exists with identity and layer references
2. No `TODO` placeholders remain (except intentional ones)
3. `wc -l AGENTS.md` < 45 lines
4. `wc -l .agent-context/layer*.md` — each < 40 lines
5. `wc -l .agent-context/memory/*.md` — stubs < 15 lines each
6. No duplicated content across files
7. `.claude/CLAUDE.md` points to `@AGENTS.md`

**Summary:**

| Metric                 | Before | After |
| ---------------------- | ------ | ----- |
| Always-loaded lines    | X      | Y     |
| On-demand lines        | 0      | Z     |
| Number of source files | X      | —     |
| Number of target files | —      | Y     |

Inform the user to restart their agent session for the new configuration to take effect.

---

## Constraints

- **Non-destructive:** Never overwrite project-owned files that already have content
- **Ask, don't guess:** If information cannot be auto-detected, ask the user
- **One fact, one place:** No duplication across files
- **No over-engineering:** Skip skills if total content < ~200 lines, skip memory stubs if domain < ~30 lines
- **Preserve knowledge:** Nothing gets deleted — it gets routed, filtered, or promoted to code
