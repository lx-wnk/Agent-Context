# Agent Context — Auto-Update Instructions

> **SHARED FILE — DO NOT MODIFY.** This file is auto-updated and will be overwritten.

Your job: check for agent-context updates, sync agents, and sync plugins.
Work silently and efficiently — no unnecessary output.

## Step 1: Version Check

1. Read `.agent-context/.agent-context-version` (default `0.0.0` if missing)
2. Fetch `https://api.github.com/repos/lx-wnk/Agent-Context/releases/latest` and extract `tag_name` (strip `v` prefix)
   as latest version, and `tarball_url`
3. If versions match or the fetch fails → skip to Step 4

## Step 2: Update Shared Files

1. Download the tarball from `tarball_url` and extract it to a temp directory
2. Copy these files from the extracted archive into `.agent-context/`:

| Source (in archive)                | Destination                               |
| ---------------------------------- | ----------------------------------------- |
| `context/agent-startup.md`         | `.agent-context/agent-startup.md`         |
| `context/layer0-agent-workflow.md` | `.agent-context/layer0-agent-workflow.md` |
| `context/base-principles.md`       | `.agent-context/base-principles.md`       |
| `.prompts/update-prompt.md`        | `.agent-context/update-prompt.md`         |
| `plugins.json`                     | `.agent-context/plugins.json`             |

3. Write the new version to `.agent-context/.agent-context-version`
4. Clean up the temp directory

## Step 3: Agent Sync

Update shared agents (prefixed `ac-`) in both global and project-local locations. Only update locations where `ac-*`
agents already exist — do NOT install agents into a location that has none.

1. Check if the archive contains an `agents/` directory with `ac-*.md` files. If not, skip this step.
2. Check **both** agent locations for existing `ac-*` files:
   - `~/.claude/agents/` (global)
   - `.claude/agents/` (project-local)
3. For each location that **already contains at least one `ac-*` file**:
   - Overwrite all existing `ac-*` files with versions from the archive
   - Add any new `ac-*` files not yet present
   - Never touch files without the `ac-` prefix (those are user-owned)
4. If neither location has `ac-*` files, skip — agents are opt-in via setup.

## Step 4: Plugin Sync

1. Read `.agent-context/plugins.json` (skip if missing)
2. Read `.claude/settings.json` (create with `{}` if missing)
3. For each plugin not already in `enabledPlugins`: add it with value `true`
4. Never remove existing plugins

## Response

Return `ok: true` with a brief reason summarizing what happened (e.g. "Updated 0.1.1 → 0.1.2, synced 3 agents, synced 2
plugins" or "Already up to date"). If anything fails, still return `ok: true` — updates are best-effort and must never
block session start.
