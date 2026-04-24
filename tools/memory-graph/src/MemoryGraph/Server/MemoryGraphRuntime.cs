using MemoryGraph.Graph;
using MemoryGraph.Storage;
using MemoryGraph.Tools;

namespace MemoryGraph.Server;

public sealed class MemoryGraphRuntime : IDisposable
{
    private MemoryGraphRuntime(
        MemoryStore memoryStore,
        KnowledgeGraph graph,
        ToolRegistry registry,
        MemoryGraphStartupMetrics metrics)
    {
        MemoryStore = memoryStore;
        Graph = graph;
        Registry = registry;
        Metrics = metrics;
    }

    public MemoryStore MemoryStore { get; }
    public KnowledgeGraph Graph { get; }
    public ToolRegistry Registry { get; }
    public MemoryGraphStartupMetrics Metrics { get; }

    public static MemoryGraphRuntime Create(MemoryGraphRuntimeOptions options)
    {
        var dbPath = Path.Combine(options.MemoryDir, "memory.db");
        var memoryStore = new MemoryStore(dbPath);
        try
        {
            var graphJsonlImport = File.Exists(options.GraphFile)
                ? memoryStore.ImportGraphJsonl(options.GraphFile)
                : null;

            var graph = new KnowledgeGraph(memoryStore);
            var skippedLines = graph.Load();

            var reconciliation = MemoryGraphReconciler.ReconcileFromStore(graph, memoryStore);
            graph.SaveIfDirty();

            var entityData = graph.GetAllEntities()
                .Select(e => (e.Name, e.Type.ToString(), e.Observations))
                .ToList();
            var prunedEntities = memoryStore.PruneGraphEntityIndex(entityData.Select(e => e.Name));
            memoryStore.IndexGraphEntities(entityData);

            var registry = BuildRegistry(graph, memoryStore, options.MemoryDir);
            var metrics = new MemoryGraphStartupMetrics(
                options.MemoryDir,
                options.GraphFile,
                dbPath,
                graphJsonlImport,
                skippedLines,
                reconciliation,
                entityData.Count,
                prunedEntities);

            return new MemoryGraphRuntime(memoryStore, graph, registry, metrics);
        }
        catch
        {
            memoryStore.Dispose();
            throw;
        }
    }

    public void Dispose()
    {
        MemoryStore.Dispose();
    }

    private static ToolRegistry BuildRegistry(KnowledgeGraph graph, MemoryStore memoryStore, string memoryDir)
    {
        var registry = new ToolRegistry();
        registry.Register(new MemoryContextTool(graph));
        registry.Register(new MemorySearchTool(graph, memoryStore));
        registry.Register(new MemoryAddEntityTool(graph));
        registry.Register(new MemoryAddRelationTool(graph));
        registry.Register(new MemoryAddInsightTool(graph));
        registry.Register(new MemoryRemoveEntityTool(graph));
        registry.Register(new MemoryRemoveRelationTool(graph));
        registry.Register(new MemoryGraphTool(graph));

        registry.Register(new MemoryReflectTool(memoryStore, graph));
        registry.Register(new MemoryDecideTool(memoryStore));
        registry.Register(new MemoryPatternTool(memoryStore));
        registry.Register(new MemoryConsolidateTool(memoryStore));
        registry.Register(new MemoryStatsTool(graph, memoryStore));
        registry.Register(new MemoryTrendTool(memoryStore, memoryDir));

        return registry;
    }
}

public sealed record MemoryGraphRuntimeOptions(string MemoryDir, string GraphFile);

public sealed record MemoryGraphStartupMetrics(
    string MemoryDir,
    string GraphFile,
    string DatabasePath,
    JsonlImportResult? GraphJsonlImport,
    int SkippedGraphLines,
    ReconciliationResult Reconciliation,
    int IndexedGraphEntities,
    int PrunedGraphEntityRows);
