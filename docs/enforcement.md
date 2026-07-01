# Enforcement & Hygiene

The layered context is advisory — these add deterministic, OS-level guardrails on top. All are optional, project-overridable, and never overwrite project-owned files.

## Deterministic Hooks

Four Claude Code hooks ship as shared scripts in `.agent-context/hooks/`, governed by the project-owned `.agent-context/hooks.conf`:

| Hook                     | Event        | Default | What it does                                                      |
| ------------------------ | ------------ | ------- | ----------------------------------------------------------------- |
| `pre-protect-secrets.sh` | PreToolUse   | on\*    | Blocks writes to `.env`/secret files (exit 2) — `PROTECTED_GLOBS` |
| `post-format.sh`         | PostToolUse  | on\*    | Runs `FORMAT_CMD` on the edited file                              |
| `stop-test-gate.sh`      | Stop         | warn    | Runs `TEST_CMD`; `warn` reports failures, `block` forces a fix    |
| `subagent-scope.sh`      | SubagentStop | off     | Flags a subagent that wrote outside `ALLOWED_SUBAGENT_PATHS`      |

\* Per-hook flags only take effect once the master switch is on. **`HOOKS_ENABLED=0` by default** — nothing fires until you opt in. To enable: set `HOOKS_ENABLED=1` in `.agent-context/hooks.conf` and fill in `FORMAT_CMD` / `TEST_CMD` for your toolchain. The scripts read the conf for all behavior, so you customize without editing shared code; for deeper changes, point `.claude/settings.json` at your own script. Hooks need no extra dependencies (`jq` is used when present, with a pure-shell fallback).

## Token Budget

`.agent-context/bin/check-token-budget.sh` counts the **effective instruction lines** of the always-on closure (the files `@`-included from `AGENTS.md`) and fails if they exceed `MAX_EFFECTIVE_LINES` in `budget.conf` (default 200). The repo's own CI (`.github/workflows/ci.yml`) enforces a tighter limit on the shared baseline so a release can't silently bloat what every install loads. Run it yourself any time:

```bash
bash .agent-context/bin/check-token-budget.sh
```

## Memory Decay

Dated memory entries carry a TTL (`(2026-01-15) ttl:90d`). `.agent-context/bin/memory-prune.sh` archives expired entries into `memory/archive/<ISO-week>.md` — dry-run by default, never deletes:

```bash
bash .agent-context/bin/memory-prune.sh           # preview what would move
bash .agent-context/bin/memory-prune.sh --apply   # archive expired entries
```

`ttl:infinite` (architecture/security) never expires. **When does memory go stale?** A lesson tagged `ttl:90d` is considered stale 90 days after its date; gotchas/quirks default to 90d, sprint-specific notes to 30d, and durable architecture/security facts to `infinite`. Stale context actively misleads — pruning keeps the live set trustworthy while preserving history in the archive.

## Portable Skills

Skills follow the open [Agent Skills standard](skill-standard.md) (`skills/<name>/SKILL.md` with `name` + `description` frontmatter), making `.agent-context/skills/` portable across Claude Code, Codex, Cursor, and Gemini. Legacy flat `skills/<name>.md` files remain valid.

## Updates

After creating a [GitHub Release](https://github.com/lx-wnk/Agent-Context/releases), projects update by re-running the `install.sh` one-liner. The script compares the installed version against the latest release (GitHub Releases API, TTL-cached for 1 hour) — if already up-to-date, it exits immediately without spawning Claude. If a new version is available, Claude downloads the shared files in parallel, overwrites them, and runs a full knowledge re-synchronization: scanning all project knowledge sources, routing new facts to optimal targets, and verifying nothing was lost. Project-owned files receive improvements additively; content is never deleted. If the API is unreachable, the installer falls back to the cached version.
