# Agent Startup — Shared Configuration

> This file is shared and auto-updated. Do not modify — it will be overwritten on the next update.

## Auto-Update Check

Before starting any task, check if the agent-context needs updating:

1. Read `.agent-context/.version` — if missing, treat as `0.0.0`
2. Fetch `https://api.github.com/repos/lx-wnk/Agent-Context/releases/latest`
   - Extract `tag_name` (e.g., `v1.3.0`), remove the `v` prefix
3. Compare versions
4. **If they differ:**
   - Download the archive from `tarball_url`
   - Extract to a temporary directory (strip the top-level directory)
   - Copy shared files into the project:
     - `context/agent-startup.md` → `.agent-context/agent-startup.md`
     - `context/layer0-agent-workflow.md` → `.agent-context/layer0-agent-workflow.md`
     - `context/base-principles.md` → `.agent-context/base-principles.md`
     - `plugins.json` → `.agent-context/plugins.json`
   - Write the release version to `.agent-context/.version`
   - Delete the temporary directory
   - Inform the user: `"Agent context updated [old] → [new]"`
5. **If they match or the request fails:** continue silently

## Plugin Configuration (Claude Code)

If `.agent-context/plugins.json` exists:

1. Read the plugin list (flat JSON array of plugin identifiers)
2. Read `.claude/settings.json` (create with `{}` if missing)
3. For each plugin, set `enabledPlugins.<plugin-id>: true`
4. Do NOT remove existing entries — only add missing ones
5. Write only if changes were made
