# Layer 3 — Guidebook

> When to load what. This is the single reference for navigating the knowledge base.

## Before You Start Any Task

1. Read `memory/lessons.md` — avoid repeating past mistakes
2. Read `memory/todo.md` — check if there's an active task plan
3. If you're unsure which memory files exist or are relevant: read `memory/index.md`

Skip files that are empty or contain only comments.

## Load By Task Type

| Working on... | Read first |
| ------------- | ---------- |

<!-- TODO: Add your project's task-routing rules. Examples:
| Cart / checkout  | `memory/cart.md`, `skills/payment-flow.md` |
| API endpoints    | `memory/api.md`, `decisions.json`          |
| Frontend styling | `memory/design-tokens.md`                  |

Note: When a domain stub grows beyond 15 lines, it expands into a directory.
e.g., `memory/cart.md` becomes `memory/cart/` with sub-files.
The original `memory/cart.md` stays as an index pointing to sub-files.
See Layer 0 → Domain Expansion for rules.
-->

## Skills Index

@.agent-context/skills/index.md

<!-- TODO: Add project-specific skills to skills/index.md -->

## Memory Files

| File                | Purpose                    | Load           |
| ------------------- | -------------------------- | -------------- |
| `memory/lessons.md` | Hard-won lessons           | Session start  |
| `memory/todo.md`    | Current task plan          | Session start  |
| `memory/index.md`   | Memory file catalog        | When uncertain |
| `memory/log.md`     | Chronological activity log | On-demand      |
| `decisions.json`    | Architectural decisions    | On-demand      |
| `memory/people.md`  | Team & stakeholders        | On-demand      |

## Save As You Go (Not After)

> **Save the moment it happens** — not after finishing the task. Discoveries get lost if deferred. See Layer 0 → Self-Improvement Loop for full rules.

When any of these occur, save IMMEDIATELY before continuing other work:

1. User correction or self-discovered insight? → `memory/lessons.md`
2. Architecture/design decision made? → `decisions.json`
3. Task complete? → Update `memory/todo.md`
4. User stated preference? → `memory/preferences.md`
5. Learned about user? → `memory/user.md`
6. Learned about team? → `memory/people.md`
7. Significant decision or event this session? → append to `memory/log.md`
