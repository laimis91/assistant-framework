# Assistant Framework — Memory Protocol

<!-- This is a template. Paths like ~/.claude/ are substituted during install.sh for non-Claude agents. -->
<!-- Appended by Assistant Framework install. Do not remove this marker. -->
<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->

## Memory System (Assistant Framework)

All cross-session memory is stored in the **knowledge graph** (`~/.claude/memory/graph.jsonl`), accessed via memory-graph MCP tools.

### Entity Types

| Type | Purpose | Priority |
|---|---|---|
| `Rule` | Behavioral mandates, corrections | Highest — always loaded at session start |
| `Preference` | User coding preferences, working style | High — loaded via memory_context |
| `Insight` | Learned facts from past sessions | Normal — loaded via memory_context |
| `Project` | Codebase / repository | Normal |
| `Technology` | Framework, library, tool | Normal |
| `Pattern` | Architectural decision | Normal |
| `Convention` | Project-specific convention | Normal |

**Project memory** — lives in `.claude/` at the project root (create on first use):

| File | Purpose |
|---|---|
| `.claude/memory.md` | Project-specific decisions, architecture, conventions (git-tracked) |
| `.claude/session.md` | Current session state: task, progress, blockers (ephemeral) |
| `.claude/working-buffer.md` | Scratch space for mid-session summaries (ephemeral) |
| `.claude/task.md` | Task journal for active work — single source of truth during build (ephemeral) |

### Rules

#### Session Start
1. Call `memory_context` with the current project name or path — returns dependencies, technologies, patterns, conventions, preferences, rules, and recent insights.
2. If `.claude/task.md` exists → read it (active task state).
3. If `.claude/session.md` exists → read it; resume from where it left off.
4. If `.claude/working-buffer.md` exists → read it, then **clear** its contents.

Rules are also injected by the session-start hook directly from `graph.jsonl`, available before the first MCP call.

#### When Corrected
If the user corrects a mistake or clarifies a preference:
1. Use `memory_add_entity` with type `Rule` to record the correction in the knowledge graph.
2. Acknowledge the correction, then continue.

#### After Task Completion
If the task produced reusable insights:
1. Use `memory_add_insight` to record the insight in the knowledge graph.
2. If `assistant-reflexion` is available, invoke it for structured reflection.

#### Memory Hygiene
- Use `memory_consolidate` to decay stale insights and archive low-confidence ones.
- Use `memory_stats` to check memory system health.
- Never store secrets, API keys, or PII in memory.

<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END -->
