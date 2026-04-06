# Decision Review — Daily Cron Prompt

> **SHARED FILE — DO NOT MODIFY.** This file is auto-updated and will be overwritten.
> Project-specific adjustments to the review logic belong in `layer2-project-core.md`.

## Scheduling

To enable automatic daily reviews, run `/schedule` and create a daily trigger that executes this prompt.
Recommended schedule: daily at 8:00 AM. You can also run this prompt manually at any time.

## Your Task

Review all decisions in `.agent-context/decisions.json` and process expired entries based on their weight.
Work silently and efficiently — only output the final summary.

## Step 1: Read & Parse

1. Read `.agent-context/decisions.json` — if missing or empty (`[]`), return `ok: true` with "No decisions to review"
2. Determine today's date

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

## Step 2: Migration (One-Time)

If `.agent-context/memory/decisions.md` exists and contains content beyond the stub comment (`<!-- Add decisions as they are made -->`):

1. Parse each decision entry from the markdown
2. Add each as a new entry to the JSON array with `weight: "medium"` and `reviewDate` set to today + 30 days
3. Generate an `id` from the date and a kebab-case slug of the decision
4. Replace the markdown file content with just the stub comment (preserving the file for backwards compatibility)

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

## Step 4: Write Back

1. Write the modified array back to `.agent-context/decisions.json`
2. Ensure valid JSON formatting

## Step 5: Summary

Return `ok: true` with a summary:

```
Decision Review: {graduated} graduated, {extended} extended, {deleted} deleted, {remaining} remaining active
```

If no decisions were due for review: `Decision Review: No decisions due for review. {total} active decisions.`
