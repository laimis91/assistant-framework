using MemoryGraph.Server;

// ── Parse CLI arguments ────────────────────────────────────────

string? memoryDir = null;
string? graphFile = null;
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

// ── Initialize runtime ─────────────────────────────────────────

using var runtime = MemoryGraphRuntime.Create(new MemoryGraphRuntimeOptions(memoryDir, graphFile));
var metrics = runtime.Metrics;

Log($"SQLite database: {metrics.DatabasePath}");
if (metrics.GraphJsonlImport is { } graphJsonlImport)
{
    var importStatus = graphJsonlImport.NoOp ? "unchanged, no-op" : "imported";
    Log($"Graph JSONL {importStatus}: {graphJsonlImport.LinesRead} lines read, {graphJsonlImport.SkippedLines} skipped, {graphJsonlImport.EntitiesCreated} entities created, {graphJsonlImport.EntitiesUpdated} entities updated, {graphJsonlImport.RelationsCreated} relations created, {graphJsonlImport.RelationsDeduplicated} relations deduplicated, {graphJsonlImport.RelationsSkipped} relations skipped");
}
else
{
    Log("Graph JSONL import: file missing, skipped");
}

Log($"Loaded graph: {runtime.Graph.EntityCount} entities, {runtime.Graph.RelationCount} relations");
Log($"Reconciled SQLite memory: {metrics.Reconciliation.ProjectsCreated} projects, {metrics.Reconciliation.InsightsCreated} insights, {metrics.Reconciliation.RelationsCreated} relations");
Log($"FTS5 index: {metrics.IndexedGraphEntities} graph entities indexed, {metrics.PrunedGraphEntityRows} stale entity rows pruned");

// ── Start MCP server ──────────────────────────────────────────

var server = new McpServer(runtime.Registry, verbose);
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
        memory-graph — MCP server providing DB-backed local memory storage

        Usage: memory-graph [OPTIONS]

        Options:
          --memory-dir PATH    Memory directory (default: auto-detect from agent)
          --graph-file PATH    Legacy JSONL import/fallback path (default: {memory-dir}/graph.jsonl)
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
