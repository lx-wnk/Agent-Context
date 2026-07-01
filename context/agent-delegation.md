# Delegating to Specialist Agents

> **⚠ SHARED FILE — DO NOT ADD PROJECT-SPECIFIC CONTENT.** Auto-updated and overwritten.
> Loaded on-demand — read this only when delegating a task to a sub-agent (pointer in `layer0-agent-workflow.md`).

When delegating a task to a specialist sub-agent, follow this context injection protocol.

## Context Injection

Specialist agents have no direct access to `.agent-context/`. Inject the context they need via the delegating prompt:

```
You are being dispatched as [agent-name].

## Project Context

[Paste relevant snippets from layer1, layer2, and decisions.json here]

## Task

[Specific task description]
```

Inject only what is relevant to the task — not all layers wholesale.

## Available Specialist Agents (requires `agents@lx-wnk` plugin)

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

## Persist Block Handling

Some agents return a `persist:` block when they produce knowledge that should be saved. Handle it as follows:

**type: adr:**

- Append a new entry to `.agent-context/decisions.json` using the title, context, decision, and consequences fields

**type: memory-update:**

- Append the content to the specified file under `.agent-context/` (e.g., `memory/lessons.md`)

The persist block is a request, not an automatic write. Review it before persisting.
