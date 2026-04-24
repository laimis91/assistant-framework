using MemoryGraph.Graph;
using MemoryGraph.Storage;
using Xunit;

namespace MemoryGraph.Tests;

public sealed class MemoryGraphReconcilerTests : IDisposable
{
    private readonly string _dbPath;
    private readonly string _graphPath;
    private readonly MemoryStore _store;
    private readonly KnowledgeGraph _graph;

    public MemoryGraphReconcilerTests()
    {
        _dbPath = Path.Combine(Path.GetTempPath(), $"memory-reconcile-{Guid.NewGuid()}.db");
        _graphPath = Path.Combine(Path.GetTempPath(), $"memory-reconcile-{Guid.NewGuid()}.jsonl");
        _store = new MemoryStore(_dbPath);
        _graph = new KnowledgeGraph(new GraphStore(_graphPath));
    }

    public void Dispose()
    {
        _store.Dispose();
        foreach (var path in new[] { _dbPath, _graphPath })
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
    }

    [Fact]
    public void ReconcileFromStore_RecoversProjectInsightsAndRelations()
    {
        _store.AddReflexion(MakeReflexion(
            lessons: "Use stable graph names\nPrune stale entity rows"));
        _store.AddReflexion(MakeReflexion(
            task: "Follow-up task",
            lessons: "[\"Parse JSON lesson arrays\", \"Use stable graph names\"]"));
        _store.AddDecision(new DecisionEntry
        {
            Title = "Use graph as context source",
            Decision = "Recover SQLite project memory into graph entities",
            Rationale = "memory_context only reads graph entities",
            Project = "RecoveredApp"
        });

        var result = MemoryGraphReconciler.ReconcileFromStore(_graph, _store);

        Assert.Equal(1, result.ProjectsCreated);
        Assert.Equal(3, result.InsightsCreated);
        Assert.Equal(3, result.RelationsCreated);

        var project = _graph.GetEntity("RecoveredApp");
        Assert.NotNull(project);
        Assert.Contains("SQLite reflexion evidence count: 2", project.Observations);
        Assert.Contains("SQLite decision evidence count: 1", project.Observations);
        Assert.Contains("Project types observed in reflexions: dotnet-api", project.Observations);

        var insights = _graph.GetEntitiesByType(EntityType.Insight).ToList();
        Assert.Equal(3, insights.Count);
        Assert.Contains(insights, i => i.Observations.Contains("Parse JSON lesson arrays"));
        Assert.All(insights, insight =>
            Assert.Contains(_graph.GetRelationsFrom(insight.Name), r =>
                r.To == "RecoveredApp" && r.Type == RelationType.AppliesTo));
    }

    [Fact]
    public void ReconcileFromStore_IsIdempotent()
    {
        _store.AddReflexion(MakeReflexion(lessons: "Use stable graph names\nPrune stale entity rows"));

        MemoryGraphReconciler.ReconcileFromStore(_graph, _store);
        var entityCount = _graph.EntityCount;
        var relationCount = _graph.RelationCount;

        var second = MemoryGraphReconciler.ReconcileFromStore(_graph, _store);

        Assert.Equal(0, second.ProjectsCreated);
        Assert.Equal(0, second.InsightsCreated);
        Assert.Equal(0, second.RelationsCreated);
        Assert.Equal(entityCount, _graph.EntityCount);
        Assert.Equal(relationCount, _graph.RelationCount);
    }

    [Fact]
    public void ReconcileFromStore_DeduplicatesCaseOnlyLessonNames()
    {
        _store.AddReflexion(MakeReflexion(lessons: "Use stable graph names"));
        _store.AddReflexion(MakeReflexion(
            task: "Follow-up task",
            lessons: "  use   stable graph   names  "));

        var result = MemoryGraphReconciler.ReconcileFromStore(_graph, _store);

        Assert.Equal(1, result.InsightsCreated);
        var insight = _graph.GetEntitiesByType(EntityType.Insight).Single();
        Assert.Contains("Use stable graph names", insight.Observations);
    }

    [Fact]
    public void ReconcileFromStore_PreservesExistingProjectCaseInsensitively()
    {
        _graph.AddOrUpdateEntity("RecoveredApp", EntityType.Project, ["existing project"]);
        _store.AddReflexion(MakeReflexion(project: "recoveredapp", lessons: "Use existing project casing"));

        var result = MemoryGraphReconciler.ReconcileFromStore(_graph, _store);

        Assert.Equal(0, result.ProjectsCreated);
        Assert.NotNull(_graph.GetEntity("RecoveredApp"));
        Assert.Single(_graph.GetEntitiesByType(EntityType.Project));
        var insight = _graph.GetEntitiesByType(EntityType.Insight).Single();
        Assert.Contains(_graph.GetRelationsFrom(insight.Name), r =>
            r.To == "RecoveredApp" && r.Type == RelationType.AppliesTo);
    }

    private static ReflexionEntry MakeReflexion(
        string task = "Recovered task",
        string project = "RecoveredApp",
        string lessons = "Use stable graph names")
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
}
