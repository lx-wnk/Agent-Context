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

### Domain Expansion

When a `memory/<domain>.md` stub exceeds 15 lines, expand it into a directory:

1. Create `memory/<domain>/` with topical sub-files (e.g., `memory/cart/pricing.md`, `memory/cart/checkout-flow.md`)
2. Replace the original `memory/<domain>.md` content with an index that lists sub-files and their purpose
3. Each sub-file follows the same rules: date required, max 30 lines — beyond that, graduate to a skill
4. Update `memory/index.md` to reflect the expansion

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
| Significant session event   | `memory/log.md` (append) |

## Self-Improvement Loop

> **MUST — Core agent responsibility.** Keeping memory current is not optional. Update the relevant file **immediately within the same session**, not "later".

### Triggers

- **User correction** → update `memory/lessons.md` with the pattern and what went wrong
- **User preference** → update `memory/preferences.md`
- **Self-discovered insight** (unexpected behavior, gotcha found during debugging, undocumented API quirk) → update `memory/lessons.md`
- **Architecture or design decision** made or confirmed → update `decisions.json`
- **New personal or team info** emerges → update `memory/user.md` or `memory/people.md`

### Session Routine

- **Session start**: read `memory/lessons.md` + `memory/preferences.md` for relevant context
- **Session end**: review whether any of the triggers above fired but were missed; if a significant decision or discovery occurred, append a one-line entry to `memory/log.md`
- **After 3+ memory updates**: scan for contradictions with existing entries before closing

### Lesson Graduation

When a lesson has proven itself (applied 3+ times, never questioned), suggest promoting it:

- Project-wide convention → move to `layer2-project-core.md`
- Domain-specific pattern → keep in `memory/<domain>.md` (or sub-file if domain is expanded)
- Remove the original entry from `memory/lessons.md` after promotion
