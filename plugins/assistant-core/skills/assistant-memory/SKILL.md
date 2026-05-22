---
name: assistant-memory
description: "This skill manages durable, policy-safe memory through the configured local memory backend when available. Use when the user says 'remember this', 'save insight', 'update memory', 'what do you know about me', 'forget', 'preferences'. Also activates when the user provides a correction or states a behavioral preference that should persist."
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
| [`contracts/output.yaml`](contracts/output.yaml) | action_taken, storage_backend, entity_name, results[], durability_decision, confirmation |

- `content` is required for save/update; `query` is required for recall/search
- `entity_type` is required for save — determines the memory entity type (Rule, Preference, Insight, etc.)
- All outputs include a human-readable `confirmation` string

The configured local memory backend is the cross-session source of truth when it is available and allowed by policy. If no approved backend exists, do not pretend memory was saved; return a blocked or no-op result and provide the text the user can save manually.

## Goal

Save, retrieve, update, or remove durable memories through the configured local memory backend while keeping session scratch state, task journals, metrics, PR numbers, issue status, and temporary progress separate from cross-session knowledge.

## Success Criteria

- The requested memory action is resolved before using memory tools.
- Saved memories have the right entity type and avoid secrets, credentials, sensitive personal data, customer data, private endpoints, and stale task artifacts.
- Recall/search results cite the backend/query or project context used.
- No markdown task/session files, metrics files, PR numbers, issue status, or short-lived TODO state are treated as durable memory.

## Constraints

- Use the configured local memory backend as the source of truth for cross-session memory when available and policy-approved.
- Store only durable rules, preferences, conventions, project identity, stable decisions, and non-obvious insights that will still matter later.
- Do not store secrets, credentials, tokens, sensitive personal/customer data, private endpoints, transient task progress, PR/issue numbers, commit SHAs, or completion logs.
- Ask only when the memory action, entity identity, save content, or privacy/scope is materially ambiguous.

## Memory Storage

All cross-session memory is accessed through the **configured local memory backend**. In this framework that may be memory-graph MCP backed by a local store, a project-approved local file, or another configured local memory tool. Project-local session/task markdown files are for session state only, not cross-session memory storage. If the backend is missing or disallowed, report `action_taken: blocked` or `no_op`.

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

1. Query configured local memory for the current project name or path when available and policy-approved — returns dependencies, technologies, patterns, conventions, preferences, rules, and durable insights.
2. If a configured task journal (`{agent_state_dir}/task.md`) or carried-forward task packet exists → read it as active task state, not memory.
3. If a configured session file exists → read it as session state; do not promote its contents to memory without filtering.
4. If a configured working buffer exists → read it, then **clear** its contents if policy allows.

Hooks do not inject rule bodies directly. Use the configured memory query/search tools to retrieve rules, preferences, and prior lessons when available.

## Recording Memory

Use configured local memory tools to record new memory when available:

| What | Tool | Entity Type |
|---|---|---|
| User correction/rule | `memory_add_entity` | `Rule` |
| Coding preference | `memory_add_entity` | `Preference` |
| Task insight/gotcha | `memory_add_insight` | `Insight` (auto-created) |
| Project registration | `memory_add_entity` | `Project` |
| Connect entities | `memory_add_relation` | — |

Do not treat markdown files as cross-session memory. Use project-local session/task files only for session state.

## Save / Skip Decision

Save only if the fact is durable and useful across sessions:
- User preference or correction that should affect future behavior.
- Stable project convention, architecture pattern, or local workflow rule.
- Non-obvious gotcha likely to prevent future mistakes.

Skip or refuse:
- Secrets, credentials, tokens, private endpoints, customer/user data.
- Task progress, PR/issue numbers, commit SHAs, "fixed X", "phase done", temporary TODOs.
- Facts easily rediscovered from the repo or likely stale within a week.
- Broad instructions that should be a skill/procedure instead of memory.

## Querying Memory

- `memory_context("ProjectName")` — get everything relevant for a project (session start)
- `memory_search("EF Core migration")` — find entities by text across the graph
- `memory_graph()` — full dump for debugging or overview

## Output

Return:
- **Action taken** - save, recall, update, forget, search, no-op, or blocked.
- **Result** - entity name, memory type, matched memories, or reason nothing was saved.
- **Evidence** - backend/tool used and relevant project/query context, or explicit note that no approved backend was available.
- **Confirmation** - concise user-facing confirmation of what changed, what was found, or why memory was skipped.
- **Gaps** - missing content, ambiguous entity identity, privacy concern, unavailable backend, or blockers preventing the memory operation.

## Rules

- Only capture genuine durable insights: gotchas, non-obvious patterns, decision rationale, and stable user/project preferences.
- Do NOT capture: obvious facts, code patterns visible in repos, things already in docs, or anything likely stale within a week.
- **Never store secrets, API keys, credentials, tokens, private endpoints, customer data, or sensitive personal data in memory**.
- Rules are highest priority — treat them as behavioral mandates, but write them as declarative facts rather than imperative commands when possible.

## Memory Hygiene

- Use configured consolidation/statistics tools when available and policy-approved to decay stale insights and archive low-confidence ones.
- Never store secrets, API keys, credentials, tokens, private endpoints, customer data, or sensitive personal data in memory.
- Replace stale memories instead of adding duplicates when a durable fact changes.

## Stop Rules

- Stop and ask before saving when the content, entity type, privacy/scope, or intended durability is unclear.
- Stop and refuse to store secrets, credentials, sensitive personal/customer data, or policy-disallowed information.
- If configured memory tools are unavailable or disallowed, report the memory operation as blocked or no-op instead of pretending it was saved.
