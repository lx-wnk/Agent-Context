# Layer 2 — Project Core

## Development Principles

- **Domain-first organization** — Group by business domain (Content, Checkout), not by technical layer (controllers, models)
- **DAL over raw SQL** — Always use EntityDefinition + Repository, never write raw SQL queries
- **Typed DTOs** — `readonly class` structs instead of associative arrays. No `array{key: type}` returns.
- **No Doctrine ORM** — Shopware uses a custom DAL. Don't use Doctrine entities, queries, or migrations.
- **Entity Indexer pattern** — Pre-compute aggregations on write for fast reads. Don't compute in read paths.

## Conventions Not Enforced by Linters

- **Entity naming:** `Vendor\Plugin\Domain\EntityName\EntityName{Definition,Entity,Collection}`
- **Repository service ID:** `vendor_entity.repository` (snake_case)
- **Table name:** `vendor_entity` (snake_case, prefixed)
- **Migrations:** One migration per schema change, never alter existing migrations
- **Admin modules:** New modules need navigation entry in `main.js`

## Testing

- Unit tests: `tests/Unit/` mirroring `src/` structure
- Integration tests: Use `IntegrationTestBehaviour` trait (provides kernel, DB, container)
- E2E tests: Playwright in `tests/e2e/`
- Always test DAL operations with real database, never mock the DAL

## Commit Convention (Conventional Commits)

```
<type>(scope): description
```

Types: `feat`, `fix`, `refactor`, `chore`, `ci`, `docs`, `test`, `perf`
Scope: Affected domain (e.g., `feat(checkout):`, `fix(dal):`)
