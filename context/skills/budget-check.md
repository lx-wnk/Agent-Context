---
name: budget-check
triggers:
  - token budget
  - always-on baseline
  - check the budget
  - map caps
description: Measure the always-on context budget and the discovery-map caps from `.agent-context/budget.conf` by reading files — no script. Used by the setup/update audit (Step 5e) and after building a discovery map.
---

# Budget Check

Two measurements, both driven by `.agent-context/budget.conf` (project-owned; read it, never edit it here).
Count by reading files with your file tools; `wc -l` / `wc -c` / `grep -c` are fine for raw numbers. Report exact numbers, never estimates.

## 1. Always-on budget

**File set** — what the agent loads at every session start:

1. Start at `.claude/CLAUDE.md` and `./CLAUDE.md` (whichever exist). Follow every `@<path>` import recursively, resolving each relative to the directory of the file that contains it. Ignore `@` inside inline code spans or fenced code blocks. An import that points at no file is reported as dangling and not counted.
2. Add each path in `SESSION_START_FILES` (relative to the project root).
3. Add each path in `INCLUDE_FILES`. For every one the walk did not reach, report `note: <path> is counted from INCLUDE_FILES but not @-imported` — that file never loads.
4. Count each file once.

**Effective lines** per file — every line counts as 1 except:

- blank lines;
- lines fully inside an HTML comment `<!-- … -->` (comments can span lines; `<!--` inside backticks does not open one);
- Markdown table separator rows (`| --- | :---: |`);
- horizontal rules (`---`, `***`, `===`).

**Verdict** — soft cap `MAX_EFFECTIVE_LINES`, hard cap `MAX_EFFECTIVE_LINES_HARD` (250 if absent; never below the soft cap):
total > hard → **FAIL**, total > soft → **WARN**, else **PASS**.

If the total is within 2 lines of either cap, count every file a second time before stating the verdict — a single miscounted line flips it there.

**Report** — a table (effective lines per file), the total with both caps and the verdict, every dangling import and every INCLUDE_FILES note, and how many of the total come from noted entries (those lines never load).

## 2. Discovery-map caps

Run after writing `map.json` and once per sub-map (`memory/map/<area>/map.json`):

- total size in bytes (`wc -c`) ≤ `MAP_MAX_TOTAL_BYTES`;
- number of `"id":` occurrences ≤ `MAP_MAX_NODES`;
- longest line, ignoring its `"globs":[…]` array, ≤ `MAP_MAX_NODE_LINE_BYTES`.

Any cap exceeded → **FAIL**: split the largest area into a sub-map or trim labels — never truncate globs.
