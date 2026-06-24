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
