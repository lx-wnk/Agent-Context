# AGENTS.md — Project Bootstrap

> All agents read and follow this file.

## Identity

<!-- TODO: Project Name | Tech Stack | Docker Container -->

## Context Architecture

@.agent-context/agent-startup.md
@.agent-context/layer0-agent-workflow.md
@.agent-context/layer1-bootstrap.md
@.agent-context/layer2-project-core.md
@.agent-context/layer3-guidebook.md

An agent that does not expand `@` includes reads the files listed above in order at session start.

## Quick Rules (Always Apply)

<!-- TODO: Add project-specific quick rules -->

## Compaction Preservation

When compacting context, always preserve:

- List of modified/created files in this session
- Active test/lint commands and their last results
- Unfinished tasks and next steps
