# Changelog

All notable changes to this project will be documented here. Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- **Per-file memory TTL defaults** — `.agent-context/bin/memory-prune.sh` now applies a default TTL to dated entries that carry no `ttl:` of their own. Ships with `lessons.md=90d` and `preferences.md`/`people.md`/`user.md=infinite`; projects tune it via `MEMORY_TTL_DEFAULTS` in `.agent-context/budget.conf`, per key, with a `*` catch-all. An explicit `ttl:` on the entry always wins, `ttl:infinite` included, and a line without a `(YYYY-MM-DD)` date is never touched. Keys match by basename at any depth.
- **Cross-repo lesson routing** — `layer0-agent-workflow.md` now covers multi-repo projects (e.g. frontend ↔ backend): the "Routing New Knowledge" table's gotcha row now names the owning repo, and the one-place rule is extended across repo boundaries. A lesson lives in the repo owning the code it describes; a shared-contract fact (API shape) has one canonical repo while sibling repos hold a pointer, never a copy. Ships entirely in the shared always-on layer, so it reaches existing installations on their next update; projects that want to declare their sibling repos do so in their own `layer1-bootstrap.md`.

### Fixed

- **Recursive memory scan** — expanded domains (`memory/<domain>/*.md`) were never pruned; the scan only looked one level deep. It now recurses, and follows symlinked memory directories and files that resolve inside the scanned tree (rewriting the target, not the link).
- **Archive self-destruct on non-canonical paths** — a trailing slash on `--dir`/`--archive` (what tab-completion produces) made the archive-exclusion glob miss, so the archive was scanned as a source and its rewrite erased every entry prior runs had moved there. Paths are canonicalized up front and a second guard refuses to rewrite anything inside the archive.
- **Leading-zero TTL parsed as octal** — a single `ttl:09d` entry raised a fatal arithmetic error that terminated the scan of that file while the run still reported success, so every genuinely expired entry after it was silently never archived. TTL arithmetic is now base ten, and a conf value with a leading zero is rejected before any file is touched.
- **Prune error handling** — an unreadable memory file no longer aborts the scan, a failed rewrite exits 2 naming the file (instead of dying at an undeclared exit 1 or reporting success), the conf can no longer override the script's own `APPLY`/`MEM_DIR`/`ARCHIVE_DIR`/shared TTL table, and the dry-run preview no longer truncates an entry at an embedded tab.

### Security

- **`.conf` files are parsed, never sourced** — `.agent-context/budget.conf` and `.agent-context/hooks.conf` are project-owned and can arrive via `git pull` from a repository nobody vetted, yet all four shared consumers ran them with `.`, which executes every command in the file. `.agent-context/bin/conf-read.sh` (new, shared) reads whitelisted `KEY=value` pairs without evaluating them, and `.agent-context/bin/memory-prune.sh`, `.agent-context/bin/check-token-budget.sh`, `.agent-context/bin/check-map-budget.sh` and `.agent-context/hooks/lib.sh` all route through it.
- **Memory pruning stays inside the memory tree** — a symlinked memory file that resolved outside the scanned directory was read, previewed and rewritten at its out-of-tree target, and its content was copied into the in-repo archive. Such a file is now reported and skipped, and the containment check is re-asserted immediately before the rewrite. The scan is also NUL-delimited, so a newline in a directory name can no longer split one path into two.

### Upgrade note

`.agent-context/bin/memory-prune.sh` is a shared, auto-updated file, so this reaches every installation on the next update. Dated entries in `lessons.md` that carried no `ttl:` were previously immortal and now expire after 90 days — because such entries are typically old, **the first `--apply` after updating will archive noticeably more than before**. Nothing is deleted: entries move to `memory/archive/<ISO-week>.md` — but archiving is not erasure, so honoring a GDPR Art. 17 request for an entry that may hold third-party personal data also means removing it from `memory/archive/*.md`. The dry-run default previews the full list, so run `bash .agent-context/bin/memory-prune.sh` once and review it before passing `--apply`. To keep the old behavior for a file, add (or edit) `MEMORY_TTL_DEFAULTS` in `.agent-context/budget.conf` — `budget.conf` is a project-owned template, so an install from before this release will not have the block yet:

```
MEMORY_TTL_DEFAULTS="
lessons.md=infinite
"
```

## [0.8.1] - 2026-07-01

### Added

- README status badges (license, latest release, CI status).

### Docs

- Completed the 0.8.0 changelog below to cover the on-demand discovery map, the installer/command UX, and the soft/hard budget cap.

## [0.8.0] - 2026-07-01

### Added

- **On-demand discovery map** — `/discover` fans out discovery subagents that record meaningful, non-obvious facts per subsystem into a tiny `map.json` (navigation) plus curated `memory/<node>.md` notes. Incremental by git watermark, size-capped by the dependency-free `.agent-context/bin/check-map-budget.sh`, and never loaded into always-on context. Shipped as a portable skill plus a `.claude/commands/discover.md` slash command.
- **Installer & command UX** — `install.sh --local-source <clone>` installs every shared file and template from a local checkout instead of downloading (implies a forced run); real Claude Code slash commands ship to `.claude/commands/` (`/discover`, `/memory-review`, `/decision-review`); `--force` now runs a full from-scratch rediscovery (merging non-destructively); `--discover` verifies the map and hands off to the interactive build. An offline install smoke test (`tests/check-install-smoke.sh`) derives its file list from the setup-prompt download table, catching a shared file that was never wired in.
- **Soft + hard token-budget cap** — `budget.conf` gains `MAX_EFFECTIVE_LINES_HARD`: over the soft `MAX_EFFECTIVE_LINES` only warns, over the hard cap fails the gate. Backward compatible (hard defaults to soft when unset).

- **Deterministic hooks** (`.agent-context/hooks/`) — four optional, project-overridable Claude Code hooks: secret-write block (PreToolUse, exit 2), auto-format (PostToolUse), test gate (Stop), and subagent scope check (SubagentStop). Behavior and project toolchain live in the project-owned `.agent-context/hooks.conf`; hook scripts are shared/auto-updated. **Off by default** (`HOOKS_ENABLED=0`) — existing projects are never silently activated. See README → "Deterministic Hooks".
- **Token-budget CI gate** — `tests/check-token-budget.sh` + `.github/workflows/ci.yml` fail the build if the always-on context closure exceeds a configurable effective-line limit (default 160 in-repo, `MAX_EFFECTIVE_LINES` in the shipped `budget.conf`). Counting engine (`.agent-context/bin/check-token-budget.sh`) ships to consumers to audit their own layers.
- **Memory decay** — `.agent-context/bin/memory-prune.sh` archives expired dated entries (`ttl:Nd` past their date) into `memory/archive/<ISO-week>.md`. Dry-run by default, `--apply` to move; `ttl:infinite` never expires. Nothing is deleted, only moved.
- **Skill standard** — `docs/skill-standard.md` documents the open Agent Skills `SKILL.md` frontmatter contract (`name` + `description`, progressive disclosure) so `skills/` is portable across Claude Code, Codex, Cursor, and Gemini.
- **Discovery digest** — `.agent-context/bin/discovery-digest.sh` produces a deterministic project inventory (manifests, services, docker, task runners, doc inventory with line counts + distillation candidates). The setup/update agent reads it first to orient — simplifies discovery without restricting it (subagents still scan deeper).
- **Knowledge distillation + Subagent 7** — discovery now extracts the _non-obvious gold_ from heavy reference docs (hard invariants → `memory/lessons.md` with `ttl:infinite`, architecture decisions → `decisions.json`, complex subsystems → `memory/<domain>.md` stubs) instead of only linking them in `knowledge-map.md`. A dedicated "Project Specifics & Complexity" subagent surfaces peculiarities, gotchas, and frequently-needed references. Existing installs backfill this on update.

### Changed

- **Headless discovery decides, never defers** — in headless/CI setup/update, the agent now resolves every discovered source in the same run (best-effort, non-destructive) instead of writing a plan-file that a human must re-run. A plan-file row left in `⏳ review` was silently dropped before, leaving `memory/` looking empty despite rich `docs/`. The plan-file is now an audit trail, not a queue.

- **Sharpened progressive disclosure** — the always-on baseline dropped from ~186 to ~141 effective lines. `layer0-agent-workflow.md` was trimmed: the delegation protocol moved to on-demand `agent-delegation.md`, and memory-restructuring procedures (domain expansion, lesson graduation, knowledge-map triggers) moved to on-demand `memory-maintenance.md`. Always-on triggers stay; the procedures load only when the matching event fires.
- `.claude/settings.json` template now registers the four hooks (inert until `HOOKS_ENABLED=1`).
- **Docs restructure** — a lean README that leads with a read-flow diagram, deep reference split into `docs/` (architecture, discovery-map, enforcement, principles, references) with an index, and a GitHub-standard `CONTRIBUTING.md`.
- **Hook hardening** — the subagent scope check flags only Write/Edit/MultiEdit (not reads); auto-format runs via an argv array instead of `eval` on the raw path; the test gate writes to a `mktemp` file instead of a predictable `/tmp` path; CI uses `npm ci`.

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
