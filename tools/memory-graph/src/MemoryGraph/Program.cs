using MemoryGraph.Graph;
using MemoryGraph.Server;
using MemoryGraph.Storage;
using MemoryGraph.Sync;
using MemoryGraph.Tools;

// ── Parse CLI arguments ────────────────────────────────────────

string? memoryDir = null;
string? graphFile = null;
var noSync = false;
var verbose = false;

for (var i = 0; i < args.Length; i++)
{
    switch (args[i])
    {
        case "--memory-dir" when i + 1 < args.Length:
            memoryDir = args[++i];
            break;
        case "--graph-file" when i + 1 < args.Length:
            graphFile = args[++i];
            break;
        case "--no-sync":
            noSync = true;
            break;
        case "--verbose":
            verbose = true;
            break;
        case "-h" or "--help":
            PrintUsage();
            return;
    }
}

// ── Resolve paths ──────────────────────────────────────────────

// Default memory directory: try common agent locations
if (memoryDir is null)
{
    var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
    var candidates = new[]
    {
        Path.Combine(home, ".claude", "memory"),
        Path.Combine(home, ".codex", "memory"),
        Path.Combine(home, ".gemini", "memory")
    };

    memoryDir = candidates.FirstOrDefault(Directory.Exists);

    if (memoryDir is null)
    {
        // Default to Claude memory directory even if it doesn't exist yet
        memoryDir = Path.Combine(home, ".claude", "memory");
    }
}

// Expand ~ in paths
memoryDir = ExpandHome(memoryDir);

graphFile ??= Path.Combine(memoryDir, "graph.jsonl");

graphFile = ExpandHome(graphFile);

Log($"Memory directory: {memoryDir}");
Log($"Graph file: {graphFile}");

// ── Initialize graph ───────────────────────────────────────────

var store = new GraphStore(graphFile);
var graph = new KnowledgeGraph(store);
var skippedLines = graph.Load();

Log($"Loaded graph: {graph.EntityCount} entities, {graph.RelationCount} relations");
if (skippedLines > 0)
{
    Console.Error.WriteLine($"[memory-graph] WARNING: {skippedLines} malformed line(s) skipped in {graphFile}");
}

// ── Markdown sync ──────────────────────────────────────────────

if (!noSync)
{
    var scanner = new MarkdownScanner(memoryDir, graph, verbose);
    var (entities, relations) = scanner.Scan();
    Log($"Markdown sync: processed {entities} entities, {relations} relations");
}

// ── Initialize SQLite store ───────────────────────────────────

var dbPath = Path.Combine(memoryDir, "memory.db");
Log($"SQLite database: {dbPath}");

using var memoryStore = new MemoryStore(dbPath);

// Index existing graph entities into FTS5 for unified search
var entityData = graph.GetAllEntities()
    .Select(e => (e.Name, e.Type.ToString(), e.Observations))
    .ToList();
memoryStore.IndexGraphEntities(entityData);
Log($"FTS5 index: {entityData.Count} graph entities indexed");

// ── Register tools ─────────────────────────────────────────────

var registry = new ToolRegistry();
registry.Register(new MemoryContextTool(graph));
registry.Register(new MemorySearchTool(graph, memoryStore));
registry.Register(new MemoryAddEntityTool(graph));
registry.Register(new MemoryAddRelationTool(graph));
registry.Register(new MemoryAddInsightTool(graph));
registry.Register(new MemoryRemoveEntityTool(graph));
registry.Register(new MemoryRemoveRelationTool(graph));
registry.Register(new MemoryGraphTool(graph));

// v2 tools — reflexion, decisions, patterns, consolidation, stats
registry.Register(new MemoryReflectTool(memoryStore));
registry.Register(new MemoryDecideTool(memoryStore));
registry.Register(new MemoryPatternTool(memoryStore));
registry.Register(new MemoryConsolidateTool(memoryStore));
registry.Register(new MemoryStatsTool(graph, memoryStore));

// ── Start MCP server ──────────────────────────────────────────

var server = new McpServer(registry, verbose);
Log("Server started, waiting for MCP messages on stdin...");
await server.RunAsync();

// ── Helpers ────────────────────────────────────────────────────

void Log(string message)
{
    if (verbose)
    {
        Console.Error.WriteLine($"[memory-graph] {message}");
    }
}

void PrintUsage()
{
    Console.Error.WriteLine("""
        memory-graph — MCP server providing a knowledge graph over markdown memory

        Usage: memory-graph [OPTIONS]

        Options:
          --memory-dir PATH    Memory directory (default: auto-detect from agent)
          --graph-file PATH    Graph file path (default: {memory-dir}/graph.jsonl)
          --no-sync            Skip markdown sync on startup
          --verbose            Log to stderr for debugging
          -h, --help           Show this help
        """);
}

string ExpandHome(string path)
{
    if (path == "~")
    {
        return Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
    }

    if (path.StartsWith("~/"))
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return Path.Combine(home, path[2..]);
    }

    return path;
}
