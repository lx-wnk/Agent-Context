# Research & References

## Core Papers

- [ETH Zurich: Evaluating AGENTS.md (arxiv 2602.11988)](https://arxiv.org/abs/2602.11988) — Empirical evaluation of context files across coding agents; finds that context files (LLM-generated and developer-committed) do not generally improve task success rates while increasing inference cost by over 20% on average; useful mainly for non-standard coding practices
- [Empirical Study of CLAUDE.md Files (arxiv 2509.14744)](https://arxiv.org/abs/2509.14744) — Analysis of 253 CLAUDE.md files across 242 repositories; validates layered hierarchy design; identifies dominant content categories (Build/Run, Implementation Details, Architecture)
- [Lost in the Middle: How LLMs Use Long Contexts (arxiv 2307.03172)](https://arxiv.org/abs/2307.03172) — Foundational paper on U-shaped position bias; explains why critical constraints belong at the top of context files, not the middle
- [Agentic Context Engineering (arxiv 2510.04618)](https://arxiv.org/abs/2510.04618) — Treats context as an evolving playbook refined through generation, reflection, and curation; directly relevant to the memory self-improvement loop
- [Tokalator: Measuring Token Cost of Instruction Files (arxiv 2604.08290)](https://arxiv.org/abs/2604.08290) — Finds 21.2% of context tokens come from unintentionally-included files; a single instruction file adds ~4,200 tokens per prompt silently
- [On the Impact of AGENTS.md Files (arxiv 2601.20404)](https://arxiv.org/abs/2601.20404) — Empirical measurement: AGENTS.md presence yields 16.58% median runtime reduction and ~20% output-token reduction when content is lean
- [SSGM: Structured Memory Governance (arxiv 2603.11768)](https://arxiv.org/abs/2603.11768) — TTL-tiered memory with semantic relevance × time-decay scoring; basis for the TTL metadata system
- [MemoryGraft: Persistent Memory Poisoning (arxiv 2512.16962)](https://arxiv.org/abs/2512.16962) — Poisoned skill/memory files can corrupt 87% of downstream agent decisions within 4 hours; motivates source attribution and trust scoring
- [A-MemGuard: Consensus Validation Defense (OpenReview)](https://openreview.net/forum?id=fVxfCEv8xG) — Dual-memory + consensus validation reports a 95%+ cut in poisoning attack success; bypassed by forged reasoning traces in FARMA (below), so it is not relied on here
- [FARMA: Forged Reasoning Attacks on Agent Memory (arxiv 2607.05029)](https://arxiv.org/abs/2607.05029) — Forged reasoning traces reach up to 100% attack success and defeat A-MemGuard and keyword filters
- [Bad Memory: Prompt Injection Risks from Memory (arxiv 2607.14611)](https://arxiv.org/abs/2607.14611) — On Claude Code and Codex, payloads already planted in memory files attack current and future sessions; making the agent write them from untrusted content is hard. Supports reviewing every memory diff over automated screening
- [VibeMemBench (arxiv 2609.23570)](https://arxiv.org/abs/2609.23570) — 11 of 12 solver/memory-system pairings fail to beat memory-off on real repository tasks, while injecting verified experience raises resolution by 1.1–4.5 pp; evidence for curated over auto-captured memory
- [EA-Graph: Artifact-Anchored Verification Memory (arxiv 2608.04278)](https://arxiv.org/abs/2608.04278) — Memory anchored to code artifacts beats prose notes under upstream drift (7/7 worlds on Haiku); basis for `ref:` anchors on memory entries
- [Do Context Files Help Coding Agents? (arxiv 2607.27250)](https://arxiv.org/abs/2607.27250) — Two-agent ablation (Claude Code, Codex): context strategy does not measurably change correctness; reconciles 2602.11988 and 2601.20404 via agent-specific task difficulty
- [SkillsBench (arxiv 2602.12670)](https://arxiv.org/abs/2602.12670) — Curated, focused skills raise pass rate by 16.6 pp across 87 tasks; focused beats exhaustive

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

## Neighbouring Systems

Adjacent tools solving a different layer of the same problem — worth combining, not substituting:

- [ProjectAtlas](https://github.com/styler-ai/ProjectAtlas) — Rust CLI and MCP server keeping a SQLite index of repository structure, symbols, and graph relations, alongside curated folder and file _purposes_. Answers _where the code is_, machine-derived and incrementally refreshed, where the `discovery-map` skill answers _why a subsystem exists_.
- [claude-mem](https://github.com/thedotmack/claude-mem) — hook-driven session memory: captures tool usage automatically, has an LLM compress it into observations, stores them in SQLite plus a vector index, and injects a bounded slice (50 observations, 10 sessions by default) into every session start. Overlaps this framework's `memory/` layer and takes the opposite side of the curation question — captured-and-compressed rather than written-by-hand — while leaving conventions, routing, and project identity untouched.
- [VOIT](https://github.com/yesitsfebreeze/voit) — Claude Code plugin running a four-tier agent workflow (Vision/Organize/Implement/Tweak) with branch-derived roles, per-worker worktrees, a fail-closed write-scope hook, and memory as an orphan-branch worktree. Answers _who does the work_; its [COMPARE.md](https://github.com/yesitsfebreeze/voit/blob/main/COMPARE.md) scores Agent-Context against it.

## Standards & Docs

- [AGENTS.md specification](https://agents.md/) — Open standard for agent instructions, stewarded by the Agentic AI Foundation (Linux Foundation)
- [Claude Code: Best Practices](https://code.claude.com/docs/en/best-practices)
- [Claude Code: Skills](https://code.claude.com/docs/en/skills)
- [Agent Creation Best Practices](best-practices-agent-creation.md) — Comprehensive guide for creating custom agent configurations (German)
