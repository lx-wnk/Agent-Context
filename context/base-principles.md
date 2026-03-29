# Base Development Principles

> Only rules that agents don't follow by default. Standard practices (KISS, YAGNI, DRY, SOLID, Clean Code) are omitted —
> every modern LLM already applies them.

## Implementation Rules

- Implement autonomously — follow existing codebase patterns, never delegate implementation to the user
- When unsure which approach fits best → present concrete options with trade-offs
- No magic strings — use constants

## Quality Gates

- No silent failures — handle errors explicitly, use early returns

## Security

- Never share `.env` file contents — if you need information, ask for the specific variable
