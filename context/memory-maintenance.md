# Memory Maintenance

> **⚠ SHARED FILE — DO NOT ADD PROJECT-SPECIFIC CONTENT.** Auto-updated and overwritten.
> Loaded on-demand — read this only when restructuring memory (stub overflow, lesson promotion, knowledge-source change). Triggers live in `layer0-agent-workflow.md`.

## Domain Expansion

When a `memory/<domain>.md` stub reaches 15 lines, expand it into a directory:

1. Create `memory/<domain>/` with topical sub-files (e.g., `memory/cart/pricing.md`, `memory/cart/checkout-flow.md`)
2. Replace the original `memory/<domain>.md` content with an index that lists sub-files and their purpose
3. Each sub-file follows the same rules: date required, max 30 lines — beyond that, graduate to a skill
4. Update `memory/index.md` to reflect the expansion

## Lesson Graduation

When a lesson has proven itself (applied 3+ times, never questioned), suggest promoting it:

- Project-wide convention → move to `layer2-project-core.md`
- Domain-specific pattern → keep in `memory/<domain>.md` (or sub-file if domain is expanded)
- Remove the original entry from `memory/lessons.md` after promotion

## Knowledge Map Triggers

Update `.agent-context/knowledge-map.md` immediately when any of the following occurs — same non-negotiable rule as all other self-improvement triggers (next action after discovery, before continuing):

| Event                                              | Action                                                   |
| -------------------------------------------------- | -------------------------------------------------------- |
| External file changed (SHA256 mismatch detected)   | Update SHA256 + Last Verified in Knowledge Sources table |
| New structured knowledge file or folder discovered | Add entry to Knowledge Sources + add row to Task Routing |
| Task type used but no routing row exists for it    | Add routing row to Task Routing based on current task    |
| Knowledge source no longer exists                  | Remove entry from Knowledge Sources table                |
