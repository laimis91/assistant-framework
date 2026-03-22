# Design: Memory v2 — Intelligent Memory System

**Status:** Draft proposal
**Priority:** P1

## Problem

The current memory system relies on markdown files + a simple .NET graph index. It requires the agent to explicitly decide to save memories, has no semantic search, no decay, and no automatic capture. Research shows systems like Mem0 (26% accuracy uplift) and Engram (80% LOCOMO benchmark) significantly outperform file-based approaches.

## Design Principles

1. **Memory should happen automatically** — the agent shouldn't need to "decide" to remember
2. **Retrieval should be semantic** — "what do I know about auth?" not "grep for auth"
3. **Stale memories should fade** — relevance decays with time unless reinforced
4. **Memory should be queryable** — not just a dump of files
5. **Markdown stays source of truth** — the database is an index, not a replacement

## Architecture

```
┌─────────────────────────────────────────────┐
│                  Agent                       │
│                                              │
│  memory_save  memory_recall  memory_reflect  │
└──────────┬──────────┬──────────┬────────────┘
           │          │          │
           ▼          ▼          ▼
┌─────────────────────────────────────────────┐
│           Memory MCP Server v2               │
│                                              │
│  ┌─────────┐  ┌──────────┐  ┌────────────┐  │
│  │ SQLite  │  │ FTS5     │  │ Knowledge  │  │
│  │ Store   │  │ Search   │  │ Graph      │  │
│  └─────────┘  └──────────┘  └────────────┘  │
│                                              │
│  ┌─────────────┐  ┌───────────────────────┐  │
│  │ Auto-Capture│  │ Decay & Consolidation │  │
│  │ Pipeline    │  │ Engine                │  │
│  └─────────────┘  └───────────────────────┘  │
│                                              │
│  ┌─────────────────────────────────────────┐ │
│  │ Markdown Sync (bidirectional)           │ │
│  └─────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

## Memory Types (expanded)

| Type | Current | Proposed |
|---|---|---|
| **Facts** | user/, feedback/ | Same + auto-extracted from conversations |
| **Insights** | insights/ | Same + auto-captured at task completion |
| **Decisions** | Not tracked | NEW: decision journal with rationale, context, outcome |
| **Patterns** | Not tracked | NEW: recurring code/arch patterns observed across projects |
| **Corrections** | feedback/ | Same + auto-linked to the context where correction was needed |
| **Performance** | Not tracked | NEW: task duration, approach used, success/failure, reflexion notes |

## New MCP Tools

### Core (upgrade existing)

| Tool | Purpose |
|---|---|
| `memory_save` | Save a memory with type, content, tags, project scope. Auto-indexes in FTS5 + graph. Writes markdown file. |
| `memory_recall` | Semantic search: "What do I know about auth in ProjectX?" Returns ranked results with relevance scores. |
| `memory_context` | (existing, enhanced) Now includes relevance-scored results, recent decisions, active patterns. |
| `memory_forget` | Mark a memory as superseded or irrelevant. Doesn't delete — marks for decay. |

### New

| Tool | Purpose |
|---|---|
| `memory_reflect` | Post-task: "Here's what I did, what worked, what didn't." Stores reflexion entry linked to task. |
| `memory_decide` | Record a decision with rationale, alternatives considered, constraints. Queryable later: "Why did we choose X?" |
| `memory_pattern` | Record a recurring pattern observed: "In this project, services always implement IDisposable." |
| `memory_consolidate` | Trigger manual consolidation: merge related memories, prune duplicates, update staleness. |
| `memory_stats` | Dashboard: total memories, by type, staleness distribution, most/least accessed. |

## Auto-Capture Pipeline

### What gets auto-captured (via hooks)

| Event | What's Captured | How |
|---|---|---|
| Task completion | Approach, outcome, duration, tools used | `session-end` hook calls `memory_reflect` |
| User correction | The correction + context | `post-correction` hook calls `memory_save` with type=correction |
| Architecture decision | Decision, rationale, alternatives | When Plan phase completes, extract decisions |
| New pattern discovered | Pattern description, where seen | When Review phase finds recurring patterns |
| Error resolved | Error, root cause, fix | When a failed build/test is resolved |

### Auto-capture flow

```
Conversation events
    │
    ▼
Hook detects capture-worthy event
    │
    ▼
Extract structured data (type, content, tags, project)
    │
    ▼
memory_save (writes markdown + indexes)
    │
    ▼
Graph updated (entities + relations)
```

## Relevance Scoring & Decay

Each memory has a relevance score (0.0 - 1.0):

```
relevance = base_relevance * time_decay * access_boost * reinforcement

where:
  base_relevance = 1.0 (starts at max)
  time_decay = 0.95 ^ (days_since_created / 30)  // halves every ~14 months
  access_boost = 1.0 + (0.1 * times_accessed_in_last_30_days)
  reinforcement = 1.5 if confirmed/referenced by user, 1.0 otherwise
```

**Corrections/feedback never decay** — they are rules, always at relevance 1.0.

## Consolidation Engine

Runs periodically (or on `memory_consolidate`):

1. **Merge**: Memories about the same topic with >80% semantic overlap → merge into one
2. **Prune**: Memories with relevance < 0.2 → archive (move to `archived/` directory)
3. **Summarize**: If a topic has >10 memories → create a summary memory, archive originals
4. **Cross-link**: Find memories that reference the same entities → add graph relations

## Migration from v1

1. Existing markdown files are imported into SQLite on first run
2. Existing graph entities/relations are preserved
3. New FTS5 index is built from all existing content
4. All existing tools continue to work (backward compatible)
5. New tools are additive

## Tech Stack

- **SQLite + FTS5** for storage and full-text search (already proven by Engram at 80% LOCOMO)
- **Existing .NET MCP server** expanded (not rewritten)
- **Markdown remains source of truth** — SQLite is the index
- Keep it self-contained: no external services, no Docker, no Python

## Open Questions

1. **Embeddings for semantic search?** FTS5 is good but not semantic. Options:
   - a) FTS5 only (simpler, proven by Engram)
   - b) Add local embeddings via ONNX runtime in .NET (more complex, better recall)
   - c) Hybrid: FTS5 for exact, optional embedding model for semantic

2. **Cross-machine sync?** Engram uses compressed chunks. Options:
   - a) Git-based (markdown files already in repo)
   - b) SQLite WAL shipping
   - c) Skip for v2, add later

3. **How aggressive should auto-capture be?** Risk: too many low-value memories pollute recall.
   - Proposal: capture to a "staging" area first, promote to permanent after confirmation or reinforcement
