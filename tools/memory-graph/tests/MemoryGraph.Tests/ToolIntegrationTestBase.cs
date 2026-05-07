using System.Text.Json;
using MemoryGraph.Graph;
using MemoryGraph.Storage;
using MemoryGraph.Tools;

namespace MemoryGraph.Tests;

public abstract class ToolIntegrationTestBase : IDisposable
{
    private readonly List<string> _tempFiles = [];

    protected (KnowledgeGraph Graph, ToolRegistry Registry) CreateTestSetup()
    {
        var tempFile = Path.Combine(Path.GetTempPath(), $"test-tools-{Guid.NewGuid()}.jsonl");
        _tempFiles.Add(tempFile);
        var store = new GraphStore(tempFile);
        var graph = new KnowledgeGraph(store);

        var registry = new ToolRegistry();
        registry.Register(new MemoryContextTool(graph));
        registry.Register(new MemorySearchTool(graph));
        registry.Register(new MemoryAddEntityTool(graph));
        registry.Register(new MemoryAddRelationTool(graph));
        registry.Register(new MemoryAddInsightTool(graph));
        registry.Register(new MemoryRemoveEntityTool(graph));
        registry.Register(new MemoryRemoveRelationTool(graph));
        registry.Register(new MemoryGraphTool(graph));

        return (graph, registry);
    }

    protected (KnowledgeGraph Graph, ToolRegistry Registry, MemoryStore Store) CreateFullTestSetup()
    {
        var tempFile = Path.Combine(Path.GetTempPath(), $"test-tools-{Guid.NewGuid()}.jsonl");
        var tempDb = Path.Combine(Path.GetTempPath(), $"test-tools-{Guid.NewGuid()}.db");
        _tempFiles.Add(tempFile);
        _tempFiles.Add(tempDb);
        var store = new GraphStore(tempFile);
        var graph = new KnowledgeGraph(store);
        var memoryStore = new MemoryStore(tempDb);

        var registry = new ToolRegistry();
        // v1 graph tools
        registry.Register(new MemoryContextTool(graph));
        registry.Register(new MemorySearchTool(graph, memoryStore));
        registry.Register(new MemoryDoctorTool(graph, memoryStore, Path.GetTempPath()));
        registry.Register(new MemoryAddEntityTool(graph));
        registry.Register(new MemoryAddRelationTool(graph));
        registry.Register(new MemoryAddInsightTool(graph));
        registry.Register(new MemoryRemoveEntityTool(graph));
        registry.Register(new MemoryRemoveRelationTool(graph));
        registry.Register(new MemoryGraphTool(graph));
        // v2 reflexion tools
        registry.Register(new MemoryReflectTool(memoryStore, graph));
        registry.Register(new MemoryDecideTool(memoryStore));
        registry.Register(new MemoryPatternTool(memoryStore));
        registry.Register(new MemoryConsolidateTool(memoryStore));
        registry.Register(new MemoryStatsTool(graph, memoryStore));

        return (graph, registry, memoryStore);
    }

    public void Dispose()
    {
        foreach (var f in _tempFiles)
        {
            try { File.Delete(f); } catch { /* best effort */ }
        }
    }

    protected static JsonElement ParseArgs(string json)
    {
        using var doc = JsonDocument.Parse(json);
        return doc.RootElement.Clone();
    }
}
