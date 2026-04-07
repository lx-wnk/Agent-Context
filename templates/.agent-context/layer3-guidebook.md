# Layer 3 — Guidebook

> When to load what. This is the single reference for navigating the knowledge base.

## Before You Start Any Task

1. Read `memory/lessons.md` — avoid repeating past mistakes
2. Read `memory/todo.md` — check if there's an active task plan

Skip files that are empty or contain only comments.

## Load By Task Type

| Working on... | Read first |
| ------------- | ---------- |

<!-- TODO: Add your project's task-routing rules. Examples:
| Cart / checkout  | `memory/cart.md`, `skills/payment-flow.md` |
| API endpoints    | `memory/api.md`, `decisions.json`          |
| Frontend styling | `memory/design-tokens.md`                  |
-->

## Skills Index

@.agent-context/skills/index.md

<!-- TODO: Add project-specific skills to skills/index.md -->

## Memory Files

| File                | Purpose                 | Load          |
| ------------------- | ----------------------- | ------------- |
| `memory/lessons.md` | Hard-won lessons        | Session start |
| `memory/todo.md`    | Current task plan       | Session start |
| `decisions.json`    | Architectural decisions | On-demand     |
| `memory/people.md`  | Team & stakeholders     | On-demand     |

## After You Finish

> Update immediately — don't defer to a future session. See Layer 0 for full rules.

1. User correction or self-discovered insight? → `memory/lessons.md`
2. Architecture/design decision made? → `decisions.json`
3. Task complete? → Update `memory/todo.md`
4. User stated preference? → `memory/preferences.md`
5. Learned about user? → `memory/user.md`
6. Learned about team? → `memory/people.md`
