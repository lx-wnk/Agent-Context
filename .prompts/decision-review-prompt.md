# Decision Review — Daily Cron Prompt

> **⚠ SHARED FILE — DO NOT ADD PROJECT-SPECIFIC CONTENT.** This file is auto-updated and will be overwritten.
> Project-specific adjustments to the review logic belong in `layer2-project-core.md`.

## Scheduling

To enable automatic daily reviews, run `/schedule` and create a daily trigger that executes this prompt.
Recommended schedule: daily at 8:00 AM. You can also run this prompt manually at any time.

## Your Task

Review all decisions in `.agent-context/decisions.json` and process expired entries based on their weight.
Work efficiently — report errors immediately, output the final summary at the end.

## Step 1: Read & Parse

1. Read `.agent-context/decisions.json` — if missing or empty (`[]`), return `ok: true` with "No decisions to review"
2. If the file exists but cannot be parsed as JSON, return `ok: false` with the parse error and first 200 characters of file content. Do NOT attempt automatic repair.
3. Determine today's date

### Expected JSON Schema

Each entry in the array follows this structure:

```json
{
  "id": "2026-03-15-use-redis-for-sessions",
  "date": "2026-03-15",
  "decision": "Use Redis instead of file-based sessions",
  "reasoning": "File sessions cause lock contention under load",
  "scope": "infrastructure",
  "weight": "high",
  "reviewDate": "2026-04-15"
}
```

Valid weights: `low`, `medium`, `high`, `critical`. The `reviewDate` determines when the decision is next evaluated.

## Step 1.5: Validate Entries

Before processing, validate each entry in the array:

1. Required fields: `id`, `date`, `decision`, `reasoning`, `scope`, `weight`, `reviewDate`
2. `weight` must be one of: `low`, `medium`, `high`, `critical`
3. `date` and `reviewDate` must match `YYYY-MM-DD` format

If entries have validation errors, include them in the final summary under an "Invalid Entries" section rather than silently skipping them. Continue processing valid entries.

## Step 2: Migration (One-Time)

If `.agent-context/memory/decisions.md` exists and contains content beyond stub comments (lines starting with `<!--`):

1. Parse each decision entry from the markdown
2. Generate an `id` from the date and a kebab-case slug of the decision
3. Add each as a new entry to the JSON array with `weight: "medium"` and `reviewDate` set to today + 30 days — skip entries whose `id` already exists in the array
4. Replace the markdown file content with just the stub comment (preserving the file for backwards compatibility)
5. If the JSON write succeeds but clearing the markdown file fails, report partial migration in the summary and return `ok: false`.

## Step 3: Process Expired Decisions

Filter for entries where `reviewDate <= today`. For each expired entry, apply the graduation logic:

For each expired decision, determine the action based on `weight`:

| Weight     | Condition                                        | Action                                                          |
| ---------- | ------------------------------------------------ | --------------------------------------------------------------- |
| `low`      | —                                                | **Delete** — tactical decisions that weren't upgraded are noise |
| `medium`   | First review (`reviewDate` < `date` + 60 days)   | **Extend** — needs more time to prove itself                    |
| `medium`   | Second review (`reviewDate` >= `date` + 60 days) | **Ask** the user: graduate, extend, or delete                   |
| `high`     | —                                                | **Graduate** — proven important, move to persistent memory      |
| `critical` | —                                                | **Graduate** — foundational decision, move to persistent memory |

### For each action:

**Graduate:** Append a formatted entry to `.agent-context/memory/lessons.md`:

```
- **[{scope}]** {decision} — {reasoning} (decided {date})
```

Then remove the entry from the JSON array.

**Extend:** Set `reviewDate` to today + 30 days. Keep in JSON.

**Delete:** Remove the entry from the JSON array.

**Ask:** Present the decision to the user and ask: graduate, extend, or delete. Then apply the chosen action.

> **Unattended mode:** If running as a scheduled trigger with no interactive user, treat "Ask" decisions as **Extend** instead. Include them in the summary as "Deferred — needs user input" so the user can review manually.
> **Detection:** Runtime-dependent — for Claude Code, triggers created via `/schedule` are unattended; manual invocations are interactive.

## Step 4: Write Back

1. Write the modified array back to `.agent-context/decisions.json`
2. Ensure valid JSON formatting
3. After writing, re-read the file and confirm it parses correctly as a JSON array. If validation fails, return `ok: false` with the error.

## Step 5: Summary

Return `ok: true` with a summary:

```
Decision Review: {graduated} graduated, {extended} extended, {deleted} deleted, {remaining} remaining active
```

If no decisions were due for review: `Decision Review: No decisions due for review. {total} active decisions.`
