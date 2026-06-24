# Changelog

All notable changes to this project will be documented here. Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.8.0] - 2026-06-23

### Added

- **Deterministic hooks** (`.agent-context/hooks/`) — four optional, project-overridable Claude Code hooks: secret-write block (PreToolUse, exit 2), auto-format (PostToolUse), test gate (Stop), and subagent scope check (SubagentStop). Behavior and project toolchain live in the project-owned `.agent-context/hooks.conf`; hook scripts are shared/auto-updated. **Off by default** (`HOOKS_ENABLED=0`) — existing projects are never silently activated. See README → "Deterministic Hooks".
- **Token-budget CI gate** — `tests/check-token-budget.sh` + `.github/workflows/ci.yml` fail the build if the always-on context closure exceeds a configurable effective-line limit (default 160 in-repo, `MAX_EFFECTIVE_LINES` in the shipped `budget.conf`). Counting engine (`bin/check-token-budget.sh`) ships to consumers to audit their own layers.
- **Memory decay** — `.agent-context/bin/memory-prune.sh` archives expired dated entries (`ttl:Nd` past their date) into `memory/archive/<ISO-week>.md`. Dry-run by default, `--apply` to move; `ttl:infinite` never expires. Nothing is deleted, only moved.
- **Skill standard** — `docs/skill-standard.md` documents the open Agent Skills `SKILL.md` frontmatter contract (`name` + `description`, progressive disclosure) so `skills/` is portable across Claude Code, Codex, Cursor, and Gemini.
- **Discovery digest** — `.agent-context/bin/discovery-digest.sh` produces a deterministic project inventory (manifests, services, docker, task runners, doc inventory with line counts + distillation candidates). The setup/update agent reads it first to orient — simplifies discovery without restricting it (subagents still scan deeper).
- **Knowledge distillation + Subagent 7** — discovery now extracts the _non-obvious gold_ from heavy reference docs (hard invariants → `memory/lessons.md` with `ttl:infinite`, architecture decisions → `decisions.json`, complex subsystems → `memory/<domain>.md` stubs) instead of only linking them in `knowledge-map.md`. A dedicated "Project Specifics & Complexity" subagent surfaces peculiarities, gotchas, and frequently-needed references. Existing installs backfill this on update.

### Changed

- **Headless discovery decides, never defers** — in headless/CI setup/update, the agent now resolves every discovered source in the same run (best-effort, non-destructive) instead of writing a plan-file that a human must re-run. A plan-file row left in `⏳ review` was silently dropped before, leaving `memory/` looking empty despite rich `docs/`. The plan-file is now an audit trail, not a queue.

- **Sharpened progressive disclosure** — the always-on baseline dropped from ~186 to ~141 effective lines. `layer0-agent-workflow.md` was trimmed: the delegation protocol moved to on-demand `agent-delegation.md`, and memory-restructuring procedures (domain expansion, lesson graduation, knowledge-map triggers) moved to on-demand `memory-maintenance.md`. Always-on triggers stay; the procedures load only when the matching event fires.
- `.claude/settings.json` template now registers the four hooks (inert until `HOOKS_ENABLED=1`).

### Migration

Automatic via the `install.sh` one-liner (UPDATE mode). New shared files (hooks, `bin/` scripts, `agent-delegation.md`, `memory-maintenance.md`) download alongside the existing shared files; project-owned `hooks.conf` and `budget.conf` are created if absent and never overwritten. Hook registration is merged into an existing `settings.json` additively and idempotently. All changes are backward compatible — no manual steps required.

## [0.7.0] - 2026-05-04

### Removed

- **`memory/log.md`** — cross-session activity log eliminated. Git history and external session notes (Obsidian, Confluence) already provide this information without merge conflicts. Existing files are removed automatically on update.

### Changed

- **`memory/todo.md`** is now local-only. The file is gitignored and no longer propagates across branches or clones — eliminates merge conflicts on per-task working state. Existing content is preserved locally, untracked on update.
- `layer0-agent-workflow.md` and `layer3-guidebook.md` updated to reflect the new memory layout.

### Migration

Automatic via the `install.sh` one-liner (UPDATE mode). The migration is idempotent: re-running setup on an already-migrated project produces no further changes.
