# Agent Context — Auto-Update Instructions

> **SHARED FILE — DO NOT MODIFY.** This file is auto-updated and will be overwritten.
> It is read by the SessionStart agent hook to perform updates.

You are running as a SessionStart agent hook. Your job: check for agent-context updates and sync plugins.
Work silently and efficiently — no unnecessary output.

## Step 1: Version Check

1. Read `.agent-context/.agent-context-version` (default `0.0.0` if missing)
2. Fetch `https://api.github.com/repos/lx-wnk/Agent-Context/releases/latest` and extract `tag_name` (strip `v` prefix) as latest version, and `tarball_url`
3. If versions match or the fetch fails → skip to Step 3

## Step 2: Update Shared Files

1. Download the tarball from `tarball_url` and extract it to a temp directory
2. Copy these files from the extracted archive into `.agent-context/`:

| Source (in archive)                | Destination                                      |
| ---------------------------------- | ------------------------------------------------ |
| `context/agent-startup.md`         | `.agent-context/agent-startup.md`                |
| `context/layer0-agent-workflow.md` | `.agent-context/layer0-agent-workflow.md`         |
| `context/base-principles.md`       | `.agent-context/base-principles.md`              |
| `.prompts/update-prompt.md`        | `.agent-context/update-prompt.md`                |
| `plugins.json`                     | `.agent-context/plugins.json`                    |

3. Write the new version to `.agent-context/.agent-context-version`
5. Clean up the temp directory

## Step 3: Plugin Sync

1. Read `.agent-context/plugins.json` (skip if missing)
2. Read `.claude/settings.json` (create with `{}` if missing)
3. For each plugin not already in `enabledPlugins`: add it with value `true`
4. Never remove existing plugins

## Response

Return `ok: true` with a brief reason summarizing what happened (e.g. "Updated 0.1.1 → 0.1.2, synced 2 plugins" or "Already up to date").
If anything fails, still return `ok: true` — updates are best-effort and must never block session start.
