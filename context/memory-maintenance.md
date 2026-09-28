# Memory Maintenance

> **⚠ SHARED FILE — DO NOT ADD PROJECT-SPECIFIC CONTENT.** Auto-updated and overwritten.
> Loaded on-demand — read this only when restructuring memory (stub overflow, lesson promotion, knowledge-source change, a lesson for a sibling repo that is not checked out). Triggers live in `layer0-agent-workflow.md`.

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

## Cross-Repo Fallback

A lesson belongs in `memory/lessons.md` of the repo that owns the code. When that repo is not checked out in this session, park the lesson instead of dropping it or leaving it here as if it were local:

1. **Park** it in this repo's `memory/lessons.md` with an `owner:<repo>` tag after the usual metadata, e.g. `- **[api]** Order list pages from 0 (2026-09-28) ttl:90d source:discovered conf:med owner:backend`. `<repo>` is the name under "Sibling Repos" in `layer1-bootstrap.md`; add the sibling there if it is missing.
2. **The tag means "misplaced"** — the entry is not a fact about this repo and is moved, never copied.
3. **Move** it once the owning repo is reachable at the path listed under "Sibling Repos": append it to that repo's `memory/lessons.md` without the `owner:` tag (date, `ttl:`, `source:` and `conf:` stay), then remove it here. The memory review (`memory-review-prompt.md`, Step 1b) does this on every run; any session that has both repos open may do it earlier.
4. **Sibling path unknown or unreachable** → leave the entry parked; the review lists it. A parked entry ages like any other lesson, so an owner that is never checked out lets it expire into the archive rather than linger.

## Knowledge Map Triggers

Update `.agent-context/knowledge-map.md` as the next action after any of the following, before continuing other work (same timing as the self-improvement triggers in `layer0-agent-workflow.md`):

| Event                                              | Action                                                   |
| -------------------------------------------------- | -------------------------------------------------------- |
| External file changed (SHA256 mismatch detected)   | Update SHA256 + Last Verified in Knowledge Sources table |
| New structured knowledge file or folder discovered | Add entry to Knowledge Sources + add row to Task Routing |
| Task type used but no routing row exists for it    | Add routing row to Task Routing based on current task    |
| Knowledge source no longer exists                  | Remove entry from Knowledge Sources table                |
