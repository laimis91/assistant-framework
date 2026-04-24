using System.Text.Json;
using MemoryGraph.Graph;
using MemoryGraph.Server;
using MemoryGraph.Storage;
using Xunit;

namespace MemoryGraph.Tests;

public sealed class MemoryGraphRuntimeTests : IDisposable
{
    private readonly string _memoryDir;

    public MemoryGraphRuntimeTests()
    {
        _memoryDir = Path.Combine(Path.GetTempPath(), $"memory-graph-runtime-{Guid.NewGuid()}");
        Directory.CreateDirectory(_memoryDir);
    }

    public void Dispose()
    {
        if (Directory.Exists(_memoryDir))
        {
            Directory.Delete(_memoryDir, recursive: true);
        }
    }

    [Fact]
    public void Create_ImportsExistingJsonlIntoSqliteAndRuntimeTools()
    {
        var graphFile = Path.Combine(_memoryDir, "graph.jsonl");
        File.WriteAllText(graphFile, """
            {"kind":"entity","name":"JsonlProject","type":"project","observations":["from jsonl"],"createdAt":"2026-04-24T00:00:00Z","updatedAt":"2026-04-24T00:00:00Z"}
            {"kind":"entity","name":"JsonlTechnology","type":"technology","observations":["import target"],"createdAt":"2026-04-24T00:00:00Z","updatedAt":"2026-04-24T00:00:00Z"}
            {"kind":"relation","from":"JsonlProject","to":"JsonlTechnology","type":"uses","detail":"runtime import","createdAt":"2026-04-24T00:00:00Z"}
            """);
        var originalJsonl = File.ReadAllText(graphFile);

        using var runtime = MemoryGraphRuntime.Create(new MemoryGraphRuntimeOptions(_memoryDir, graphFile));

        var result = runtime.Registry.Execute("memory_graph", ParseArgs("{}"));
        var graphJsonlImport = Assert.IsType<JsonlImportResult>(runtime.Metrics.GraphJsonlImport);

        Assert.False(result.IsError);
        Assert.Contains("JsonlProject", result.Content[0].Text);
        Assert.Contains("from jsonl", result.Content[0].Text);
        Assert.Contains("JsonlTechnology", result.Content[0].Text);
        Assert.Contains("runtime import", result.Content[0].Text);
        Assert.NotNull(runtime.MemoryStore.GetGraphEntity("JsonlProject"));
        Assert.False(graphJsonlImport.NoOp);
        Assert.Equal(2, graphJsonlImport.EntitiesCreated);
        Assert.Equal(1, graphJsonlImport.RelationsCreated);
        Assert.Equal(originalJsonl, File.ReadAllText(graphFile));
        Assert.Equal(0, runtime.Metrics.SkippedGraphLines);
    }

    [Fact]
    public void Create_RuntimeRegistryIncludesAllProgramStartupTools()
    {
        var graphFile = Path.Combine(_memoryDir, "missing-graph.jsonl");

        using var runtime = MemoryGraphRuntime.Create(new MemoryGraphRuntimeOptions(_memoryDir, graphFile));

        var toolNames = runtime.Registry.GetDefinitions()
            .Select(definition => definition.Name)
            .Order(StringComparer.Ordinal)
            .ToList();

        Assert.Equal([
            "memory_add_entity",
            "memory_add_insight",
            "memory_add_relation",
            "memory_consolidate",
            "memory_context",
            "memory_decide",
            "memory_graph",
            "memory_pattern",
            "memory_reflect",
            "memory_remove_entity",
            "memory_remove_relation",
            "memory_search",
            "memory_stats",
            "memory_trend"
        ], toolNames);
    }

    [Fact]
    public void Create_IndexesImportedJsonlGraphEntitiesForMemorySearchWithRelations()
    {
        var graphFile = Path.Combine(_memoryDir, "graph.jsonl");
        File.WriteAllText(graphFile, """
            {"kind":"entity","name":"JsonlProject","type":"project","observations":["from jsonl searchable"],"createdAt":"2026-04-24T00:00:00Z","updatedAt":"2026-04-24T00:00:00Z"}
            {"kind":"entity","name":"JsonlTechnology","type":"technology","observations":["relation endpoint"],"createdAt":"2026-04-24T00:00:00Z","updatedAt":"2026-04-24T00:00:00Z"}
            {"kind":"relation","from":"JsonlProject","to":"JsonlTechnology","type":"uses","detail":"runtime import relation","createdAt":"2026-04-24T00:00:00Z"}
            """);

        using var runtime = MemoryGraphRuntime.Create(new MemoryGraphRuntimeOptions(_memoryDir, graphFile));
        using var search = ExecuteSearch(runtime, """
            {"query":"JsonlProject","types":["entity"]}
            """);

        Assert.Equal("fts5", search.RootElement.GetProperty("searchMode").GetString());
        var project = AssertSingleSearchResult(search, "JsonlProject");
        var relation = Assert.Single(project.GetProperty("relations").EnumerateArray());
        Assert.Equal("JsonlProject", relation.GetProperty("from").GetString());
        Assert.Equal("JsonlTechnology", relation.GetProperty("to").GetString());
        Assert.Equal("Uses", relation.GetProperty("type").GetString());
        Assert.Equal("runtime import relation", relation.GetProperty("detail").GetString());
    }

    [Fact]
    public void Create_RepeatedWithSameJsonlIsNoOpAndPreservesDbRows()
    {
        var graphFile = Path.Combine(_memoryDir, "graph.jsonl");
        File.WriteAllText(graphFile, """
            {"kind":"entity","name":"JsonlProject","type":"project","observations":["from jsonl"],"createdAt":"2026-04-24T00:00:00Z","updatedAt":"2026-04-24T00:00:00Z"}
            """);

        using (var runtime = MemoryGraphRuntime.Create(new MemoryGraphRuntimeOptions(_memoryDir, graphFile)))
        {
            runtime.MemoryStore.AddOrUpdateGraphEntity("DbOnlyProject", EntityType.Project, ["from sqlite"]);
            var graphJsonlImport = Assert.IsType<JsonlImportResult>(runtime.Metrics.GraphJsonlImport);
            Assert.False(graphJsonlImport.NoOp);
        }

        using var repeatedRuntime = MemoryGraphRuntime.Create(new MemoryGraphRuntimeOptions(_memoryDir, graphFile));
        var result = repeatedRuntime.Registry.Execute("memory_graph", ParseArgs("{}"));
        var repeatedGraphJsonlImport = Assert.IsType<JsonlImportResult>(repeatedRuntime.Metrics.GraphJsonlImport);

        Assert.True(repeatedGraphJsonlImport.NoOp);
        Assert.False(result.IsError);
        Assert.Contains("JsonlProject", result.Content[0].Text);
        Assert.Contains("DbOnlyProject", result.Content[0].Text);
        Assert.Contains("from sqlite", result.Content[0].Text);
        Assert.Equal(2, repeatedRuntime.Graph.EntityCount);
    }

    [Fact]
    public void Create_MissingJsonlDoesNotFailAndKeepsExistingDbRowsVisible()
    {
        var missingGraphFile = Path.Combine(_memoryDir, "missing-graph.jsonl");
        using (var seedStore = new MemoryStore(Path.Combine(_memoryDir, "memory.db")))
        {
            seedStore.AddOrUpdateGraphEntity("DbOnlyProject", EntityType.Project, ["from sqlite"]);
        }

        using var runtime = MemoryGraphRuntime.Create(new MemoryGraphRuntimeOptions(_memoryDir, missingGraphFile));
        var result = runtime.Registry.Execute("memory_graph", ParseArgs("{}"));

        Assert.Null(runtime.Metrics.GraphJsonlImport);
        Assert.False(result.IsError);
        Assert.Contains("DbOnlyProject", result.Content[0].Text);
        Assert.Contains("from sqlite", result.Content[0].Text);
    }

    [Fact]
    public void Create_DoesNotDeleteDbRowsAbsentFromJsonl()
    {
        var graphFile = Path.Combine(_memoryDir, "graph.jsonl");
        File.WriteAllText(graphFile, """
            {"kind":"entity","name":"JsonlProject","type":"project","observations":["from jsonl"],"createdAt":"2026-04-24T00:00:00Z","updatedAt":"2026-04-24T00:00:00Z"}
            """);

        using (var seedStore = new MemoryStore(Path.Combine(_memoryDir, "memory.db")))
        {
            seedStore.AddOrUpdateGraphEntity("DbOnlyProject", EntityType.Project, ["from sqlite"]);
        }

        using var runtime = MemoryGraphRuntime.Create(new MemoryGraphRuntimeOptions(_memoryDir, graphFile));
        var result = runtime.Registry.Execute("memory_graph", ParseArgs("{}"));

        Assert.False(result.IsError);
        Assert.Contains("JsonlProject", result.Content[0].Text);
        Assert.Contains("DbOnlyProject", result.Content[0].Text);
        Assert.NotNull(runtime.MemoryStore.GetGraphEntity("DbOnlyProject"));
        Assert.Equal(2, runtime.Graph.EntityCount);
    }

    [Fact]
    public void Create_ReconcilesRelationalRowsIntoPersistentSqliteGraph()
    {
        var graphFile = Path.Combine(_memoryDir, "missing-graph.jsonl");
        var dbPath = Path.Combine(_memoryDir, "memory.db");
        using (var seedStore = new MemoryStore(dbPath))
        {
            seedStore.AddReflexion(MakeReflexion(
                lessons: "Recover startup rows\nPersist recovered insights"));
            seedStore.AddDecision(new DecisionEntry
            {
                Title = "Use SQLite graph storage",
                Decision = "Startup reconciliation writes recovered entities into graph tables",
                Rationale = "Runtime tools read from the DB-backed knowledge graph",
                Project = "RecoveredRuntime"
            });
        }

        using (var runtime = MemoryGraphRuntime.Create(new MemoryGraphRuntimeOptions(_memoryDir, graphFile)))
        {
            var result = runtime.Registry.Execute("memory_graph", ParseArgs("{}"));
            var project = Assert.IsType<Entity>(runtime.Graph.GetEntity("RecoveredRuntime"));
            var insights = runtime.Graph.GetEntitiesByType(EntityType.Insight).ToList();

            Assert.False(result.IsError);
            Assert.Contains("RecoveredRuntime", result.Content[0].Text);
            Assert.Contains("Recover startup rows", result.Content[0].Text);
            Assert.Contains("Persist recovered insights", result.Content[0].Text);
            Assert.Equal(1, runtime.Metrics.Reconciliation.ProjectsCreated);
            Assert.Equal(2, runtime.Metrics.Reconciliation.InsightsCreated);
            Assert.Equal(2, runtime.Metrics.Reconciliation.RelationsCreated);
            Assert.Contains("SQLite reflexion evidence count: 1", project.Observations);
            Assert.Contains("SQLite decision evidence count: 1", project.Observations);
            Assert.Equal(2, insights.Count);
            Assert.All(insights, insight =>
                Assert.Contains(runtime.Graph.GetRelationsFrom(insight.Name), relation =>
                    relation.To == "RecoveredRuntime" && relation.Type == RelationType.AppliesTo));
        }

        using var reopenedStore = new MemoryStore(dbPath);
        var reopenedGraph = new KnowledgeGraph(reopenedStore);
        reopenedGraph.Load();

        Assert.NotNull(reopenedGraph.GetEntity("RecoveredRuntime"));
        Assert.Equal(3, reopenedGraph.EntityCount);
        Assert.Equal(2, reopenedGraph.RelationCount);
        Assert.Contains(reopenedGraph.GetEntitiesByType(EntityType.Insight), insight =>
            insight.Observations.Contains("Recover startup rows"));
        Assert.Contains(reopenedGraph.GetEntitiesByType(EntityType.Insight), insight =>
            insight.Observations.Contains("Persist recovered insights"));
    }

    [Fact]
    public void Create_IndexesRelationalReconciliationEntitiesForMemorySearch()
    {
        var graphFile = Path.Combine(_memoryDir, "missing-graph.jsonl");
        var dbPath = Path.Combine(_memoryDir, "memory.db");
        using (var seedStore = new MemoryStore(dbPath))
        {
            seedStore.AddReflexion(MakeReflexion(
                lessons: "Recovered entity should be searchable"));
            seedStore.AddDecision(new DecisionEntry
            {
                Title = "Recover graph search entity",
                Decision = "Relational reconciliation creates DB graph entities before FTS alignment",
                Rationale = "Startup search should see recovered graph entities",
                Project = "RecoveredRuntime"
            });
        }

        using var runtime = MemoryGraphRuntime.Create(new MemoryGraphRuntimeOptions(_memoryDir, graphFile));
        using var search = ExecuteSearch(runtime, """
            {"query":"SQLite reflexion evidence","types":["entity"]}
            """);

        Assert.Equal("fts5", search.RootElement.GetProperty("searchMode").GetString());
        AssertSingleSearchResult(search, "RecoveredRuntime");
    }

    [Fact]
    public void Create_PrunesStaleGraphEntityFtsRowsBeforeMemorySearchReturnsResults()
    {
        var graphFile = Path.Combine(_memoryDir, "missing-graph.jsonl");
        using (var seedStore = new MemoryStore(Path.Combine(_memoryDir, "memory.db")))
        {
            seedStore.IndexInFts("entity", "OrphanProject", "OrphanProject", "orphan startup searchable", "Project");
        }

        using var runtime = MemoryGraphRuntime.Create(new MemoryGraphRuntimeOptions(_memoryDir, graphFile));
        using var search = ExecuteSearch(runtime, """
            {"query":"orphan startup searchable","types":["entity"]}
            """);

        Assert.Equal(1, runtime.Metrics.PrunedGraphEntityRows);
        Assert.Empty(search.RootElement.GetProperty("results").EnumerateArray());
    }

    [Fact]
    public void Create_RepeatedRelationalReconciliationDoesNotDuplicateGraphRows()
    {
        var graphFile = Path.Combine(_memoryDir, "missing-graph.jsonl");
        var dbPath = Path.Combine(_memoryDir, "memory.db");
        using (var seedStore = new MemoryStore(dbPath))
        {
            seedStore.AddReflexion(MakeReflexion(
                lessons: "Recover startup rows\nPersist recovered insights"));
            seedStore.AddDecision(new DecisionEntry
            {
                Title = "Use SQLite graph storage",
                Decision = "Startup reconciliation writes recovered entities into graph tables",
                Rationale = "Runtime tools read from the DB-backed knowledge graph",
                Project = "RecoveredRuntime"
            });
        }

        int entityCount;
        int relationCount;
        int observationCount;
        using (var runtime = MemoryGraphRuntime.Create(new MemoryGraphRuntimeOptions(_memoryDir, graphFile)))
        {
            entityCount = runtime.Graph.EntityCount;
            relationCount = runtime.Graph.RelationCount;
            observationCount = CountObservations(runtime.Graph);
        }

        using var repeatedRuntime = MemoryGraphRuntime.Create(new MemoryGraphRuntimeOptions(_memoryDir, graphFile));

        Assert.Equal(0, repeatedRuntime.Metrics.Reconciliation.ProjectsCreated);
        Assert.Equal(0, repeatedRuntime.Metrics.Reconciliation.InsightsCreated);
        Assert.Equal(0, repeatedRuntime.Metrics.Reconciliation.RelationsCreated);
        Assert.Equal(entityCount, repeatedRuntime.Graph.EntityCount);
        Assert.Equal(relationCount, repeatedRuntime.Graph.RelationCount);
        Assert.Equal(observationCount, CountObservations(repeatedRuntime.Graph));
    }

    private static int CountObservations(KnowledgeGraph graph)
    {
        return graph.GetAllEntities().Sum(entity => entity.Observations.Count);
    }

    private static JsonDocument ExecuteSearch(MemoryGraphRuntime runtime, string json)
    {
        var result = runtime.Registry.Execute("memory_search", ParseArgs(json));
        Assert.False(result.IsError);
        return JsonDocument.Parse(result.Content[0].Text);
    }

    private static JsonElement AssertSingleSearchResult(JsonDocument search, string sourceId)
    {
        var matches = search.RootElement.GetProperty("results")
            .EnumerateArray()
            .Where(result => result.GetProperty("sourceId").GetString() == sourceId)
            .ToList();

        return Assert.Single(matches);
    }

    private static ReflexionEntry MakeReflexion(
        string task = "Recovered task",
        string project = "RecoveredRuntime",
        string lessons = "Recover startup rows")
    {
        return new ReflexionEntry
        {
            TaskDescription = task,
            Project = project,
            ProjectType = "dotnet-api",
            TaskType = "bugfix",
            Size = "small",
            WentWell = "Recovered relational data",
            WentWrong = "",
            Lessons = lessons,
            PlanAccuracy = 4,
            EstimateAccuracy = 4,
            FirstAttemptSuccess = true
        };
    }

    private static JsonElement ParseArgs(string json)
    {
        using var doc = JsonDocument.Parse(json);
        return doc.RootElement.Clone();
    }
}
