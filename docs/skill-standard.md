# Skill Standard (SKILL.md)

Agent-Context skills follow the open [Agent Skills standard](https://agentskills.io) (stewarded alongside
the `AGENTS.md` ecosystem). Writing skills to this contract makes `.agent-context/skills/` portable across
Claude Code, Codex, Cursor, Gemini CLI, and any other agent that implements the standard — the same skill
folder works everywhere without a rewrite.

## The Contract

A skill is a **directory** containing a `SKILL.md` file. `SKILL.md` opens with a YAML frontmatter block with
exactly two required fields:

```markdown
---
name: payment-flow
description: Use when working on cart, checkout, or payment capture — covers the Mollie webhook order, idempotency keys, and the refund state machine.
---

# Payment Flow

<full skill body — instructions, steps, references>
```

| Field         | Required | Rule                                                                                                                                                                                      |
| ------------- | -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `name`        | yes      | kebab-case, matches the directory name, unique within `skills/`                                                                                                                           |
| `description` | yes      | One line. **Starts with the trigger** ("Use when…") then what it covers. This is the only text the agent sees until the skill activates — it must carry enough signal to route correctly. |

No other fields are required. Optional metadata (e.g. `license`, `allowed-tools`) may be added where a host
agent supports it, but portability only depends on `name` + `description`.

## Progressive Disclosure (why the contract is shaped this way)

The standard is built around three load levels — this is the same "stubs + skills" economy Agent-Context uses
everywhere:

1. **Always loaded:** only `name` + `description` (one row in `skills/index.md`). Near-zero token cost.
2. **Loaded on match:** the `SKILL.md` body, pulled in only when a task matches the description's trigger.
3. **Loaded on demand:** any extra files the body references (scripts, large tables, templates) — read only
   if the body tells the agent to open them.

A heavy reference therefore costs almost nothing until the moment it is actually needed. Keep `SKILL.md`
bodies focused; push bulk material (long tables, schemas, example sets) into sibling files the body links to.

## Layout in Agent-Context

```
.agent-context/skills/
  index.md                      # registry: name | trigger | description (always loaded)
  payment-flow/
    SKILL.md                    # frontmatter + body
    refund-states.md            # on-demand reference linked from SKILL.md
  api-pagination/
    SKILL.md
```

`skills/index.md` is the always-on routing layer: one row per skill, mirroring each `SKILL.md`'s `name` and
`description`. Layer 0 → Skill Lookup tells the agent to scan this index before any task and open the matching
`SKILL.md`.

## Backward Compatibility (legacy single-file skills)

Earlier Agent-Context installs used a flat `skills/<name>.md` file with YAML trigger frontmatter, rather than a
`skills/<name>/SKILL.md` directory. **Both forms remain valid** — the agent loads either when the index points
to it. No migration is forced.

To migrate a legacy skill to the portable standard (optional):

1. Create `skills/<name>/` and move the file to `skills/<name>/SKILL.md`.
2. Ensure the frontmatter has `name` (kebab-case, = folder name) and a trigger-first `description`.
3. Split any bulk reference content into sibling files linked from the body.
4. Update the row in `skills/index.md` if the path display changes.

## Authoring Checklist

- [ ] Directory name = `name` = kebab-case
- [ ] `description` starts with the trigger condition, then the coverage
- [ ] Body is focused; bulk material lives in linked sibling files
- [ ] A matching row exists in `skills/index.md`
- [ ] Content is project-specific and **not** discoverable from source code (same filter as all context files)
