# Layer 3 — Guidebook

> When to load what. This is the single reference for navigating the knowledge base.

## Before You Start Any Task

1. Read `memory/user.md` — understand who you're working with
2. Read `memory/preferences.md` — respect stated preferences
3. Read `memory/lessons.md` — avoid repeating past mistakes
4. Read `memory/todo.md` — check if there's an active task plan

## Load By Task Type

| Working on...               | Read first                                 |
| --------------------------- | ------------------------------------------ | --- |
| <!-- e.g., Cart / checkout  | `memory/cart.md`, `skills/payment-flow.md` | --> |
| <!-- e.g., API endpoints    | `memory/api.md`, `decisions.json`          | --> |
| <!-- e.g., Frontend styling | `memory/design-tokens.md`                  | --> |

<!-- TODO: Add your project's task-routing rules above -->

## Skills Index

### Shared Skills

@.agent-context/skills/index.md

### Project Skills

| Skill | Triggers | Content |
| ----- | -------- | ------- |

<!-- TODO: Project-specific skills -->

## Memory Files

| File                    | Purpose                     | Load          |
| ----------------------- | --------------------------- | ------------- |
| `memory/user.md`        | Primary user profile        | Session start |
| `memory/preferences.md` | Agent behavior preferences  | Session start |
| `memory/lessons.md`     | Hard-won lessons            | Session start |
| `memory/todo.md`        | Current task plan           | Session start |
| `memory/decisions.md`   | Architectural decisions     | On-demand     |
| `memory/people.md`      | Team members & stakeholders | On-demand     |

## After You Finish

1. New decision? → `memory/decisions.md`
2. User correction? → `memory/lessons.md`
3. Task complete? → Update `memory/todo.md`
4. Learned about user? → `memory/user.md`
5. Learned about team? → `memory/people.md`
6. User stated preference? → `memory/preferences.md`
