# Memory Review — Monthly Cron Prompt

> **⚠ SHARED FILE — DO NOT ADD PROJECT-SPECIFIC CONTENT.** This file is auto-updated and will be overwritten.

## Scheduling

To enable automatic monthly reviews, run `/schedule` and create a monthly trigger that executes this prompt.
Recommended schedule: 1st of each month at 9:00 AM. You can also run this prompt manually at any time.

## Your Task

Review all memory files in `.agent-context/memory/` for staleness, duplicates, and graduation candidates.
Work efficiently — report errors immediately, output the final summary at the end.

## Step 1: Inventory

1. List all files in `.agent-context/memory/` (including sub-files in expanded domain directories like `memory/<domain>/`)
2. If `.agent-context/memory/` does not exist, return `ok: false` with an error explaining the directory is missing.
3. For each file, count non-comment lines and extract all entries with dates
4. If any file cannot be read, include it in the summary under an "Errors" section rather than silently skipping it.
5. Determine today's date

## Step 2: Staleness Check

For each memory entry that has a date (format `YYYY-MM-DD`):

1. Extract inline TTL marker if present (e.g., `ttl:90d`, `ttl:infinite`, `ttl:30d`)
2. Apply TTL rules:

| TTL                        | Rule                                                                                                            |
| -------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `ttl:infinite`             | Never expires — skip staleness check                                                                            |
| `ttl:Nd` (e.g., `ttl:90d`) | Flag as **stale** when (date + 0.75×N days) < today; flag as **archive candidate** when (date + N days) < today |
| No TTL present             | Apply defaults: <90 days keep, 90-180 days **stale**, >180 days **archive candidate**                           |

3. Entries without dates: flag as **undated** in summary (suggest adding date + TTL).

## Step 3: Duplicate Detection

Scan across all memory files for semantically duplicate information:

- Same fact stated in different files
- Information that is now discoverable from source code (check by grepping the codebase)
- Entries that contradict each other — flag as **conflict**, include both in summary. Higher `conf:` value wins; equal conf requires user resolution.

Flag duplicates in summary. If the codebase grep cannot be performed (wrong directory, timeout, or error), report the source-code discoverability check as "skipped" rather than reporting 0 duplicates. The other two checks (cross-file duplicates, contradictions) can still be performed from memory files alone.

## Step 4: Graduation Candidates

Identify lessons in `memory/lessons.md` that should be promoted to `layer2-project-core.md`:

A lesson is a graduation candidate if:

- It has been applied 3+ times (look for `conf:high` tag or other indicators in the entry text)
- It describes a project-wide convention (not domain-specific)
- It has survived 2+ review cycles without being questioned

Flag candidates in summary — never auto-promote (user decision).

## Step 5: Domain Expansion Check

If any `memory/<domain>/` directories exist (expanded domains):

1. List all sub-files in each expanded domain directory
2. For each sub-file, count non-comment lines
3. Flag sub-files exceeding 30 lines as **skill candidates** — suggest graduating to `skills/<reference>.md`

## Step 6: Summary

Return `ok: true` with a summary (adapt counts to include expanded domain sub-files):

```
Memory Review: {total_files} files, {total_entries} entries
- {fresh} fresh, {stale} stale, {archive} archive candidates
- {undated} entries without dates
- {duplicates} potential duplicates
- {graduation} graduation candidates
```

If any items need attention, list them:

```
## Items Needing Attention

### Stale (90+ days)
- `memory/commands.md`: "Docker port 8080 for API" (2025-11-15)

### Graduation Candidates
- `memory/lessons.md`: "[testing] Always seed the database before integration tests" — consider promoting to layer2

### Duplicates
- "PHP 8.2 minimum" appears in both `memory/architecture.md` and `layer1-bootstrap.md`
```
