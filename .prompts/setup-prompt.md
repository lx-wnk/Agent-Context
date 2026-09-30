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

### AI Docs (inventory first, then route)

Built-in directories and files always treated as AI docs. The knowledge inventory (Phase S2 in SETUP, Step 5a in UPDATE) reads **every** one of them that exists, so its content is routed into the layers before anything is removed:

- `.ai/`
- `.agent-context/` (only migrate away from it when replacing with a newer structure — never delete the current destination)
- `AGENTS.md` (Agent-Context entry point — never delete during migration, only referenced)
- `CLAUDE.md` (root — `install.sh` swaps it for the bootstrap pointer; the agent never deletes it)
- `GEMINI.md` (root)
- `.claude/CLAUDE.md` (bootstrap pointer — never delete during migration, only referenced)
- `.claude/rules/`
- `.cursorrules`
- `.cursor/rules/`
- `.github/copilot-instructions.md`

If the prompt was invoked with an `--ai-dirs` argument (injected by `install.sh`), those directories extend this built-in list.

What may be removed after the inventory — this list is exhaustive:

- **Other tools' live configuration — never deleted or emptied:** `GEMINI.md`, `.claude/rules/`, `.cursorrules`, `.cursor/rules/`, `.github/copilot-instructions.md`. Their content is routed into the layers; the files stay, so they keep working for teammates who use those tools.
- **Legacy Agent-Context artefacts — removable only when recoverable:** `.ai/` and the `--ai-dirs` directories, and only when every file in them is committed to git and unmodified (Step 4.5c). Anything untracked, modified, or ignored stays in place and goes to the `UNRESOLVED` list.
- Nothing else is removed by this prompt.

### Real Docs (never modify, move, or delete)

Any file **not** in a built-in AI-doc path or a directory supplied via `--ai-dirs` is automatically a **Real Doc**. Only treat classification as uncertain for files **inside** those candidate AI-managed locations when it is unclear whether they are agent-managed infrastructure or project knowledge; in that case, default to **Real Doc** (conservative) and add it to the `UNRESOLVED` list in the post-migration report.

---

## Step 0: Interactive Mode Detection (run first)

Run this before reading or acting on any other step — later steps branch on `INTERACTIVE_MODE`. There is exactly one rule, and every later mention of interactive, headless, or asking the user follows it:

- Your launching instruction contains `HEADLESS: no user is present; never wait for input, decide per the prompt's headless rules.` (appended by `install.sh`) → `INTERACTIVE_MODE=false`. Never ask a question and never wait for input; decide as described in **Plan-File Mode** and record every decision there.
- The directive is absent (a user pasted or referenced this prompt in a session) → `INTERACTIVE_MODE=true`. Ask the user wherever this prompt says to ask.

Do not infer the mode from anything else — not from a TTY check, `CI`, `-p`, or the existence of `.claude/settings.json`.

**Installer-managed files:** if your launching instruction contains `INSTALLER MANAGES: …` (appended by `install.sh`), the installer has already copied the shared files (Step 2) and will itself write `.claude/commands/`, the hook entries in `.claude/settings.json`, `.claude/CLAUDE.md` and the version file after you finish. Do not write any of them and do not try to obtain permission for them: skip Step 2 (log `Step 2/5: Installing shared files — done by the installer`), skip every `.claude/` file in Step 3, skip Step 4.7 (log `Step 4.7: Hook registration — done by the installer`) and skip **Record the Installed Version**. Everything else — templates under `.agent-context/`, migration, discovery, knowledge re-sync — stays yours.

**Shell:** the Bash tool may run zsh. Every multi-line block in this prompt is written for bash 3.2 — run it as `bash <<'AC_SH'` … `AC_SH` (the blocks with bash-only syntax are already wrapped). Single-line commands are portable as written.

In non-interactive mode (`INTERACTIVE_MODE=false`), write progress to `.agent-context/setup.log` at the start of each step via a Bash tool call:

```bash
echo "[agent-context] Step N/5: <description>" >> .agent-context/setup.log
```

Create the log file at the very start (before Step 1) so `tail -f` can attach immediately:

```bash
mkdir -p .agent-context && : > .agent-context/setup.log
```

Every sub-step gets exactly one line of its own, in the form `[agent-context] Step <id>: <name> — <result>`, written when the sub-step ends; `install.sh` prints each log line on its own line, so never combine sub-steps into one line and log nothing else in between. The `MIGRATION_CLEANUP: ran` and `UNRESOLVED:` lines of Step 4.5 are the only additional lines.

Every number in a log line (versions, counts of files, sources, facts, lines) comes from a command run in this session — `cat`, `ls | wc -l`, `grep -c`, `wc -l`, or a count of the command output you are reporting on. Never estimate a number; if no command produced it, leave it out.

Example log entries:

```
[agent-context] Mode: UPDATE (0.3.0 → 0.5.0)
[agent-context] Step 1/5: Checking version...
[agent-context] Step 2/5: Installing shared files...
[agent-context] Step 3/5: Processing template files...
[agent-context] Step 4/5: Compatibility check...
[agent-context] Step 4.5: Migration cleanup — skipped (no legacy AI dirs found)
[agent-context] Step 4.6: Memory layout — already migrated
[agent-context] Step 4.7: Hook registration — already registered
[agent-context] Step 5/5: Knowledge re-sync...
[agent-context] Step 5.0: Change gate — 2 of 14 sources changed, re-syncing those
[agent-context] Step 5a: Fact inventory — 9 facts from 2 sources
[agent-context] Step 5b: Routing — 7 appended, 2 already present
[agent-context] Step 5c: Integrity check — all facts accounted for
[agent-context] Step 5d: Knowledge map — 2 hashes refreshed
[agent-context] Step 5e: Token budget — PASS (171 effective lines)
[agent-context] Done.
```

Write `[agent-context] Done.` as the final log line — not as a numbered step.

---

## Mode Detection

1. If `.agent-context/.agent-context-version` exists → **UPDATE** mode
2. Otherwise → **SETUP** mode

> **Launch directive** (from `install.sh`): If your launching instruction contains `FORCE / FULL REDISCOVERY`, run the **full SETUP-depth discovery even in UPDATE mode** — re-scan the entire codebase and rebuild the knowledge inventory from scratch, do not just reconcile deltas; merge into existing memory/decisions/knowledge-map and never delete a still-valid fact. (The discovery **map** — `map.json` + per-node notes — is built separately by the interactive `/discover` command, not here.)

If `INTERACTIVE_MODE=true`, announce the detected mode. In non-interactive mode, do NOT log the mode here — log it in Step 1 once the target version is known.

---

## Step 1: Version Selection

> **Local source mode:** If your launching instruction contains `LOCAL SOURCE MODE` (set by `install.sh --local-source <path>`), SKIP this entire step — do not query the GitHub releases API and do not pick a version. Take the target version from `<path>/CHANGELOG.md` (latest entry). In Steps 2 and 3, copy every file from `<path>/<relative-path>` instead of fetching from GitHub (do not build any `<tag>` URL).

> **Pinned target:** If your launching instruction contains `TARGET VERSION: <tag>` (set by `install.sh`, which fetched this prompt from that same tag), skip sub-steps 2–3 and 5–7 — do not query the releases API; the target is exactly `<tag>`. If `<tag>` is older than the installed version, never downgrade: log it and skip to Step 4.

1. Determine the installed version. If your launching instruction contains `INSTALLED VERSION: <version or none>` (set by `install.sh`), use that value verbatim — `none` means nothing is installed. Otherwise read it with `cat .agent-context/.agent-context-version` (missing file → none). Never infer it from the CHANGELOG, the layer files, or memory.
2. Fetch the release list from `https://api.github.com/repos/lx-wnk/Agent-Context/releases`
3. If the fetch fails or returns no releases:
   - **SETUP:** abort with an informative message — version selection is required
   - **UPDATE:** inform the user that releases could not be checked, skip to Step 4
     > **Note:** When invoked via `install.sh`, a shell-level fast-path runs before this agent starts and exits early when the installed version equals the latest release. That check is skipped when the release lookup fails or returns nothing, in local-source mode, when no version is installed, and under `--force` — so a running agent does not prove an update is needed. Direct invocation without `install.sh` always runs the full update flow.
4. If `INTERACTIVE_MODE=false`: skip the version prompt entirely — do not present a table or ask any question. Use the pinned target (see above) if there is one; otherwise use the latest stable release. Then log the mode, with the installed version exactly as determined in sub-step 1 and the target tag:
   ```bash
   echo "[agent-context] Mode: UPDATE (<installed> → <target>)" >> .agent-context/setup.log
   # or for SETUP:
   echo "[agent-context] Mode: SETUP (installing <target>)" >> .agent-context/setup.log
   ```
5. Present the available versions to the user (mark which is current, which is latest stable, and label pre-releases as `(pre-release)`)
6. Ask the user which version to install — default is `latest stable`
7. If the user declines → skip to Step 4
8. Store the selected version tag (e.g. `v0.5.0`) — it is used to build raw file URLs in Steps 2 and 3.

## Step 2: Install Shared Files

> Skipped entirely when the launching instruction contains `INSTALLER MANAGES` (see Step 0).

Fetch each shared file directly from GitHub raw content — no tarball or temp directory needed.

Base URL: `https://raw.githubusercontent.com/lx-wnk/Agent-Context/<tag>/`

| Source path                            | Destination                                   |
| -------------------------------------- | --------------------------------------------- |
| `context/agent-startup.md`             | `.agent-context/agent-startup.md`             |
| `context/layer0-agent-workflow.md`     | `.agent-context/layer0-agent-workflow.md`     |
| `context/base-principles.md`           | `.agent-context/base-principles.md`           |
| `context/agent-delegation.md`          | `.agent-context/agent-delegation.md`          |
| `context/memory-maintenance.md`        | `.agent-context/memory-maintenance.md`        |
| `.prompts/decision-review-prompt.md`   | `.agent-context/decision-review-prompt.md`    |
| `.prompts/memory-review-prompt.md`     | `.agent-context/memory-review-prompt.md`      |
| `context/bin/conf-read.sh`             | `.agent-context/bin/conf-read.sh`             |
| `context/bin/check-token-budget.sh`    | `.agent-context/bin/check-token-budget.sh`    |
| `context/bin/measure-baseline.sh`      | `.agent-context/bin/measure-baseline.sh`      |
| `context/bin/memory-prune.sh`          | `.agent-context/bin/memory-prune.sh`          |
| `context/bin/discovery-digest.sh`      | `.agent-context/bin/discovery-digest.sh`      |
| `context/bin/check-map-budget.sh`      | `.agent-context/bin/check-map-budget.sh`      |
| `context/bin/setup-steps.sh`           | `.agent-context/bin/setup-steps.sh`           |
| `context/skills/discovery-map.md`      | `.agent-context/skills/discovery-map.md`      |
| `context/commands/discover.md`         | `.claude/commands/discover.md`                |
| `context/commands/memory-review.md`    | `.claude/commands/memory-review.md`           |
| `context/commands/decision-review.md`  | `.claude/commands/decision-review.md`         |
| `context/hooks/lib.sh`                 | `.agent-context/hooks/lib.sh`                 |
| `context/hooks/pre-protect-secrets.sh` | `.agent-context/hooks/pre-protect-secrets.sh` |
| `context/hooks/post-format.sh`         | `.agent-context/hooks/post-format.sh`         |
| `context/hooks/stop-test-gate.sh`      | `.agent-context/hooks/stop-test-gate.sh`      |
| `context/hooks/subagent-scope.sh`      | `.agent-context/hooks/subagent-scope.sh`      |

Fetch all files **in parallel** — spawn each curl in the background and wait for all. Create `.agent-context/bin/`, `.agent-context/hooks/`, `.agent-context/skills/`, and `.claude/commands/` first (`mkdir -p .agent-context/bin .agent-context/hooks .agent-context/skills .claude/commands`) and `chmod +x` the scripts under `bin/` and `hooks/` after download:

```bash
bash <<'AC_SH'
mkdir -p .agent-context/bin .agent-context/hooks .agent-context/skills .claude/commands
pids=()
(curl -fsSL "https://raw.githubusercontent.com/lx-wnk/Agent-Context/<tag>/context/agent-startup.md" \
    -o ".agent-context/agent-startup.md.tmp" && mv ".agent-context/agent-startup.md.tmp" ".agent-context/agent-startup.md" || { rm -f ".agent-context/agent-startup.md.tmp"; exit 1; }) & pids+=($!)
(curl -fsSL "https://raw.githubusercontent.com/lx-wnk/Agent-Context/<tag>/context/layer0-agent-workflow.md" \
    -o ".agent-context/layer0-agent-workflow.md.tmp" && mv ".agent-context/layer0-agent-workflow.md.tmp" ".agent-context/layer0-agent-workflow.md" || { rm -f ".agent-context/layer0-agent-workflow.md.tmp"; exit 1; }) & pids+=($!)
(curl -fsSL "https://raw.githubusercontent.com/lx-wnk/Agent-Context/<tag>/context/base-principles.md" \
    -o ".agent-context/base-principles.md.tmp" && mv ".agent-context/base-principles.md.tmp" ".agent-context/base-principles.md" || { rm -f ".agent-context/base-principles.md.tmp"; exit 1; }) & pids+=($!)
(curl -fsSL "https://raw.githubusercontent.com/lx-wnk/Agent-Context/<tag>/context/agent-delegation.md" \
    -o ".agent-context/agent-delegation.md.tmp" && mv ".agent-context/agent-delegation.md.tmp" ".agent-context/agent-delegation.md" || { rm -f ".agent-context/agent-delegation.md.tmp"; exit 1; }) & pids+=($!)
(curl -fsSL "https://raw.githubusercontent.com/lx-wnk/Agent-Context/<tag>/context/memory-maintenance.md" \
    -o ".agent-context/memory-maintenance.md.tmp" && mv ".agent-context/memory-maintenance.md.tmp" ".agent-context/memory-maintenance.md" || { rm -f ".agent-context/memory-maintenance.md.tmp"; exit 1; }) & pids+=($!)
(curl -fsSL "https://raw.githubusercontent.com/lx-wnk/Agent-Context/<tag>/.prompts/decision-review-prompt.md" \
    -o ".agent-context/decision-review-prompt.md.tmp" && mv ".agent-context/decision-review-prompt.md.tmp" ".agent-context/decision-review-prompt.md" || { rm -f ".agent-context/decision-review-prompt.md.tmp"; exit 1; }) & pids+=($!)
(curl -fsSL "https://raw.githubusercontent.com/lx-wnk/Agent-Context/<tag>/.prompts/memory-review-prompt.md" \
    -o ".agent-context/memory-review-prompt.md.tmp" && mv ".agent-context/memory-review-prompt.md.tmp" ".agent-context/memory-review-prompt.md" || { rm -f ".agent-context/memory-review-prompt.md.tmp"; exit 1; }) & pids+=($!)
(curl -fsSL "https://raw.githubusercontent.com/lx-wnk/Agent-Context/<tag>/context/bin/conf-read.sh" \
    -o ".agent-context/bin/conf-read.sh.tmp" && mv ".agent-context/bin/conf-read.sh.tmp" ".agent-context/bin/conf-read.sh" || { rm -f ".agent-context/bin/conf-read.sh.tmp"; exit 1; }) & pids+=($!)
(curl -fsSL "https://raw.githubusercontent.com/lx-wnk/Agent-Context/<tag>/context/bin/check-token-budget.sh" \
    -o ".agent-context/bin/check-token-budget.sh.tmp" && mv ".agent-context/bin/check-token-budget.sh.tmp" ".agent-context/bin/check-token-budget.sh" || { rm -f ".agent-context/bin/check-token-budget.sh.tmp"; exit 1; }) & pids+=($!)
(curl -fsSL "https://raw.githubusercontent.com/lx-wnk/Agent-Context/<tag>/context/bin/measure-baseline.sh" \
    -o ".agent-context/bin/measure-baseline.sh.tmp" && mv ".agent-context/bin/measure-baseline.sh.tmp" ".agent-context/bin/measure-baseline.sh" || { rm -f ".agent-context/bin/measure-baseline.sh.tmp"; exit 1; }) & pids+=($!)
(curl -fsSL "https://raw.githubusercontent.com/lx-wnk/Agent-Context/<tag>/context/bin/memory-prune.sh" \
    -o ".agent-context/bin/memory-prune.sh.tmp" && mv ".agent-context/bin/memory-prune.sh.tmp" ".agent-context/bin/memory-prune.sh" || { rm -f ".agent-context/bin/memory-prune.sh.tmp"; exit 1; }) & pids+=($!)
(curl -fsSL "https://raw.githubusercontent.com/lx-wnk/Agent-Context/<tag>/context/bin/discovery-digest.sh" \
    -o ".agent-context/bin/discovery-digest.sh.tmp" && mv ".agent-context/bin/discovery-digest.sh.tmp" ".agent-context/bin/discovery-digest.sh" || { rm -f ".agent-context/bin/discovery-digest.sh.tmp"; exit 1; }) & pids+=($!)
(curl -fsSL "https://raw.githubusercontent.com/lx-wnk/Agent-Context/<tag>/context/bin/check-map-budget.sh" \
    -o ".agent-context/bin/check-map-budget.sh.tmp" && mv ".agent-context/bin/check-map-budget.sh.tmp" ".agent-context/bin/check-map-budget.sh" || { rm -f ".agent-context/bin/check-map-budget.sh.tmp"; exit 1; }) & pids+=($!)
(curl -fsSL "https://raw.githubusercontent.com/lx-wnk/Agent-Context/<tag>/context/bin/setup-steps.sh" \
    -o ".agent-context/bin/setup-steps.sh.tmp" && mv ".agent-context/bin/setup-steps.sh.tmp" ".agent-context/bin/setup-steps.sh" || { rm -f ".agent-context/bin/setup-steps.sh.tmp"; exit 1; }) & pids+=($!)
(curl -fsSL "https://raw.githubusercontent.com/lx-wnk/Agent-Context/<tag>/context/skills/discovery-map.md" \
    -o ".agent-context/skills/discovery-map.md.tmp" && mv ".agent-context/skills/discovery-map.md.tmp" ".agent-context/skills/discovery-map.md" || { rm -f ".agent-context/skills/discovery-map.md.tmp"; exit 1; }) & pids+=($!)
# Shipped commands all reference .agent-context/; a same-named file without it is the user's own — keep it.
for _cmd in discover.md memory-review.md decision-review.md; do
  (_dst=".claude/commands/$_cmd"
  if [ -f "$_dst" ] && ! grep -q '\.agent-context/' "$_dst"; then
    echo "Skipping $_dst: user-owned command (no .agent-context/ reference)" >&2; exit 0
  fi
  curl -fsSL "https://raw.githubusercontent.com/lx-wnk/Agent-Context/<tag>/context/commands/$_cmd" \
      -o "$_dst.tmp" && mv "$_dst.tmp" "$_dst" || { rm -f "$_dst.tmp"; exit 1; }) & pids+=($!)
done
for _hook in lib.sh pre-protect-secrets.sh post-format.sh stop-test-gate.sh subagent-scope.sh; do
  (curl -fsSL "https://raw.githubusercontent.com/lx-wnk/Agent-Context/<tag>/context/hooks/$_hook" \
      -o ".agent-context/hooks/$_hook.tmp" && mv ".agent-context/hooks/$_hook.tmp" ".agent-context/hooks/$_hook" || { rm -f ".agent-context/hooks/$_hook.tmp"; exit 1; }) & pids+=($!)
done

fail=0
for pid in "${pids[@]}"; do
    wait "$pid" || fail=1
done
if [ "$fail" -ne 0 ]; then
    rm -f .agent-context/*.tmp .agent-context/bin/*.tmp .agent-context/hooks/*.tmp .agent-context/skills/*.tmp .claude/commands/*.tmp
    echo "Error: one or more shared file downloads failed" >&2
    exit 1
fi
chmod +x .agent-context/bin/*.sh .agent-context/hooks/*.sh 2>/dev/null || true
AC_SH
```

A `.claude/commands/` file without an `.agent-context/` reference is a user-owned command of the same name: the block leaves it untouched and prints `Skipping …`. List every skipped command in the final summary so the user can rename theirs to receive ours.

> **Important:** If the parallel download block above exits non-zero (any file failed to download), **stop here.** The version file is written only by **Record the Installed Version** at the very end of a successful run, so a failed run leaves the old version (or none) in place and the next `install.sh` run retries.

## Step 3: Template Files

> With `INSTALLER MANAGES` (Step 0): install every template except those under `.claude/` — the installer writes those.

List all template files recursively via the GitHub Git Trees API (returns all nested paths in one call).
The `<tag>` placeholder is used directly as the tree ref — GitHub's API accepts branch/tag names here, not only SHAs (documented: "SHA1 value or ref (branch or tag) name of the tree"). Release tags are annotated; the Trees API peels a tag name to its commit's tree, so no prior `/git/refs/tags/<tag>` call is needed. If the lookup ever yields no templates, the block below aborts instead of installing nothing.

```bash
bash <<'AC_SH'
# Parse blob paths under templates/ with an awk state machine.
# Relies on GitHub's stable pretty-printed JSON format (one field per line, consistent since 2011).
_tree=$(curl -fsSL "https://api.github.com/repos/lx-wnk/Agent-Context/git/trees/<tag>?recursive=1")
_tmpls=$(printf '%s\n' "$_tree" | awk '
  /"path":/  { p = $0; sub(/.*"path": "/,  "", p); sub(/".*/, "", p); path = p }
  /"type":/  { t = $0; sub(/.*"type": "/,  "", t); sub(/".*/, "", t); type = t }
  /^[[:space:]]*\}/ {
    if (type == "blob" && substr(path, 1, 10) == "templates/")
      print substr(path, 11)
    path = ""; type = ""
  }
')

[ -z "$_tmpls" ] && { echo "Error: no templates parsed from API response — JSON format may have changed" >&2; exit 1; }

_pids=(); _dests=()
while IFS= read -r _rel; do
  [ -z "$_rel" ] && continue
  # Reject path traversal and absolute paths before allowlist check.
  case "$_rel" in
    *..*|/*|*\\*) echo "Skipping $_rel: unsafe path" >&2; continue ;;
  esac
  # Only write to known-safe destinations — guards against future templates landing
  # outside .agent-context/ (e.g. templates/README.md would clobber a project README).
  case "$_rel" in
    AGENTS.md|CLAUDE.md) ;;
    .agent-context/*|.claude/*) ;;
    *) echo "Skipping $_rel: outside allowlist" >&2; continue ;;
  esac
  [ -f "$_rel" ] && continue  # project-owned — never overwrite
  mkdir -p "$(dirname "$_rel")"
  _url="https://raw.githubusercontent.com/lx-wnk/Agent-Context/<tag>/templates/$_rel"
  (curl -fsSL "$_url" -o "$_rel.tmp" && mv "$_rel.tmp" "$_rel" \
    || { rm -f "$_rel.tmp"; exit 1; }) &
  _pids+=($!); _dests+=("$_rel")
done <<< "$_tmpls"

_fail=0
for _i in "${!_pids[@]}"; do
  wait "${_pids[$_i]}" || { echo "Error: failed to download ${_dests[$_i]}" >&2; _fail=1; }
done
[ "$_fail" -eq 0 ] || { for _d in "${_dests[@]}"; do rm -f "$_d.tmp"; done; exit 1; }
AC_SH
```

If a destination file already exists → skip it (project-owned, never overwrite).

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

| Signal                                                     | Action                                                                    |
| ---------------------------------------------------------- | ------------------------------------------------------------------------- |
| Size <30 lines AND maps cleanly to one layer               | Auto-route to target layer, no question                                   |
| Size >100 lines OR file has a table of contents            | Auto → add to `knowledge-map.md` as reference **AND distill** (see below) |
| Existing `setup-decisions.json` entry with matching SHA256 | Reuse previous decision silently                                          |

### Distillation (MANDATORY for every `reference` source)

A `knowledge-map.md` pointer alone is **not enough** — a large design/spec/architecture doc carries non-obvious facts that must be loaded by task routing, not just linked. For each source routed as `reference`, extract its **non-obvious gold** into the narrowest fitting home (skip anything discoverable from code):

| What to extract from the doc                                              | Goes to                                                                                    |
| ------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| Architecture decision + rationale (ADRs, "we chose X because Y")          | `decisions.json`                                                                           |
| Hard invariant / gotcha / "must/never" constraint (determinism, security) | `memory/lessons.md` (`ttl:infinite` for architecture/security)                             |
| A complex recurring subsystem (combat, economy, generation, auth)         | `memory/<domain>.md` stub: 3–8 lines of the non-obvious model + a pointer to the full spec |
| Domain glossary / project-specific terminology                            | `memory/<domain>.md` or `layer2-project-core.md`                                           |
| Frequently-needed reference too heavy for a stub (>30 lines distilled)    | `skills/<name>/SKILL.md`                                                                   |

Rules: each fact in exactly ONE place; the stub/lesson **summarizes** and links the spec (it does not copy it). Prefer 1–2 high-value nuggets per doc over exhaustive transcription — capture what a future task would otherwise have to re-derive. This is how "Besonderheiten / complex topics / perspektivisch benötigt" actually reach the agent.

### Requires Ack/Nack

In `INTERACTIVE_MODE=true`, ask the user when (in `INTERACTIVE_MODE=false`, decide these cases per **Plan-File Mode** instead):

- Confidence <0.8 OR content spans multiple layer categories
- Two sources contain contradicting information about the same topic
- A structured knowledge folder is discovered for the first time
- Size is 30–100 lines AND category is ambiguous

### Interactive Mode (`INTERACTIVE_MODE=true`)

Batch all pending Ack/Nack decisions into a single message:

```
I found the following — please confirm:
1. docs/architecture.md → reference in knowledge-map (287 lines, structured)  [Ack/Nack]
2. docs/api-guide.md    → reference in knowledge-map (412 lines, has TOC)     [Ack/Nack]
3. CONTRIBUTING.md      → consolidate into layer2 (18 lines, conventions)     [Ack/Nack]
```

High-confidence auto-decisions are listed in the summary only — not asked.

### Plan-File Mode (`INTERACTIVE_MODE=false`)

In headless mode, write `.agent-context/setup-plan.md` for transparency:

```markdown
# Setup Plan — YYYY-MM-DD

| #   | Source                     | Action      | Confidence | Status         |
| --- | -------------------------- | ----------- | ---------- | -------------- |
| 1   | docs/architecture.md       | reference   | 0.91       | ✅ auto        |
| 2   | CONTRIBUTING.md            | consolidate | 0.85       | ✅ auto        |
| 3   | src/: conflict rule A vs B | keep rule A | 0.55       | ✅ best-effort |
```

**Headless does NOT defer — it decides.** `install.sh` runs the agent once with `-p` and never re-runs it, so a `⏳ review` row would be silently dropped and its knowledge lost (this is the "memory looks empty" failure). Therefore, in headless mode you MUST resolve every row in this same run:

- Apply each source's `recommended_action` as a **best-effort** decision and execute it (route + distill). Mark it `✅ best-effort` in the plan.
- For a **conflict** between two sources, pick the higher-confidence / more-specific / more-recent one, apply it, and record the loser in the row note — do not skip the topic.
- Choose **non-destructive** resolutions when unsure: `reference` (+ distill) over `consolidate`, append over rewrite. Never delete a Real Doc.
- The plan file is an audit trail of what was auto-applied, **not** a queue waiting for a human. Leave no row in `⏳ review` when the run ends.

(`INTERACTIVE_MODE=true` still asks; only `INTERACTIVE_MODE=false` auto-resolves.)

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

Other tools' live configuration (`GEMINI.md`, `.claude/rules/`, `.cursorrules`, `.cursor/rules/`, `.github/copilot-instructions.md`) is a knowledge source like any other: record every file of it here, with its SHA256, the first time it is routed. The Step 5.0 change gate then re-syncs it only when it changes.

## Step 4.5: Migration Cleanup (SETUP and UPDATE)

Run this step in both SETUP and UPDATE mode — it self-skips in 4.5a if no legacy Agent-Context artefact is found.

### 4.5a: Detect old AI directories

Check whether any built-in AI-doc directories (other than `.agent-context/` itself) exist. The script also checks the `--ai-dirs` paths (the installer passes them as `AI_DIRS`; otherwise give them as the comma-separated argument) and skips a root `CLAUDE.md` that is only the `@AGENTS.md` pointer:

```bash
bash .agent-context/bin/setup-steps.sh detect-legacy
```

If none found → log `[agent-context] Step 4.5: Migration cleanup — skipped (no legacy AI dirs found)` and skip to Step 4.6 (4.6 and 4.7 still run).

If only other tools' live configuration or the root `CLAUDE.md` was found — no `.ai/` and no `--ai-dirs` path — log `[agent-context] Step 4.5: Migration cleanup — skipped (only other tools' config found; kept)` and skip to Step 4.6. That content reaches the layers through the normal knowledge-source path (Phase S2 / Step 5, recorded in `setup-decisions.json`), not through this step, and it never sets `MIGRATION_CLEANUP: ran`.

### 4.5b: Classify all files in old AI directories

For each found old directory/file:

1. Apply the **File Classification** rules from the top of this prompt.
2. Any file that cannot be classified confidently → add to `UNRESOLVED` list, do NOT touch it (log command in 4.5d).
3. Other tools' live configuration (`GEMINI.md`, `.claude/rules/`, `.cursorrules`, `.cursor/rules/`, `.github/copilot-instructions.md`) → keep in place; its content is routed by the inventory.
4. Legacy Agent-Context artefacts (`.ai/`, `--ai-dirs` directories) → removal candidates for 4.5c.

### 4.5c: Remove legacy Agent-Context artefacts (recoverable only)

Before removing a candidate, make sure its content has been inventoried and routed: in SETUP, Phase S2 already read it; in UPDATE, this step runs before Step 5, so read it now and route it with the **Knowledge Decision Logic** (same rules as Steps 5a–5b).

Remove the candidates in one call — the script removes a candidate only when git can restore it (every file under it tracked, committed and unmodified, nothing ignored inside), logs any other candidate as `UNRESOLVED`, and writes `MIGRATION_CLEANUP: ran` only after an actual removal:

```bash
bash .agent-context/bin/setup-steps.sh remove-legacy <candidate>...   # e.g. remove-legacy .ai
```

`MIGRATION_CLEANUP: ran` means exactly one thing: this run removed at least one legacy Agent-Context artefact. Steps 5.0 and 5d depend on that meaning. Finish Step 4.5 with its result line, e.g. `[agent-context] Step 4.5: Migration cleanup — removed .ai` or `[agent-context] Step 4.5: Migration cleanup — nothing removed (1 unresolved)`.

Do NOT delete Real Docs. Do NOT delete or empty other tools' live configuration. Do NOT carry path references to removed artefacts into the new structure.
A directory is only safe to remove if **all** of its contents are confirmed AI-docs. If any file inside cannot be confidently classified, skip the whole directory and add the unclassifiable paths to the `UNRESOLVED` list instead.
Do NOT delete `.agent-context/` itself — it is the destination of this migration.

### 4.5d: Mark UNRESOLVED files

If any files could not be classified, store them for the post-migration report:

```bash
# One line per unresolved file:
echo "[agent-context] UNRESOLVED: <path/to/file>" >> .agent-context/setup.log
```

If nothing is unresolved, skip this step. Never write `MIGRATION_CLEANUP: ran` here — only the 4.5c `remove-legacy` call writes it, and only after a removal.

---

## Step 4.6: Memory Layout Migration (UPDATE only)

This step migrates existing projects to the new memory layout: `memory/log.md` is retired, `memory/todo.md` becomes local-only. The step is idempotent — re-running on an already-migrated project is a no-op.

### 4.6a: Retire `memory/log.md` if present

If `.agent-context/memory/log.md` exists in the working tree: a tracked copy is removed (Git history keeps it); an untracked copy has no other copy, so it is moved to the memory archive (appended if an archived log already exists):

```bash
if git ls-files --error-unmatch .agent-context/memory/log.md >/dev/null 2>&1; then
  git rm -f .agent-context/memory/log.md
  echo "Removed memory/log.md — cross-session activity now lives in Git history."
elif [ -f .agent-context/memory/log.md ]; then
  mkdir -p .agent-context/memory/archive
  cat .agent-context/memory/log.md >> .agent-context/memory/archive/log.md \
    && rm -f .agent-context/memory/log.md
  echo "Moved untracked memory/log.md to memory/archive/log.md — cross-session activity now lives in Git history."
fi
```

### 4.6b: Untrack `memory/todo.md` if currently tracked

If `.agent-context/memory/todo.md` is tracked by git, untrack it (preserving the working-tree copy). The gitignore block that prevents future tracking is added in Step 4.6c.

`-f` is used so untracking succeeds even when the index has diverged from both HEAD and the working tree (e.g., staged-and-then-edited todo.md):

```bash
if git ls-files --error-unmatch .agent-context/memory/todo.md >/dev/null 2>&1; then
  git rm -f --cached .agent-context/memory/todo.md
  echo "memory/todo.md is now local-only. Your existing content is preserved but no longer tracked."
fi
```

### 4.6c: Ensure the gitignore block is present

Append the agent-context gitignore block to the consumer's `.gitignore` if (and only if) the marker `###> agent-context (transient working state) ###` is not already present. This makes the operation idempotent across re-runs.

```bash
bash .agent-context/bin/setup-steps.sh ensure-gitignore
```

### Idempotency

All three substeps are guarded by existence/tracking/marker checks — running this step twice produces no further changes. There is no separate marker file; the absence of `memory/log.md` (an archived copy under `memory/archive/` does not count), the untracked status of `memory/todo.md`, and the presence of the gitignore marker collectively encode "migration done".

---

## Step 4.7: Hook Registration (SETUP and UPDATE)

> Skipped when the launching instruction contains `INSTALLER MANAGES` (Step 0) — the installer merges the hook entries itself.

Agent-Context ships four optional, deterministic hooks (`.agent-context/hooks/`): secret-write block (PreToolUse), auto-format (PostToolUse), test gate (Stop), and subagent scope check (SubagentStop). The secret-write block is **on by default** (switch it off with `PROTECT_SECRETS=0`); the other three are **off** until `HOOKS_ENABLED=1` is set in the gitignored, per-developer `.agent-context/hooks.local.conf` — registering them enables only the secret-write block.

**Registration is additive and idempotent — never overwrite or remove existing `settings.json` content.**

1. **SETUP (no prior `.claude/settings.json`):** the template `settings.json` already contains the four hook registrations — nothing to do. In `INTERACTIVE_MODE=true`, you MAY ask the user whether to enable hooks now; if yes, set `HOOKS_ENABLED=1` in `.agent-context/hooks.conf` and fill `FORMAT_CMD` / `TEST_CMD` from the discovered toolchain (Phase S2). Otherwise leave `HOOKS_ENABLED=0`.

2. **UPDATE (existing `.claude/settings.json`):** read it and check each of the four hooks **separately** — a hook counts as registered only when its own script name (`pre-protect-secrets.sh`, `post-format.sh`, `stop-test-gate.sh`, `subagent-scope.sh`) appears in a hook command. If all four are registered → **skip**. Otherwise merge only the missing entries from below into the existing `hooks` object **additively** — preserve every existing key and every existing hook entry, only appending these. Do not touch `HOOKS_ENABLED` (stays `0` — existing projects are never silently activated).

   After writing, validate the merged file and report the result in the Step 4.7 log line (`registered N of 4, JSON valid` / `JSON unvalidated`). If validation fails, restore the file from the copy you read and log the step as failed:

   ```bash
   bash <<'AC_SH'
   f=.claude/settings.json
   for h in pre-protect-secrets.sh post-format.sh stop-test-gate.sh subagent-scope.sh; do
     grep -q "\.agent-context/hooks/$h" "$f" && echo "registered: $h" || echo "missing: $h"
   done
   if command -v jq >/dev/null 2>&1; then jq empty "$f" && echo "JSON valid (jq)"
   elif command -v python3 >/dev/null 2>&1; then python3 -m json.tool "$f" >/dev/null && echo "JSON valid (python3)"
   else echo "JSON unvalidated (no jq or python3)"; fi
   AC_SH
   ```

Canonical entries to merge (matchers and event names exactly as shown):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PROJECT_DIR}\"/.agent-context/hooks/pre-protect-secrets.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PROJECT_DIR}\"/.agent-context/hooks/post-format.sh",
            "timeout": 60
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PROJECT_DIR}\"/.agent-context/hooks/stop-test-gate.sh",
            "timeout": 600
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PROJECT_DIR}\"/.agent-context/hooks/subagent-scope.sh",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

If the user's `settings.json` already has entries for one of these events (e.g. their own `PreToolUse`), append our entry to that event's array rather than replacing it. Report in the summary that hooks were registered (disabled) and how to enable them (`HOOKS_ENABLED=1` + commands in `hooks.conf`).

---

## Step 5: Knowledge Re-Sync (UPDATE mode)

After updating shared files (Steps 1–4), re-synchronize project knowledge — but only when a knowledge source actually changed. A release that only ships new shared files must not cost a full scan.

### 5.0: Change gate

Skip this gate and run 5a–5e in full when the launching instruction contains `FORCE / FULL REDISCOVERY`, or when `grep -q "MIGRATION_CLEANUP: ran" .agent-context/setup.log` succeeds.

Otherwise compare the knowledge sources with `.agent-context/setup-decisions.json`:

1. For every path recorded there, compute `sha256sum <path>` (`shasum -a 256` on macOS) and compare it with the recorded `sha256`. A missing file counts as changed.
2. From `git ls-files --cached --others --exclude-standard`, list Markdown and structured-data documentation files outside `.agent-context/` that are not recorded yet and would qualify as a Knowledge Map Source (Global Constraint above), plus every file of other tools' live configuration (File Classification) that is not recorded yet.

If nothing changed and nothing is new → log `[agent-context] Step 5.0: Change gate — no source changed, 5a–5d skipped`, run only 5e, and finish. Otherwise log how many sources changed and run 5a–5d **for the changed and new sources only**; unchanged sources keep their routing. Source-code knowledge is not re-scanned by this gate — a full code re-scan is what `--force` (or the interactive `/discover`) is for.

### 5a: Consolidated Fact Inventory

Apply the **Global Constraint: Knowledge Map Sources** — run `git ls-files --cached --others --exclude-standard` and only consider files in that output.

Generate the discovery digest first (orientation; delete it at the end of the run):

```bash
bash .agent-context/bin/discovery-digest.sh > .agent-context/discovery-digest.md 2>/dev/null || true
```

Launch parallel subagents (same set as SETUP Phase S2 — **including Subagent 7: Project Specifics & Complexity**) to scan within the constraint set:

- Existing `.agent-context/` (all layers, memory/, decisions.json, skills/)
- Every built-in AI-doc path that exists (see **File Classification** — incl. other tools' configuration, which is read but never deleted)
- All root-level `*.md` files
- Any folder containing 3+ markdown or structured-data files
- The digest's "Distillation candidates" — heavy docs whose non-obvious gold may never have been distilled on an older install

Check `.agent-context/setup-decisions.json` for existing decisions — skip sources with matching SHA256.

For new or changed sources: apply Knowledge Decision Logic, including the **Distillation** step (extract invariants → `memory/lessons.md`, decisions → `decisions.json`, complex subsystems → `memory/<domain>.md`). In `INTERACTIVE_MODE=false`, follow the headless-decides policy — never leave a source in `⏳ review`. **An existing install with rich `docs/` but near-empty `memory/` is the signal that distillation never ran — backfill it now.**

### 5b: Routing & Restructuring (additive-only)

Route facts to their targets — **additive only, never overwrite existing content**:

| Fact Type                                        | Target                   | Rule                                                                |
| ------------------------------------------------ | ------------------------ | ------------------------------------------------------------------- |
| Project-wide convention                          | `layer2-project-core.md` | Append if keyword not already present                               |
| Domain-specific fact                             | `memory/<domain>.md`     | Append if keyword not already present                               |
| Heavy reference (>30 lines)                      | `skills/<reference>.md`  | Create if skill does not exist                                      |
| Gotcha / lesson                                  | `memory/lessons.md`      | Append with today's date, `ttl:90d source:discovered conf:med`      |
| Hard invariant (determinism, security, ordering) | `memory/lessons.md`      | Append with `ttl:infinite` — these don't go stale                   |
| Complex subsystem summary                        | `memory/<domain>.md`     | Create stub (3–8 lines, non-obvious model + spec pointer) if absent |
| Architecture decision                            | `decisions.json`         | Append to JSON array if id not present                              |
| External knowledge pointer                       | `knowledge-map.md`       | Append row if source not already listed                             |

Keyword check: search target file for 2–3 key terms from the fact. If found → skip. If not found → append.

### 5c: Global Integrity Check

For each fact/finding collected in 5a:

1. Search for its 2–3 key terms across all `.agent-context/` files and `knowledge-map.md`
2. If no match found → list as missing
3. If any facts are missing: in `INTERACTIVE_MODE=true`, report them to the user, do NOT commit — ask how to resolve; in `INTERACTIVE_MODE=false`, route each one now per **Plan-File Mode** (best-effort, non-destructive) and list any fact that still has no home in the summary
4. If all facts are accounted for → proceed

### 5d: knowledge-map.md Update

**If Migration Cleanup (Step 4.5c) removed a legacy artefact in this run** (check: `grep -q "MIGRATION_CLEANUP: ran" .agent-context/setup.log`):

Re-verify every Real-Doc row of `knowledge-map.md` (row-level edits only — never empty the file or recreate it from the template); reconcile `setup-decisions.json` by removing stale entries:

1. For `.agent-context/setup-decisions.json` keep entries whose source file still exists — only remove entries pointing to deleted paths
2. Scan all Real Docs currently in the repo (apply **Global Constraint: Knowledge Map Sources**)
3. Compute fresh SHA256 for each source: `sha256sum <file>`
4. In `knowledge-map.md`, update the rows whose source is a Real Doc (SHA256, Last Verified), append rows for Real Docs not listed yet, and drop rows whose source path no longer exists. Keep every row that points to `memory/`, `map.json`, `decisions.json`, or `skills/` — those come from discovery or were curated by hand
5. Ensure entries exist in `setup-decisions.json` for all currently-existing Real Docs; update SHA256 where changed
6. Scan `.agent-context/skills/` and rebuild `skills/index.md` from what actually exists there

No old paths. No stale hashes. No entries for files that no longer exist.

**Otherwise** (`MIGRATION_CLEANUP: ran` not found in log — incl. runs that only kept other tools' config)**:**

For each source with `action = "reference"`:

- Update SHA256 and Last Verified if the file has changed
- Add any new sources discovered since last run
- Remove entries for sources that no longer exist

Update `.agent-context/setup-decisions.json` with all new decisions.

### 5e: Token Budget Audit

Run `wc -l .agent-context/layer*.md .agent-context/knowledge-map.md .agent-context/memory/*.md` and report:

- Layer files ≥ 50 lines: flag as bloated
- `knowledge-map.md` ≥ 100 lines: flag for cleanup
- Memory files ≥ 500 lines: flag as skill graduation candidate
- Include the audit table in the summary output (✅ / ⚠️ per file)
- Run the always-on budget gate: `bash .agent-context/bin/check-token-budget.sh` (reads `.agent-context/budget.conf`). Before recommending anything, classify every `note: <file> is counted from INCLUDE_FILES but not @-imported` line — those files never load, so their lines are not a real cost:
  - **Import drift** — a template of the target version (`templates/` in the Agent-Context source) has an `@` line that resolves to `<file>`, but the project's copy of that file does not (project-owned layer files are never updated). Report the template file and line and the missing `@` line. Offer: add the import (the file then loads and its lines become real), or remove the entry if the project keeps the file out on purpose.
  - **Stale entry** — no template imports `<file>`. Offer: remove it from `INCLUDE_FILES`, or move it to `SESSION_START_FILES` if agents read it at session start.
  - For every option, give the projected total and its status against the soft and hard caps (PASS / WARN / FAIL). If `budget.conf` has no `SESSION_START_FILES` or `MAX_EFFECTIVE_LINES_HARD`, also recommend adding them (CHANGELOG 0.10.0 upgrade note).
  - Only lines that load (walked imports and `SESSION_START_FILES`) count as over budget; for those, recommend moving optional content behind routing. `budget.conf` and the layer files are project-owned — report and recommend, never edit them here.

## Record the Installed Version (last action)

> Skipped when the launching instruction contains `INSTALLER MANAGES` (Step 0) — the installer writes the version only after verifying the install.

Run this as the last action of a successful run — after Step 5e in UPDATE, after Phase S5 in SETUP — and immediately before writing `[agent-context] Done.`. Run it only if Steps 2 and 3 both completed for `<tag>` in this run; if the update was skipped, declined, refused as a downgrade, or any step failed, do not touch the file, so the next `install.sh` run retries:

```bash
echo "<tag>" > .agent-context/.agent-context-version
```

## UPDATE Mode: Done

If in UPDATE mode, skip all remaining phases (after **Record the Installed Version**). Return `ok: true` with a brief summary (e.g. "Updated 0.1.1 → 0.1.2" or "Already up to date" or "User declined update"). Always return `ok: true` — even on failure.

Always output the following at the very end of the UPDATE run. Omit the `UNRESOLVED` block if the list is empty:

```
Migration complete.

UNRESOLVED (could not be classified — review manually):
  - <file1>
  - <file2>

If anything didn't go as expected, resume this session with:
  claude --resume $CLAUDE_SESSION_ID
```

`$CLAUDE_SESSION_ID` is exported by `install.sh` before invoking the agent. If unset (fallback scenario), omit the resume line.

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
.claude/CLAUDE.md                        Bootstrap pointer → @../AGENTS.md
.claude/settings.json                    Settings file (created if missing, never overwritten)
.agent-context/
  agent-startup.md                       🔒 SHARED — do NOT modify (auto-updated)
  layer0-agent-workflow.md               🔒 SHARED — do NOT modify (auto-updated)
  base-principles.md                     🔒 SHARED — do NOT modify (auto-updated)
  agent-delegation.md                    🔒 SHARED — on-demand delegation protocol (auto-updated)
  memory-maintenance.md                  🔒 SHARED — on-demand memory restructuring (auto-updated)
  .agent-context-version                 🔒 SHARED — written last by a successful setup/update
  memory-review-prompt.md               🔒 SHARED — do NOT modify (auto-updated)
  decision-review-prompt.md              🔒 SHARED — do NOT modify (auto-updated)
  bin/
    conf-read.sh                         🔒 SHARED — non-evaluating .conf parser (auto-updated)
    check-token-budget.sh                🔒 SHARED — always-on budget gate (auto-updated)
    measure-baseline.sh                  🔒 SHARED — layered-vs-flat baseline report (auto-updated)
    memory-prune.sh                      🔒 SHARED — memory decay/archive (auto-updated)
    discovery-digest.sh                  🔒 SHARED — deterministic discovery inventory (auto-updated)
    check-map-budget.sh                  🔒 SHARED — discovery-map cap gate (auto-updated)
    setup-steps.sh                       🔒 SHARED — deterministic setup steps (auto-updated)
  hooks/
    lib.sh                               🔒 SHARED — hook helpers (auto-updated)
    pre-protect-secrets.sh               🔒 SHARED — PreToolUse secret block (auto-updated)
    post-format.sh                       🔒 SHARED — PostToolUse auto-format (auto-updated)
    stop-test-gate.sh                    🔒 SHARED — Stop test gate (auto-updated)
    subagent-scope.sh                    🔒 SHARED — SubagentStop scope check (auto-updated)
  hooks.conf                             PROJECT — hook toggles + toolchain (never overwritten)
  budget.conf                            PROJECT — token-budget + memory-TTL config (never overwritten)
  knowledge-map.md                       PROJECT — maintained by agent, never recreate from template
  setup-decisions.json                   PROJECT — maintained by agent, never recreate from template
  decisions.json                         PROJECT — structured decisions (auto-reviewed)
  layer1-bootstrap.md                    PROJECT — customize freely
  layer2-project-core.md                 PROJECT — customize freely
  layer3-guidebook.md                    PROJECT — customize freely
  skills/
    index.md                             PROJECT — skill registry
    discovery-map.md                     🔒 SHARED — on-demand discovery skill (auto-updated)
  memory/                                PROJECT — customize freely
    index.md                             Memory file catalog
    lessons.md
    people.md
    preferences.md
    todo.md                              (local-only, gitignored)
    user.md
    map/                                 Discovery map.json + <node>.md notes (built by /discover, not here)
```

#### Ownership rules

**🔒 SHARED files** are overwritten on every auto-update. Never add project-specific content to them — it will be lost.
Put project-specific workflow rules in `layer2-project-core.md`, task routing in `layer3-guidebook.md`.

**PROJECT files** are created once from templates and never overwritten. All project customization goes here.

### Phase S2: Discovery (Parallel Subagent Scan)

**First, generate the discovery digest** — a deterministic orientation map so no manifest, service, or doc is missed and the subagents spend their budget on judgement rather than re-scanning:

```bash
bash .agent-context/bin/discovery-digest.sh > .agent-context/discovery-digest.md 2>/dev/null \
  || echo "(digest script unavailable — subagents scan unaided)"
```

Pass the digest's contents to every subagent as orientation. It is an **accelerator, not a whitelist** — subagents must still scan deeper than the digest lists. The "Documentation inventory" and "Distillation candidates" tables in the digest are the authoritative list of docs to process (every row must end up either routed+distilled or explicitly classified `ignore` — none silently skipped). Delete `.agent-context/discovery-digest.md` at the end of the run (it is a transient scratch file, not project knowledge).

Launch **7 parallel subagents** to scan the project, and run all seven — each covers a source type the others don't, so skipping one silently drops knowledge from the map.

#### Subagent 1: Documentation & Knowledge Scanner

Apply the **Global Constraint: Knowledge Map Sources** — run `git ls-files --cached --others --exclude-standard` and only consider files in that output.

Scan for all existing documentation and structured knowledge sources within that set:

- Root-level markdown files: `CLAUDE.md`, `AGENTS.md`, `README.md`, `CONTRIBUTING.md`, `CHANGELOG.md`
- `.claude/rules/*.md`, `skills-lock.json`
- Other AI-doc paths (see **File Classification**): `GEMINI.md`, `.cursorrules`, `.cursor/rules/`, `.github/copilot-instructions.md`, `.ai/`, and any `--ai-dirs` directory — read for routing, never deleted by the inventory
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
- `.env.example` / `.env.dist` — `APP_URL`, `BASE_URL`, `SHOP_URL`, other domains

Never read `.env` (or `.env.local` and similar) — it holds secrets. If a domain appears only there, grep the named keys with credentials masked, and never copy anything else from it:

```bash
grep -E '^(APP_URL|BASE_URL|SHOP_URL)=' .env | sed -E 's#://[^/@]*@#://***@#'
```

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

#### Subagent 7: Project Specifics & Complexity

This subagent exists to capture what the others miss: **non-obvious peculiarities, hard-won constraints, and the complex subsystems a future task will repeatedly need.** Read the "Distillation candidates" from the digest (the heavy design/spec/architecture docs) plus any in-code signals, and surface:

- **Hard invariants / gotchas** — determinism requirements, integer-only math, custom PRNG, idempotency keys, re-simulation/anti-cheat rules, ordering constraints, security boundaries. Anything where "if you don't know this, you'll break it."
- **Architecture decisions + rationale** — ADRs, "we chose X over Y because Z", explicit trade-offs.
- **Complex recurring subsystems** — name each (e.g. combat engine, economy/balancing, procedural generation, auth/RLS) with a 1–2 line non-obvious model summary and the spec path.
- **Domain glossary** — project-specific terms a newcomer/agent wouldn't infer from code.
- **Frequently-needed references** — the docs that will be opened again and again for a whole class of tasks.

For each finding output: `{ "kind": "invariant|decision|subsystem|glossary|reference", "summary": "<1-2 lines, non-obvious only>", "source": "<doc path>", "target": "memory/lessons.md|decisions.json|memory/<domain>.md|skills/<name>/SKILL.md" }`.

Apply the **discoverability filter**: skip anything an agent could read straight from the code. Only capture what must be told. These findings feed the **Distillation** step — they are the primary mechanism for getting Besonderheiten and complex topics into task-routed memory.

#### Merge Results

Collect all subagent outputs. Document each finding with its target layer:

| Finding type                              | Document in                       |
| ----------------------------------------- | --------------------------------- |
| Project name, stack                       | `layer1-bootstrap.md`             |
| Docker, domains                           | `layer1-bootstrap.md`             |
| Conventions, CI, testing                  | `layer2-project-core.md`          |
| Skills, task routing                      | `layer3-guidebook.md`             |
| Invariant / gotcha (Subagent 7)           | `memory/lessons.md`               |
| Architecture decision (Subagent 7)        | `decisions.json`                  |
| Complex subsystem / glossary (Subagent 7) | `memory/<domain>.md` (or skill)   |
| Existing doc content                      | Input for Phase S3 classification |

Only ask the user for values that no subagent could auto-detect. In `INTERACTIVE_MODE=false`, leave such a value as a `TODO` placeholder and list it in the summary instead.

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

- Run **Step 4.5: Migration Cleanup** — removes only committed, unmodified legacy Agent-Context artefacts (`.ai/`, `--ai-dirs` directories)
- Do NOT delete or empty other tools' source files (`GEMINI.md`, `.claude/rules/`, `.cursorrules`, `.cursor/rules/`, `.github/copilot-instructions.md`) — their content is routed into the layers, the files keep working for teammates
- Verify `.agent-context/` is NOT in `.gitignore`

**Verification:**

1. `AGENTS.md` exists with identity and layer references
2. No `TODO` placeholders remain (except intentional ones)
3. `wc -l AGENTS.md` < 45 lines
4. Check `.agent-context/memory/*.md` line counts — domain stubs < 15 lines each (skip `index.md` and `todo.md`)
5. **Token Budget Audit** — run `wc -l .agent-context/layer*.md .agent-context/knowledge-map.md .agent-context/memory/*.md` and report:
   - Layer files ≥ 50 lines: flag as bloated
   - `knowledge-map.md` ≥ 100 lines: flag for cleanup
   - Memory files ≥ 500 lines: flag as skill graduation candidate
   - Include the audit table in the summary output (✅ / ⚠️ per file)
6. No duplicated content across files
7. `.claude/CLAUDE.md` points to `@../AGENTS.md` (imports resolve relative to the importing file)
8. **Migration audit checklist from Phase S3.5 is 100% checked off**
9. `.agent-context/memory/index.md` exists
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

**Gitignore for transient memory state:**

Make `memory/todo.md` local-only. If the file is already tracked (e.g., a prior abandoned setup or a project that pre-tracked the path), untrack it first — same semantics as Step 4.6b for UPDATE mode:

```bash
if git ls-files --error-unmatch .agent-context/memory/todo.md >/dev/null 2>&1; then
  git rm -f --cached .agent-context/memory/todo.md
fi
```

Then append the agent-context gitignore block to the consumer's `.gitignore` so the file stays untracked. The block is idempotent — guarded by the marker check, re-runs are a no-op:

```bash
bash .agent-context/bin/setup-steps.sh ensure-gitignore
```

Then run **Record the Installed Version** as the last action before `[agent-context] Done.`

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

`$CLAUDE_SESSION_ID` is exported by `install.sh` before invoking the agent. If unset (fallback scenario), omit the resume line.

---

## Error Handling

- **Network failure** (API unreachable, raw file or Trees API download fails):
  - **SETUP:** abort — cannot proceed without release files
  - **UPDATE:** skip update, keep existing files, return `ok: true`
- **Corrupted/incomplete archive**: Do NOT overwrite existing files with partial content. Skip update, return `ok: true`
- **File write failure**: Log which file failed, continue with remaining files
- **UPDATE mode** is best-effort — never block session start. **SETUP mode** should fail fast with clear messages.

## Constraints

- **Non-destructive:** Never overwrite project-owned files that already have content
- **Ask or decide, never guess silently:** If information cannot be auto-detected, ask the user in `INTERACTIVE_MODE=true`; in `INTERACTIVE_MODE=false`, decide per **Plan-File Mode** and record the decision (Step 0)
- **One fact, one place:** No duplication across files
- **No over-engineering:** Skip skills if total content < ~200 lines, skip memory stubs if domain < ~30 lines
- **Preserve knowledge:** Nothing gets deleted — it gets routed, filtered, or promoted to code. The only removals are committed, unmodified legacy Agent-Context artefacts (Step 4.5c) and a tracked `memory/log.md` (Step 4.6a), both recoverable from git; other tools' configuration is never deleted or emptied
- **Audit before overwrite:** Always run Phase S3.5 before overwriting shared files in existing projects — the new shared files are generic and will silently drop project-specific workflow rules
