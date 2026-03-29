# Layer 0 — Agent Workflow

> **⚠ SHARED FILE — DO NOT ADD PROJECT-SPECIFIC CONTENT.** This file is auto-updated and will be overwritten.
> Project-specific workflow rules belong in `layer2-project-core.md`, task routing belongs in `layer3-guidebook.md`.

## Skill Lookup

- Before starting any task, check `.agent-context/skills/index.md` for a matching skill — read and follow it

## Memory Update Rules

- Store non-discoverable learnings (gotchas, external IDs, decisions) in `.agent-context/memory/`
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
| Architecture decision       | `memory/decisions.md`    |

## Self-Improvement Loop

- After ANY correction from the user → update `memory/lessons.md` with the pattern
- Review lessons at session start for relevant context
