# DAL Conventions

Full reference available in `.agent-context/skills/dal-reference.md`.

**Quick facts:**
- Always use `EntityDefinition` + `EntityRepository` — never raw SQL
- Translation fallback: current → parent → system default (EN)
- Version-aware writes: use `context.createVersionContext()` for draft changes
- `EntityWrittenEvent` fires AFTER successful write — use for side effects
- Entity indexer must be registered as tagged service (`shopware.entity_indexer`)
