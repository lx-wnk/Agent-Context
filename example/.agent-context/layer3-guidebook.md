# Layer 3 — Guidebook (Load by Task)

## Skills (On-Demand, Full Reference)

Heavy reference docs in `.agent-context/skills/`. Load when you need full details.

| Skill | Triggers | Content |
|-------|----------|---------|
| `skills/dal-reference.md` | DAL, entity, definition, repository, migration | DAL patterns, entity lifecycle, indexer, versioning |
| `skills/admin-reference.md` | admin, vue, module, component, meteor | Admin SPA patterns, module structure, Meteor components |
| `skills/infrastructure.md` | docker, ci, make, phpstan, phpunit, pipeline | Docker setup, CI pipeline, Make targets, tool config |

## Memory Files (Lightweight, Load by Task)

| Task | Load These |
|------|-----------|
| DAL / Entity work | `dal-conventions` + skill `dal-reference` |
| Admin module | `admin-conventions` + skill `admin-reference` |
| Storefront / Twig | `storefront-conventions` |
| Plugin development | `dal-conventions`, `architecture` |
| CI / Linting | skill `infrastructure` |
| CMS work | `dal-conventions`, `storefront-conventions` |
| Bug investigation | `lessons`, `architecture` |

## Memory File Index

| File | Content |
|------|---------|
| `architecture.md` | Domain overview, plugin patterns, non-obvious details |
| `dal-conventions.md` | DAL gotchas, translation chain, version-aware writes |
| `admin-conventions.md` | Vue patterns, state management, Meteor usage |
| `storefront-conventions.md` | Twig security, theme inheritance, JS plugin system |
| `infrastructure.md` | Quick facts stub (Docker, CI commands) |
| `decisions.md` | Architecture decisions and rationale |
| `lessons.md` | Gotchas, known bugs, hard-won knowledge |
