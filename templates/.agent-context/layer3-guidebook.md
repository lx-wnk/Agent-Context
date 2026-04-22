# Layer 3 — Guidebook

> When to load what. This is the single reference for navigating the knowledge base.

## Before You Start Any Task

1. Follow Layer 0 Session Routine (loads `memory/lessons.md`, `memory/preferences.md`, `memory/todo.md`)
2. If you're unsure which memory files exist or are relevant: read `memory/index.md`

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

## Knowledge Map

External knowledge sources and task-based routing to project docs, architecture files, and other structured knowledge. Updated automatically on every agent run.

@.agent-context/knowledge-map.md

## Skills Index

@.agent-context/skills/index.md

<!-- TODO: Add project-specific skills to skills/index.md -->

## Memory Files

| File                    | Purpose                    | Load           |
| ----------------------- | -------------------------- | -------------- |
| `memory/lessons.md`     | Hard-won lessons           | Session start  |
| `memory/preferences.md` | Agent behavior preferences | Session start  |
| `memory/todo.md`        | Current task plan          | Session start  |
| `memory/index.md`       | Memory file catalog        | When uncertain |
| `memory/log.md`         | Chronological activity log | On-demand      |
| `decisions.json`        | Architectural decisions    | On-demand      |
| `memory/people.md`      | Team & stakeholders        | On-demand      |
| `memory/user.md`        | User profile               | On-demand      |

## Save As You Go (Not After)

> **Save the moment it happens** — not after finishing the task. Discoveries get lost if deferred. See Layer 0 → Self-Improvement Loop for triggers, routing, and the "When in Doubt, Save" heuristic.
