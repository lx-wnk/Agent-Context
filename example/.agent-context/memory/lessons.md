# Lessons & Gotchas

## Translation Fallback Chain

DAL loads system-default language first as base, then overlays context language. If the system-default translation row is missing, fields may appear empty even though a translation exists in another language.

## Entity Indexer Ordering

Indexers run in registration order. If indexer B depends on data computed by indexer A, ensure A is registered first in `services.xml`.

## Admin Module Hot Reload

After adding a new admin module or changing `main.js`, a full `bin/build-administration.sh` is required. Watcher does not pick up new module registrations.

## Migration Destructive vs. Regular

`Migration::update()` runs always. `Migration::updateDestructive()` runs only with explicit flag. Put column drops and table deletes in `updateDestructive()`.
