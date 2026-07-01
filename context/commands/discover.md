---
description: Build or refresh the on-demand discovery map (concept graph + per-node notes)
---

Run the Agent-Context discovery-map skill: read `.agent-context/skills/discovery-map.md` and follow it exactly to build — or, if `.agent-context/map.json` already exists, incrementally refresh — the map plus the per-node `memory/<node>.md` notes. Then run `.agent-context/bin/check-map-budget.sh` to confirm the size caps.

The map stays on-demand: never load `map.json` or the node notes into always-on context.
