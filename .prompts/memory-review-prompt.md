# Memory Review — Monthly Cron Prompt

> **SHARED FILE — DO NOT MODIFY.** This file is auto-updated and will be overwritten.

## Scheduling

To enable automatic monthly reviews, run `/schedule` and create a monthly trigger that executes this prompt.
Recommended schedule: 1st of each month at 9:00 AM. You can also run this prompt manually at any time.

## Your Task

Review all memory files in `.agent-context/memory/` for staleness, duplicates, and graduation candidates.
Work silently and efficiently — only output the final summary.

## Step 1: Inventory

1. List all files in `.agent-context/memory/`
2. For each file, count non-comment lines and extract all entries with dates
3. Determine today's date

## Step 2: Staleness Check

For each memory entry that has a date (format `YYYY-MM-DD`):

| Age         | Action                                                        |
| ----------- | ------------------------------------------------------------- |
| < 90 days   | Keep — still fresh                                            |
| 90-180 days | Flag as **stale** — include in summary for user review        |
| > 180 days  | Flag as **archive candidate** — suggest removal or graduation |

Entries without dates: flag as **undated** in summary (suggest adding a date).

## Step 3: Duplicate Detection

Scan across all memory files for semantically duplicate information:

- Same fact stated in different files
- Information that is now discoverable from source code (check by grepping the codebase)
- Entries that contradict each other

Flag duplicates in summary.

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
