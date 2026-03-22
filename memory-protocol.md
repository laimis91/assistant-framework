# Assistant Framework — Memory Protocol

<!-- This is a template. Paths like ~/.claude/ are substituted during install.sh for non-Claude agents. -->
<!-- Appended by Assistant Framework install. Do not remove this marker. -->
<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->

## Global Memory System (Assistant Framework)

Two layers of memory:

**Global memory** — lives in `~/.claude/memory/` (survives reinstalls, shared across all projects):

| Location | Purpose |
|---|---|
| `~/.claude/memory/user/` | User preferences, role, working style |
| `~/.claude/memory/feedback/` | Corrections and guidance rules (highest priority — always loaded) |
| `~/.claude/memory/insights/` | Task learnings, gotchas, patterns |
| `~/.claude/memory/INDEX.md` | Memory index (≤ 50 lines) |

**Project memory** — lives in `.claude/` at the project root (create on first use):

| File | Purpose |
|---|---|
| `.claude/memory.md` | Project-specific decisions, architecture, conventions (git-tracked) |
| `.claude/session.md` | Current session state: task, progress, blockers (ephemeral) |
| `.claude/working-buffer.md` | Scratch space for mid-session summaries (ephemeral) |
| `.claude/task.md` | Task journal for active work — single source of truth during build (ephemeral) |

### Rules

#### Session Start

**With Memory Graph MCP server (preferred):**
1. Call `memory_context` with the current project name or path — returns dependencies, technologies, patterns, conventions, preferences, and recent insights in one call.
2. Load feedback rules from `~/.claude/memory/feedback/*.md` — these always apply (graph does not replace feedback files).
3. If `.claude/task.md` exists → read it (active task state).
4. If `.claude/session.md` exists → read it; resume from where it left off.
5. If `.claude/working-buffer.md` exists → read it, then **clear** its contents.

**Without Memory Graph (fallback):**
1. If `.claude/memory.md` exists → read it (project-specific context).
2. Read `~/.claude/memory/INDEX.md` → scan for relevant global entries.
3. Load `~/.claude/memory/user/*.md` if the task benefits from user context.
4. Load `~/.claude/memory/feedback/*.md` — these are rules, always relevant.
5. If `.claude/task.md` exists → read it (active task state).
6. If `.claude/session.md` exists → read it; resume from where it left off.
7. If `.claude/working-buffer.md` exists → read it, then **clear** its contents.

#### When Corrected
If the user corrects a mistake or clarifies a preference:
1. Capture the correction to `~/.claude/memory/feedback/` using the assistant-memory skill templates.
2. Update `~/.claude/memory/INDEX.md` with the new feedback entry.
3. Acknowledge the correction, then continue.

#### After Task Completion
If the task produced reusable insights (patterns discovered, gotchas found, architectural decisions):
1. Capture to `~/.claude/memory/insights/` with date prefix: `YYYY-MM-DD-topic.md`
2. Update `~/.claude/memory/INDEX.md` with the new entry.
3. If Memory Graph is available, also call `memory_add_insight` to index it in the graph.

#### Memory Hygiene
- Keep `INDEX.md` concise (≤ 50 lines) — it's loaded every session.
- Prune stale insights when they are superseded.
- Never store secrets, API keys, or PII in memory files.

<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END -->
