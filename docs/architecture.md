# Architecture

Full mental model of the layer system, how the repo maps onto a target project, and what happens at
setup, update, and runtime. See [README.md](../README.md) for the front-page pitch and quick start.

## Layer System

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

Paste [`.prompts/setup-prompt.md`](../.prompts/setup-prompt.md) into Claude Code. It:

1. Downloads the latest release from the GitHub Releases API
2. Copies **shared files** from `context/` → `.agent-context/` (overwritable)
3. Creates **project-owned files** from `templates/` → `AGENTS.md`, layers 1-3, memory stubs (never overwritten)
4. Writes the release version to `.agent-context/.agent-context-version`
5. Discovers your tech stack and fills in the TODO placeholders — and **distills** the non-obvious gold from your docs (hard invariants, architecture decisions, complex subsystems) into `memory/`, `decisions.json`, and skills, so it loads by task routing rather than sitting unread. A deterministic discovery digest (`bin/discovery-digest.sh`) orients the scan so no doc is missed. Memory stubs that stay empty after setup are expected — runtime-accumulated knowledge (lessons, preferences) fills as you work.

### Every Session (automatic)

Updates can be triggered manually by fetching the setup prompt from remote and following its instructions:

1. Reads `.agent-context/.agent-context-version` (local) and fetches the latest release tag from the GitHub API (remote, cached for 1 hour)
2. **If already up-to-date and templates intact:** exits immediately — no Claude spawn needed
3. **If versions differ:** spawns Claude, which downloads shared files in parallel, writes the new version
4. **If API fails:** falls back to the cached version; warns if the cache is stale

### What the agent sees at runtime

```
AGENTS.md                               ← Agent reads this first
  @.agent-context/agent-startup.md      ← Version check, update info
  @.agent-context/layer0-agent-workflow  ← Memory routing, skill lookup
  @.agent-context/layer1-bootstrap      ← Tech stack, Docker, domains
  @.agent-context/layer2-project-core   ← Your conventions + critical rules
  @.agent-context/layer3-guidebook      ← Task routing → memory/skills on-demand
```

Total baseline: ~150-200 lines. Heavy reference (skills, memory) is loaded only when the task matches.

### Read flow

The baseline (layers + indexes) loads once at session start. Everything heavy — skill bodies, domain
memory, external docs, the discovery map — is pulled only when a task's routing calls for it, so context
stays small no matter how large the project's knowledge grows. The [read-flow diagram](../README.md#architecture)
in the README shows the full picture.

Only the **indexes** (`knowledge-map.md`, `skills/index.md`) sit in the baseline; the **bodies** they point
to are read lazily. The discovery map is the same pattern one level deeper: read the small `map.json`, then
open only the 1–2 node notes the task needs. See [Discovery Map](discovery-map.md) for details.

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
    ├── agent-delegation.md                ← Delegation protocol, on-demand (shared)
    ├── memory-maintenance.md              ← Memory restructuring, on-demand (shared)
    ├── layer1-bootstrap.md                ← Project identity, Docker, domains
    ├── layer2-project-core.md             ← Dev principles + critical rules
    ├── layer3-guidebook.md                ← Task routing, skills, memory
    ├── .agent-context-version              ← Installed version (written by setup/update)
    ├── decisions.json                     ← Architectural decisions (structured)
    ├── knowledge-map.md                   ← Universal knowledge pointer index (auto-maintained)
    ├── memory-review-prompt.md            ← Memory review prompt (shared)
    ├── decision-review-prompt.md          ← Decision review prompt (shared)
    ├── hooks.conf                         ← Hook toggles + toolchain (project-owned)
    ├── budget.conf                        ← Token-budget config (project-owned)
    ├── bin/                               ← Shared tooling (auto-updated)
    │   ├── check-token-budget.sh          ← Always-on budget audit
    │   ├── memory-prune.sh                ← Memory decay / archive
    │   ├── discovery-digest.sh            ← Deterministic discovery inventory
    │   └── check-map-budget.sh            ← Discovery-map cap gate
    ├── hooks/                             ← Shared hook scripts (auto-updated)
    │   ├── lib.sh
    │   ├── pre-protect-secrets.sh          ← PreToolUse: block secret writes
    │   ├── post-format.sh                  ← PostToolUse: auto-format
    │   ├── stop-test-gate.sh               ← Stop: test gate
    │   └── subagent-scope.sh               ← SubagentStop: scope check
    ├── skills/
    │   ├── index.md                       ← Skill registry (on-demand)
    │   └── discovery-map.md               ← On-demand discovery skill
    └── memory/
        ├── decisions.md                   ← Legacy stub (migrated to decisions.json)
        ├── lessons.md                     ← Hard-won lessons
        ├── people.md                      ← Team members & stakeholders
        ├── preferences.md                 ← Agent behavior preferences
        ├── todo.md                        ← Active task plan (local-only, gitignored)
        ├── user.md                        ← Primary user profile
        └── index.md                       ← Memory file catalog
```

### Alternative: paste into a session

Paste the contents of [`.prompts/setup-prompt.md`](../.prompts/setup-prompt.md) directly into a Claude Code session if you prefer to confirm each step interactively.

Pass `--force` for a **full from-scratch rediscovery**: it re-scans the entire codebase at setup depth even on an existing install and merges into your knowledge without deleting still-valid facts (a normal update only reconciles deltas). Pass `--discover` to check for a [discovery map](discovery-map.md) after the run and, if none exists, point you to the interactive `/discover` command — the headless installer does not build the map itself (a rich map needs fan-out discovery, which runs reliably only in an interactive session).

## Repository Structure

```
agent-context/
├── context/           # Shared agent context (copied to .agent-context/)
│   ├── bin/           #   Shared tooling: token-budget gate, memory-prune
│   └── hooks/         #   Shared hook scripts (lib + 4 hooks)
├── templates/         # Project setup templates (copied once, never overwritten)
├── tests/             # Pure-bash tests (install, coverage, budget, prune, hooks)
├── .github/workflows/ # CI: prettier, shell tests, token-budget gate
├── plugins.json       # Base plugin set for Claude Code
├── example.md         # Annotated example (Shopware 6 project)
├── install.sh         # Installer script (curl one-liner entry point)
├── .prompts/          # Prompt files for Claude (setup + review instructions)
└── README.md
```

## Agents

Specialist agents (`ac-*`) are distributed as the [`agents@lx-wnk`](https://github.com/lx-wnk/agents) plugin — installed automatically via `plugins.json`. See the plugin repo for the full agent list and documentation.

## Example

See [`example.md`](../example.md) for a complete annotated walkthrough of a Shopware 6 project. Each file is described in prose — shared files link back to `context/`, project-owned files explain what they contain and why.
