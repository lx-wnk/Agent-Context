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
ref pinning), uses your branch's prompt, and always runs the agent (there is no release to compare
against, so the "already up to date" short-circuit never applies). It runs a normal update; add
`--force` for a full from-scratch rediscovery. `install.sh` installs into the current directory, so `cd` into the target first:

```bash
cd ~/code/my-other-project
bash ~/code/Agent-Context/install.sh --local-source ~/code/Agent-Context
```

`--local-source <path>` (or the env var `AGENT_CONTEXT_SOURCE=<path>`) selects the local prompt and files;
`--force` is independent of it. Replace the example paths with your clone and target project. For an
already-released version, drop the flag and use the normal [install one-liner](README.md#installation).

## Running the checks

```bash
npm test              # every tests/*.sh suite in sequence — see the "test" script in package.json for the list
npm run prettier      # check formatting (CI-style)
npm run prettier:fix  # auto-fix formatting
```

CI does not run shellcheck yet. Run it on every shell file you change and fix what it reports:

```bash
shellcheck -x install.sh tests/*.sh context/bin/*.sh context/hooks/*.sh
```

## Pull requests

- Commit messages are written in English, with a [Conventional Commits](https://www.conventionalcommits.org/) subject (`feat(scope): …`, `fix: …`, `docs: …`, `chore(release): …`).
- Every user-visible change adds an entry under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md) (Added, Changed, Fixed, Removed, Security, Docs).
- PRs follow [`.github/pull_request_template.md`](.github/pull_request_template.md) — summary, changes, notes on trade-offs or breaking changes, and the checklist.

## Releasing

1. Open a release PR (`chore(release): X.Y.Z`) that renames `## [Unreleased]` in CHANGELOG.md to `## [X.Y.Z] - YYYY-MM-DD` and starts a new empty `## [Unreleased]` section. Merge it.
2. On the merged `main`, create an annotated tag without a `v` prefix and push it: `git tag -a X.Y.Z -m "X.Y.Z"` then `git push origin X.Y.Z`.
3. Publish the release: `gh release create X.Y.Z --notes-file <notes>`, with the CHANGELOG section as notes. `install.sh` installs the release marked latest.

`package.json` stays at `0.0.0-dev`; the release tag is the version.
