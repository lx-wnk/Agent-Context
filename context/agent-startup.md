# Agent Startup — Shared Configuration

> **⚠ SHARED FILE — DO NOT ADD PROJECT-SPECIFIC CONTENT.**
> This file is auto-updated and will be overwritten. Project-specific rules belong in `layer1-bootstrap.md` or
> `layer2-project-core.md`.

## Auto-Update

Updates are handled automatically by the SessionStart hook in `.claude/settings.json`, which runs
`.agent-context/scripts/agent-context-update.sh` at every session start. The script checks for new releases, updates shared
files (including the script itself), and syncs plugins — no agent involvement needed.

For non-Claude-Code agents: check `.agent-context/.version` against
`https://api.github.com/repos/lx-wnk/Agent-Context/releases/latest` and update shared files if versions differ:
`context/agent-startup.md`, `context/layer0-agent-workflow.md`, `context/base-principles.md`, `plugins.json`, and
`scripts/agent-context-update.sh` → `.agent-context/scripts/`.
