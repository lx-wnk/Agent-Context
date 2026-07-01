# Research & References

## Core Papers

- [ETH Zurich: Evaluating AGENTS.md (arxiv 2602.11988)](https://arxiv.org/abs/2602.11988) — Empirical evaluation of context files across coding agents; finds auto-generated context tends to reduce task success rates while increasing token cost by 20%+
- [Empirical Study of CLAUDE.md Files (arxiv 2509.14744)](https://arxiv.org/abs/2509.14744) — Analysis of 253 CLAUDE.md files across 242 repositories; validates layered hierarchy design; identifies dominant content categories (Build/Run, Implementation Details, Architecture)
- [Lost in the Middle: How LLMs Use Long Contexts (arxiv 2307.03172)](https://arxiv.org/abs/2307.03172) — Foundational paper on U-shaped position bias; explains why critical constraints belong at the top of context files, not the middle
- [Agentic Context Engineering (arxiv 2510.04618)](https://arxiv.org/abs/2510.04618) — Treats context as an evolving playbook refined through generation, reflection, and curation; directly relevant to the memory self-improvement loop
- [Tokalator: Measuring Token Cost of Instruction Files (arxiv 2604.08290)](https://arxiv.org/abs/2604.08290) — Finds 21.2% of context tokens come from unintentionally-included files; a single instruction file adds ~4,200 tokens per prompt silently
- [On the Impact of AGENTS.md Files (arxiv 2601.20404)](https://arxiv.org/abs/2601.20404) — Empirical measurement: AGENTS.md presence yields 16.58% median runtime reduction and ~20% output-token reduction when content is lean
- [SSGM: Structured Memory Governance (arxiv 2603.11768)](https://arxiv.org/abs/2603.11768) — TTL-tiered memory with semantic relevance × time-decay scoring; basis for the TTL metadata system
- [MemoryGraft: Persistent Memory Poisoning (arxiv 2512.16962)](https://arxiv.org/abs/2512.16962) — Poisoned skill/memory files can corrupt 87% of downstream agent decisions within 4 hours; motivates source attribution and trust scoring
- [A-MemGuard: Consensus Validation Defense (OpenReview)](https://openreview.net/forum?id=fVxfCEv8xG) — Dual-memory + consensus validation cuts poisoning attack success by 95%+

## Engineering & Best Practices

- [Addy Osmani: Stop Using /init for AGENTS.md](https://addyosmani.com/blog/agents-md/) — The "discoverable?" filter for what belongs in context files
- [Anthropic: Effective Context Engineering for AI Agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) — Authoritative guide on context design for agentic systems
- [Anthropic: How We Built Our Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system) — Orchestrator/subagent patterns; multi-agent outperformed single-agent Claude Opus 4 by 90%+ on internal evals
- [Anthropic: Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) — Structured environments for multi-session tasks; relevant to setup/update prompt design
- [Context Engineering for Coding Agents — Thoughtworks](https://martinfowler.com/articles/exploring-gen-ai/context-engineering-coding-agents.html) — Practical framing of context engineering for coding workflows (Birgitta Böckeler, published on martinfowler.com)
- [Want better AI outputs? Try context engineering — GitHub Blog](https://github.blog/ai-and-ml/generative-ai/want-better-ai-outputs-try-context-engineering/) — Accessible overview of context engineering concepts
- [llms.txt standard](https://llmstxt.org/) — Curated pointer-index file for LLM navigation of large doc sets without modification; basis for the knowledge-map.md pattern
- [Terraform plan/apply](https://developer.hashicorp.com/terraform/cli/commands/plan) — Plan-before-execute UX pattern; basis for setup-plan.md and Ack/Nack flow
- [Nx migrations.json](https://nx.dev/docs/reference/nx/migrations) — Persisted decision manifest for idempotent re-runs; basis for setup-decisions.json
- [Copier: Template Updating](https://copier.readthedocs.io/en/stable/updating/) — Three-way merge approach for project-owned files (evaluated and adapted — conflict markers replaced with additive-only + integrity check)

## Standards & Docs

- [AGENTS.md specification](https://agents.md/) — Open standard for agent instructions, stewarded by the Agentic AI Foundation (Linux Foundation)
- [Claude Code: Best Practices](https://code.claude.com/docs/en/best-practices)
- [Claude Code: Skills](https://code.claude.com/docs/en/skills)
- [Agent Creation Best Practices](best-practices-agent-creation.md) — Comprehensive guide for creating custom agent configurations (German)
