using MemoryGraph.Graph;
using MemoryGraph.Sync;
using Xunit;

namespace MemoryGraph.Tests;

public class EntityExtractorTests
{
    [Fact]
    public void ExtractFromInsight_ExtractsEntityFromTitle()
    {
        var content = """
            # EF Core SaveChanges batching

            When saving multiple entities, use AddRange instead of Add in a loop.
            This avoids N+1 database writes.
            """;

        var result = EntityExtractor.ExtractFromInsight(content, "insights/ef-core.md", []);

        Assert.Single(result.Entities);
        Assert.Equal("EF Core SaveChanges batching", result.Entities[0].Name);
        Assert.Equal(EntityType.Insight, result.Entities[0].Type);
        Assert.Equal("insights/ef-core.md", result.Entities[0].SourceFile);
        Assert.Equal(2, result.Entities[0].Observations.Count);
    }

    [Fact]
    public void ExtractFromInsight_LinksToKnownEntities()
    {
        var content = """
            # Performance fix for API

            The API was slow because of N+1 queries in EF Core.
            """;

        var existingEntities = new List<Entity>
        {
            new() { Name = "API", Type = EntityType.Project },
            new() { Name = "EF Core", Type = EntityType.Technology }
        };

        var result = EntityExtractor.ExtractFromInsight(content, "insights/perf.md", existingEntities);

        Assert.Single(result.Entities);
        Assert.Equal(2, result.Relations.Count);
        Assert.All(result.Relations, r => Assert.Equal(RelationType.AppliesTo, r.Type));
    }

    [Fact]
    public void ExtractFromInsight_NoTitle_ReturnsEmpty()
    {
        var content = "Just some text without a heading";

        var result = EntityExtractor.ExtractFromInsight(content, "test.md", []);

        Assert.Empty(result.Entities);
    }

    [Fact]
    public void ExtractFromProfile_ExtractsPreferences()
    {
        var content = """
            # Developer Profile

            - prefers var when type is obvious
            - uses braces for single-line blocks
            - Naming: PascalCase for public members
            """;

        var result = EntityExtractor.ExtractFromProfile(content, "user/profile.md");

        Assert.True(result.Entities.Count >= 2);
        Assert.All(result.Entities, e => Assert.Equal(EntityType.Preference, e.Type));
        Assert.All(result.Entities, e => Assert.Equal("user/profile.md", e.SourceFile));
    }

    [Fact]
    public void ExtractFromFeedback_ExtractsConventions()
    {
        var content = """
            # Code Review Feedback

            - always use guard clauses for null checks
            - never use string concatenation for SQL
            - convention: test names follow Method_Case_Expected
            """;

        var result = EntityExtractor.ExtractFromFeedback(content, "feedback/review.md");

        Assert.True(result.Entities.Count >= 2);
        Assert.All(result.Entities, e =>
            Assert.Equal(EntityType.Convention, e.Type));
    }

    [Fact]
    public void ExtractFromProfile_IgnoresHttpUrls()
    {
        var content = """
            - Reference: https://docs.microsoft.com/en-us/dotnet
            - prefers explicit types for complex expressions
            """;

        var result = EntityExtractor.ExtractFromProfile(content, "user/profile.md");

        // Should extract the preference but not the URL line as a key:value
        Assert.All(result.Entities, e =>
        {
            Assert.DoesNotContain("http", e.Observations[0], StringComparison.OrdinalIgnoreCase);
        });
    }

    [Fact]
    public void ExtractFromInsight_StripsListMarkers()
    {
        var content = """
            # Test Insight

            - First observation
            * Second observation
            """;

        var result = EntityExtractor.ExtractFromInsight(content, "test.md", []);

        Assert.Single(result.Entities);
        Assert.Contains("First observation", result.Entities[0].Observations);
        Assert.Contains("Second observation", result.Entities[0].Observations);
    }
}
