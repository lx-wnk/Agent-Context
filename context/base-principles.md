# Base Development Principles

> **⚠ SHARED FILE — DO NOT ADD PROJECT-SPECIFIC CONTENT.** This file is auto-updated and will be overwritten.
> Project-specific principles belong in `layer2-project-core.md`.
>
> Standard practices (KISS, YAGNI, DRY, SOLID, Clean Code) are intentionally omitted — every modern LLM already applies
> them. Adding them wastes context budget and reduces performance (ETH Zurich, 2026).

## Implementation Rules

- Implement autonomously — follow existing codebase patterns, never delegate implementation to the user
- When unsure which approach fits best → present concrete options with trade-offs
- No magic strings — use constants

## Quality Gates

- No silent failures — handle errors explicitly, use early returns

## Security

- Never share `.env` file contents — if you need information, ask for the specific variable

## Context Hygiene

- Never add information discoverable from source code — it wastes context and reduces performance (ETH Zurich, 2026)
- Place critical constraints at the beginning of context files — models lose accuracy in the middle (Chroma, 2025)
- Prefer concrete rules over general principles — LLMs already know KISS/YAGNI/DRY/SOLID
- Review memory files periodically — stale context actively misleads (read `memory-review-prompt.md`)
