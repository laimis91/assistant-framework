---
name: assistant-memory
description: "This skill manages cross-session memory through memory-graph MCP. Use when the user says 'remember this', 'save insight', 'update memory', 'what do you know about me', 'forget', 'preferences'. Also activates when the user provides a correction or states a behavioral preference that should persist."
triggers:
  - pattern: "remember this|save insight|update memory|what do you know about me|forget|memory|preferences"
    priority: 70
    min_words: 3
    reminder: "This request matches assistant-memory. Load and follow this SKILL.md and its contracts before managing memory."
---

# Memory Management

## Contracts

| File | Purpose |
|---|---|
| [`contracts/input.yaml`](contracts/input.yaml) | action (save/recall/update/forget/search), content, entity_type, query |
| [`contracts/output.yaml`](contracts/output.yaml) | action_taken, entity_name, results[], confirmation |

- `content` is required for save/update; `query` is required for recall/search
- `entity_type` is required for save — determines the memory entity type (Rule, Preference, Insight, etc.)
- All outputs include a human-readable `confirmation` string

The memory-graph MCP backed by the local memory store is the cross-session source of truth for memory across projects and sessions.

## Memory Storage

All cross-session memory is accessed through **memory-graph MCP tools**, backed by the local memory store under `~/.claude/memory`. Project-local session/task markdown files are for session state only, not cross-session memory storage.

Entity types:
| Type | Purpose | Example |
|---|---|---|
| `Rule` | Behavioral mandates, corrections (highest priority — retrieve via `memory_context`) | "NEVER skip workflow skills" |
| `Preference` | User coding preferences, working style | "Prefers var when type is obvious" |
| `Insight` | Learned facts from past sessions | "EF Core migration gotcha with nullable columns" |
| `Project` | Codebase / repository | "Assistant Framework" |
| `Technology` | Framework, library, tool | "EF Core", "ASP.NET Core" |
| `Pattern` | Architectural decision | "Clean Architecture", "CQRS" |
| `Convention` | Project-specific convention | "Test naming: Method_Case_Expected" |

## Session Start Protocol

1. Call `memory_context` with the current project name or path — returns dependencies, technologies, patterns, conventions, preferences, rules, and recent insights.
2. If `.claude/task.md` exists → read it (active task state).
3. If `.claude/session.md` exists → read it; resume from where it left off.
4. If `.claude/working-buffer.md` exists → read it, then **clear** its contents.

Hooks do not inject rule bodies directly. Use `memory_context` and `memory_search` to retrieve rules, preferences, and prior lessons.

## Recording Memory

Use MCP tools to record new memory:

| What | Tool | Entity Type |
|---|---|---|
| User correction/rule | `memory_add_entity` | `Rule` |
| Coding preference | `memory_add_entity` | `Preference` |
| Task insight/gotcha | `memory_add_insight` | `Insight` (auto-created) |
| Project registration | `memory_add_entity` | `Project` |
| Connect entities | `memory_add_relation` | — |

Do not treat markdown files as cross-session memory. Use project-local session/task files only for session state.

## Querying Memory

- `memory_context("ProjectName")` — get everything relevant for a project (session start)
- `memory_search("EF Core migration")` — find entities by text across the graph
- `memory_graph()` — full dump for debugging or overview

## Rules

- Only capture genuine insights: gotchas, non-obvious patterns, decision rationale
- Do NOT capture: obvious facts, code patterns visible in repos, things already in docs
- **Never store secrets, API keys, credentials, or PII in memory**
- Rules are highest priority — treat them as behavioral mandates

## Memory Hygiene

- Use `memory_consolidate` periodically to decay stale insights and archive low-confidence ones.
- Use `memory_stats` to check memory system health.
- Never store secrets, API keys, credentials, or PII in memory.
