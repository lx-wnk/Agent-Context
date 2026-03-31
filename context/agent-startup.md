# Agent Startup — Shared Configuration

> **⚠ SHARED FILE — DO NOT ADD PROJECT-SPECIFIC CONTENT.** This file is auto-updated and will be overwritten.
> Project-specific rules belong in `layer1-bootstrap.md` or `layer2-project-core.md`.

## Auto-Update

Updates are handled automatically by a SessionStart agent hook in `.claude/settings.json`. On every session start, a
subagent reads `.agent-context/update-prompt.md` and performs the update: checks for new releases, updates shared files
(including the prompt itself), and syncs plugins.
