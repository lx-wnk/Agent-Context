# Enforcement & Hygiene

The layered context is advisory — these add deterministic, OS-level guardrails on top. All are optional, project-overridable, and never overwrite project-owned files.

## Deterministic Hooks

Four Claude Code hooks ship as shared scripts in `.agent-context/hooks/`, governed by the committed `.agent-context/hooks.conf` and the user-local `.agent-context/hooks.local.conf`:

| Hook                     | Event        | Default | What it does                                                      |
| ------------------------ | ------------ | ------- | ----------------------------------------------------------------- |
| `pre-protect-secrets.sh` | PreToolUse   | on\*    | Blocks writes to `.env`/secret files (exit 2) — `PROTECTED_GLOBS` |
| `post-format.sh`         | PostToolUse  | on\*    | Runs `FORMAT_CMD` on the edited file                              |
| `stop-test-gate.sh`      | Stop         | warn    | Runs `TEST_CMD`; `warn` reports failures, `block` forces a fix    |
| `subagent-scope.sh`      | SubagentStop | off     | Flags a subagent that wrote outside `ALLOWED_SUBAGENT_PATHS`      |

\* Per-hook flags only take effect once the master switch is on. **`HOOKS_ENABLED=0` by default** — nothing fires until you opt in. To enable: set `HOOKS_ENABLED=1` and your toolchain's `FORMAT_CMD` / `TEST_CMD` in the gitignored, per-developer `.agent-context/hooks.local.conf`. Those three keys are read **only** from that file and ignored in the committed `hooks.conf`: `TEST_CMD` and `FORMAT_CMD` are executed, so a `git pull` must not be able to switch hooks on or change what they run. Every other key comes from `hooks.conf`, and `hooks.local.conf` may override it. Both files are parsed, never sourced. The scripts read the confs for all behavior, so you customize without editing shared code; for deeper changes, point `.claude/settings.json` at your own script. Hooks need no extra dependencies (`jq` is used when present, with a pure-shell fallback).

## Token Budget

`.agent-context/bin/check-token-budget.sh` counts the **effective instruction lines** of what actually loads: the `@`-import closure walked from `.claude/CLAUDE.md` (and a root `CLAUDE.md`, if present), each import resolved relative to the file that contains it, plus the files listed in `budget.conf`. `SESSION_START_FILES` lists the reads an agent does at every session start without an import (the template ships `memory/lessons.md` and `memory/preferences.md`); they are counted silently. `INCLUDE_FILES` is the legacy additive list: its entries still count, but each one the walk does not reach is printed as a `note:`, so a stale entry for a file that no longer loads cannot count silently. An import that points at no file is reported as a warning. Two caps in `budget.conf`: over the **soft cap** `MAX_EFFECTIVE_LINES` (default 200) only warns — so a real project filling its layers isn't blocked at line 201 — while over the **hard cap** `MAX_EFFECTIVE_LINES_HARD` fails. The hard cap defaults to 250 when the line is absent; set it equal to the soft cap to make the soft cap a hard failure. The repo's own CI (`.github/workflows/ci.yml`) enforces a tighter single limit on the shared baseline so a release can't silently bloat what every install loads. Run it yourself any time:

```bash
bash .agent-context/bin/check-token-budget.sh
```

## Baseline Measurement

The token budget says whether the always-on closure is small. It does not say what layering actually buys, and "loads less" is a claim until something counts it. `.agent-context/bin/measure-baseline.sh` counts both halves:

```bash
bash .agent-context/bin/measure-baseline.sh          # table
bash .agent-context/bin/measure-baseline.sh --json   # same numbers, machine-readable
```

- **layered** — the always-on set exactly as the budget gate resolves it: the walked `@`-import closure plus `SESSION_START_FILES` and `INCLUDE_FILES`, read at every session start.
- **on-demand** — `memory/` (minus `memory/archive/`), `skills/`, `agent-delegation.md`, `memory-maintenance.md`, and any `map.json`: project knowledge pulled only when a task's keywords match it.
- **flat** — the sum, i.e. the pre-layering shape where one file holds everything.

Each set is reported as effective instruction lines, file bytes, and `ceil(bytes/4)` as a token estimate. Counting is delegated to `check-token-budget.sh --json`, so one engine defines both the gate and the report and the two can never disagree.

**Read the delta honestly.** It is the always-on load a flat setup pays on every session and a layered one does not — an **upper bound**, reached only by a task that needs none of the on-demand set. A task that pulls two skills pays for those two skills. Nothing here models file reads the agent "would otherwise have done"; the moment a measurement starts counting hypothetical reads it stops being a measurement.

## Memory Decay

Dated memory entries carry a TTL (`(2026-01-15) ttl:90d`). `.agent-context/bin/memory-prune.sh` archives expired entries into `memory/archive/<ISO-week>.md` — dry-run by default, never deletes:

```bash
bash .agent-context/bin/memory-prune.sh           # preview what would move
bash .agent-context/bin/memory-prune.sh --apply   # archive expired entries
```

`ttl:infinite` (architecture/security) never expires. **When does memory go stale?** A lesson tagged `ttl:90d` is considered stale 90 days after its date. An entry that carries a date but no `ttl:` falls back to the per-file default — 90d for `lessons.md`, `infinite` for `preferences.md`, `people.md`, and `user.md` — configurable per project through `MEMORY_TTL_DEFAULTS` in `.agent-context/budget.conf`. Conf keys merge into the shared table per key — files you don't list keep their shared default — and match by basename at any depth, so a `lessons.md` entry also governs `memory/<domain>/lessons.md`. An explicit `ttl:` on the entry always wins. Stale context actively misleads — pruning keeps the live set trustworthy while preserving history in the archive. Archiving is not erasure: a memory file can hold third-party personal data, so honoring a GDPR Art. 17 request means also removing the entry from `memory/archive/*.md`. A memory directory that multiple projects reach via a symlinked `memory/` (or a shared `--dir`) is per-project on the archive side too — archiving resolves from the invoking project's own `--dir`/`--archive`, not from where the content physically lives, so pruning content shared by N projects can produce N independent, divergent archive copies unless every project points `--archive` at the same location.

## Portable Skills

Skills follow the open [Agent Skills standard](skill-standard.md) (`skills/<name>/SKILL.md` with `name` + `description` frontmatter), making `.agent-context/skills/` portable across Claude Code, Codex, Cursor, and Gemini. Legacy flat `skills/<name>.md` files remain valid.

## Updates

After creating a [GitHub Release](https://github.com/lx-wnk/Agent-Context/releases), projects update by re-running the `install.sh` one-liner. The script compares the installed version against the latest release (GitHub Releases API, TTL-cached for 1 hour) — if already up-to-date, it exits immediately without spawning Claude. If a new version is available, Claude downloads the shared files in parallel, overwrites them, and runs a full knowledge re-synchronization: scanning all project knowledge sources, routing new facts to optimal targets, and verifying nothing was lost. Project-owned files receive improvements additively; content is never deleted. If the API is unreachable, the installer falls back to the cached version.
