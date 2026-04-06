# Layer 0 — Agent Workflow

> **⚠ SHARED FILE — DO NOT ADD PROJECT-SPECIFIC CONTENT.** This file is auto-updated and will be overwritten.
> Project-specific workflow rules belong in `layer2-project-core.md`, task routing belongs in `layer3-guidebook.md`.

## Skill Lookup

- Before starting any task, check `.agent-context/skills/index.md` for a matching skill — read and follow it

## Memory Update Rules

- Store non-discoverable learnings (gotchas, external IDs, decisions) in `.agent-context/memory/`
- Every memory entry MUST include a date `(YYYY-MM-DD)` — enables staleness tracking
- Memory stubs: max 15 lines, one per domain
- Heavy references (>30 lines): create a skill in `.agent-context/skills/` with YAML trigger frontmatter
- Each fact lives in exactly ONE place. No duplicates across files.

## Routing New Knowledge

| Type                        | Target                   |
| --------------------------- | ------------------------ |
| Project-wide convention     | `layer2-project-core.md` |
| Domain-specific fact        | `memory/<domain>.md`     |
| Heavy reference (>30 lines) | `skills/<reference>.md`  |
| Gotcha / hard-won lesson    | `memory/lessons.md`      |
| Architecture decision       | `decisions.json`         |
| User profile detail         | `memory/user.md`         |
| Agent behavior preference   | `memory/preferences.md`  |
| Team member / stakeholder   | `memory/people.md`       |

## Self-Improvement Loop

- After ANY correction from the user → update `memory/lessons.md` with the pattern
- User states a preference → update `memory/preferences.md`
- New personal or team info emerges → update `memory/user.md` or `memory/people.md`
- Review lessons + preferences at session start for relevant context
