# Key Principles

## 1. "Can the agent discover this by reading the code?"

Based on the [ETH Zurich study (2026)](https://arxiv.org/abs/2602.11988): auto-generated context files tend to **reduce** task success rates while increasing token cost by over 20%. Only include information that is **not discoverable** from source code.

**Keep:** Gotchas, non-linter conventions, architecture decisions, external system references, CI workflows. **Remove:** Directory trees, entity fields, route tables, service registrations, dependency lists.

## 2. Narrowest fitting scope

Route information to the most specific level possible:

| Scope                       | Target                   |
| --------------------------- | ------------------------ |
| General philosophy          | `layer2-project-core.md` |
| Domain convention           | `memory/<domain>.md`     |
| Heavy reference (>30 lines) | `skills/<reference>.md`  |
| Gotcha / lesson             | `memory/lessons.md`      |

A PHP convention loaded during a CSS fix is wasted context.

## 3. Stubs + Skills pattern

Memory files are lightweight stubs (~10 lines) with quick facts. Full reference lives in skills, loaded only when trigger keywords match. This achieves near-zero baseline cost for heavy documentation.

## 4. Knowledge re-sync when knowledge changed

Updates are not file patches, but they are not full rescans either. SETUP and `--force` perform a full knowledge synchronization: scan all knowledge sources (agent-context, source code, docs, architecture files), build a consolidated fact inventory, route facts to optimal targets, and verify global integrity. A normal UPDATE first checks which recorded sources changed (SHA256 against `setup-decisions.json`) or are new, re-syncs only those, and skips the scan when nothing changed — a release that only ships new shared files costs seconds, not minutes. Either way no fact is lost: it may move, but it must be traceable somewhere.

## 5. Self-maintaining knowledge map

`knowledge-map.md` is the single routing index for all project knowledge — both internal (agent-context) and external (docs, architecture files, API specs). Agents update it immediately when sources change, following the same non-negotiable rule as `lessons.md` updates. The map always reflects current project reality.
