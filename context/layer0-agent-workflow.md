# Layer 0 — Agent Workflow

> **⚠ SHARED FILE — DO NOT ADD PROJECT-SPECIFIC CONTENT.** This file is auto-updated and will be overwritten.
> Project-specific workflow rules belong in `layer2-project-core.md`, task routing belongs in `layer3-guidebook.md`.

## Skill Lookup

- Before starting any task, check `.agent-context/skills/index.md` for a matching skill — read and follow it

## Memory Update Rules

- Store non-discoverable learnings (gotchas, external IDs, decisions) in `.agent-context/memory/`
- Every memory entry MUST include a date `(YYYY-MM-DD)` — enables staleness tracking
- Memory stubs: max 15 lines, one per domain
- Heavy references (>30 lines): create a skill in `.agent-context/skills/` with YAML trigger frontmatter
- Each fact lives in exactly ONE place. No duplicates across files.

### Domain Expansion

When a `memory/<domain>.md` stub reaches 15 lines, expand it into a directory:

1. Create `memory/<domain>/` with topical sub-files (e.g., `memory/cart/pricing.md`, `memory/cart/checkout-flow.md`)
2. Replace the original `memory/<domain>.md` content with an index that lists sub-files and their purpose
3. Each sub-file follows the same rules: date required, max 30 lines — beyond that, graduate to a skill
4. Update `memory/index.md` to reflect the expansion

## Routing New Knowledge

| Type                        | Target                                                                             |
| --------------------------- | ---------------------------------------------------------------------------------- |
| Project-wide convention     | `layer2-project-core.md`                                                           |
| Domain-specific fact        | `memory/<domain>.md`                                                               |
| Heavy reference (>30 lines) | `skills/<reference>.md`                                                            |
| Gotcha / hard-won lesson    | `memory/lessons.md` (include `ttl:90d source:discovered conf:med` for new entries) |
| Architecture decision       | `decisions.json`                                                                   |
| External knowledge pointer  | `knowledge-map.md` (add row to Knowledge Sources + Task Routing)                   |
| User profile detail         | `memory/user.md`                                                                   |
| Agent behavior preference   | `memory/preferences.md`                                                            |
| Team member / stakeholder   | `memory/people.md`                                                                 |

## Self-Improvement Loop

> **MUST — Non-negotiable.** Every trigger below MUST result in an immediate write — the very next action after the discovery, before continuing other work. Do not batch or defer.

### Triggers

Save immediately when ANY of the following occurs:

- **User correction** → update `memory/lessons.md` with the pattern and what went wrong
- **User preference** → update `memory/preferences.md`
- **Self-discovered insight or technical discovery** (unexpected behavior, gotcha, undocumented API quirk, non-obvious format found during debugging or research) → update `memory/lessons.md` or relevant domain file
- **Architecture or design decision** made or confirmed → update `decisions.json`
- **New personal or team info** emerges → update `memory/user.md` or `memory/people.md`

### When in Doubt, Save

If you're unsure whether something is worth saving, ask: "Would a future session benefit from knowing this, and is it NOT discoverable from source code?" If yes — save it. Unnecessary entries can be cleaned up, but lost discoveries cannot be recovered.

### Session Routine

- **Session start**: read `memory/lessons.md` + `memory/preferences.md`; if `memory/todo.md` exists (local-only, gitignored), read it for the active task plan
- **During session**: triggers are handled inline (see directive above)
- **Session end**: review whether any triggers fired but were missed and persist them. Cross-session activity history lives in Git history and external session logs (e.g., Obsidian) — not in repo memory
- **After 3+ memory updates**: scan for contradictions with existing entries before closing

### Knowledge Map Triggers

Update `.agent-context/knowledge-map.md` immediately when any of the following occurs — same non-negotiable rule as all other triggers (next action after discovery, before continuing):

| Event                                              | Action                                                   |
| -------------------------------------------------- | -------------------------------------------------------- |
| External file changed (SHA256 mismatch detected)   | Update SHA256 + Last Verified in Knowledge Sources table |
| New structured knowledge file or folder discovered | Add entry to Knowledge Sources + add row to Task Routing |
| Task type used but no routing row exists for it    | Add routing row to Task Routing based on current task    |
| Knowledge source no longer exists                  | Remove entry from Knowledge Sources table                |

### Lesson Graduation

When a lesson has proven itself (applied 3+ times, never questioned), suggest promoting it:

- Project-wide convention → move to `layer2-project-core.md`
- Domain-specific pattern → keep in `memory/<domain>.md` (or sub-file if domain is expanded)
- Remove the original entry from `memory/lessons.md` after promotion

## Delegating to Specialist Agents

When delegating a task to a specialist sub-agent, follow this context injection protocol:

### Context Injection

Specialist agents have no direct access to `.agent-context/`. Inject the context they need via the delegating prompt:

```
You are being dispatched as [agent-name].

## Project Context

[Paste relevant snippets from layer1, layer2, and decisions.json here]

## Task

[Specific task description]
```

Inject only what is relevant to the task — not all layers wholesale.

### Available Specialist Agents (requires `agents@lx-wnk` plugin)

> **Optional.** The following table only applies if the `agents@lx-wnk` plugin is installed.
> If agents are not available, skip this table and delegate to general-purpose sub-agents instead.

| Agent          | Inject                                         |
| -------------- | ---------------------------------------------- |
| `ac-backend`   | layer1 stack, layer2 rules, relevant decisions |
| `ac-frontend`  | layer1 stack, layer2 CSS/component conventions |
| `ac-testing`   | layer2 test conventions and QA command         |
| `ac-architect` | layer2 conventions, relevant decisions         |
| `ac-review`    | layer2 coding conventions                      |
| `ac-concept`   | layer1 stack, relevant constraints             |
| `ac-chrome`    | layer1 local domains and ports                 |
| Others         | task description alone is sufficient           |

### Persist Block Handling

Some agents return a `persist:` block when they produce knowledge that should be saved. Handle it as follows:

**type: adr:**

- Append a new entry to `.agent-context/decisions.json` using the title, context, decision, and consequences fields

**type: memory-update:**

- Append the content to the specified file under `.agent-context/` (e.g., `memory/lessons.md`)

The persist block is a request, not an automatic write. Review it before persisting.
