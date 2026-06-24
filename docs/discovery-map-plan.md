# Discovery Map Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an on-demand, agent-authored discovery map (concept graph + curated per-node notes) that absorbs Graphify's auto-generation / queryable / scaling strengths without loading anything into the always-on baseline.

**Architecture:** A new shared Skill `discovery-map` orchestrates fan-out discovery subagents that read the cheap `discovery-digest.sh` inventory, judge each subsystem, and write a tiny `map.json` (navigate) plus `memory/<node>.md` (depth). A new shared deterministic validator `check-map-budget.sh` (no JSON-parser dependency) enforces size caps from `budget.conf`, guarded by a fixtures unit test. Everything is pulled on-demand — never `@`-included.

**Tech Stack:** Bash (POSIX/Bash 3.2, awk state machines, no jq/python — matches repo's dependency-free direction), Markdown skills with YAML trigger frontmatter, JSON artifact, Prettier.

**Spec:** `docs/discovery-map-design.md`

**Base branch:** `feat/deterministic-hooks-budget-decay` (has `budget.conf`, `context/bin/`, `tests/check-*-unit.sh` patterns this plan mirrors).

---

## File Structure

| File                                           | Action          | Responsibility                                                                                                     |
| ---------------------------------------------- | --------------- | ------------------------------------------------------------------------------------------------------------------ |
| `templates/.agent-context/budget.conf`         | Modify          | Add map-cap keys (`MAP_FILE`, `MAP_MAX_TOTAL_BYTES`, `MAP_MAX_NODES`, `MAP_MAX_NODE_LINE_BYTES`)                   |
| `context/bin/check-map-budget.sh`              | Create (shared) | Deterministic cap validator for `map.json` — bytes / node-count / longest-line proxies                             |
| `tests/check-map-budget-unit.sh`               | Create          | Fixture-driven unit tests for the validator                                                                        |
| `context/skills/discovery-map.md`              | Create (shared) | The discovery Skill: fan-out, watermark incremental, writes map.json + notes + knowledge-map rows + cap self-check |
| `templates/.agent-context/skills/index.md`     | Modify          | Register the discovery-map skill row                                                                               |
| `templates/.agent-context/layer3-guidebook.md` | Modify          | Routing row: unknown-subsystem / onboarding → discovery-map                                                        |
| `.prompts/setup-prompt.md`                     | Modify          | Wire both shared files (skill + validator) into Step 2 download table + parallel curl block + mkdir/chmod          |
| `package.json`                                 | Modify          | Add `bash tests/check-map-budget-unit.sh` to the `test` script                                                     |
| `README.md`                                    | Modify          | New "On-demand Discovery Map" section + comparison vs auto-graph tools                                             |
| `CLAUDE.md`                                    | Modify          | Architecture table + artifact + shared-files note                                                                  |

**Not touched:** `templates/.agent-context/decisions.json` stays `[]` (project-owned template). `install.sh` `check_critical_templates()` unchanged (no new _template_ — `budget.conf` is already guarded; the new files are _shared_, guarded via setup-prompt download list).

---

## map.json schema (authoritative — referenced by validator, unit test, and skill)

One node per line inside `"nodes"` so longest-line is a per-node size proxy.

```jsonc
{
  "generated": "2026-06-24",
  "nodes": [
    {
      "id": "auth",
      "label": "Authentication & Sessions",
      "globs": ["src/auth/**"],
      "note": "memory/auth.md",
      "watermark": "<sha>",
      "stale": false,
    },
  ],
  "edges": [{ "from": "billing", "to": "auth", "rel": "depends-on", "why": "shared user ctx" }],
}
```

Caps (deterministic, no JSON parser):

- `MAP_MAX_TOTAL_BYTES` — whole file (`wc -c`). Small on purpose → forces hierarchy on big repos.
- `MAP_MAX_NODES` — count of `"id":` occurrences.
- `MAP_MAX_NODE_LINE_BYTES` — longest line length (awk), proxy for a single node's size.

---

## Task 1: Add map-cap keys to budget.conf

**Files:**

- Modify: `templates/.agent-context/budget.conf` (append a new section at end)

- [ ] **Step 1: Append the cap section**

Add to the END of `templates/.agent-context/budget.conf`:

```bash

# --- Discovery map caps (read by .agent-context/bin/check-map-budget.sh) ---
# The discovery map is pulled ON-DEMAND, never @-included. These caps keep the
# top index tiny so even a 10k-file repo costs only a small index + 1–2 node notes.
# A coarse repo that exceeds MAP_MAX_TOTAL_BYTES must split hierarchically into
# memory/<area>/map.json (see the discovery-map skill).

# Path to the top-level map relative to the project root.
MAP_FILE=".agent-context/map.json"

# Whole-file byte ceiling for the top index. Deliberately small.
MAP_MAX_TOTAL_BYTES=16384

# Max number of nodes in the top index (counted as "id": occurrences).
MAP_MAX_NODES=60

# Longest single line allowed (one node per line → per-node size proxy).
MAP_MAX_NODE_LINE_BYTES=400
```

- [ ] **Step 2: Verify it sources cleanly**

Run: `bash -n templates/.agent-context/budget.conf && ( . templates/.agent-context/budget.conf && echo "MAP_FILE=$MAP_FILE MAP_MAX_NODES=$MAP_MAX_NODES" )`
Expected: prints `MAP_FILE=.agent-context/map.json MAP_MAX_NODES=60`, no syntax error.

- [ ] **Step 3: Commit**

```bash
git add templates/.agent-context/budget.conf
git commit -m "feat(discovery-map): add map size caps to budget.conf"
```

---

## Task 2: Create the cap validator (TDD)

**Files:**

- Test: `tests/check-map-budget-unit.sh`
- Create: `context/bin/check-map-budget.sh`

- [ ] **Step 1: Write the failing unit test**

Create `tests/check-map-budget-unit.sh`:

```bash
#!/usr/bin/env bash
# tests/check-map-budget-unit.sh — unit tests for the discovery-map cap validator.
#
# Verifies the deterministic caps (total bytes, node count, longest line) and the
# conf-driven path. No JSON parser is used — caps are byte/line/count proxies.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="$REPO_ROOT/context/bin/check-map-budget.sh"

PASS=0
FAIL=0
TMP_ROOTS=()
cleanup() { for d in "${TMP_ROOTS[@]:-}"; do [ -d "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT
mk_tmp() { local d; d=$(mktemp -d "${TMPDIR:-/tmp}/mapbudget.XXXXXX"); TMP_ROOTS+=("$d"); echo "$d"; }
pass() { printf "  PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL  %s\n    => %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

# Write a conf with generous caps unless overridden by args: write_conf DIR [TOTAL] [NODES] [LINE]
write_conf() {
    local d="$1" total="${2:-100000}" nodes="${3:-100}" line="${4:-100000}"
    cat > "$d/budget.conf" <<EOF
MAP_FILE="$d/map.json"
MAP_MAX_TOTAL_BYTES=$total
MAP_MAX_NODES=$nodes
MAP_MAX_NODE_LINE_BYTES=$line
EOF
}

# A valid 2-node map, one node per line.
write_map() {
    local d="$1"
    cat > "$d/map.json" <<'EOF'
{
  "generated": "2026-06-24",
  "nodes": [
    {"id":"auth","label":"Auth","globs":["src/auth/**"],"note":"memory/auth.md","watermark":"abc","stale":false},
    {"id":"billing","label":"Billing","globs":["src/billing/**"],"note":"memory/billing.md","watermark":"def","stale":false}
  ],
  "edges": [
    {"from":"billing","to":"auth","rel":"depends-on","why":"shared user ctx"}
  ]
}
EOF
}

echo "=== map-budget validator unit tests ==="
echo ""

# 1. Valid map within all caps → exit 0.
t=$(mk_tmp); write_conf "$t"; write_map "$t"
if bash "$ENGINE" --conf "$t/budget.conf" --quiet >/dev/null 2>&1; then pass "valid map within caps exits 0"; else fail "valid map within caps exits 0" "exited non-zero"; fi

# 2. Node count over cap → exit 1.
t=$(mk_tmp); write_conf "$t" 100000 1 100000; write_map "$t"
if bash "$ENGINE" --conf "$t/budget.conf" --quiet >/dev/null 2>&1; then fail "node-count over cap exits non-zero" "exited 0"; else pass "node-count over cap exits non-zero"; fi

# 3. Total bytes over cap → exit 1.
t=$(mk_tmp); write_conf "$t" 10 100 100000; write_map "$t"
if bash "$ENGINE" --conf "$t/budget.conf" --quiet >/dev/null 2>&1; then fail "total-bytes over cap exits non-zero" "exited 0"; else pass "total-bytes over cap exits non-zero"; fi

# 4. Longest line over cap → exit 1.
t=$(mk_tmp); write_conf "$t" 100000 100 50; write_map "$t"
if bash "$ENGINE" --conf "$t/budget.conf" --quiet >/dev/null 2>&1; then fail "longest-line over cap exits non-zero" "exited 0"; else pass "longest-line over cap exits non-zero"; fi

# 5. Missing map file → usage/config error exit 2.
t=$(mk_tmp); write_conf "$t"
code=0; bash "$ENGINE" --conf "$t/budget.conf" --quiet >/dev/null 2>&1 || code=$?
[ "$code" -eq 2 ] && pass "missing map file exits 2" || fail "missing map file exits 2" "got exit $code"

# 6. Explicit --map arg overrides conf MAP_FILE.
t=$(mk_tmp); write_conf "$t" 100000 100 100000; write_map "$t"
mv "$t/map.json" "$t/other.json"
if bash "$ENGINE" --conf "$t/budget.conf" --map "$t/other.json" --quiet >/dev/null 2>&1; then pass "--map overrides conf MAP_FILE"; else fail "--map overrides conf MAP_FILE" "exited non-zero"; fi

echo ""
echo "================================================"
TOTAL=$((PASS + FAIL))
printf "Results: %d/%d passed\n" "$PASS" "$TOTAL"
[ "$FAIL" -eq 0 ] && { echo "ALL PASSED"; exit 0; } || { echo "FAILED"; exit 1; }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/check-map-budget-unit.sh`
Expected: FAIL — every case errors because `context/bin/check-map-budget.sh` does not exist yet (engine path not found).

- [ ] **Step 3: Implement the validator**

Create `context/bin/check-map-budget.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Discovery-map cap gate. Keeps the on-demand map.json tiny so it never floods context.
#
# Deterministic caps (no JSON parser — byte/line/count proxies, same philosophy as
# check-token-budget.sh): total file bytes, node count ("id": occurrences), and the
# longest line (one node per line → per-node size proxy).
#
# Usage:
#   check-map-budget.sh [--conf PATH] [--map PATH] [--quiet]
#
# Resolution: --map overrides conf MAP_FILE; caps come from the conf.
# Exit codes: 0 = within caps, 1 = over a cap, 2 = usage/config error.

CONF=".agent-context/budget.conf"
MAP_OVERRIDE=""
QUIET=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --conf) CONF="${2:-}"; shift 2 ;;
        --conf=*) CONF="${1#--conf=}"; shift ;;
        --map) MAP_OVERRIDE="${2:-}"; shift 2 ;;
        --map=*) MAP_OVERRIDE="${1#--map=}"; shift ;;
        --quiet) QUIET=1; shift ;;
        -*) echo "Unknown option: $1" >&2; exit 2 ;;
        *) echo "Unexpected argument: $1" >&2; exit 2 ;;
    esac
done

MAP_FILE=".agent-context/map.json"
MAP_MAX_TOTAL_BYTES=16384
MAP_MAX_NODES=60
MAP_MAX_NODE_LINE_BYTES=400
if [ -f "$CONF" ]; then
    # shellcheck disable=SC1090
    . "$CONF"
fi
[ -n "$MAP_OVERRIDE" ] && MAP_FILE="$MAP_OVERRIDE"

for v in MAP_MAX_TOTAL_BYTES MAP_MAX_NODES MAP_MAX_NODE_LINE_BYTES; do
    eval "val=\${$v}"
    if ! [[ "$val" =~ ^[0-9]+$ ]]; then
        echo "Error: $v must be an integer, got '$val'." >&2
        exit 2
    fi
done

if [ ! -f "$MAP_FILE" ]; then
    echo "Error: map file not found: $MAP_FILE (run the discovery-map skill first)." >&2
    exit 2
fi

total_bytes=$(wc -c < "$MAP_FILE" | tr -d ' ')
node_count=$(grep -c '"id"[[:space:]]*:' "$MAP_FILE" || true)
max_line=$(awk '{ if (length($0) > m) m = length($0) } END { print m+0 }' "$MAP_FILE")

over=0
report=""
check() { # name actual limit
    local name="$1" actual="$2" limit="$3" status="ok"
    if [ "$actual" -gt "$limit" ]; then status="OVER"; over=1; fi
    report="${report}$(printf '  %-22s %8d  (limit %d)  %s' "$name" "$actual" "$limit" "$status")\n"
}
check "total bytes" "$total_bytes" "$MAP_MAX_TOTAL_BYTES"
check "node count" "$node_count" "$MAP_MAX_NODES"
check "longest line bytes" "$max_line" "$MAP_MAX_NODE_LINE_BYTES"

if [ "$QUIET" -ne 1 ]; then
    echo "Discovery-map cap audit ($MAP_FILE):"
    printf '%b' "$report"
fi

if [ "$over" -eq 1 ]; then
    echo "FAIL: discovery map exceeds a cap. Split coarse areas into memory/<area>/map.json" >&2
    echo "      (hierarchy), or trim node lines. The top index must stay flat." >&2
    exit 1
fi

[ "$QUIET" -ne 1 ] && echo "PASS: discovery map within caps."
exit 0
```

- [ ] **Step 4: Make it executable and run the test to verify it passes**

Run: `chmod +x context/bin/check-map-budget.sh && bash tests/check-map-budget-unit.sh`
Expected: `ALL PASSED` (6/6).

- [ ] **Step 5: Commit**

```bash
git add context/bin/check-map-budget.sh tests/check-map-budget-unit.sh
git commit -m "feat(discovery-map): add deterministic map cap validator + unit tests"
```

---

## Task 3: Wire the unit test into npm test

**Files:**

- Modify: `package.json` (the `test` script)

- [ ] **Step 1: Append the test to the chain**

In `package.json`, change the `test` script: append ` && bash tests/check-map-budget-unit.sh` to the very end of the existing chain (after `check-discovery-digest-unit.sh`).

Resulting line:

```json
    "test": "bash tests/install.sh && bash tests/check-template-coverage.sh && bash tests/check-token-budget-unit.sh && bash tests/check-token-budget.sh && bash tests/check-memory-prune-unit.sh && bash tests/check-hooks-unit.sh && bash tests/check-discovery-digest-unit.sh && bash tests/check-map-budget-unit.sh"
```

- [ ] **Step 2: Run the full suite**

Run: `npm test`
Expected: all suites pass, including the new `map-budget validator unit tests` block (`ALL PASSED`).

- [ ] **Step 3: Commit**

```bash
git add package.json
git commit -m "test(discovery-map): run map-budget unit tests in npm test"
```

---

## Task 4: Author the discovery-map skill

**Files:**

- Create: `context/skills/discovery-map.md`

This is agent-judgment work, so it ships as a Skill (markdown instructions), not a shell script. No automated test — it is verified by the wiring tests (Task 6) and by README/DoD.

- [ ] **Step 1: Create the skill file**

Create `context/skills/discovery-map.md` with this exact content:

```markdown
---
name: discovery-map
triggers:
  - discover the project
  - map the project
  - build discovery map
  - /discover
  - onboarding into this codebase
  - where does X live
description: On-demand, agent-authored concept map of the project. Fan-out discovery subagents record meaningful, non-obvious things per subsystem into a tiny map.json plus curated memory/<node>.md notes. Pulled on demand — never loaded at startup.
---

# Discovery Map

Build or refresh an on-demand concept map of this project. The map is a navigation
index; depth lives in per-node memory notes. NEVER `@`-include the map or notes — they
are pulled only when a task needs them.

## Hard rule — never flood context

- `map.json` and `memory/<node>.md` load in NO layer. They are read on demand only.
- Keep `map.json` structural, not prose: one node per line, no narrative.
- After writing, you MUST run the cap gate:
  `bash .agent-context/bin/check-map-budget.sh`
  If it FAILS, split the largest area into `memory/<area>/map.json` (hierarchy) and
  re-run until it passes. The top index stays flat regardless of repo size.

## Inputs

1. Run the cheap deterministic inventory first:
   `bash .agent-context/bin/discovery-digest.sh`
   Use it to orient — manifests, directory structure, services. Do not re-grep what it
   already lists; spend judgment on what is non-obvious.

## First run (full)

1. From the digest + directory structure, partition the repo into coarse subsystems
   (areas), not files. Each becomes a node id.
2. Fan out: dispatch one discovery subagent per node, in parallel. Give each only its
   glob(s) and this instruction: "Inspect this area with a discovery focus. Record ONLY
   meaningful, non-obvious things — gotchas, why-decisions, cross-cutting constraints,
   surprising couplings. Do NOT record what is greppable from the code. Return a compact
   note and any edges you noticed to other areas." Keep the orchestrator lean — never
   hold a full scan yourself.
3. Merge results. Write:
   - `.agent-context/map.json` — nodes (id, label, globs, note pointer, watermark, stale)
     - edges (from, to, rel, why). One node per line. Set each node's `watermark` to the
       current HEAD sha of its globs: `git log -n 1 --format=%H -- <glob>`.
   - `memory/<node>.md` — the curated depth note for each node (only meaningful things).
   - Append routing rows to `.agent-context/knowledge-map.md` Task Routing table
     (`Working on <area> → memory/<node>.md`), following the row-edit convention in
     Layer 0 → Knowledge Map Triggers. Edit rows only; preserve other content.
4. Run the cap gate (see Hard rule). Split hierarchically if needed.

## Re-run (incremental)

1. Read `.agent-context/map.json`.
2. For each node, compare its `watermark` against `git log -n 1 --format=%H -- <glob>`.
   If different, mark `"stale": true`.
3. Fan out ONLY over stale nodes. Re-note, refresh each watermark, clear `stale`.
   Unchanged nodes cost nothing. Cost is proportional to change, not repo size.
4. Run the cap gate.

## Querying (for the consuming agent, on demand)

Read `.agent-context/map.json` (small) → pick the 1–2 relevant nodes for the task →
read only those `memory/<node>.md`. Never read all notes. This scoped read IS the query.
If a node is `stale`, treat its note as possibly outdated and consider re-running discovery
for that node.
```

- [ ] **Step 2: Verify frontmatter parses and the cap-gate reference is correct**

Run: `head -12 context/skills/discovery-map.md && grep -n "check-map-budget.sh" context/skills/discovery-map.md`
Expected: YAML frontmatter (name/triggers/description) prints, and the cap-gate invocation line is present.

- [ ] **Step 3: Commit**

```bash
git add context/skills/discovery-map.md
git commit -m "feat(discovery-map): add the on-demand discovery skill"
```

---

## Task 5: Register the skill in index + layer3 routing

**Files:**

- Modify: `templates/.agent-context/skills/index.md`
- Modify: `templates/.agent-context/layer3-guidebook.md`

- [ ] **Step 1: Add the skill row to the index**

In `templates/.agent-context/skills/index.md`, add a data row to the `| Skill | Triggers | Description |` table (replace the empty body, keeping the header):

```markdown
| Skill           | Triggers                                                                 | Description                                                                                            |
| --------------- | ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------ |
| `discovery-map` | "discover/map the project", "/discover", onboarding, "where does X live" | On-demand concept map; fan-out discovery into a tiny `map.json` + `memory/<node>.md`. Never always-on. |
```

- [ ] **Step 2: Add a routing row to Layer 3**

In `templates/.agent-context/layer3-guidebook.md`, under `## Load By Task Type`, add a real data row to the table (it currently has only a header + commented examples):

```markdown
| Working on...                                           | Read first                                                                                  |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Unfamiliar subsystem / onboarding / "where does X live" | Run `/discover` (discovery-map skill), then `map.json` → pick node → its `memory/<node>.md` |
```

- [ ] **Step 3: Verify formatting**

Run: `npm run prettier -- --check templates/.agent-context/skills/index.md templates/.agent-context/layer3-guidebook.md`
Expected: both pass (or run `npm run prettier:fix` then re-check).

- [ ] **Step 4: Commit**

```bash
git add templates/.agent-context/skills/index.md templates/.agent-context/layer3-guidebook.md
git commit -m "feat(discovery-map): register skill in index and layer3 routing"
```

---

## Task 6: Wire shared files into setup-prompt download (+ coverage)

**Files:**

- Modify: `.prompts/setup-prompt.md` (Step 2 download table, mkdir line, parallel curl block)

The skill and validator are SHARED (auto-updated), so they must be downloaded during setup.
`map.json` and `memory/<node>.md` are generated per-project — they are NOT downloaded.

- [ ] **Step 1: Add rows to the Step 2 download table**

In `.prompts/setup-prompt.md`, in the `| Source path | Destination |` table (currently ending at the `subagent-scope.sh` row), add two rows:

```markdown
| `context/bin/check-map-budget.sh` | `.agent-context/bin/check-map-budget.sh` |
| `context/skills/discovery-map.md` | `.agent-context/skills/discovery-map.md` |
```

- [ ] **Step 2: Ensure the skills dir is created before download**

In the same file, change the `mkdir -p .agent-context/bin .agent-context/hooks` line to also create the skills dir:

```bash
mkdir -p .agent-context/bin .agent-context/hooks .agent-context/skills
```

- [ ] **Step 3: Add the two curl jobs to the parallel block**

In the parallel curl block (the `& pids+=($!)` jobs), add these two jobs alongside the other `context/bin/*` jobs:

```bash
(curl -fsSL "https://raw.githubusercontent.com/lx-wnk/Agent-Context/<tag>/context/bin/check-map-budget.sh" \
    -o ".agent-context/bin/check-map-budget.sh.tmp" && mv ".agent-context/bin/check-map-budget.sh.tmp" ".agent-context/bin/check-map-budget.sh" || { rm -f ".agent-context/bin/check-map-budget.sh.tmp"; exit 1; }) & pids+=($!)
(curl -fsSL "https://raw.githubusercontent.com/lx-wnk/Agent-Context/<tag>/context/skills/discovery-map.md" \
    -o ".agent-context/skills/discovery-map.md.tmp" && mv ".agent-context/skills/discovery-map.md.tmp" ".agent-context/skills/discovery-map.md" || { rm -f ".agent-context/skills/discovery-map.md.tmp"; exit 1; }) & pids+=($!)
```

(The existing `chmod +x .agent-context/bin/*.sh .agent-context/hooks/*.sh` line already covers the new validator. The `.tmp` cleanup line already globs `bin/*.tmp`; add `skills/*.tmp` to it if present.)

- [ ] **Step 4: Verify every downloaded shared file has a matching table row and curl job**

Run:

```bash
grep -c "check-map-budget.sh" .prompts/setup-prompt.md
grep -c "discovery-map.md" .prompts/setup-prompt.md
```

Expected: `check-map-budget.sh` appears at least 3 times (table + curl url + dest), `discovery-map.md` at least 3 times. Confirm the destination dir `.agent-context/skills` is in the `mkdir -p` line: `grep "mkdir -p .agent-context" .prompts/setup-prompt.md` shows `skills`.

- [ ] **Step 5: Run the wiring/coverage tests**

Run: `bash tests/install.sh && bash tests/check-template-coverage.sh`
Expected: PASS. If `tests/install.sh` enumerates shared files and asserts each appears in the setup-prompt download list, the two new files must be present (Steps 1–3 satisfy this). If it FAILS naming a new file, ensure its row + curl job exist verbatim.

- [ ] **Step 6: Commit**

```bash
git add .prompts/setup-prompt.md
git commit -m "feat(discovery-map): wire skill + validator into setup-prompt download"
```

---

## Task 7: Positioning — README

**Files:**

- Modify: `README.md` (insert a new section after `## Example`, before `## Key Principles`)

- [ ] **Step 1: Insert the Discovery Map section**

In `README.md`, between the `## Example` section and `## Key Principles`, insert:

```markdown
## On-demand Discovery Map

For large or unfamiliar codebases, run `/discover` (the `discovery-map` skill). Fan-out
discovery subagents inspect each subsystem and record **meaningful, non-obvious things**
— gotchas, why-decisions, surprising couplings — into a tiny `map.json` (navigation) plus
curated `memory/<node>.md` notes (depth). Re-runs are incremental: only subsystems whose
files changed (by git watermark) are re-discovered.

The map is **pulled on demand, never loaded at startup**. The consuming agent reads the
small index, picks the 1–2 relevant nodes, and reads only those notes — so even a
10k-file repo costs the always-on baseline nothing.

### How it differs from auto-graph tools

|              | Auto-graph tools (e.g. Graphify)                 | Agent-Context discovery map                                     |
| ------------ | ------------------------------------------------ | --------------------------------------------------------------- |
| Loading      | Graph available, can grow unwieldy (>5000 nodes) | On-demand only; top index byte-capped in CI                     |
| Content      | Mechanical symbol/call graph from parsers        | Agent judgment — non-obvious facts, not what's greppable        |
| Scaling      | Graph grows with the codebase                    | Top index stays flat; depth lazy underneath, hierarchical split |
| Cost control | Re-extraction, external API for non-code         | Incremental by git watermark; no extra runtime deps             |
| Enforcement  | —                                                | Caps in `budget.conf`, enforced by `check-map-budget.sh` + CI   |
```

- [ ] **Step 2: Update Repository Structure if it lists files**

If the `## Repository Structure` section enumerates `context/bin/` or `context/skills/`, add `check-map-budget.sh` and `discovery-map.md`. Run `grep -n "discovery-digest\|check-token-budget" README.md` to find the listing style; mirror it. If no per-file listing exists, skip.

- [ ] **Step 3: Verify formatting**

Run: `npm run prettier -- --check README.md`
Expected: pass (or `npm run prettier:fix`).

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs(discovery-map): document on-demand discovery map + comparison"
```

---

## Task 8: Positioning — CLAUDE.md

**Files:**

- Modify: `CLAUDE.md` (Architecture + shared-files description)

- [ ] **Step 1: Note the new shared files**

In `CLAUDE.md` under the File Ownership Model, in the Shared files bullet, extend the parenthetical to mention the new files. Change:

```markdown
- **Shared files** (`context/`, incl. `context/bin/` and `context/hooks/`): Overwritten on every auto-update in target projects. Changes here propagate to all installations.
```

to:

```markdown
- **Shared files** (`context/`, incl. `context/bin/`, `context/hooks/`, and `context/skills/`): Overwritten on every auto-update in target projects. Changes here propagate to all installations. Includes the `discovery-map` skill and the `check-map-budget.sh` cap validator.
```

- [ ] **Step 2: Add the discovery map to Key Conventions**

Under `## Key Conventions`, add a bullet:

```markdown
- **Discovery map**: `/discover` (discovery-map skill) builds an on-demand `map.json` + `memory/<node>.md` notes; pulled lazily, never `@`-included; size-capped by `check-map-budget.sh` (caps in `budget.conf`).
```

- [ ] **Step 3: Verify the "When adding a new shared file" guidance still holds**

The existing CLAUDE.md line says new shared files must be wired into `.prompts/setup-prompt.md` Step 2 — Task 6 did exactly that. No change needed; just confirm by reading that paragraph.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(discovery-map): record discovery map in project conventions"
```

---

## Task 9: Final verification (Definition of Done)

- [ ] **Step 1: Full test suite**

Run: `npm test`
Expected: all suites pass, including `check-map-budget-unit.sh`.

- [ ] **Step 2: Formatting**

Run: `npm run prettier`
Expected: clean (no files would be reformatted).

- [ ] **Step 3: README accuracy check (DoD rule)**

Re-read `README.md`: the Discovery Map section, installation steps, and repository structure must reflect what was built (skill name `/discover`, files `context/skills/discovery-map.md`, `context/bin/check-map-budget.sh`, caps in `budget.conf`). Fix any drift.

- [ ] **Step 4: Confirm nothing is always-on**

Run: `grep -n "map.json\|discovery-map" templates/.agent-context/budget.conf`
Expected: `map.json` appears ONLY under the discovery caps section, and is NOT in `INCLUDE_FILES`. The always-on closure must not include the map or node notes.

Run: `bash context/bin/check-token-budget.sh --conf templates/.agent-context/budget.conf` is NOT applicable here (paths are project-relative); instead just visually confirm `INCLUDE_FILES` is unchanged from Task 1.

- [ ] **Step 5: Final commit (if any drift fixed)**

```bash
git add -A
git commit -m "docs(discovery-map): final DoD pass — README/baseline accuracy"
```

---

## Self-Review Notes

- **Spec coverage:** auto-generation → Task 4 (fan-out skill); on-demand query → Task 4 "Querying" + Task 5 routing; scaling → Task 4 incremental + hierarchy, Task 2 caps; context-budget guarantees → Task 1 + Task 2 + Task 9 Step 4; positioning → Tasks 7–8. All spec sections mapped.
- **No new template** → `decisions.json` stays `[]`; `budget.conf` (existing template) is extended, already guarded by `check-template-coverage.sh`.
- **Dependency-free** → validator uses `wc`/`grep`/`awk` only; no jq/python.
- **Naming consistency:** validator file `check-map-budget.sh`, conf keys `MAP_MAX_TOTAL_BYTES` / `MAP_MAX_NODES` / `MAP_MAX_NODE_LINE_BYTES` / `MAP_FILE`, skill `discovery-map`, command `/discover` — used identically across all tasks.
- **Open items from spec deferred here, now decided:** caps = 16384 B / 60 nodes / 400 B line (Task 1); trigger = `/discover` + keyword triggers (Task 4 frontmatter); node partitioning = agent-decided, seeded from `discovery-digest.sh` (Task 4 step 1).

```

```
