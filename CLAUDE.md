# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Read `tools/progress/operating-guidance.md` for every activity in this repository.

## Documentation maintenance

Start repository work at [docs/README.md](docs/README.md), then load the task-specific guide, relevant [specification](docs/specs/README.md) and owning source. For features and relevant bug fixes, update affected durable specs and canonical guides in the same change, or report a concrete reason they remain accurate. Before handoff, check changed claims against source, verify changed links, and name the documentation updated. Add new durable documents to the owning index with explicit status. Keep development plans, task journals and per-run evidence in local Git-ignored state; commit durable requirements under `docs/specs/`. Historical plans and proposals do not establish implemented behavior.

## Project Overview

Assistant Framework v0.2.0 (see `version.txt`) — a personal AI assistant framework providing composable skills, agents, rules, and tools for Claude Code and Codex. This is a **framework repo**, not an application — it ships as a plugin marketplace (`.claude-plugin/marketplace.json`, `.agents/plugins/marketplace.json`) serving the generated plugin in `plugins/assistant-framework/`.

Root `skills/assistant-*` directories are the editable source of truth. Keep behavior-driving skill prose, contracts, evals, tests, and documentation aligned.

## Build and Test Commands

### Validation

```bash
tools/skills/validate-skills.sh          # Skill frontmatter and structure
./tests/test-p0-p4-contracts.sh          # Contract suites
tools/skills/sync-operating-guidance.sh --apply   # After editing tools/progress/*.md: resync skill copies
python3 tools/skills/check-skill-containment.py   # Skill folders stay self-contained
tools/skills/sync-role-prompts.sh --apply         # After editing agents/: resync skills' references/roles/
python3 tools/skills/sync-plugin.py --apply       # After any skills/ change: regenerate the plugin
```

### Packaging

`skills/` stays the source of truth; never edit `plugins/assistant-framework/` by hand. Bump `version.txt` when shipped skills change, or plugin users get no update. `python3 tools/skills/build-chat-zips.py` builds Claude chat upload ZIPs into `dist/chat-skills/`. See [docs/specs/plugin-marketplace-packaging.md](docs/specs/plugin-marketplace-packaging.md).

## Architecture

assistant-research is a Process skill; research contracts and evidence methods remain authoritative.

### Two-layer design

1. **Skills** (`skills/`) — Markdown-based prompt modules. Each skill has a `SKILL.md` entry point with required YAML frontmatter (`name` and `description`) and optional repository `requires` for validated hard dependencies. Sub-files load on demand (progressive loading). Skills are agent-agnostic.

2. **Tools** (`tools/`) — Script utilities used for repository validation, plugin generation and evals. Skills do not need them at run time, apart from the optional pattern library in a checkout.
   - `progress/` — Canonical shared operating guidance and wire boundary; each skill carries a synced copy.
   - `skills/` — Skill validator and contract-guide/workflow-reference sync scripts.
   - `evals/` — Skill and framework instruction eval runners.
   - `patterns/` — Pattern library script.

### Skill anatomy

```
skills/<skill-name>/
  SKILL.md              # Entry point — always loaded when triggered
  contracts/            # Input/output YAML contracts
  *.md                  # Sub-tools loaded on demand
  playbooks/            # (workflow) Project-type architecture guides
  references/           # (workflow) Templates, prompts, checklists
```

Each supported agent discovers installed skills natively from required names and descriptions, then follows body instructions after activation. Use `requires` only for validated hard dependencies. Keep representative activation examples only in contracts and positive/negative evals; top-level `effort` and `triggers` metadata are retired and rejected by validation.

### Agent configurations

`agents/` contains agent-specific definitions (architect, builder-tester, code-mapper, code-reviewer, explorer, intelligent-writer, mechanical-writer, qa-evaluator, lens-researcher, research-peer-reviewer, plus the compatibility `reviewer` and deprecated `code-writer` roles) for multi-agent orchestration. Claude agents are markdown files (`agents/claude/*.md`), Codex agents are TOML files (`agents/codex/*.toml`). These define subagent roles, tool access, and prompts. The plugin does not ship them; skills carry the role prompts in `references/roles/` (synced by `tools/skills/sync-role-prompts.sh`) so a fresh general-purpose agent can take a role.

Do not weaken permission prompts or destructive-operation safeguards.

## Mandatory: Skill Contract Design Guide

When creating or modifying skills, you **must** follow the contract design guide at `docs/skill-contract-design-guide.md`. Read it before starting any skill work. Key rules:

- **Start with precise instructions.** Retain contracts only for actual tool/agent/persisted consumers or an explicit requested schema. Utility, Analysis and Process are not file quotas.
- **Required fields must have `on_missing` actions** — never leave the agent guessing what to do when data is absent.
- **Enum types must list all values** — open-ended enums defeat the purpose of typing.
- **Validation rules are plain English** — no regex, no code, no framework syntax.
- **Phase gates are binary assertions** — "X is true" or "X is false", nothing subjective.
- **Handoff schemas must match** — producer's `return_fields` must satisfy consumer's `context_fields`.
- **Corrective actions must be actionable** — "fix it" is not a corrective action; "re-dispatch CodeMapper requesting the missing field" is.
- **Consumed contracts need compatibility decisions** — removing required fields requires versioning and aligned consumers; preserve historical labels.
- **Expert-judgment guidance needs an evidenced method** — derive cue-to-method decisions from representative expert cases or an authoritative method; see the creator's `references/expert-method-design.md`.

Use the field schema, phase gate schema, and handoff schema formats defined in the guide. Refer to existing skills' `contracts/` directories for examples.

## Key conventions

- **Skills are markdown, not code.** They are prompt engineering artifacts. Edit them as structured prose, not programs.
- **Native skill discovery drives routing.** Adding a new skill requires only a well-described SKILL.md and any actual consumed contracts; no runtime script changes are needed.
- **sync-plugin.py auto-discovers skills** — any subdirectory of `skills/` containing a SKILL.md ships in the plugin.
- **Contracts** (`contracts/` dirs) define structured input/output schemas in YAML. Instruction-only skills are valid; see the canonical guide.
- **Contract checks test behavior, not wording.** Add a check under `tests/p0-p4/` only when it fails for a defect a user or maintainer would notice (structure, safety, contract consistency, eval grading); a check that only pins a sentence in a skill file is not added. See `docs/specs/contract-test-cleanup.md` R-TC-1.
- **C# code** targets modern .NET and follows the existing Clean Architecture style. Tests use descriptive names and Arrange-Act-Assert where applicable.
