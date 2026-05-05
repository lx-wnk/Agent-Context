# Changelog

All notable changes to this project will be documented here. Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.7.0] - 2026-05-04

### Removed

- **`memory/log.md`** — cross-session activity log eliminated. Git history and external session notes (Obsidian, Confluence) already provide this information without merge conflicts. Existing files are removed automatically on update.

### Changed

- **`memory/todo.md`** is now local-only. The file is gitignored and no longer propagates across branches or clones — eliminates merge conflicts on per-task working state. Existing content is preserved locally, untracked on update.
- `layer0-agent-workflow.md` and `layer3-guidebook.md` updated to reflect the new memory layout.

### Migration

Automatic via the `install.sh` one-liner (UPDATE mode). The migration is idempotent: re-running setup on an already-migrated project produces no further changes.
