using MemoryGraph.Graph;
using Xunit;

namespace MemoryGraph.Tests;

public class KnowledgeGraphTests
{
    private static KnowledgeGraph CreateGraph()
    {
        // Use a temp file that doesn't exist yet — in-memory only
        var store = new GraphStore(Path.Combine(Path.GetTempPath(), $"test-graph-{Guid.NewGuid()}.jsonl"));
        return new KnowledgeGraph(store);
    }

    [Fact]
    public void AddEntity_NewEntity_ReturnsCreated()
    {
        var graph = CreateGraph();

        var (created, newObs) = graph.AddOrUpdateEntity("TestProject", EntityType.Project, ["obs1", "obs2"]);

        Assert.True(created);
        Assert.Equal(2, newObs);
        Assert.Equal(1, graph.EntityCount);
    }

    [Fact]
    public void AddEntity_ExistingEntity_MergesObservations()
    {
        var graph = CreateGraph();
        graph.AddOrUpdateEntity("TestProject", EntityType.Project, ["obs1", "obs2"]);

        var (created, newObs) = graph.AddOrUpdateEntity("TestProject", EntityType.Project, ["obs2", "obs3"]);

        Assert.False(created);
        Assert.Equal(1, newObs); // only obs3 is new

        var entity = graph.GetEntity("TestProject");
        Assert.NotNull(entity);
        Assert.Equal(3, entity.Observations.Count);
    }

    [Fact]
    public void AddEntity_CaseInsensitiveLookup()
    {
        var graph = CreateGraph();
        graph.AddOrUpdateEntity("TestProject", EntityType.Project, ["obs1"]);

        var entity = graph.GetEntity("testproject");

        Assert.NotNull(entity);
        Assert.Equal("TestProject", entity.Name);
    }

    [Fact]
    public void RemoveEntity_RemovesEntityAndRelations()
    {
        var graph = CreateGraph();
        graph.AddOrUpdateEntity("A", EntityType.Project, ["project A"]);
        graph.AddOrUpdateEntity("B", EntityType.Project, ["project B"]);
        graph.AddRelation("A", "B", RelationType.DependsOn, "test");

        var (removed, relationsRemoved) = graph.RemoveEntity("A");

        Assert.True(removed);
        Assert.Equal(1, relationsRemoved);
        Assert.Null(graph.GetEntity("A"));
        Assert.Equal(0, graph.RelationCount);
    }

    [Fact]
    public void RemoveEntity_NonExistent_ReturnsFalse()
    {
        var graph = CreateGraph();

        var (removed, _) = graph.RemoveEntity("nonexistent");

        Assert.False(removed);
    }

    [Fact]
    public void AddRelation_NewRelation_ReturnsTrue()
    {
        var graph = CreateGraph();

        var created = graph.AddRelation("A", "B", RelationType.DependsOn, "test");

        Assert.True(created);
        Assert.Equal(1, graph.RelationCount);
    }

    [Fact]
    public void AddRelation_Duplicate_ReturnsFalse()
    {
        var graph = CreateGraph();
        graph.AddRelation("A", "B", RelationType.DependsOn, "test");

        var created = graph.AddRelation("A", "B", RelationType.DependsOn, "different detail");

        Assert.False(created);
        Assert.Equal(1, graph.RelationCount);
    }

    [Fact]
    public void AddRelation_SameEntitiesDifferentType_CreatesBoth()
    {
        var graph = CreateGraph();
        graph.AddRelation("A", "B", RelationType.DependsOn);

        var created = graph.AddRelation("A", "B", RelationType.SharedWith);

        Assert.True(created);
        Assert.Equal(2, graph.RelationCount);
    }

    [Fact]
    public void RemoveRelation_Existing_ReturnsTrue()
    {
        var graph = CreateGraph();
        graph.AddRelation("A", "B", RelationType.DependsOn);

        var removed = graph.RemoveRelation("A", "B", RelationType.DependsOn);

        Assert.True(removed);
        Assert.Equal(0, graph.RelationCount);
    }

    [Fact]
    public void RemoveRelation_NonExistent_ReturnsFalse()
    {
        var graph = CreateGraph();

        var removed = graph.RemoveRelation("A", "B", RelationType.DependsOn);

        Assert.False(removed);
    }

    [Fact]
    public void GetRelationsFor_ReturnsFromAndTo()
    {
        var graph = CreateGraph();
        graph.AddRelation("A", "B", RelationType.DependsOn);
        graph.AddRelation("C", "A", RelationType.ManagedBy);

        var relations = graph.GetRelationsFor("A").ToList();

        Assert.Equal(2, relations.Count);
    }

    [Fact]
    public void Search_ByName_FindsEntity()
    {
        var graph = CreateGraph();
        graph.AddOrUpdateEntity("DesktopApp", EntityType.Project, ["WPF app"]);
        graph.AddOrUpdateEntity("API", EntityType.Project, ["ASP.NET Core"]);

        var results = graph.Search("Desktop");

        Assert.Single(results);
        Assert.Equal("DesktopApp", results[0].Name);
    }

    [Fact]
    public void Search_ByObservation_FindsEntity()
    {
        var graph = CreateGraph();
        graph.AddOrUpdateEntity("API", EntityType.Project, ["ASP.NET Core Minimal APIs", "EF Core"]);

        var results = graph.Search("EF Core");

        Assert.Single(results);
        Assert.Equal("API", results[0].Name);
    }

    [Fact]
    public void Search_WithTypeFilter_FiltersResults()
    {
        var graph = CreateGraph();
        graph.AddOrUpdateEntity("EF Core", EntityType.Technology, ["ORM"]);
        graph.AddOrUpdateEntity("API", EntityType.Project, ["Uses EF Core"]);

        var results = graph.Search("EF Core", [EntityType.Technology]);

        Assert.Single(results);
        Assert.Equal("EF Core", results[0].Name);
    }

    [Fact]
    public void GetEntitiesByType_ReturnsCorrectType()
    {
        var graph = CreateGraph();
        graph.AddOrUpdateEntity("A", EntityType.Project, ["p1"]);
        graph.AddOrUpdateEntity("B", EntityType.Technology, ["t1"]);
        graph.AddOrUpdateEntity("C", EntityType.Project, ["p2"]);

        var projects = graph.GetEntitiesByType(EntityType.Project).ToList();

        Assert.Equal(2, projects.Count);
        Assert.All(projects, p => Assert.Equal(EntityType.Project, p.Type));
    }

    [Fact]
    public void DirtyFlag_NotClearedByNoOpMerge()
    {
        var tempFile = Path.Combine(Path.GetTempPath(), $"test-dirty-{Guid.NewGuid()}.jsonl");
        var store = new GraphStore(tempFile);
        var graph = new KnowledgeGraph(store);

        // Create entity A — dirty = true
        graph.AddOrUpdateEntity("A", EntityType.Project, ["new project"]);

        // No-op merge on B (B doesn't exist, so this creates it, but then...)
        graph.AddOrUpdateEntity("B", EntityType.Project, ["existing"]);

        // No-op merge: B already has "existing" — should NOT clear dirty flag
        graph.AddOrUpdateEntity("B", EntityType.Project, ["existing"]);

        // Save should persist both A and B
        graph.SaveIfDirty();

        // Reload and verify both entities survived
        var graph2 = new KnowledgeGraph(new GraphStore(tempFile));
        graph2.Load();
        Assert.NotNull(graph2.GetEntity("A"));
        Assert.NotNull(graph2.GetEntity("B"));
    }
}
