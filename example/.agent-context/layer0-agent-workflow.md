# Layer 0 — Agent Workflow

## Plan First

Before multi-step tasks: outline approach, identify affected files, check for existing patterns in the codebase.

## Verification

Run `composer run check` before committing. This triggers PHPStan, PHP-CS-Fixer, and PHPUnit.
For frontend: `npm run lint && npm run test` in the relevant bundle.

## Skills Installation

If `.agents/skills/` is missing or empty, restore external skills from `skills-lock.json` before starting work.

## Self-Improvement

When you discover gotchas, update `.agent-context/memory/lessons.md`.
When architecture changes, update `.agent-context/memory/architecture.md`.

## Routing User Learnings

When the user asks to remember something, route it to the **narrowest fitting scope**:

| Scope | Target | Example |
|-------|--------|---------|
| General dev philosophy | `layer2-project-core.md` | "Prefer composition over inheritance" |
| DAL / entity convention | `memory/dal-conventions.md` | "Always use version-aware writes" |
| Admin / Vue convention | `memory/admin-conventions.md` | "No Vuex for new modules" |
| Storefront / Twig | `memory/storefront-conventions.md` | "No inline styles" |
| CI / tooling | `memory/infrastructure.md` | "Always use -B flag for Make" |
| Platform gotcha | `memory/lessons.md` | "Translation fallback chain order" |
| Architecture decision | `memory/decisions.md` | "Why we chose X over Y" |

**Rule:** Domain-specific before global. Keep context proportional to the task.
