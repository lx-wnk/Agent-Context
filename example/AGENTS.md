# Shopware — Agent Instructions

Shopware 6.7 | PHP 8.2+ | Symfony 7 | MySQL 8.0+ / MariaDB 10.11+ | Custom DAL (no Doctrine ORM)

Modular monolith: `src/Core/{Framework,System,Content,Checkout}`. Plugins in `custom/plugins/`.

## Context Architecture

Layer files in `.agent-context/` — load what you need:

| Layer | File | Always Load? |
|-------|------|-------------|
| 0 | `layer0-agent-workflow.md` | Yes |
| 1 | `layer1-bootstrap.md` | Yes |
| 2 | `layer2-project-core.md` | Yes |
| 3 | `layer3-guidebook.md` | On task start |

Memory files in `.agent-context/memory/` — lightweight stubs with quick facts.
Skills in `.agent-context/skills/` — full reference docs, load on-demand (see guidebook).

## Quick Rules (Always Apply)

1. **Pre-commit:** `composer run check` — never commit with failing CI
2. **DAL over Doctrine:** Use EntityDefinition + Repository pattern, never raw SQL or Doctrine
3. **Typed DTOs:** `readonly class` structs instead of associative arrays for return values
4. **Conventional Commits:** `<type>(scope): description`
5. **Testing:** PHPUnit with `IntegrationTestBehaviour` trait for integration tests
6. **Skills:** If `.agents/skills/` is missing, install from `skills-lock.json` before starting work

## Compaction Preservation

When compacting context, always preserve:
- List of modified/created files in this session
- Current bundle or domain being worked on
- Active test/lint commands and their last results
- Any entity definitions or migration state in progress
- Unfinished tasks and next steps
