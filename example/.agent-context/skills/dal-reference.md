---
name: dal-reference
description: Shopware DAL patterns, entity lifecycle, indexer, versioning, translation system
triggers:
  - DAL
  - entity
  - definition
  - repository
  - migration
  - indexer
  - versioning
  - translation
---

# Data Abstraction Layer — Full Reference

## Core Concepts

Shopware's DAL is a custom thin abstraction optimized for e-commerce. No Doctrine ORM.

```
EntityDefinition → defines schema (fields, associations, flags)
Entity           → data object (auto-generated from definition)
EntityCollection → typed collection of entities
EntityRepository → CRUD + search operations
```

## Entity Definition Pattern

Every entity needs three classes + service registration:

1. `EntityDefinition` — field schema, table name, entity class
2. `Entity` — data object with getters/setters
3. `EntityCollection` — typed collection

Service tag: `shopware.entity.definition`

## Field Types

- `StringField`, `IntField`, `BoolField`, `FloatField`, `DateTimeField`
- `FkField` + `ManyToOneAssociationField` — foreign key relationships
- `OneToManyAssociationField`, `ManyToManyAssociationField`
- `TranslatedField` — wraps a field for multi-language support
- `JsonField` — structured JSON with sub-field definitions

## Translation System

- Entities with translations need a `TranslationDefinition` companion
- Fallback chain: **current language → parent language → system default**
- System default language MUST have a translation row — otherwise fields appear empty
- Use `TranslatedField` in the main definition, actual field in the translation definition

## Entity Indexer Pattern

Pre-compute aggregations on write for fast reads:

1. Implement `EntityIndexer` interface
2. Register as service with tag `shopware.entity_indexer`
3. Handle `EntityWrittenEvent` to trigger re-indexing
4. Store computed data in dedicated columns or index tables

**Important:** Indexers run in registration order. Dependencies between indexers require correct ordering in `services.xml`.

## Versioning

- `context.createVersionContext(versionId)` — creates a draft context
- Changes in versioned context are invisible until merged
- `repository.merge(versionId, context)` — applies draft to live
- Use for preview/staging workflows

## Repository Operations

```php
// Search
$criteria = new Criteria();
$criteria->addFilter(new EqualsFilter('active', true));
$criteria->addAssociation('translations');
$result = $repository->search($criteria, $context);

// Write
$repository->upsert([['id' => $id, 'name' => 'Example']], $context);

// Delete
$repository->delete([['id' => $id]], $context);
```

## Migration Conventions

- One migration per schema change
- Never alter existing migrations
- `update()` — runs always (additive changes: new columns, tables)
- `updateDestructive()` — runs only with flag (drops, deletes)
- Timestamp-based naming: `Migration{timestamp}{Description}`
