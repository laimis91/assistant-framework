# Memory Graph — MCP Server Design

Self-contained C# MCP server providing a knowledge graph over the existing markdown memory system. Runs locally via stdio transport — no external dependencies, no cloud services.

## Problem

The agent starts each session by reading memory files, but has no way to ask targeted questions like:
- "What do I know about the desktop app project?"
- "What technologies does the API use?"
- "What projects depend on this API?"
- "What patterns should I follow in this codebase?"

With 5-10 projects and growing insights, reading everything is wasteful. The agent needs a queryable index.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Agent (Claude / Codex / Gemini)                    │
│                                                     │
│  MCP tool calls:                                    │
│    memory_context("DesktopApp")                     │
│    memory_search("EF Core migration")              │
│    memory_add_insight(...)                           │
│                                                     │
├─────────────── stdio (JSON-RPC) ────────────────────┤
│                                                     │
│  Memory Graph Server (C# self-contained binary)     │
│                                                     │
│  ┌───────────────┐  ┌────────────────────────────┐  │
│  │ Graph Engine   │  │ Markdown Sync              │  │
│  │ (in-memory)    │←→│ (reads/indexes .md files)  │  │
│  └───────┬───────┘  └────────────────────────────┘  │
│          │                                          │
│  ┌───────▼───────┐                                  │
│  │ graph.jsonl    │  ← persistent graph storage     │
│  └───────────────┘                                  │
│                                                     │
│  Storage: ~/.{agent}/memory/graph.jsonl              │
│  Indexes: ~/.{agent}/memory/ (reads .md files)       │
└─────────────────────────────────────────────────────┘
```

## Data Model

### Entity Types

```csharp
public enum EntityType
{
    Project,      // a codebase / repository
    Technology,   // framework, library, tool (EF Core, WPF, ASP.NET Core)
    Pattern,      // architectural decision (Clean Architecture, CQRS, guard clauses)
    Preference,   // user coding preference (var usage, naming style)
    Insight,      // learned fact from a past session
    Convention    // project-specific convention (test naming, folder structure)
}
```

### Entity

```csharp
public record Entity
{
    public string Name { get; init; }          // unique identifier
    public EntityType Type { get; init; }
    public List<string> Observations { get; init; } // atomic facts
    public string? SourceFile { get; init; }   // markdown file this came from (nullable)
    public DateTime CreatedAt { get; init; }
    public DateTime UpdatedAt { get; init; }
}
```

### Relation Types

```csharp
public enum RelationType
{
    // Project relationships
    DependsOn,      // Project A depends on Project B (API calls, shared libs)
    ManagedBy,      // Project A is managed/configured by Project B
    SharedWith,     // Projects share a component (shared DB, common lib)

    // Project ↔ Technology
    Uses,           // Project uses Technology

    // Project ↔ Pattern
    Follows,        // Project follows Pattern

    // Project ↔ Convention
    HasConvention,  // Project has Convention

    // Insight ↔ Project/Technology
    AppliesTo,      // Insight applies to Project or Technology

    // Preference scope
    ScopedTo,       // Preference scoped to Project (vs global)
}
```

### Relation

```csharp
public record Relation
{
    public string From { get; init; }          // entity name
    public string To { get; init; }            // entity name
    public RelationType Type { get; init; }
    public string? Detail { get; init; }       // optional context
    public DateTime CreatedAt { get; init; }
}
```

### Storage Format (graph.jsonl)

Each line is a JSON object with a `kind` discriminator:

```jsonl
{"kind":"entity","name":"DesktopApp","type":"Project","observations":["WPF app with MVVM","Sends HTTP requests to API","Uses .NET 8"],"sourceFile":null,"createdAt":"2026-03-18T10:00:00Z","updatedAt":"2026-03-18T10:00:00Z"}
{"kind":"entity","name":"API","type":"Project","observations":["ASP.NET Core Minimal APIs","Clean Architecture","EF Core for data access"],"sourceFile":null,"createdAt":"2026-03-18T10:00:00Z","updatedAt":"2026-03-18T10:00:00Z"}
{"kind":"entity","name":"WebAdmin","type":"Project","observations":["Blazor WebAssembly","Controls features and access for DesktopApp"],"sourceFile":null,"createdAt":"2026-03-18T10:00:00Z","updatedAt":"2026-03-18T10:00:00Z"}
{"kind":"entity","name":"EF Core","type":"Technology","observations":["ORM for .NET","Code-first migrations"],"sourceFile":null,"createdAt":"2026-03-18T10:00:00Z","updatedAt":"2026-03-18T10:00:00Z"}
{"kind":"relation","from":"DesktopApp","to":"API","type":"DependsOn","detail":"HTTP calls for all data operations","createdAt":"2026-03-18T10:00:00Z"}
{"kind":"relation","from":"WebAdmin","to":"DesktopApp","type":"ManagedBy","detail":"Feature flags and user access control","createdAt":"2026-03-18T10:00:00Z"}
{"kind":"relation","from":"API","to":"EF Core","type":"Uses","detail":null,"createdAt":"2026-03-18T10:00:00Z"}
```

## MCP Tools

### 1. `memory_context` — "What do I need to know?"

The primary tool. Given a project name (or auto-detected from cwd), returns everything relevant: the project entity, related projects, technologies, patterns, conventions, recent insights, and applicable preferences.

```
Input:  { "project": "DesktopApp" }
        or { "path": "/home/user/Projects/DesktopApp" }

Output: {
    "project": { "name": "DesktopApp", "type": "Project", "observations": [...] },
    "dependencies": [
        { "project": "API", "relation": "DependsOn", "detail": "HTTP calls..." }
    ],
    "technologies": ["WPF", ".NET 8", "MVVM"],
    "patterns": ["MVVM", "guard clauses"],
    "conventions": ["test naming: {Method}_{Case}_{Expected}"],
    "preferences": ["prefer var when type is obvious", "use braces for single-line blocks"],
    "recentInsights": [
        { "name": "...", "observations": [...], "date": "2026-03-15" }
    ]
}
```

This is what the session-start hook would call to inject relevant context.

### 2. `memory_search` — Find entities by text

Full-text search across entity names, types, and observations.

```
Input:  { "query": "EF Core migration", "types": ["Insight", "Pattern"] }
Output: { "results": [ { entity, relations } ] }
```

### 3. `memory_add_entity` — Create or update an entity

```
Input:  { "name": "DesktopApp", "type": "Project", "observations": ["WPF with MVVM", "Uses .NET 8"] }
Output: { "created": true } or { "updated": true, "newObservations": 1 }
```

If entity exists, new observations are merged (deduped). Existing observations are preserved.

### 4. `memory_add_relation` — Connect two entities

```
Input:  { "from": "DesktopApp", "to": "API", "type": "DependsOn", "detail": "HTTP calls" }
Output: { "created": true } or { "exists": true }
```

Deduplicates by (from, to, type).

### 5. `memory_add_insight` — Record a learned fact

Convenience tool that creates an Insight entity and links it to relevant projects/technologies.

```
Input:  {
    "insight": "EF Core SaveChanges in a loop causes N+1 writes — batch with AddRange",
    "appliesTo": ["API", "EF Core"],
    "source": "task-2026-03-18-fix-performance"
}
Output: { "entity": "insight-2026-03-18-ef-core-batch", "relations": 2 }
```

### 6. `memory_remove_entity` — Delete an entity and its relations

```
Input:  { "name": "OldProject" }
Output: { "removed": true, "relationsRemoved": 3 }
```

### 7. `memory_remove_relation` — Delete a specific relation

```
Input:  { "from": "DesktopApp", "to": "OldAPI", "type": "DependsOn" }
Output: { "removed": true }
```

### 8. `memory_graph` — Return the full graph (for debugging/overview)

```
Input:  {}
Output: { "entities": [...], "relations": [...], "stats": { "entities": 15, "relations": 22 } }
```

## Markdown Sync

The server indexes existing markdown files on startup and watches for changes:

```
~/.claude/memory/
  INDEX.md           → scan for project names, extract entity hints
  user/profile.md    → extract Preference entities
  feedback/*.md      → extract Convention/Preference entities
  insights/*.md      → extract Insight entities, link to projects
```

### Sync rules

1. **Startup**: read all `.md` files under the memory directory, extract entities and relations, merge into graph (markdown is source of truth for conflicts)
2. **Entity sourcing**: entities extracted from markdown get `sourceFile` set — so we know where they came from
3. **No markdown writes**: the server never modifies markdown files. It only reads them and maintains the graph index.
4. **Agent writes**: when the agent uses `memory_add_insight`, the server writes to `graph.jsonl` only. The `assistant-memory` skill still writes markdown files. The graph is a queryable index, not a replacement.
5. **Manual entities**: entities created via `memory_add_entity` (not from markdown) have `sourceFile: null` — these are graph-only facts.

### Extraction heuristics

From `insights/*.md`:
- Title line → Insight entity name
- Body text → observations
- If mentions a known Project name → `AppliesTo` relation
- If mentions a known Technology name → `AppliesTo` relation

From `user/profile.md`:
- Key-value style lines → Preference entities
- "prefers X" / "uses Y" → observations

From `feedback/*.md`:
- Rule statements → Convention or Preference entities
- "always/never" statements → observations

## Project Structure

```
tools/memory-graph/
  DESIGN.md                        ← this file
  src/
    MemoryGraph/
      MemoryGraph.csproj           ← self-contained, no external NuGet (except System.Text.Json)
      Program.cs                   ← MCP stdio server entry point
      Server/
        McpServer.cs               ← JSON-RPC message loop (stdin/stdout)
        McpTypes.cs                ← MCP protocol types (initialize, tools/list, tools/call)
      Graph/
        KnowledgeGraph.cs          ← in-memory graph + CRUD operations
        Entity.cs                  ← entity model
        Relation.cs                ← relation model
        GraphStore.cs              ← JSONL read/write
      Tools/
        MemoryContextTool.cs       ← memory_context implementation
        MemorySearchTool.cs        ← memory_search implementation
        MemoryAddEntityTool.cs     ← memory_add_entity implementation
        MemoryAddRelationTool.cs   ← memory_add_relation implementation
        MemoryAddInsightTool.cs    ← memory_add_insight implementation
        MemoryRemoveTool.cs        ← memory_remove_entity + memory_remove_relation
        MemoryGraphTool.cs         ← memory_graph (full dump)
      Sync/
        MarkdownScanner.cs         ← reads .md files, extracts entities/relations
        EntityExtractor.cs         ← heuristic extraction from markdown text
  tests/
    MemoryGraph.Tests/
      MemoryGraph.Tests.csproj
      KnowledgeGraphTests.cs
      GraphStoreTests.cs
      MarkdownScannerTests.cs
      EntityExtractorTests.cs
      ToolIntegrationTests.cs
```

## Build & Distribution

```bash
# Build self-contained single file
dotnet publish src/MemoryGraph/MemoryGraph.csproj \
  -c Release \
  -r <RID> \
  --self-contained true \
  -p:PublishSingleFile=true \
  -p:IncludeNativeLibrariesForSelfExtract=true \
  -o dist/<platform>/

# RIDs: osx-arm64, osx-x64, linux-x64, win-x64
```

The install.sh script would:
1. Check if pre-built binary exists for current platform
2. If not, build from source (requires .NET SDK)
3. Copy binary to `~/.{agent}/tools/memory-graph`
4. Register the MCP server in agent settings

## Agent Integration

### Claude Code (`~/.claude/settings.json`)

```json
{
  "mcpServers": {
    "memory-graph": {
      "command": "~/.claude/tools/memory-graph/memory-graph",
      "args": ["--memory-dir", "~/.claude/memory"]
    }
  }
}
```

### Codex (`~/.codex/config.toml` or equivalent)

```toml
[mcp.memory-graph]
command = "~/.codex/tools/memory-graph/memory-graph"
args = ["--memory-dir", "~/.codex/memory"]
```

### Session-start hook enhancement

The existing `session-start.sh` hook could call `memory_context` with the current project path to auto-inject relevant graph context at session start — replacing the current "read all memory files" approach with targeted context retrieval.

## CLI Arguments

```
memory-graph [OPTIONS]

Options:
  --memory-dir PATH    Memory directory (default: auto-detect from agent)
  --graph-file PATH    Graph file path (default: {memory-dir}/graph.jsonl)
  --no-sync            Skip markdown sync on startup
  --verbose            Log to stderr for debugging
```

## Design Decisions

1. **JSONL over SQLite**: JSONL is human-readable, git-diffable, and trivial to parse. At 5-10 projects with ~100 entities, performance is not a concern. SQLite would be premature.

2. **Read-only markdown**: The graph indexes markdown but never writes to it. This preserves the existing human-readable memory system and avoids conflicts with the `assistant-memory` skill.

3. **Graph as index, not source of truth**: Markdown files remain the source of truth. The graph is a queryable acceleration layer. If `graph.jsonl` is deleted, it can be rebuilt from markdown.

4. **Stdio transport over HTTP**: Stdio is simpler, requires no port management, and is the standard MCP transport for local tools. No security concerns about open ports.

5. **Self-contained binary**: No runtime dependencies. Works on the restricted PC without .NET SDK installed (if pre-built). The `RollForward=LatestMajor` approach from cognitive-complexity also applies here for source builds.

6. **No external NuGet packages**: Only `System.Text.Json` (built-in). Keeps the binary small and avoids dependency management issues on restricted machines.

## v2 Additions: SQLite + FTS5 + Reflexion

### Architecture (v2)

The v2 upgrade adds a SQLite database (`memory.db`) alongside the existing JSONL graph. SQLite provides:
- **FTS5 full-text search** across all memory content (entities, reflexions, decisions, strategy lessons)
- **Reflexion storage** for post-task self-assessments
- **Decision journal** for architectural decisions with rationale
- **Strategy lessons** per project type with confidence scoring and decay
- **Calibration tracking** for prediction accuracy

The JSONL graph remains the source of truth for entities and relations. SQLite is an acceleration layer that also stores new data types (reflexions, decisions, etc.).

### New MCP Tools (v2)

| # | Tool | Purpose |
|---|---|---|
| 9 | `memory_reflect` | Record post-task reflexion: what worked, what didn't, lessons learned |
| 10 | `memory_decide` | Record a decision with rationale, alternatives, constraints |
| 11 | `memory_pattern` | Record/reinforce a recurring pattern for a project type |
| 12 | `memory_consolidate` | Decay stale lessons, archive low-confidence ones |
| 13 | `memory_stats` | Dashboard: entity/relation counts, reflexions, calibration accuracy |

### Enhanced Search (v2)

`memory_search` now uses FTS5 for ranked results across all content. Falls back to in-memory graph search if FTS5 query fails. Supports FTS5 syntax (AND, OR, NOT, phrases in quotes).

### Strategy Lessons

Strategy lessons accumulate per project type and phase (discover, plan, build, review). They have:
- **Confidence score** (0.0 - 1.0): increases when reinforced, decays over time
- **Reinforcement count**: how many times the same lesson was observed
- **Auto-decay**: lessons not reinforced in 90+ days lose confidence
- **Archive threshold**: lessons below 0.1 confidence are deleted during consolidation

### Storage

```
~/.{agent}/memory/
  graph.jsonl          ← existing entity/relation graph
  memory.db            ← NEW: SQLite + FTS5 (reflexions, decisions, strategies, FTS index)
```

### Dependencies

v2 adds one NuGet dependency: `Microsoft.Data.Sqlite` (8.0.x). This is a lightweight SQLite wrapper included with .NET — no native dependency management needed.

## Future Extensions

- **File watcher**: Watch markdown directory for changes and re-sync automatically
- **Semantic similarity**: Embed observations and search by meaning (requires external model)
- **Project auto-detection**: Scan `~/Developer/Projects/` and auto-register projects
- **Cross-agent sync**: If Claude and Codex share the same memory directory, the graph serves both
- **Auto-capture hooks**: Automatically record reflexions/decisions from conversation events
