# Example: Shopware 6 Project

> This example shows how the agent-context architecture looks in a real Shopware 6.7 project. Each file is described in
> prose — no duplicated content to maintain.

## Project Structure

```
AGENTS.md
.agent-context/
  agent-startup.md            ← shared (auto-updated)
  layer0-agent-workflow.md    ← shared (auto-updated)
  base-principles.md          ← shared (auto-updated)
  plugins.json                ← shared (auto-updated)
  .agent-context-version                    ← written by agent
  layer1-bootstrap.md         ← project-owned
  layer2-project-core.md      ← project-owned
  layer3-guidebook.md         ← project-owned
  memory/
    architecture.md
    dal-conventions.md
    decisions.md
    infrastructure.md
    lessons.md
  skills/
    dal-reference.md
    infrastructure.md
```

---

## Shared Files

These are identical across all projects using agent-context. They are overwritten on every auto-update.

### `agent-startup.md`

→ See [context/agent-startup.md](context/agent-startup.md)

### `layer0-agent-workflow.md`

→ See [context/layer0-agent-workflow.md](context/layer0-agent-workflow.md)

### `base-principles.md`

→ See [context/base-principles.md](context/base-principles.md)

---

## Project-Owned Files

These are created once by the installer and then owned by the project. Auto-updates never touch them.

### `AGENTS.md` — Entry Point (~35 lines)

Identifies the project as Shopware 6.7 with PHP 8.2+, Symfony 7, MySQL 8.0+, and a custom DAL (no Doctrine ORM).
Describes the modular monolith structure (`src/Core/{Framework,System,Content,Checkout}`, plugins in `custom/plugins/`).
References `@.agent-context/agent-startup.md` for auto-updates. Lists 5 quick rules: always run `composer run check`
before committing, DAL over Doctrine, typed DTOs with `readonly class`, Conventional Commits, and PHPUnit with
`IntegrationTestBehaviour`. Includes compaction preservation hints for long sessions.

### `layer1-bootstrap.md` — Tech Stack & Domains (~25 lines)

Maps the six core domains (Framework, System, Content, Checkout, Admin, Storefront) to their paths and responsibilities.
Lists the full tech stack with versions: PHP ≥8.2, Symfony 7, MySQL 8.0+/MariaDB 10.11+, Vue.js 3 + Meteor components
for Admin, Twig + Bootstrap 5 for Storefront, Composer and npm/Webpack for builds, GitHub Actions for CI.

### `layer2-project-core.md` — Conventions & Rules (~35 lines)

Establishes domain-first code organization (group by business domain, not technical layer). Mandates the custom DAL with
EntityDefinition and Repository patterns — raw SQL and Doctrine are prohibited. Requires typed DTOs using
`readonly class` structs instead of associative arrays. Documents the Entity Indexer pattern for pre-computed
aggregations. Defines testing strategy: unit tests in `tests/Unit/`, integration tests with `IntegrationTestBehaviour`
and real database, E2E via Playwright. Commit format: Conventional Commits (`<type>(scope): description`).

### `layer3-guidebook.md` — Task Routing (~30 lines)

Maps tasks to the right context files: DAL work → load `memory/dal-conventions.md` + `skills/dal-reference.md`, admin
modules → load admin conventions, storefront/Twig → load storefront conventions, CI/linting → load
`memory/infrastructure.md` + `skills/infrastructure.md`. Notes external skills in `.agents/skills/` (gitignored,
restored from `skills-lock.json`). Provides a file index so the agent knows what's available without reading everything.

---

## Memory Files (Stubs, ~10-15 lines each)

Lightweight quick-fact files. The agent loads them based on the task-routing table in layer 3.

### `memory/architecture.md`

Concise overview of Shopware's modular monolith with domain-first organization. Highlights non-obvious details: custom
DAL (not Doctrine), Entity Indexer pattern for write-time pre-computation, parent-child inheritance in variant products,
translation fallback chain (current → parent → system default), and static vs. dynamic CMS resolvers.

### `memory/dal-conventions.md`

Quick facts about DAL usage, pointing to `skills/dal-reference.md` for the full reference. Covers: always use
EntityDefinition and EntityRepository (never raw SQL), translation fallback mechanism, version-aware writes with
`context.createVersionContext()`, EntityWrittenEvent timing, and entity indexer registration order.

### `memory/decisions.md`

Three key architectural decisions with rationale: (1) Custom DAL over Doctrine — e-commerce needs optimized read paths
with pre-computed aggregations that don't fit Doctrine's unit-of-work. (2) Domain-first module organization — business
domains own their entities, services, and routes. (3) Meteor Component Library for admin UI consistency.

### `memory/infrastructure.md`

Quick facts about dev infrastructure, pointing to `skills/infrastructure.md` for full commands. Lists primary build
commands, QA verification (`composer run check`), CI pipeline (GitHub Actions), and Docker services (MySQL 3306,
Elasticsearch 9200, Admin 8080).

### `memory/lessons.md`

Four hard-won gotchas: (1) Translation fallback — system-default language must have a translation row or fields appear
empty. (2) Entity indexer ordering — indexers run in registration order, dependencies require correct sequence. (3)
Admin hot reload — requires full build script, watcher alone doesn't suffice. (4) Migration patterns — `update()` for
additive changes (always runs), `updateDestructive()` for breaking changes (requires explicit flag).

---

## Skills (Full Reference, loaded on-demand)

Heavy documentation that the agent loads only when the task matches. This is where the "stubs + skills" pattern pays off
— ~100 lines of DAL reference costs nothing when you're fixing a CSS bug.

### `skills/dal-reference.md` (~80 lines)

Comprehensive DAL reference: core concepts (EntityDefinition, Entity, EntityCollection, EntityRepository), the entity
definition pattern (three classes + service registration), all field types (string, int, bool, relationships,
translated, JSON), translation system with fallback chain, Entity Indexer implementation, versioning with
`createVersionContext()` for draft workflows, repository CRUD operations, and migration conventions.

### `skills/infrastructure.md` (~60 lines)

Full infrastructure reference: development setup commands, build instructions (full, storefront-only, admin-only, theme
compilation), frontend watch scripts, QA pipeline commands, GitHub Actions CI (7 parallel jobs), Docker services table,
and useful console commands for cache, plugins, indexing, and task processing.
