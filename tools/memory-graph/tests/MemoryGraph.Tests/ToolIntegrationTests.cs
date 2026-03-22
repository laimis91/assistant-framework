using System.Text.Json;
using MemoryGraph.Graph;
using MemoryGraph.Storage;
using MemoryGraph.Tools;
using Xunit;

namespace MemoryGraph.Tests;

public class ToolIntegrationTests : IDisposable
{
    private readonly List<string> _tempFiles = [];

    private (KnowledgeGraph Graph, ToolRegistry Registry) CreateTestSetup()
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

    private (KnowledgeGraph Graph, ToolRegistry Registry, MemoryStore Store) CreateFullTestSetup()
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
        registry.Register(new MemoryAddEntityTool(graph));
        registry.Register(new MemoryAddRelationTool(graph));
        registry.Register(new MemoryAddInsightTool(graph));
        registry.Register(new MemoryRemoveEntityTool(graph));
        registry.Register(new MemoryRemoveRelationTool(graph));
        registry.Register(new MemoryGraphTool(graph));
        // v2 reflexion tools
        registry.Register(new MemoryReflectTool(memoryStore));
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

    private static JsonElement ParseArgs(string json)
    {
        using var doc = JsonDocument.Parse(json);
        return doc.RootElement.Clone();
    }

    [Fact]
    public void AddEntity_ThenSearch_FindsIt()
    {
        var (_, registry) = CreateTestSetup();

        // Add entity
        var addResult = registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "DesktopApp", "type": "Project", "observations": ["WPF app", "Uses MVVM"]}
            """));
        Assert.False(addResult.IsError);
        Assert.Contains("created", addResult.Content[0].Text);

        // Search for it
        var searchResult = registry.Execute("memory_search", ParseArgs("""
            {"query": "WPF"}
            """));
        Assert.False(searchResult.IsError);
        Assert.Contains("DesktopApp", searchResult.Content[0].Text);
    }

    [Fact]
    public void AddRelation_ThenContext_ShowsDependency()
    {
        var (_, registry) = CreateTestSetup();

        // Add two projects
        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "DesktopApp", "type": "Project", "observations": ["WPF app"]}
            """));
        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "API", "type": "Project", "observations": ["ASP.NET Core"]}
            """));

        // Add relation
        var relResult = registry.Execute("memory_add_relation", ParseArgs("""
            {"from": "DesktopApp", "to": "API", "type": "DependsOn", "detail": "HTTP calls"}
            """));
        Assert.False(relResult.IsError);

        // Get context
        var contextResult = registry.Execute("memory_context", ParseArgs("""
            {"project": "DesktopApp"}
            """));
        Assert.False(contextResult.IsError);
        Assert.Contains("API", contextResult.Content[0].Text);
        Assert.Contains("DependsOn", contextResult.Content[0].Text);
    }

    [Fact]
    public void AddInsight_CreatesEntityAndRelations()
    {
        var (graph, registry) = CreateTestSetup();

        // Add a project first
        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "API", "type": "Project", "observations": ["ASP.NET Core"]}
            """));

        // Add insight
        var result = registry.Execute("memory_add_insight", ParseArgs("""
            {"insight": "EF Core SaveChanges in a loop causes N+1", "appliesTo": ["API"], "source": "task-2026-03-18"}
            """));
        Assert.False(result.IsError);
        Assert.Contains("entity", result.Content[0].Text);
        Assert.Contains("relations", result.Content[0].Text);

        // Verify insight entity was created
        var insights = graph.GetEntitiesByType(EntityType.Insight).ToList();
        Assert.Single(insights);
        Assert.Contains("EF Core SaveChanges in a loop causes N+1", insights[0].Observations);
    }

    [Fact]
    public void RemoveEntity_RemovesFromGraph()
    {
        var (graph, registry) = CreateTestSetup();

        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "OldProject", "type": "Project", "observations": ["deprecated"]}
            """));
        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "API", "type": "Project", "observations": ["api target"]}
            """));
        registry.Execute("memory_add_relation", ParseArgs("""
            {"from": "OldProject", "to": "API", "type": "DependsOn"}
            """));

        var result = registry.Execute("memory_remove_entity", ParseArgs("""
            {"name": "OldProject"}
            """));
        Assert.False(result.IsError);
        Assert.Contains("removed", result.Content[0].Text);

        Assert.Null(graph.GetEntity("OldProject"));
        Assert.Equal(0, graph.RelationCount);
    }

    [Fact]
    public void RemoveRelation_RemovesSpecificRelation()
    {
        var (graph, registry) = CreateTestSetup();

        // Create entities first (AddRelation validates endpoints)
        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "A", "type": "Project", "observations": ["entity A"]}
            """));
        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "B", "type": "Project", "observations": ["entity B"]}
            """));

        registry.Execute("memory_add_relation", ParseArgs("""
            {"from": "A", "to": "B", "type": "DependsOn"}
            """));
        registry.Execute("memory_add_relation", ParseArgs("""
            {"from": "A", "to": "B", "type": "SharedWith"}
            """));

        var result = registry.Execute("memory_remove_relation", ParseArgs("""
            {"from": "A", "to": "B", "type": "DependsOn"}
            """));
        Assert.False(result.IsError);

        Assert.Equal(1, graph.RelationCount);
    }

    [Fact]
    public void MemoryGraph_ReturnsFullDump()
    {
        var (_, registry) = CreateTestSetup();

        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "P1", "type": "Project", "observations": ["project 1"]}
            """));
        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "P2", "type": "Project", "observations": ["project 2"]}
            """));
        registry.Execute("memory_add_relation", ParseArgs("""
            {"from": "P1", "to": "P2", "type": "DependsOn"}
            """));

        var result = registry.Execute("memory_graph", ParseArgs("{}"));
        Assert.False(result.IsError);

        var text = result.Content[0].Text;
        Assert.Contains("P1", text);
        Assert.Contains("P2", text);
        Assert.Contains("\"entities\":2", text);
        Assert.Contains("\"relations\":1", text);
    }

    [Fact]
    public void UnknownTool_ReturnsError()
    {
        var (_, registry) = CreateTestSetup();

        var result = registry.Execute("nonexistent_tool", ParseArgs("{}"));

        Assert.True(result.IsError);
        Assert.Contains("Unknown tool", result.Content[0].Text);
    }

    [Fact]
    public void Context_NonExistentProject_ReturnsAvailableProjects()
    {
        var (_, registry) = CreateTestSetup();

        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "RealProject", "type": "Project", "observations": ["exists"]}
            """));

        var result = registry.Execute("memory_context", ParseArgs("""
            {"project": "FakeProject"}
            """));
        Assert.False(result.IsError);
        Assert.Contains("RealProject", result.Content[0].Text);
    }

    [Fact]
    public void Context_WithPath_AutoDetectsProjectName()
    {
        var (_, registry) = CreateTestSetup();

        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "DesktopApp", "type": "Project", "observations": ["WPF"]}
            """));

        var result = registry.Execute("memory_context", ParseArgs("""
            {"path": "/Users/dev/Projects/DesktopApp"}
            """));
        Assert.False(result.IsError);
        Assert.Contains("DesktopApp", result.Content[0].Text);
        Assert.Contains("WPF", result.Content[0].Text);
    }

    [Fact]
    public void AddEntity_InvalidType_ReturnsError()
    {
        var (_, registry) = CreateTestSetup();

        var result = registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "Test", "type": "InvalidType", "observations": ["test"]}
            """));

        Assert.True(result.IsError);
        Assert.Contains("Invalid entity type", result.Content[0].Text);
    }

    [Fact]
    public void ToolRegistry_ListsAllTools_V1()
    {
        var (_, registry) = CreateTestSetup();

        var definitions = registry.GetDefinitions();

        Assert.Equal(8, definitions.Count);
        Assert.Contains(definitions, d => d.Name == "memory_context");
        Assert.Contains(definitions, d => d.Name == "memory_search");
        Assert.Contains(definitions, d => d.Name == "memory_add_entity");
        Assert.Contains(definitions, d => d.Name == "memory_add_relation");
        Assert.Contains(definitions, d => d.Name == "memory_add_insight");
        Assert.Contains(definitions, d => d.Name == "memory_remove_entity");
        Assert.Contains(definitions, d => d.Name == "memory_remove_relation");
        Assert.Contains(definitions, d => d.Name == "memory_graph");
    }

    [Fact]
    public void ToolRegistry_ListsAllTools_Full()
    {
        var (_, registry, store) = CreateFullTestSetup();
        store.Dispose();

        var definitions = registry.GetDefinitions();

        Assert.Equal(13, definitions.Count);
        Assert.Contains(definitions, d => d.Name == "memory_reflect");
        Assert.Contains(definitions, d => d.Name == "memory_decide");
        Assert.Contains(definitions, d => d.Name == "memory_pattern");
        Assert.Contains(definitions, d => d.Name == "memory_consolidate");
        Assert.Contains(definitions, d => d.Name == "memory_stats");
    }

    [Fact]
    public void Context_ManagedByRelation_ShowsCorrectDirection()
    {
        var (_, registry) = CreateTestSetup();

        // DesktopApp is managed by WebAdmin (DesktopApp --ManagedBy--> WebAdmin)
        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "DesktopApp", "type": "Project", "observations": ["WPF app"]}
            """));
        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "WebAdmin", "type": "Project", "observations": ["Blazor admin panel"]}
            """));
        registry.Execute("memory_add_relation", ParseArgs("""
            {"from": "DesktopApp", "to": "WebAdmin", "type": "ManagedBy", "detail": "Feature flags and access control"}
            """));

        // Context for DesktopApp should show WebAdmin in managedBy
        var result = registry.Execute("memory_context", ParseArgs("""
            {"project": "DesktopApp"}
            """));
        Assert.False(result.IsError);

        var text = result.Content[0].Text;
        Assert.Contains("WebAdmin", text);
        Assert.Contains("managedBy", text);
    }

    // ── V2 Reflexion Tool Tests ──────────────────────────────────────────────

    [Fact]
    public void Reflect_RecordsReflexionAndExtractsLessons()
    {
        var (_, registry, store) = CreateFullTestSetup();
        using (store)
        {
            var result = registry.Execute("memory_reflect", ParseArgs("""
                {
                    "task": "Add caching layer",
                    "project": "API",
                    "projectType": "dotnet-api",
                    "taskType": "feature",
                    "size": "medium",
                    "wentWell": ["Clean separation of concerns"],
                    "wentWrong": ["Missed edge case in TTL"],
                    "lessons": ["Always test TTL expiry in integration tests"],
                    "planAccuracy": 4,
                    "estimateAccuracy": 3,
                    "firstAttemptSuccess": true
                }
                """));
            Assert.False(result.IsError);
            var text = result.Content[0].Text;
            Assert.Contains("reflexionId", text);
            Assert.Contains("lessonsCreated", text);
        }
    }

    [Fact]
    public void Reflect_MinimalArgs_Succeeds()
    {
        var (_, registry, store) = CreateFullTestSetup();
        using (store)
        {
            var result = registry.Execute("memory_reflect", ParseArgs("""
                {"task": "Fix login bug", "project": "WebApp"}
                """));
            Assert.False(result.IsError);
            Assert.Contains("reflexionId", result.Content[0].Text);
        }
    }

    [Fact]
    public void Decide_RecordsDecision()
    {
        var (_, registry, store) = CreateFullTestSetup();
        using (store)
        {
            var result = registry.Execute("memory_decide", ParseArgs("""
                {
                    "title": "Use Redis for caching",
                    "decision": "Redis over in-memory cache",
                    "rationale": "Need shared cache across instances",
                    "alternatives": "In-memory: simpler but not shared. Memcached: less feature-rich.",
                    "project": "API",
                    "tags": "caching, infrastructure"
                }
                """));
            Assert.False(result.IsError);
            var text = result.Content[0].Text;
            Assert.Contains("decisionId", text);
            Assert.Contains("Use Redis for caching", text);
        }
    }

    [Fact]
    public void Pattern_RecordsNewPattern()
    {
        var (_, registry, store) = CreateFullTestSetup();
        using (store)
        {
            var result = registry.Execute("memory_pattern", ParseArgs("""
                {
                    "projectType": "dotnet-api",
                    "phase": "build",
                    "pattern": "Services always implement IDisposable",
                    "confidence": 0.7
                }
                """));
            Assert.False(result.IsError);
            var text = result.Content[0].Text;
            Assert.Contains("lessonId", text);
            Assert.Contains("dotnet-api", text);
        }
    }

    [Fact]
    public void Pattern_ReinforcesExistingPattern()
    {
        var (_, registry, store) = CreateFullTestSetup();
        using (store)
        {
            // Add pattern first time
            registry.Execute("memory_pattern", ParseArgs("""
                {
                    "projectType": "dotnet-api",
                    "phase": "build",
                    "pattern": "Services always implement IDisposable"
                }
                """));

            // Add same pattern again — should reinforce
            var result = registry.Execute("memory_pattern", ParseArgs("""
                {
                    "projectType": "dotnet-api",
                    "phase": "build",
                    "pattern": "Services always implement IDisposable"
                }
                """));
            Assert.False(result.IsError);
            var text = result.Content[0].Text;
            Assert.Contains("reinforced", text);
        }
    }

    [Fact]
    public void Consolidate_RunsWithoutError()
    {
        var (_, registry, store) = CreateFullTestSetup();
        using (store)
        {
            var result = registry.Execute("memory_consolidate", ParseArgs("{}"));
            Assert.False(result.IsError);
            var text = result.Content[0].Text;
            Assert.Contains("decayed", text);
            Assert.Contains("archived", text);
        }
    }

    [Fact]
    public void Stats_ReturnsGraphAndMemoryCounts()
    {
        var (_, registry, store) = CreateFullTestSetup();
        using (store)
        {
            // Add some data
            registry.Execute("memory_add_entity", ParseArgs("""
                {"name": "TestProject", "type": "Project", "observations": ["test"]}
                """));
            registry.Execute("memory_reflect", ParseArgs("""
                {"task": "Test task", "project": "TestProject"}
                """));
            registry.Execute("memory_decide", ParseArgs("""
                {"title": "Test decision", "decision": "Option A", "rationale": "Simpler"}
                """));

            var result = registry.Execute("memory_stats", ParseArgs("{}"));
            Assert.False(result.IsError);
            var text = result.Content[0].Text;
            Assert.Contains("entities", text);
            Assert.Contains("relations", text);
            Assert.Contains("reflexions", text);
            Assert.Contains("decisions", text);
        }
    }

    [Fact]
    public void Stats_FiltersByProjectType()
    {
        var (_, registry, store) = CreateFullTestSetup();
        using (store)
        {
            var result = registry.Execute("memory_stats", ParseArgs("""
                {"projectType": "dotnet-api"}
                """));
            Assert.False(result.IsError);
        }
    }
}
