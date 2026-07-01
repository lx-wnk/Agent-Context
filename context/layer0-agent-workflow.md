# Layer 0 — Agent Workflow

> **⚠ SHARED FILE — DO NOT ADD PROJECT-SPECIFIC CONTENT.** This file is auto-updated and will be overwritten.
> Project-specific workflow rules belong in `layer2-project-core.md`, task routing belongs in `layer3-guidebook.md`.

## Skill Lookup

- Before starting any task, check `.agent-context/skills/index.md` for a matching skill — read and follow it
- Skills follow the Agent Skills standard (`skills/<name>/SKILL.md`, `name` + `description` frontmatter; legacy flat `skills/<name>.md` still valid) — see https://github.com/lx-wnk/Agent-Context/blob/main/docs/skill-standard.md when authoring

## Memory Update Rules

- Store non-discoverable learnings (gotchas, external IDs, decisions) in `.agent-context/memory/`
- Every memory entry MUST include a date `(YYYY-MM-DD)` — enables staleness tracking
- Memory stubs: max 15 lines, one per domain
- Heavy references (>30 lines): create a skill in `.agent-context/skills/` with YAML trigger frontmatter
- Each fact lives in exactly ONE place. No duplicates across files.
- When a `memory/<domain>.md` stub reaches 15 lines, expand it into a directory — see `.agent-context/memory-maintenance.md` (Domain Expansion)

### Memory Decay

- Dated entries expire when `today > date + ttl`; `ttl:infinite` never expires (architecture/security)
- Archive expired entries (never delete): `bash .agent-context/bin/memory-prune.sh` (dry-run) then `--apply` → moves them to `memory/archive/<ISO-week>.md`

## Routing New Knowledge

| Type                        | Target                                                                             |
| --------------------------- | ---------------------------------------------------------------------------------- |
| Project-wide convention     | `layer2-project-core.md`                                                           |
| Domain-specific fact        | `memory/<domain>.md`                                                               |
| Heavy reference (>30 lines) | `skills/<reference>.md`                                                            |
| Gotcha / hard-won lesson    | `memory/lessons.md` (include `ttl:90d source:discovered conf:med` for new entries) |
| Architecture decision       | `decisions.json`                                                                   |
| External knowledge pointer  | `knowledge-map.md` (add row to Knowledge Sources + Task Routing)                   |
| User profile detail         | `memory/user.md`                                                                   |
| Agent behavior preference   | `memory/preferences.md`                                                            |
| Team member / stakeholder   | `memory/people.md`                                                                 |

## Self-Improvement Loop

> **MUST — Non-negotiable.** Every trigger below MUST result in an immediate write — the very next action after the discovery, before continuing other work. Do not batch or defer.

### Triggers

Save immediately when ANY of the following occurs:

- **User correction** → update `memory/lessons.md` with the pattern and what went wrong
- **User preference** → update `memory/preferences.md`
- **Self-discovered insight or technical discovery** (unexpected behavior, gotcha, undocumented API quirk, non-obvious format found during debugging or research) → update `memory/lessons.md` or relevant domain file
- **Architecture or design decision** made or confirmed → update `decisions.json`
- **New personal or team info** emerges → update `memory/user.md` or `memory/people.md`

### When in Doubt, Save

If you're unsure whether something is worth saving, ask: "Would a future session benefit from knowing this, and is it NOT discoverable from source code?" If yes — save it. Unnecessary entries can be cleaned up, but lost discoveries cannot be recovered.

### Session Routine

- **Session start**: read `memory/lessons.md` + `memory/preferences.md`; if `memory/todo.md` exists (local-only, gitignored), read it for the active task plan
- **During session**: triggers are handled inline (see directive above)
- **Session end**: review whether any triggers fired but were missed and persist them. Cross-session activity history lives in Git history and external session logs (e.g., Obsidian) — not in repo memory
- **After 3+ memory updates**: scan for contradictions with existing entries before closing
- **Knowledge source changed / lesson proven 3+ times**: update `knowledge-map.md` / promote the lesson — procedures in `.agent-context/memory-maintenance.md` (Knowledge Map Triggers, Lesson Graduation)

## Delegating to Specialist Agents

When delegating a task to a sub-agent, FIRST read `.agent-context/agent-delegation.md` — it holds the context-injection protocol, the specialist-agent table, and `persist:` block handling. Sub-agents cannot see `.agent-context/`, so inject only the relevant layer1/layer2/decisions snippets into the delegating prompt.
