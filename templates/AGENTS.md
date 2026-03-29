# AGENTS.md — Project Bootstrap

> All agents MUST read and follow this file.

## Identity

<!-- TODO: Project Name | Tech Stack | Docker Container -->

## Shared Configuration

@.agent-context/agent-startup.md

## Context Architecture

| Layer | File                                     | Content                         |
| ----- | ---------------------------------------- | ------------------------------- |
| 0     | @.agent-context/layer0-agent-workflow.md | Agent Workflow (shared)         |
| 1     | @.agent-context/layer1-bootstrap.md      | Project identity, tech stack    |
| 2     | @.agent-context/layer2-project-core.md   | Dev principles + critical rules |
| 3     | @.agent-context/layer3-guidebook.md      | Task routing, skills, memory    |

## Quick Rules (Always Apply)

<!-- TODO: Add project-specific quick rules -->

## Compaction Preservation

When compacting context, always preserve:

- List of modified/created files in this session
- Active test/lint commands and their last results
- Unfinished tasks and next steps
