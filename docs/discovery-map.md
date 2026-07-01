# On-demand Discovery Map

For large or unfamiliar codebases, build a discovery map. In Claude Code, type `/discover`
(installed as a slash command at `.claude/commands/discover.md`); with any other agent, just
ask to "discover the project" and the `discovery-map` skill is loaded via skill routing. (Running
`install.sh --discover` does not build the map itself — it just points you here afterwards, because
fan-out discovery needs an interactive session.) Fan-out discovery subagents inspect
each subsystem and record **meaningful, non-obvious things** — gotchas, why-decisions, surprising
couplings — into a tiny `map.json` (navigation) plus curated `memory/<node>.md` notes (depth).
Re-runs are incremental: only subsystems whose files changed (by git watermark) are re-discovered.

The map is **pulled on demand, never loaded at startup**. The consuming agent reads the
small index, picks the 1–2 relevant nodes, and reads only those notes — so even a
10k-file repo costs the always-on baseline nothing.

## How it differs from auto-graph tools

|              | Auto-graph tools (e.g. Graphify)                 | Agent-Context discovery map                                     |
| ------------ | ------------------------------------------------ | --------------------------------------------------------------- |
| Loading      | Graph available, can grow unwieldy (>5000 nodes) | On-demand only; top index byte-capped in CI                     |
| Content      | Mechanical symbol/call graph from parsers        | Agent judgment — non-obvious facts, not what's greppable        |
| Scaling      | Graph grows with the codebase                    | Top index stays flat; depth lazy underneath, hierarchical split |
| Cost control | Re-extraction, external API for non-code         | Incremental by git watermark; no extra runtime deps             |
| Enforcement  | —                                                | Caps in `budget.conf`, enforced by `check-map-budget.sh` + CI   |

## Further reading

- [Discovery Map design](discovery-map-design.md)
- [Discovery Map implementation plan](discovery-map-plan.md)

See also [Architecture](architecture.md) and [Enforcement & Hygiene](enforcement.md).
