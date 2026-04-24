using MemoryGraph.Storage;
using Xunit;

namespace MemoryGraph.Tests;

public sealed class MemoryStoreTests : IDisposable
{
    private readonly string _dbPath;
    private readonly MemoryStore _store;

    public MemoryStoreTests()
    {
        _dbPath = Path.Combine(Path.GetTempPath(), $"memory-test-{Guid.NewGuid()}.db");
        _store = new MemoryStore(_dbPath);
    }

    public void Dispose()
    {
        _store.Dispose();
        if (File.Exists(_dbPath))
        {
            File.Delete(_dbPath);
        }
    }

    // ── Reflexion tests ─────────────────────────────────────────

    [Fact]
    public void AddReflexion_ReturnsPositiveId()
    {
        var id = _store.AddReflexion(MakeReflexion());
        Assert.True(id > 0);
    }

    [Fact]
    public void GetReflexions_ReturnsStoredEntries()
    {
        _store.AddReflexion(MakeReflexion("Task A", projectType: "dotnet-api"));
        _store.AddReflexion(MakeReflexion("Task B", projectType: "blazor"));
        _store.AddReflexion(MakeReflexion("Task C", projectType: "dotnet-api"));

        var all = _store.GetReflexions();
        Assert.Equal(3, all.Count);

        var apiOnly = _store.GetReflexions(projectType: "dotnet-api");
        Assert.Equal(2, apiOnly.Count);
    }

    [Fact]
    public void GetReflexions_FiltersByTaskType()
    {
        _store.AddReflexion(MakeReflexion("Fix bug", taskType: "bugfix"));
        _store.AddReflexion(MakeReflexion("Add feature", taskType: "feature"));

        var bugfixes = _store.GetReflexions(taskType: "bugfix");
        Assert.Single(bugfixes);
        Assert.Equal("Fix bug", bugfixes[0].TaskDescription);
    }

    // ── Decision tests ──────────────────────────────────────────

    [Fact]
    public void AddDecision_ReturnsPositiveId()
    {
        var id = _store.AddDecision(MakeDecision());
        Assert.True(id > 0);
    }

    [Fact]
    public void GetDecisions_FiltersByProject()
    {
        _store.AddDecision(MakeDecision("Use Redis", project: "API"));
        _store.AddDecision(MakeDecision("Use SQLite", project: "Desktop"));

        var apiDecisions = _store.GetDecisions(project: "API");
        Assert.Single(apiDecisions);
        Assert.Equal("Use Redis", apiDecisions[0].Title);
    }

    // ── Strategy Lesson tests ───────────────────────────────────

    [Fact]
    public void AddStrategyLesson_CreatesNewLesson()
    {
        var id = _store.AddStrategyLesson(new StrategyLesson
        {
            ProjectType = "dotnet-api",
            Phase = "build",
            Lesson = "Always run tests after each file change",
            Confidence = 0.5
        });
        Assert.True(id > 0);
    }

    [Fact]
    public void AddStrategyLesson_ReinforcesExistingLesson()
    {
        var lesson = new StrategyLesson
        {
            ProjectType = "dotnet-api",
            Phase = "build",
            Lesson = "Always run tests after each file change",
            Confidence = 0.5
        };

        var id1 = _store.AddStrategyLesson(lesson);
        var id2 = _store.AddStrategyLesson(lesson); // same lesson — should reinforce

        Assert.Equal(id1, id2);

        var lessons = _store.GetStrategyLessons("dotnet-api", "build");
        Assert.Single(lessons);
        Assert.True(lessons[0].Confidence > 0.5); // should have increased
        Assert.Equal(2, lessons[0].ReinforcementCount);
    }

    [Fact]
    public void GetStrategyLessons_FiltersbyMinConfidence()
    {
        _store.AddStrategyLesson(new StrategyLesson
        {
            ProjectType = "dotnet-api",
            Phase = "build",
            Lesson = "High confidence lesson",
            Confidence = 0.9
        });
        _store.AddStrategyLesson(new StrategyLesson
        {
            ProjectType = "dotnet-api",
            Phase = "build",
            Lesson = "Low confidence lesson",
            Confidence = 0.1
        });

        var high = _store.GetStrategyLessons("dotnet-api", minConfidence: 0.5);
        Assert.Single(high);
        Assert.Equal("High confidence lesson", high[0].Lesson);
    }

    // ── FTS5 Search tests ───────────────────────────────────────

    [Fact]
    public void Search_FindsIndexedContent()
    {
        _store.IndexInFts("entity", "TestProject", "TestProject", "ASP.NET Core API with EF Core", "Project");

        var results = _store.Search("ASP.NET");
        Assert.Single(results);
        Assert.Equal("TestProject", results[0].Title);
    }

    [Fact]
    public void Search_FiltersBySourceType()
    {
        _store.IndexInFts("entity", "Proj", "Proj", "A project", "Project");
        _store.IndexInFts("reflexion", "1", "Fix bug", "Fixed a null ref", "bugfix");

        var entityOnly = _store.Search("project", sourceType: "entity");
        Assert.Single(entityOnly);

        var reflexionOnly = _store.Search("null ref", sourceType: "reflexion");
        Assert.Single(reflexionOnly);
    }

    [Fact]
    public void Search_ReflexionsAreIndexed()
    {
        _store.AddReflexion(MakeReflexion("Fix authentication bypass", wentWell: "Found root cause quickly"));

        var results = _store.Search("authentication");
        Assert.NotEmpty(results);
    }

    [Fact]
    public void Search_DecisionsAreIndexed()
    {
        _store.AddDecision(MakeDecision("Use Redis for distributed caching"));

        var results = _store.Search("Redis caching");
        Assert.NotEmpty(results);
    }

    // ── Calibration tests ───────────────────────────────────────

    [Fact]
    public void CalibrationStats_TracksAccuracy()
    {
        _store.AddCalibration("size", "small", "small", true, "dotnet-api");
        _store.AddCalibration("size", "small", "medium", false, "dotnet-api");
        _store.AddCalibration("size", "medium", "medium", true, "dotnet-api");

        var stats = _store.GetCalibrationStats("dotnet-api");
        Assert.True(stats.ByType.ContainsKey("size"));
        Assert.Equal(3, stats.ByType["size"].Total);
        Assert.Equal(2, stats.ByType["size"].Accurate);
    }

    // ── Stats tests ─────────────────────────────────────────────

    [Fact]
    public void GetStats_ReturnsCounts()
    {
        _store.AddReflexion(MakeReflexion());
        _store.AddDecision(MakeDecision());
        _store.AddStrategyLesson(new StrategyLesson
        {
            ProjectType = "test", Phase = "build", Lesson = "test lesson"
        });

        var stats = _store.GetStats();
        Assert.Equal(1, stats.Reflexions);
        Assert.Equal(1, stats.Decisions);
        Assert.Equal(1, stats.StrategyLessons);
    }

    // ── Consolidation tests ─────────────────────────────────────

    [Fact]
    public void ConsolidateStrategyLessons_ReturnsZeroWhenFresh()
    {
        _store.AddStrategyLesson(new StrategyLesson
        {
            ProjectType = "test", Phase = "build", Lesson = "fresh lesson", Confidence = 0.5
        });

        var (decayed, archived) = _store.ConsolidateStrategyLessons();
        Assert.Equal(0, decayed);
        Assert.Equal(0, archived);
    }

    // ── Stale lesson count tests ────────────────────────────────

    [Fact]
    public void GetStaleLessonCount_ReturnsZeroWhenFresh()
    {
        _store.AddStrategyLesson(new StrategyLesson
        {
            ProjectType = "test", Phase = "build", Lesson = "fresh lesson", Confidence = 0.5
        });

        var count = _store.GetStaleLessonCount(90);
        Assert.Equal(0, count);
    }

    [Fact]
    public void GetStaleLessonCount_ExcludesLowConfidence()
    {
        _store.AddStrategyLesson(new StrategyLesson
        {
            ProjectType = "test", Phase = "build", Lesson = "low conf", Confidence = 0.05
        });

        var count = _store.GetStaleLessonCount(0); // 0 days = everything is stale
        Assert.Equal(0, count); // But confidence too low, so excluded
    }

    // ── Helpers ──────────────────────────────────────────────────

    private static ReflexionEntry MakeReflexion(
        string task = "Test task",
        string project = "TestProject",
        string? projectType = null,
        string? taskType = null,
        string? wentWell = null)
    {
        return new ReflexionEntry
        {
            TaskDescription = task,
            Project = project,
            ProjectType = projectType ?? "dotnet-api",
            TaskType = taskType ?? "feature",
            Size = "small",
            WentWell = wentWell ?? "Things went well",
            WentWrong = "Minor issues",
            Lessons = "Learned something",
            PlanAccuracy = 4,
            EstimateAccuracy = 3,
            FirstAttemptSuccess = true
        };
    }

    private static DecisionEntry MakeDecision(string title = "Test Decision", string? project = null)
    {
        return new DecisionEntry
        {
            Title = title,
            Decision = "We decided to do X",
            Rationale = "Because Y",
            Alternatives = "Could have done Z",
            Project = project
        };
    }

}
