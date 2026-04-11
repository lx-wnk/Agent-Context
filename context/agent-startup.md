# Agent Startup — Shared Configuration

> **⚠ SHARED FILE — DO NOT ADD PROJECT-SPECIFIC CONTENT.** This file is auto-updated and will be overwritten.
> Project-specific rules belong in `layer1-bootstrap.md` or `layer2-project-core.md`.

## Auto-Update

Updates can be triggered manually:

1. Fetch the latest release tag from `https://api.github.com/repos/lx-wnk/Agent-Context/releases/latest` (use
   `tag_name`)
2. Fetch the setup prompt from
   `https://raw.githubusercontent.com/lx-wnk/Agent-Context/{tag_name}/.prompts/setup-prompt.md`
3. Follow its instructions — it auto-detects UPDATE mode, checks for new releases, updates shared files, and syncs
   plugins

If any fetch returns a non-200 status, report the error and do not proceed. Compare the fetched version against
`.agent-context/.agent-context-version` using semver — refuse downgrades.
