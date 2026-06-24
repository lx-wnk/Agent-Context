# Discovery Map — Design Spec

**Date:** 2026-06-24
**Status:** Approved (brainstorming), pending implementation plan
**Author:** Agent-Context maintainers

## Motivation

Comparison with [Graphify](https://graphify.net/) surfaced three strengths Agent-Context lacked:
auto-generation (no manual curation), on-demand queryable retrieval, and scaling with codebase size.
This feature absorbs those strengths **without** violating Agent-Context's core thesis: minimal
always-on context (ETH Zürich 2026 — auto-generated always-on context reduces agent performance ~3%).

The reconciling insight: Graphify-style auto-generation is acceptable when it is **pulled on-demand**,
never **pushed into the startup baseline**. We add an agent-authored, judgment-based discovery layer
that stays lazy and CI-capped.

Explicitly rejected: a mechanical file/symbol listing. Discovery is semantic judgment — an agent
inspects the project with a discovery focus and records meaningful, non-obvious things — not a grep dump.

## Goal

A new shared Skill, `discovery-map`, that:

1. Auto-generates a lightweight concept graph of the project via fan-out discovery subagents.
2. Stores depth as curated per-node notes.
3. Is queryable on-demand (scoped reads), never loaded always-on.
4. Scales flat: even a 10k-file repo costs the agent only the small top index + 1–2 node notes per task.

## Non-Negotiable Constraint — Context Budget

The graph/notes must NEVER flood context, even in large projects. Guarantee chain:

1. **Never `@`-included.** `map.json` and `memory/<node>.md` load in NO layer. Baseline stays
   ~150–200 lines, still guarded by `tests/check-token-budget.sh`.
2. **Top index stays tiny — structural, not prose.** Nodes = subsystems/concepts (coarse), not files.
   Each node is one compact line. No prose in `map.json`.
3. **Lazy node expansion.** Agent reads `map.json` (small) → selects 1–2 relevant nodes → reads only
   those `memory/<node>.md`. Never all notes. This scoped read IS the "query".
4. **Hard size caps, CI-enforced.** Per-node line cap + top-level total cap. When a large repo exceeds
   the top cap → **hierarchical**: top map holds areas, each area expands into `memory/<area>/map.json`.
   Top index never scales with repo size (stays flat). New test `tests/check-map-budget.sh` enforces this.
5. **Fan-out keeps the orchestrator lean.** Discovery subagents scan in parallel and return only
   compressed notes. The main agent never holds the full scan.

## Architecture — Approach A (Standalone Skill)

Chosen over (B) folding into `agent-context-init` — too much coupling, harder to re-trigger, bloats setup —
and (C) replacing `knowledge-map.md` — breaks mature Layer-3 `@`-includes, migration risk.

Approach A is isolated (one responsibility), separately triggerable, scales via fan-out, and **reuses**
`discovery-digest.sh` + `knowledge-map.md` rather than replacing them (no DRY break, no migration).

## Artifacts

### `.agent-context/map.json` — lightweight concept graph (committed, NOT always-on)

```jsonc
{
  "generated": "2026-06-24",
  "nodes": [
    {
      "id": "auth",
      "label": "Authentication & Sessions",
      "globs": ["src/auth/**", "middleware/session*"],
      "note": "memory/auth.md", // pointer to depth
      "watermark": "<commit-sha>", // staleness anchor (HEAD when node last discovered)
      "stale": false,
    },
  ],
  "edges": [{ "from": "billing", "to": "auth", "rel": "depends-on", "why": "shared user ctx" }],
}
```

### `memory/<node>.md` — curated depth per node (committed)

Only "meaningful things": non-obvious facts, gotchas, why-decisions. NOT what is greppable from code
(thesis). When a node grows past the per-node memory rule, it expands into `memory/<node>/` per the
existing domain-expansion convention.

### `knowledge-map.md` — reused, not replaced

Discovery appends routing rows (`Working on auth → memory/auth.md`). Existing Layer-3 `@`-include stays.

**Role separation:** `map.json` = navigate/scope/staleness · `memory/<node>.md` = detail ·
`knowledge-map.md` = human routing surface.

## Skill Flow

Command-triggered (e.g. `/discover`). Pure Skill markdown for the judgment work — no shell script for
the semantic layer (project preference: agent-judgment automation ships as a Skill, not `bin/*.sh`).

### First run (full)

1. Orchestrator runs `discovery-digest.sh` → cheap deterministic inventory (manifests, dir structure).
   This is the only shell, and it already exists.
2. Orchestrator partitions the repo into areas/subsystems (from digest + dir structure) → node list.
3. **Fan-out:** one discovery subagent per node, in parallel. Each free-scans its glob, records only
   meaningful things (non-obvious, why, gotchas), returns a compact note + detected edges.
4. Orchestrator merges → writes `map.json` (nodes + edges + watermark = current HEAD SHA per glob),
   `memory/<node>.md` (notes), appends `knowledge-map.md` routing rows.

### Re-run (incremental — Graphify `--update`, lazy)

1. Skill reads `map.json`, compares each node's `watermark` against `git log` of its globs.
2. Changed nodes → `stale: true`. Unchanged → skipped (no cost).
3. Fan-out over stale nodes only. Re-note, refresh watermark. Cost ∝ change, not repo size.

`git log -- <glob>` is the single source of truth for staleness — no hook, no state DB, no timestamp.

### Scaling

When an area exceeds the node cap → the Skill spawns a sub-discovery that builds
`memory/<area>/map.json` (the hierarchy from the Context Budget section). Recursive, but the top stays flat.

## Integration / Wiring

Per CLAUDE.md conventions:

- **Skill = shared** (framework logic, should receive auto-updates). Ship the skill file in the shared
  set; wire into `.prompts/setup-prompt.md` Step 2 (download list + parallel curl block) — otherwise the
  coverage test fails. Register in `.agent-context/skills/index.md`.
- **Caps reuse `budget.conf`** (already exists) — no new template, DRY.
- **Outputs committed:** `map.json` and `memory/<node>.md` (shared knowledge, like `knowledge-map.md`).
- **Layer 3:** add a routing row — "unknown subsystem / onboarding → `/discover`, then `map.json` → node note".
  On-demand, no `@`-include.

## Positioning ("pimp")

- `README.md`: new section "On-demand Discovery Map" — agent-authored, judgment over mechanical,
  zero always-on cost, flat scaling. Comparison table vs auto-graph tools (on-demand vs always-on,
  judgment vs tree-sitter, CI-capped vs unwieldy >5000 nodes).
- `CLAUDE.md`: extend the architecture table + artifact list.
- `decisions.json`: record "on-demand agent discovery, curated-first, why no always-on auto-graph (ETH −3%)".

## Testing

- `tests/check-map-budget.sh` — enforces per-node cap + top cap + hierarchy obligation. Added to `npm test`.
- Extend the setup-prompt coverage test: the new shared skill must appear in the download list.

## Definition of Done

- README accurate (DoD rule): installation, structure, behavior reflect the feature.
- `npm test` green.
- `npm run prettier` clean.

## Open Questions (deferred to implementation plan)

- Exact cap numbers for `budget.conf` (per-node bytes, top-level total).
- Skill trigger surface: `/discover` slash command vs Skill-tool name vs both.
- Whether `map.json` node partitioning is fully agent-decided or seeded from `discovery-digest.sh` sections.
