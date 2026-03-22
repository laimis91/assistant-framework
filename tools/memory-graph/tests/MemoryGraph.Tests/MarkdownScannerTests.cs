using MemoryGraph.Graph;
using MemoryGraph.Sync;
using Xunit;

namespace MemoryGraph.Tests;

public class MarkdownScannerTests
{
    private static (string Dir, KnowledgeGraph Graph) CreateTestSetup()
    {
        var dir = Path.Combine(Path.GetTempPath(), $"test-memory-{Guid.NewGuid()}");
        Directory.CreateDirectory(dir);

        var store = new GraphStore(Path.Combine(dir, "graph.jsonl"));
        var graph = new KnowledgeGraph(store);

        return (dir, graph);
    }

    [Fact]
    public void Scan_InsightsDirectory_ExtractsInsights()
    {
        var (dir, graph) = CreateTestSetup();
        var insightsDir = Path.Combine(dir, "insights");
        Directory.CreateDirectory(insightsDir);

        File.WriteAllText(Path.Combine(insightsDir, "ef-core.md"), """
            # EF Core batching tip

            Use AddRange instead of Add in a loop.
            """);

        var scanner = new MarkdownScanner(dir, graph);
        var (entities, _) = scanner.Scan();

        Assert.True(entities > 0);
        var insight = graph.GetEntity("EF Core batching tip");
        Assert.NotNull(insight);
        Assert.Equal(EntityType.Insight, insight.Type);

        // Cleanup
        Directory.Delete(dir, true);
    }

    [Fact]
    public void Scan_ProfileFile_ExtractsPreferences()
    {
        var (dir, graph) = CreateTestSetup();
        var userDir = Path.Combine(dir, "user");
        Directory.CreateDirectory(userDir);

        File.WriteAllText(Path.Combine(userDir, "profile.md"), """
            # Profile

            - prefers var when type is obvious
            - Naming: PascalCase for public members
            """);

        var scanner = new MarkdownScanner(dir, graph);
        var (entities, _) = scanner.Scan();

        Assert.True(entities > 0);
        var preferences = graph.GetEntitiesByType(EntityType.Preference).ToList();
        Assert.True(preferences.Count >= 1);

        // Cleanup
        Directory.Delete(dir, true);
    }

    [Fact]
    public void Scan_FeedbackDirectory_ExtractsConventions()
    {
        var (dir, graph) = CreateTestSetup();
        var feedbackDir = Path.Combine(dir, "feedback");
        Directory.CreateDirectory(feedbackDir);

        File.WriteAllText(Path.Combine(feedbackDir, "review.md"), """
            # Review Feedback

            - always use guard clauses for null checks
            - never concatenate SQL strings
            """);

        var scanner = new MarkdownScanner(dir, graph);
        var (entities, _) = scanner.Scan();

        Assert.True(entities > 0);
        var conventions = graph.GetEntitiesByType(EntityType.Convention).ToList();
        Assert.True(conventions.Count >= 2);

        // Cleanup
        Directory.Delete(dir, true);
    }

    [Fact]
    public void Scan_NonExistentDirectory_ReturnsZero()
    {
        var store = new GraphStore(Path.Combine(Path.GetTempPath(), $"test-{Guid.NewGuid()}.jsonl"));
        var graph = new KnowledgeGraph(store);

        var scanner = new MarkdownScanner("/nonexistent/path", graph);
        var (entities, relations) = scanner.Scan();

        Assert.Equal(0, entities);
        Assert.Equal(0, relations);
    }

    [Fact]
    public void Scan_InsightWithKnownProject_CreatesRelation()
    {
        var (dir, graph) = CreateTestSetup();

        // Pre-populate a project entity
        graph.AddOrUpdateEntity("API", EntityType.Project, ["ASP.NET Core"]);

        var insightsDir = Path.Combine(dir, "insights");
        Directory.CreateDirectory(insightsDir);

        File.WriteAllText(Path.Combine(insightsDir, "api-perf.md"), """
            # API Performance Issue

            The API had slow response times due to N+1 queries.
            """);

        var scanner = new MarkdownScanner(dir, graph);
        scanner.Scan();

        var relations = graph.GetRelationsFor("API Performance Issue").ToList();
        Assert.Contains(relations, r => r.To == "API" && r.Type == RelationType.AppliesTo);

        // Cleanup
        Directory.Delete(dir, true);
    }

    [Fact]
    public void Scan_EmptyDirectories_DoesNotCrash()
    {
        var (dir, graph) = CreateTestSetup();
        Directory.CreateDirectory(Path.Combine(dir, "insights"));
        Directory.CreateDirectory(Path.Combine(dir, "feedback"));
        Directory.CreateDirectory(Path.Combine(dir, "user"));

        var scanner = new MarkdownScanner(dir, graph);
        var (entities, relations) = scanner.Scan();

        Assert.Equal(0, entities);
        Assert.Equal(0, relations);

        // Cleanup
        Directory.Delete(dir, true);
    }
}
