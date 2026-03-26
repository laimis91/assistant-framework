---
name: assistant-memory
description: "Memory management for cross-session learning. Captures user preferences, feedback, and task insights that persist across all projects and sessions. Triggers on: 'remember this', 'save insight', 'update memory', 'what do you know about me', 'forget', 'memory', 'preferences'."
triggers:
  - pattern: "remember this|save insight|update memory|what do you know about me|forget|memory|preferences"
    priority: 70
    min_words: 3
    reminder: "This request matches assistant-memory. Consider whether the Skill tool should be invoked with skill='assistant-memory' for memory management."
---

# Memory Management

## Contracts

| File | Purpose |
|---|---|
| [`contracts/input.yaml`](contracts/input.yaml) | action (save/recall/update/forget/search), content, memory_type, query |
| [`contracts/output.yaml`](contracts/output.yaml) | action_taken, file_path, results[], confirmation |

- `content` is required for save/update; `query` is required for recall/search
- `memory_type` is required for save — determines which subdirectory receives the file
- All outputs include a human-readable `confirmation` string

Global memory that persists across all projects and sessions. Data lives in `~/.claude/memory/` (outside any skill directory — survives reinstalls).

## Memory Structure

```
~/.claude/memory/
  INDEX.md              <-- Read at session start (index only, not all files)
  user/                 <-- User preferences, role, working style
  feedback/             <-- Corrections and guidance (highest priority)
  insights/             <-- Task learnings, gotchas, patterns
```

## Session Start Protocol

### With Memory Graph (preferred)

If the `memory-graph` MCP server is available, use it for targeted context retrieval:

1. Call `memory_context` with the current project name or path — returns dependencies, technologies, patterns, conventions, preferences, and recent insights in one call
2. Load `~/.claude/memory/feedback/*.md` — these are rules, always relevant (graph does not replace feedback files)
3. If `.claude/task.md` exists → read it (active task state)
4. If `.claude/session.md` exists → read it; resume from where it left off
5. If `.claude/working-buffer.md` exists → read it, then **clear** its contents

This replaces reading all global memory files — the graph returns only what's relevant. Project-local files (task.md, session.md, working-buffer.md) are still read directly. Use `memory_search` for targeted follow-up queries on specific topics.

### Without Memory Graph (fallback)

If the MCP server is not registered or not responding:

1. If `.claude/memory.md` exists → read it (project-specific context)
2. Read `~/.claude/memory/INDEX.md` → scan for relevant global entries
3. Load `~/.claude/memory/user/*.md` if the task would benefit from user context
4. Load `~/.claude/memory/feedback/*.md` — these are rules, always relevant
5. If `.claude/task.md` exists → read it (active task state)
6. If `.claude/session.md` exists → read it; resume from where it left off
7. If `.claude/working-buffer.md` exists → read it, then **clear** its contents

## What to Capture

### User preferences (`user/`)
When you learn something about how the user works, their role, tech preferences, or working style.

**Template** (see `templates/user-pref-template.md`):
```markdown
# [Topic]
- [preference or fact]
- [preference or fact]
```

### Feedback and corrections (`feedback/`)
When the user corrects your approach or states a rule. These are highest priority — always loaded.

**Template** (see `templates/feedback-template.md`):
```markdown
# [Rule title]
**Date:** YYYY-MM-DD
**Context:** [what happened]
**Feedback:** [user's exact words or paraphrase]
**Rule:** [the rule to follow going forward]
```

### Task insights (`insights/`)
At task completion, if something non-obvious was discovered. File naming: `YYYY-MM-DD-topic.md`.

**Template** (see `templates/insight-template.md`):
```markdown
# [Insight title]
**Date:** YYYY-MM-DD
**Task:** [what was being done]
**Insight:** [the non-obvious finding]
**Applies to:** [when this matters]
```

## Writing Memory

After capturing any entry:
1. Write the file to the appropriate directory
2. Update `~/.claude/memory/INDEX.md` with a link and one-line description
3. Keep INDEX.md under 50 lines — prune stale entries when needed

## Using the Knowledge Graph

When the `memory-graph` MCP server is available, use its tools alongside markdown writes:

### Querying
- `memory_context("ProjectName")` — get everything relevant for a project (session start)
- `memory_search("EF Core migration")` — find entities by text across the graph
- `memory_graph()` — full dump for debugging or overview

### Recording (complements markdown writes)
After writing a markdown file (insight, feedback, preference), also record it in the graph:

- `memory_add_entity` — register a project, technology, pattern, or convention
- `memory_add_relation` — connect entities (e.g., "DesktopApp DependsOn API")
- `memory_add_insight` — record a learned fact and link it to projects/technologies (creates entity + relations in one call)

### When to use which
| Action | Markdown | Graph |
|---|---|---|
| Capture insight | Write `insights/YYYY-MM-DD-topic.md` | Also call `memory_add_insight` |
| Record feedback | Write `feedback/rule-name.md` | Graph indexes it on next startup |
| Register project | Not needed | `memory_add_entity` with type Project |
| Link projects | Not possible | `memory_add_relation` (DependsOn, Uses, etc.) |
| Query context | Read files manually | `memory_context` (one call) |

The graph is a queryable index over markdown — both systems complement each other. Markdown remains the source of truth; the graph provides fast, targeted access.

## Rules

- Only capture genuine insights: gotchas, non-obvious patterns, decision rationale
- Do NOT capture: obvious facts, code patterns visible in repos, things already in docs
- **Never store secrets, API keys, credentials, or PII in memory files**
- Keep INDEX.md under 50 lines — prune stale entries
- Each memory file should be short (under 20 lines)
- Feedback files are rules — treat them as higher priority than defaults

## Memory Hygiene

- Review INDEX.md periodically — remove entries for deleted or outdated files
- Insights older than 6 months with no relevance — consider archiving or deleting
- If INDEX.md exceeds 50 lines, consolidate related entries
