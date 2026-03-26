# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Assistant Framework v0.2.0 — a personal AI assistant framework providing 12+ composable skills, lifecycle hooks, and tools for Claude Code, Codex, and Gemini CLI. This is a **framework repo**, not an application — it installs into agent home directories (`~/.claude/`, `~/.codex/`, `~/.gemini/`).

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

### Hook Tests

```bash
./tests/test-hooks.sh                    # All tests
./tests/test-hooks.sh --verbose          # With output
./tests/test-hooks.sh --filter stop      # Filter by name
```

### Installation

```bash
./install.sh --agent claude              # Install all skills + hooks + memory seed
./install.sh --agent claude --skill assistant-workflow  # Single skill
./install.sh --agent claude --no-hooks   # Skills only
./install.sh --agent claude --dry-run    # Preview
./install.sh --agent claude --test-hooks # Validate hooks
```

## Architecture

### Three-layer design

1. **Skills** (`skills/`) — Markdown-based prompt modules. Each skill has a `SKILL.md` entry point with YAML frontmatter (name, description, triggers). Sub-files load on demand (progressive loading). Skills are agent-agnostic.

2. **Hooks** (`hooks/`) — Shell scripts that fire on agent lifecycle events (SessionStart, UserPromptSubmit, Stop, PreCompact, PostCompact, etc.). Agent-specific settings files (`claude-settings.json`, `gemini-settings.json`, `codex-settings.json`) map events to scripts. Hooks enforce behaviors like skill routing, review gating, and memory injection.

3. **Tools** (`tools/`) — Compiled utilities exposed as MCP servers or CLI tools.
   - `memory-graph/` — C# MCP server (stdio, JSON-RPC) with 14 tools. In-memory knowledge graph + SQLite/FTS5 for reflexions/decisions. Source in `src/MemoryGraph/` with subdirs: `Graph/`, `Storage/`, `Tools/`, `Server/`, `Sync/`.
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

Skills are routed by the `skill-router.sh` hook, which pattern-matches user prompts against `triggers:` frontmatter in each SKILL.md. Priority ordering resolves conflicts (higher priority = matched first).

### Hook lifecycle

| Hook Script | Event | Purpose |
|---|---|---|
| `session-start.sh` | SessionStart | Inject task journal + memory feedback |
| `skill-router.sh` | UserPromptSubmit | Route prompts to matching skills |
| `learning-signals.sh` | UserPromptSubmit | Detect corrections/approvals for trend analysis |
| `stop-review.sh` | Stop | Enforce self-review before task completion |
| `pre-compress.sh` | PreCompact | Save state before context compression |
| `post-compact.sh` | PostCompact | Re-inject context after compaction |
| `task-completed.sh` | TaskCompleted | Post-task processing |
| `subagent-monitor.sh` | SubagentStart | Monitor subagent spawning |
| `session-end.sh` | SessionEnd | Reminder to capture insights |

### Agent configurations

`agents/` contains agent-specific definitions (reviewer, builder-tester, code-writer, code-mapper, explorer, architect) for multi-agent orchestration. Claude agents are markdown files (`agents/claude/*.md`), Codex agents are TOML files (`agents/codex/*.toml`). These define subagent roles, tool access, and prompts.

### Memory seed

`memory-seed/` contains initial memory data installed on first run (never overwrites existing data). Includes user profile template, feedback rules, and sample insights.

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
- **Triggers drive routing.** Adding a new skill requires only a SKILL.md with `triggers:` frontmatter — no script changes needed.
- **Hooks are bash scripts** that output plain text (Claude) or JSON (Gemini). They must exit 0 under normal conditions.
- **install.sh auto-discovers skills** — any subdirectory of `skills/` containing a SKILL.md is installable.
- **Contracts** (`contracts/` dirs) define structured input/output schemas in YAML. All assistant skills have contracts; see the Mandatory section above.
- **Unity skills** (`unity-*`) are a separate family targeting Unity game development via UnityMCP.
