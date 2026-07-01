# Contributing to Agent Context Architecture

Thanks for considering a contribution. This project is a template system installed into other projects — see [README.md](README.md) for the architecture overview.

## Offline install smoke test (no network, no release, no agent)

The fastest way to verify your changes install cleanly. It derives the shared-file list from the
`setup-prompt.md` download table, copies everything from your working tree into a throwaway target,
and runs the installed gates — so it also catches a new shared file you forgot to wire into the table:

```bash
bash tests/check-install-smoke.sh            # temp dir, auto-removed
bash tests/check-install-smoke.sh /tmp/ac    # keep the installed tree to inspect it
```

This runs as part of `npm test`, so CI guards it on every change.

## Full agent dry-run in another project

The smoke test above runs in isolation. To see how Agent-Context actually installs into a **real
codebase** — real files to discover, an existing `.claude/` to merge, layers filled from your stack —
run the installer inside that project with `--local-source` pointing at your clone. It installs every
shared file and template **from your local working tree** instead of downloading (no release tag, no
ref pinning), uses your branch's prompt, and forces a run (bypassing the "already up to date"
short-circuit). `install.sh` installs into the current directory, so `cd` into the target first:

```bash
cd ~/code/my-other-project
bash ~/code/Agent-Context/install.sh --local-source ~/code/Agent-Context
```

`--local-source <path>` (or the env var `AGENT_CONTEXT_SOURCE=<path>`) is the one knob — it implies the
local prompt and a forced run. Replace the example paths with your clone and target project. For an
already-released version, drop the flag and use the normal [install one-liner](README.md#installation).

## Running the checks

```bash
npm test              # full test suite: install, template coverage, token budget, memory-prune, hooks, discovery digest, map budget, smoke test, local-source
npm run prettier      # check formatting (CI-style)
npm run prettier:fix  # auto-fix formatting
```

## Pull requests

Commit messages must be written in English. PRs follow the checklist in [`.github/pull_request_template.md`](.github/pull_request_template.md) — summary, changes, and notes on trade-offs or breaking changes.
