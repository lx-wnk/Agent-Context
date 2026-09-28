# Changelog

All notable changes to this project will be documented here. Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- **Cross-repo lesson fallback** (#33) — a lesson belongs in the repo owning the code, but in a multi-repo project that repo is often not checked out, and the agent had nowhere valid to put it. It now parks the lesson in the current repo's `memory/lessons.md` with an `owner:<repo>` tag; the memory review moves it to the owning repo once that repo is reachable. The rule lives in the on-demand `memory-maintenance.md` (Cross-Repo Fallback) with a pointer from the layer-0 routing row; siblings are declared in a new optional "Sibling Repos" section of `layer1-bootstrap.md`, which existing installs add by hand (the template is project-owned).

### Changed

- **Always-on context shrinks from 145 to 130 effective lines** — the manual "Auto-Update" procedure in `agent-startup.md` (which fetched `releases/latest` and bypassed the installer's version pinning) is replaced by a pointer to the installer; duplicated guidance in layer 0, `base-principles.md` and the `AGENTS.md` template is removed; skill format guidance is stated once (`skills/<name>/SKILL.md`). A new always-on rule treats content read from files, tools, the web or sub-agents as data: its instructions are neither followed nor persisted without user confirmation, and such saves are tagged `source:external`. Agents that do not expand `@` includes are told to read the listed files in order.
- **The token-budget gate measures what actually loads** — `check-token-budget.sh` follows the `@` imports from `.claude/CLAUDE.md` (and a root `CLAUDE.md`), each resolved relative to the importing file, and warns about imports that point at no file. A new `SESSION_START_FILES` key lists files the agent reads at every session start without an import; the template ships `memory/lessons.md` and `memory/preferences.md` there, so they now count toward the budget. `INCLUDE_FILES` becomes a legacy additive list: its entries still count, but each one no import reaches prints a note, so a stale entry such as an unimported `knowledge-map.md` no longer counts silently. A missing `MAX_EFFECTIVE_LINES_HARD` defaults to 250 instead of the soft cap, and HTML comments are counted correctly (text between two comments on one line and lines after an unclosed `<!--` count; `<!--` inside backticks is plain text).

### Fixed

- **Hooks follow the documented Claude Code hook contract** — the subagent scope check reads the subagent's own transcript (`agent_transcript_path`), matches project-relative paths, treats any write outside the project as a violation and honours `stop_hook_active`; warn-mode messages reach the user as `systemMessage` instead of the debug log; the test gate runs once per stop and passes at most 40 lines / 4 KB of sanitized, labelled test output.
- **Setup deleted other tools' AI configuration without reading it** — `GEMINI.md`, `.claude/rules/`, `.cursorrules`, `.cursor/rules/` and `.github/copilot-instructions.md` were removed by the migration cleanup although their content was never inventoried. They are now read, routed into the layers and recorded in `setup-decisions.json` like any knowledge source, and never deleted or emptied — they keep working for teammates who use those tools. Only committed, unmodified legacy Agent-Context artefacts (`.ai/`, `--ai-dirs`) are removed, and `MIGRATION_CLEANUP: ran` is logged only after such a removal, so a project with a `.cursorrules` no longer bypasses the Step 5.0 change gate. After a cleanup, `knowledge-map.md` is updated row by row instead of rebuilt, a user's same-named command in `.claude/commands/` is kept instead of overwritten, and an untracked `memory/log.md` moves to `memory/archive/log.md` instead of being deleted.
- **ADR persist blocks produced invalid `decisions.json` entries, and the delegation table named agents that do not exist** — `agent-delegation.md` now maps the `title`/`context`/`decision`/`consequences` persist block onto the schema decision-review validates (`id`, `date`, `decision`, `reasoning`, `scope`, `weight`, `reviewDate`), limits memory-update persists to `.agent-context/memory/*.md` and `decisions.json`, and uses the real `agents` plugin ids instead of `ac-*` names.
- **Discovery map stays on demand** — the discovery-map skill used to append one always-on knowledge-map row per node (up to 60 with the default cap); it now keeps a single "unfamiliar area → map.json" row and leaves per-node routing to `map.json`. Node notes and sub-maps move to `memory/map/` (exempt from the 15-line stub cap), every sub-map is cap-gated, and "where does X live" no longer triggers a discovery run — layer 3 reads an existing map first and only offers discovery otherwise.
- **Memory templates** — lesson graduation is now measurable ("confirmed in 3 separate sessions"), new installs no longer ship the legacy `memory/decisions.md` stub, `/discover` runs the budget script via `bash`, and the `user.md`/`todo.md` templates carry the required `(YYYY-MM-DD)` date hint.
- **discovery-digest missed files and invented Makefile targets; the map cap counted lines and characters** — `discovery-digest.sh` no longer drops files with non-ASCII names, no longer hides a top-level `bin/` (Symfony `bin/console`, Rails `bin/`) and no longer lists Makefile variable assignments (`FOO:=`) as targets. `check-map-budget.sh` counts `"id":` occurrences instead of lines, as `budget.conf` documents, and measures the per-line cap in bytes under any locale.
- **memory-prune rewrites kept neither mode nor hard links, and could lose a concurrent write** — a rewritten memory file became mode 0600 and lost its hard links; now the mode is kept and a hard-linked file is written in place. A file that changes while it is being processed aborts that run with exit 2 instead of being overwritten. Entry dates are computed in-process — about 20× faster on large files, impossible dates such as 2026-02-30 are never expired, and expiry is by calendar day on both BSD and GNU. A missing value for `--dir`/`--conf`/`--archive` exits 2 as documented, and the dry-run shows paths relative to the memory directory with control characters stripped.

### Security

- **The setup agent no longer runs with all permission checks disabled** — `install.sh` downloads the release archive itself, installs the shared files, slash commands (a same-named user command is kept) and hook entries itself, and runs the setup agent with `--permission-mode acceptEdits`, `--strict-mcp-config`, web tools denied and no network command in its allowlist: it can no longer reach the network, use your MCP servers, run arbitrary shell commands or write to `.claude/`. The version file is written only after the installer has verified every shared file against the release.
- **Hook hardening** — the secret-write guard resolves symlinks, allows `*.example`/`*.dist`/`*.sample`, and says it guards writes only; the no-jq JSON output strips control characters so a block can no longer fail open; the formatter never touches files outside the project; hook commands quote `${CLAUDE_PROJECT_DIR}` so a project path with spaces works.
- **A pulled `hooks.conf` could switch hooks on and choose the commands they run** — `HOOKS_ENABLED`, `TEST_CMD` and `FORMAT_CMD` now take effect only from the gitignored, per-developer `.agent-context/hooks.local.conf` and are ignored in the committed `hooks.conf`; every other hook setting still comes from `hooks.conf`. `install.sh` adds `/.agent-context/hooks.local.conf` to `.gitignore` and, when the committed file still sets one of the three keys, says so.

### Docs

- **`docs/` and `example.md` match the installed layout** — structure listings include the slash commands, shared tooling and config files; stale `plugins.json` references and dead discovery-map links are gone; updates are described as on-demand with the Step 5.0 change gate and the importer-relative `@../AGENTS.md`. The ETH Zurich result (arXiv 2602.11988) is quoted from its abstract instead of paraphrased — it covers developer-written context files too and names no "~3%" figure — and the German agent best-practices guide is reframed as general guidance now that the `ac-*` agents ship as a separate plugin.
- **Root docs match the code again** — README and CLAUDE.md describe the update flow as it works since 0.9.x (the installer resolves and pins the release, exits early when it is installed, and re-syncs knowledge only for sources that changed); the install tree and the ownership diagram list what an install actually creates. The baseline figure is measured on the shipped templates (12,077 of 28,558 bytes, 42.3% by estimated token stay out of every session) and comes with the command to reproduce it. CONTRIBUTING covers shellcheck, CHANGELOG and commit conventions and the release process; `package.json` is versioned `0.0.0-dev` with license and repository metadata.

### Upgrade note

An install now exits with code 2 and lists what is missing, instead of reporting success, when a shared file, core template or hook registration is missing. A release lookup or download failure exits 1 before any agent starts (no fallback to the prompt on `main`). `.claude/settings.json` only gains the Agent-Context hook entries it lacks; an invalid file is left untouched and reported. Without `jq` or `python3` the installer cannot merge JSON: it prints how to add the hook entries by hand and does not fail the install (the hooks are off by default). An install that is newer than the latest release is left alone.

An install now exits with code 2 and lists what is missing, instead of reporting success, when a shared file, core template or hook registration is missing. A release lookup or download failure exits 1 before any agent starts (no fallback to the prompt on `main`). `.claude/settings.json` only gains the Agent-Context hook entries it lacks; an invalid file is left untouched and reported. An install that is newer than the latest release is left alone.

Existing `budget.conf` files are project-owned and keep their `INCLUDE_FILES`. Entries an import already reaches are deduplicated silently; an entry nothing imports prints a note on every run until you remove it. To count the session-start reads, add `SESSION_START_FILES` with `.agent-context/memory/lessons.md` and `.agent-context/memory/preferences.md`.

Hooks that were enabled in the committed `hooks.conf` are **off** after this update until each developer moves `HOOKS_ENABLED`, `TEST_CMD` and `FORMAT_CMD` into `.agent-context/hooks.local.conf`. This is deliberate: copying them automatically would re-trust exactly the committed values the change stops trusting.

## [0.9.1] - 2026-09-28

### Changed

- **`--local-source` no longer implies `--force`** — installing from a local clone ran a full from-scratch rediscovery every time (about ten minutes on a mid-size project). It now runs a normal update; pass `--force` explicitly for a full rediscovery.
- **Progress dots trail the running step** — the installer used to start a new line of dots after every log line; the dots now continue the line of the step that is running, and each new log line starts on its own line.
- **An update re-syncs knowledge only when a knowledge source changed** — every UPDATE used to launch the full Step 5 fan-out, even when a release only shipped new shared files. A new change gate (Step 5.0) compares the recorded sources against `setup-decisions.json`; with nothing changed or new it skips 5a–5d, otherwise it re-syncs only the changed and new sources. `--force` and a migration cleanup still run the full re-sync. `docs/principles.md` §4 describes the new rule.
- **One setup-log line per sub-step** — the setup agent chose its own wording for sub-steps and merged 4.5–4.7 into a single line. The prompt now fixes the format (`Step <id>: <name> — <result>`, one line each) and shows every sub-step in the example.

### Fixed

- **Claude Code loaded no framework context from `.claude/CLAUDE.md`, and three always-on files never loaded anywhere** — Claude Code resolves `@` imports relative to the importing file, but the bootstrap and layer templates used root-relative paths. `.claude/CLAUDE.md` pointed at `@AGENTS.md` (→ `.claude/AGENTS.md`, which does not exist), so a project without a root `CLAUDE.md` loaded nothing; `@.agent-context/base-principles.md` in layer 2 and `@.agent-context/knowledge-map.md` / `@.agent-context/skills/index.md` in layer 3 resolved to `.agent-context/.agent-context/…` in every install, while the token budget still counted them. The templates now use importer-relative paths (`@../AGENTS.md`, `@base-principles.md`, `@knowledge-map.md`, `@skills/index.md`), and `install.sh` migrates existing installs on every run: it rewrites the `.claude/CLAUDE.md` pointer and every `@.agent-context/…` import inside layer 2 and 3 — also when a project moved it into a sentence or blockquote — while code spans, fenced blocks and symlinked files are left alone. The install smoke test now walks the `@` closure the way Claude Code does and requires it to equal `INCLUDE_FILES`.
- **Step 4.5 skipped Steps 4.6 and 4.7 when no legacy AI directory existed** — "If none found → skip to Step 5" jumped over the memory-layout migration and the hook registration; it now continues with Step 4.6.
- **A `CLAUDE.md -> AGENTS.md` symlink destroyed AGENTS.md** — `install.sh` wrote the bootstrap pointer through the link, replacing AGENTS.md with a self-reference that the next run then counted as "already up to date". A symlinked `CLAUDE.md` is now skipped and reported.
- **A failing setup agent skipped all failure handling** — under `set -e`, a non-zero `wait` ended `install.sh` on the spot, so the failure was never reported and the guard that protects `CLAUDE.md` was dead code. The exit code is now captured: `CLAUDE.md` stays untouched, the failure is reported with the path of the kept `setup.log`, and the installer exits with the agent's code.
- **Sourcing `install.sh` from zsh ran the installer** — the "run only when executed" guard compared `${BASH_SOURCE[0]:-$0}` with `$0`; zsh has no `BASH_SOURCE` and sets `$0` to the sourced file, so the guard always passed and the full installer (including the `claude` spawn) ran. `install.sh` now refuses any non-bash shell up front.
- **`--local-source` was only recognized as the first argument** — `install.sh --force --local-source ./clone` silently ran a remote install, and `--local-source` without a path did the same. The flag is now honored in any position and in the `--local-source=<path>` spelling; a missing path — including a following flag such as `--local-source --force` — exits 1 with "requires a path", and the not-found error names both the flag and `AGENT_CONTEXT_SOURCE`.
- **Stale-cache warning never printed** — `get_latest_version` ran inside `$(...)`, so the `CACHE_STALE` flag it set was lost with the subshell and the fast-path never warned that its "already up to date" rested on a stale cache. It now sets `LATEST_VERSION`/`CACHE_STALE` in the caller's shell.

### Security

- **memory-prune wrote through symlinks out of the project** — the archive file name (`archive/<ISO-week>.md`) is predictable, and neither the archive file nor the archive directory was contained, so a repository shipping `archive/<week>.md -> ~/.bashrc` made `--apply` append its own expired entries to that file. On `--apply`, the default memory directory must now resolve inside the project and the default archive directory inside the memory directory, and a symlinked archive file is always refused (exit 2, source untouched). An explicit `--dir`/`--archive` stays the caller's choice, so deliberately shared memory directories keep working.
- **Secret-protection globs were expanded against the project root** — `PROTECTED_GLOBS` went through filename expansion, so an existing `a.pem` or `.env.local` narrowed `*.pem` / `.env.*` to that one name and every other matching file was writable again; matching was also case-sensitive, so `.ENV` reached `.env` on case-insensitive filesystems. Patterns are now matched literally and case-insensitively.
- **A CRLF `hooks.conf` switched every hook off** — `HOOKS_ENABLED=1\r` never equalled `1`. `conf-read.sh` now strips a trailing CR.
- **An escaped quote truncated a conf value** — `TEST_CMD="echo \"hi\" && false"` was read as `echo \`, a test gate that always passes. `conf-read.sh` does not do shell escaping, so such a key is now ignored and named on stderr instead of silently shortened.

### Docs

- **The README claimed installing never weakens a permission guard** — the installer runs its setup agent with `--dangerously-skip-permissions`. The README now says so, lists what the installer runs and names the repository-content injection surface; `SECURITY.md` scope covers it.
- **The one-liner silently dropped flags** — `bash -c "$(curl …)" --force` binds `--force` to `$0`. The README documents the `_ --force` form and a flag table.
- **0.9.0 entry** — release date corrected to 2026-09-27; the new `measure-baseline.sh` is listed.

## [0.9.0] - 2026-09-27

### Added

- **Measured layered-vs-flat baseline** — new shared `.agent-context/bin/measure-baseline.sh` reports what layering keeps out of every session: effective lines, bytes and a token estimate for the always-on set, the on-demand set and their flat sum. `check-token-budget.sh` gained `--json` output, which the measurement reuses so one engine defines both the gate and the numbers.
- **Per-file memory TTL defaults** — `.agent-context/bin/memory-prune.sh` now applies a default TTL to dated entries that carry no `ttl:` of their own. Ships with `lessons.md=90d` and `preferences.md`/`people.md`/`user.md=infinite`; projects tune it via `MEMORY_TTL_DEFAULTS` in `.agent-context/budget.conf`, per key, with a `*` catch-all. An explicit `ttl:` on the entry always wins, `ttl:infinite` included, and a line without a `(YYYY-MM-DD)` date is never touched. Keys match by basename at any depth.
- **Cross-repo lesson routing** — `layer0-agent-workflow.md` now covers multi-repo projects (e.g. frontend ↔ backend): the "Routing New Knowledge" table's gotcha row now points at the owning repo's `memory/lessons.md`, and the one-place rule is extended across repo boundaries. A lesson lives in the repo owning the code it describes; a shared-contract fact (API shape) has one canonical repo while sibling repos hold a pointer, never a copy. Ships entirely in the shared always-on layer, so it reaches existing installations on their next update; projects that want to declare their sibling repos do so in their own `layer1-bootstrap.md`.

### Changed

- **Prompt audit for current Claude models** — ran the `/claude-api prompt-audit` pass over every model-facing file. Stacked pressure language (`MUST — Non-negotiable`, `Do NOT attempt automatic repair`, `Work efficiently`, repeated "run first" lines) is now a single plain instruction that states its reason: in `layer0-agent-workflow.md`, `memory-maintenance.md`, `setup-prompt.md` (Step 0, discovery subagents), both review prompts and `templates/AGENTS.md`. `decision-review-prompt.md` had two lead-in sentences saying the same thing and a JSON-validity step that the re-read check already covers; both are merged into one. Fragile-operation scripts and emphasis that states a reason are unchanged.

### Fixed

- **Installer fetched the setup prompt from `main`, the files from the release tag** — `install.sh` always read `.prompts/setup-prompt.md` from `main`, while the prompt downloaded every shared file from the latest release tag. Any shared file merged to `main` before the next release therefore 404'd and rolled the whole update back (e.g. `context/bin/conf-read.sh` against `0.8.1`). The prompt is now fetched from the same release tag and told to install exactly that tag (`TARGET VERSION: <tag>`); `main` is only the fallback when the release lookup fails. `--force` is now parsed before the lookup, so it bypasses the version cache as documented. A pinned target is never a downgrade and skips the agent's own release lookup.
- **Installer crashed on Linux once a version cache existed** — `stat -f %m` ran first, which GNU `stat` reads as `--file-system` and answers on stdout, so the cache age became garbage and `set -u` aborted `install.sh`. GNU `stat -c %Y` now runs first.
- **Stale "Layer 0 →" pointers** — `discovery-map.md`, `templates/.agent-context/knowledge-map.md` and `layer3-guidebook.md` sent agents to "Layer 0 → Knowledge Map Triggers" and "Layer 0 → Domain Expansion", but both sections now live in `.agent-context/memory-maintenance.md`. The pointers now name that file.
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
