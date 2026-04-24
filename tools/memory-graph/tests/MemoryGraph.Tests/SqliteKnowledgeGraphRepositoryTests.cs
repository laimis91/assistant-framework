using MemoryGraph.Graph;
using MemoryGraph.Storage;
using Xunit;

namespace MemoryGraph.Tests;

public sealed class SqliteKnowledgeGraphRepositoryTests : IDisposable
{
    private readonly string _dbPath;
    private readonly MemoryStore _store;
    private readonly KnowledgeGraph _graph;

    public SqliteKnowledgeGraphRepositoryTests()
    {
        _dbPath = Path.Combine(Path.GetTempPath(), $"sqlite-knowledge-graph-{Guid.NewGuid()}.db");
        _store = new MemoryStore(_dbPath);
        _graph = new KnowledgeGraph(_store);
    }

    public void Dispose()
    {
        _store.Dispose();
        if (File.Exists(_dbPath))
        {
            File.Delete(_dbPath);
        }
    }

    [Fact]
    public void AddOrUpdateEntity_UsesCaseInsensitiveLookupAndReturnsObservationCounts()
    {
        var created = _graph.AddOrUpdateEntity(
            "TestProject",
            EntityType.Project,
            ["Uses SQLite", "Has graph tables"],
            sourceFile: "graph.jsonl");

        var updated = _graph.AddOrUpdateEntity(
            "testproject",
            EntityType.Technology,
            ["uses sqlite", "Runs in MemoryStore"],
            sourceFile: "ignored.jsonl");

        var entity = _graph.GetEntity("TESTPROJECT");

        Assert.True(created.Created);
        Assert.Equal(2, created.NewObservations);
        Assert.False(updated.Created);
        Assert.Equal(1, updated.NewObservations);
        Assert.Equal(1, _graph.EntityCount);
        Assert.NotNull(entity);
        Assert.Equal("TestProject", entity.Name);
        Assert.Equal(EntityType.Project, entity.Type);
        Assert.Equal("graph.jsonl", entity.SourceFile);
        Assert.Equal(["Uses SQLite", "Has graph tables", "Runs in MemoryStore"], entity.Observations);
    }

    [Fact]
    public void RelationOperations_DedupeAndQueryCaseInsensitively()
    {
        _graph.AddOrUpdateEntity("ProjectA", EntityType.Project, ["A"]);
        _graph.AddOrUpdateEntity("ProjectB", EntityType.Project, ["B"]);
        _graph.AddOrUpdateEntity("Library", EntityType.Technology, ["Lib"]);

        Assert.True(_graph.AddRelation("projecta", "PROJECTB", RelationType.DependsOn, "HTTP"));
        Assert.False(_graph.AddRelation("ProjectA", "ProjectB", RelationType.DependsOn, "duplicate detail"));
        Assert.True(_graph.AddRelation("ProjectB", "Library", RelationType.Uses));

        var fromA = _graph.GetRelationsFrom("PROJECTA").ToList();
        var toB = _graph.GetRelationsTo("projectb").ToList();
        var forB = _graph.GetRelationsFor("PROJECTB").ToList();
        var all = _graph.GetAllRelations();

        Assert.Equal(2, _graph.RelationCount);
        Assert.Single(fromA);
        Assert.Equal("ProjectA", fromA[0].From);
        Assert.Equal("ProjectB", fromA[0].To);
        Assert.Equal("HTTP", fromA[0].Detail);
        Assert.Single(toB);
        Assert.Equal(2, forB.Count);
        Assert.Equal(2, all.Count);

        Assert.True(_graph.RemoveRelation("PROJECTA", "projectb", RelationType.DependsOn));
        Assert.False(_graph.RemoveRelation("PROJECTA", "projectb", RelationType.DependsOn));
        Assert.Empty(_graph.GetRelationsFrom("ProjectA"));
    }

    [Fact]
    public void AddRelation_WithMissingEndpoints_ReturnsFalseAndDoesNotPersist()
    {
        Assert.False(_graph.AddRelation("MissingA", "MissingB", RelationType.DependsOn, "dangling"));

        Assert.Equal(0, _graph.RelationCount);
        Assert.Empty(_graph.GetAllRelations());
        Assert.Empty(_graph.GetRelationsFrom("missinga"));
        Assert.Empty(_graph.GetRelationsTo("missingb"));
        Assert.Empty(_graph.GetRelationsFor("MissingA"));

        using var reopenedStore = new MemoryStore(_dbPath);
        var reopenedGraph = new KnowledgeGraph(reopenedStore);

        Assert.Equal(0, reopenedGraph.Load());
        Assert.Equal(0, reopenedGraph.RelationCount);
        Assert.Empty(reopenedGraph.GetAllRelations());
    }

    [Fact]
    public void RemoveEntity_CascadesRelations()
    {
        _graph.AddOrUpdateEntity("ProjectA", EntityType.Project, ["A"]);
        _graph.AddOrUpdateEntity("ProjectB", EntityType.Project, ["B"]);
        _graph.AddRelation("ProjectA", "ProjectB", RelationType.DependsOn);
        _graph.AddRelation("ProjectB", "ProjectA", RelationType.SharedWith);

        var removed = _graph.RemoveEntity("projecta");

        Assert.True(removed.Removed);
        Assert.Equal(2, removed.RelationsRemoved);
        Assert.Null(_graph.GetEntity("ProjectA"));
        Assert.Equal(0, _graph.RelationCount);
    }

    [Fact]
    public void Search_FindsNameObservationAndAppliesTypeFilter()
    {
        _graph.AddOrUpdateEntity("DesktopApp", EntityType.Project, ["WPF app"]);
        _graph.AddOrUpdateEntity("EF Core", EntityType.Technology, ["ORM"]);
        _graph.AddOrUpdateEntity("API", EntityType.Project, ["Uses EF Core"]);

        var byName = _graph.Search("Desktop");
        var byObservation = _graph.Search("WPF");
        var byType = _graph.Search("EF Core", [EntityType.Technology]);

        Assert.Single(byName);
        Assert.Equal("DesktopApp", byName[0].Name);
        Assert.Single(byObservation);
        Assert.Equal("DesktopApp", byObservation[0].Name);
        Assert.Single(byType);
        Assert.Equal("EF Core", byType[0].Name);
    }

    [Fact]
    public void FindByAlias_FindsProjectAliasesOnly()
    {
        _graph.AddOrUpdateEntity("Assistant", EntityType.Project, ["Aliases: V1, Laiwyn"]);
        _graph.AddOrUpdateEntity("SQLite", EntityType.Technology, ["Aliases: V1"]);

        var results = _graph.FindByAlias("laiwyn");

        Assert.Single(results);
        Assert.Equal("Assistant", results[0].Name);
    }

    [Fact]
    public void SaveIfDirty_IsNoOpBecauseSqliteWritesImmediately()
    {
        _graph.AddOrUpdateEntity("PersistedProject", EntityType.Project, ["stored in SQLite"]);
        _graph.SaveIfDirty();

        using var reopenedStore = new MemoryStore(_dbPath);
        var reopenedGraph = new KnowledgeGraph(reopenedStore);

        Assert.Equal(0, reopenedGraph.Load());
        Assert.NotNull(reopenedGraph.GetEntity("persistedproject"));
    }
}
