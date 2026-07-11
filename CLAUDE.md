# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Assistant Framework v0.3.0 — a personal AI assistant framework providing composable skills, agents, rules, and tools for Claude Code, Codex, and Gemini CLI. This is a **framework repo**, not an application — it installs into agent home directories (`~/.claude/`, `~/.codex/`, `~/.gemini/`).

## Build and Test Commands

### Memory Graph

```bash
# Build
dotnet build tools/memory-graph/src/MemoryGraph/MemoryGraph.csproj --tl:on -v:minimal

# Run tests
dotnet test tools/memory-graph/tests/MemoryGraph.Tests/MemoryGraph.Tests.csproj --tl:on -v:minimal

# Run a single test
dotnet test tools/memory-graph/tests/MemoryGraph.Tests/ --filter "FullyQualifiedName~TestMethodName"
```

Target framework: .NET 8 (`net8.0`), with `RollForward=LatestMajor`. Single dependency: `Microsoft.Data.Sqlite`.

### Cognitive Complexity Tool

```bash
dotnet build tools/cognitive-complexity/CognitiveComplexity.csproj --tl:on -v:minimal
```

### Installation

```bash
./install.sh --agent claude              # Install all skills + memory seed
./install.sh --agent claude --skill assistant-workflow  # Single skill
./install.sh --agent claude --dry-run    # Preview
```

## Architecture

### Two-layer design

1. **Skills** (`skills/`) — Markdown-based prompt modules. Each skill has a `SKILL.md` entry point with YAML frontmatter (name, description, triggers). Sub-files load on demand (progressive loading). Skills are agent-agnostic.

2. **Tools** (`tools/`) — Compiled utilities exposed as MCP servers or CLI tools.
   - `memory-graph/` — C# MCP server (stdio, JSON-RPC) with 14 tools. In-memory knowledge graph + SQLite/FTS5 for reflexions/decisions. Source in `src/MemoryGraph/` with subdirs: `Graph/`, `Storage/`, `Tools/`, `Server/`.
   - `cognitive-complexity/` — Roslyn-based method complexity scorer used by the review stage.

### Skill anatomy

```
skills/<skill-name>/
  SKILL.md              # Entry point — always loaded when triggered
  contracts/            # Input/output YAML contracts
  *.md                  # Sub-tools loaded on demand
  playbooks/            # (workflow) Project-type architecture guides
  references/           # (workflow) Templates, prompts, checklists
  scripts/              # (workflow) Automation scripts (decompose, agents)
  agents/               # (workflow) Agent preset configs per platform
```

Each supported agent discovers installed skills natively from skill metadata and instructions. `triggers:` metadata remains useful for repository evals and documentation, but no routing script is installed.

### Agent configurations

`agents/` contains agent-specific definitions (reviewer, builder-tester, code-writer, code-mapper, explorer, architect) for multi-agent orchestration. Claude agents are markdown files (`agents/claude/*.md`), Codex agents are TOML files (`agents/codex/*.toml`). These define subagent roles, tool access, and prompts.

### Codex execution policy rules

`codex-rules/` contains Starlark `.rules` files installed to `~/.codex/rules/`. These provide **deterministic** enforcement (system-level, not prompt-level) — they always execute regardless of LLM reasoning. Current rules:
- `workflow.rules` — Git safety (block force push, confirm commits/pushes), destructive operation guards, build/test allow-listing

## Mandatory: Skill Contract Design Guide

When creating or modifying skills, you **must** follow the contract design guide at `docs/skill-contract-design-guide.md`. Read it before starting any skill work. Key rules:

- **Every skill must have contracts.** At minimum: `contracts/input.yaml` and `contracts/output.yaml`. Process skills (workflow, review, tdd, security) also need `phase-gates.yaml` and `handoffs.yaml`. Analysis skills (thinking, research, ideate) also need `phase-gates.yaml`.
- **Required fields must have `on_missing` actions** — never leave the agent guessing what to do when data is absent.
- **Enum types must list all values** — open-ended enums defeat the purpose of typing.
- **Validation rules are plain English** — no regex, no code, no framework syntax.
- **Phase gates are binary assertions** — "X is true" or "X is false", nothing subjective.
- **Handoff schemas must match** — producer's `return_fields` must satisfy consumer's `context_fields`.
- **Corrective actions must be actionable** — "fix it" is not a corrective action; "re-dispatch CodeMapper requesting the missing field" is.
- **Contracts only grow** — adding fields is safe, removing required fields is a breaking change.

Use the field schema, phase gate schema, and handoff schema formats defined in the guide. Refer to existing skills' `contracts/` directories for examples.

## Key conventions

- **Skills are markdown, not code.** They are prompt engineering artifacts. Edit them as structured prose, not programs.
- **Native skill discovery drives routing.** Adding a new skill requires only a well-described SKILL.md and its contracts; no runtime script changes are needed.
- **install.sh auto-discovers skills** — any subdirectory of `skills/` containing a SKILL.md is installable.
- **Contracts** (`contracts/` dirs) define structured input/output schemas in YAML. All assistant skills have contracts; see the Mandatory section above.
- **Unity skills** (`unity-*`) are a separate family targeting Unity game development via UnityMCP.
