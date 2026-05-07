using MemoryGraph.Graph;
using MemoryGraph.Storage;
using Xunit;

namespace MemoryGraph.Tests;

public sealed class MemorySearchToolIntegrationTests : ToolIntegrationTestBase
{
    [Fact]
    public void Search_DoesNotPruneOrphanFtsEntity()
    {
        var (graph, registry, store) = CreateFullTestSetup();
        using (store)
        {
            graph.AddOrUpdateEntity("RealProject", EntityType.Project, ["real entity"]);
            store.IndexInFts("entity", "OrphanProject", "OrphanProject", "orphan searchable content", "Project");
            Assert.Equal(1, store.CountStaleGraphEntityFtsRows(graph.GetAllEntities().Select(e => e.Name)));

            var result = registry.Execute("memory_search", ParseArgs("""
                {"query": "orphan"}
                """));

            Assert.False(result.IsError);
            Assert.DoesNotContain("OrphanProject", result.Content[0].Text);
            Assert.Equal(1, store.CountStaleGraphEntityFtsRows(graph.GetAllEntities().Select(e => e.Name)));
        }
    }

    [Fact]
    public void Search_DoesNotReturnNonCanonicalEntityFtsRow()
    {
        var (graph, registry, store) = CreateFullTestSetup();
        using (store)
        {
            graph.AddOrUpdateEntity("API", EntityType.Project, ["canonical entity"]);
            store.IndexInFts("entity", "api", "api", "casevariantneedle stale lowercase content", "Project");
            Assert.Equal(1, store.CountStaleGraphEntityFtsRows(graph.GetAllEntities().Select(e => e.Name)));

            var result = registry.Execute("memory_search", ParseArgs("""
                {"query": "casevariantneedle"}
                """));

            Assert.False(result.IsError);
            var text = result.Content[0].Text;
            Assert.Contains("\"results\":[]", text);
            Assert.DoesNotContain("api", text);
            Assert.Equal(1, store.CountStaleGraphEntityFtsRows(graph.GetAllEntities().Select(e => e.Name)));
        }
    }

    [Fact]
    public void Search_RefillsWhenStaleEntityHitsOccupyInitialLimit()
    {
        var (_, registry, store) = CreateFullTestSetup();
        using (store)
        {
            for (var i = 0; i < 25; i++)
            {
                store.IndexInFts("entity", $"OrphanProject{i:D2}", $"OrphanProject{i:D2}",
                    "searchlimitneedle stale entity content", "Project");
            }

            store.AddDecision(new DecisionEntry
            {
                Title = "Valid limit recovery decision",
                Decision = "searchlimitneedle valid decision content",
                Rationale = "Non-entity memory should still be returned after stale entity filtering",
                Tags = "searchlimitneedle"
            });

            var result = registry.Execute("memory_search", ParseArgs("""
                {"query": "searchlimitneedle"}
                """));

            Assert.False(result.IsError);
            var text = result.Content[0].Text;
            Assert.Contains("Valid limit recovery decision", text);
            Assert.DoesNotContain("OrphanProject00", text);
        }
    }

    [Fact]
    public void Search_GraphFallbackHandlesBooleanOrTerms()
    {
        var (_, registry) = CreateTestSetup();

        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "Assistant Framework", "type": "Project", "observations": ["AI coding agent enhancement framework"]}
            """));

        var result = registry.Execute("memory_search", ParseArgs("""
            {"query": "Assistant/V1 OR Framework"}
            """));

        Assert.False(result.IsError);
        var text = result.Content[0].Text;
        Assert.Contains("Assistant Framework", text);
        Assert.Contains("\"searchMode\":\"graph\"", text);
    }

    [Fact]
    public void Search_GraphFallbackTreatsLowercaseOperatorWordsAsLiteralTerms()
    {
        var (_, registry) = CreateTestSetup();

        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "Privacy Rule", "type": "Rule", "observations": ["do not log PII in diagnostics"]}
            """));

        var result = registry.Execute("memory_search", ParseArgs("""
            {"query": "do not log PII"}
            """));

        Assert.False(result.IsError);
        var text = result.Content[0].Text;
        Assert.Contains("Privacy Rule", text);
        Assert.Contains("\"searchMode\":\"graph\"", text);
    }

    [Fact]
    public void Search_GraphFallbackIgnoresEmptyQuotedLiteral()
    {
        var (_, registry) = CreateTestSetup();

        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "Assistant Framework", "type": "Project", "observations": ["AI coding agent enhancement framework"]}
            """));

        var result = registry.Execute("memory_search", ParseArgs("""
            {"query": "\"\""}
            """));

        Assert.False(result.IsError);
        var text = result.Content[0].Text;
        Assert.Contains("\"results\":[]", text);
        Assert.Contains("\"searchMode\":\"graph\"", text);
        Assert.DoesNotContain("Assistant Framework", text);
    }

    [Fact]
    public void Search_EntityTypeFiltersApplyWhenFtsSucceeds()
    {
        var (graph, registry, store) = CreateFullTestSetup();
        using (store)
        {
            graph.AddOrUpdateEntity("Project Memory", EntityType.Project, ["sharedneedle project observation"]);
            graph.AddOrUpdateEntity("Rule Memory", EntityType.Rule, ["sharedneedle rule observation"]);
            store.IndexInFts("entity", "Project Memory", "Project Memory", "sharedneedle project observation", "Project");
            store.IndexInFts("entity", "Rule Memory", "Rule Memory", "sharedneedle rule observation", "Rule");

            var result = registry.Execute("memory_search", ParseArgs("""
                {"query": "sharedneedle", "types": ["Rule"]}
                """));

            Assert.False(result.IsError);
            var text = result.Content[0].Text;
            Assert.Contains("Rule Memory", text);
            Assert.DoesNotContain("Project Memory", text);
            Assert.Contains("\"searchMode\":\"fts5\"", text);
        }
    }

    [Fact]
    public void Search_EntityTypeFiltersApplyBeforeFtsLimit()
    {
        var (graph, registry, store) = CreateFullTestSetup();
        using (store)
        {
            for (var i = 0; i < 225; i++)
            {
                var projectName = $"Crowding Project {i:D3}";
                graph.AddOrUpdateEntity(projectName, EntityType.Project, ["entitytypelimitneedle project observation"]);
                store.IndexInFts("entity", projectName, projectName, "entitytypelimitneedle project observation", "Project");
            }

            graph.AddOrUpdateEntity("Selected Rule", EntityType.Rule, ["entitytypelimitneedle rule observation"]);
            store.IndexInFts("entity", "Selected Rule", "Selected Rule", "entitytypelimitneedle rule observation", "Rule");

            var result = registry.Execute("memory_search", ParseArgs("""
                {"query": "entitytypelimitneedle", "types": ["Rule"]}
                """));

            Assert.False(result.IsError);
            var text = result.Content[0].Text;
            Assert.Contains("Selected Rule", text);
            Assert.DoesNotContain("Crowding Project 000", text);
            Assert.Contains("\"searchMode\":\"fts5\"", text);
        }
    }

    [Fact]
    public void Search_SourceTypeFiltersStillApply()
    {
        var (graph, registry, store) = CreateFullTestSetup();
        using (store)
        {
            graph.AddOrUpdateEntity("Search Entity", EntityType.Project, ["sourceneedle entity observation"]);
            store.IndexInFts("entity", "Search Entity", "Search Entity", "sourceneedle entity observation", "Project");
            store.AddDecision(new DecisionEntry
            {
                Title = "Source decision",
                Decision = "sourceneedle decision content",
                Rationale = "Decision result should survive source filtering",
                Tags = "sourceneedle"
            });
            store.AddReflexion(new ReflexionEntry
            {
                TaskDescription = "Source reflexion",
                Project = "SearchProject",
                WentWell = "sourceneedle reflexion content",
                WentWrong = "",
                Lessons = "filter reflexions by source",
                PlanAccuracy = 4,
                EstimateAccuracy = 4,
                FirstAttemptSuccess = true
            });

            var result = registry.Execute("memory_search", ParseArgs("""
                {"query": "sourceneedle", "types": ["decision"]}
                """));

            Assert.False(result.IsError);
            var text = result.Content[0].Text;
            Assert.Contains("Source decision", text);
            Assert.DoesNotContain("Search Entity", text);
            Assert.DoesNotContain("Source reflexion", text);
            Assert.Contains("\"searchMode\":\"fts5\"", text);
        }
    }

    [Fact]
    public void Search_MixedSourceAndEntityTypeFiltersReturnUnionResults()
    {
        var (graph, registry, store) = CreateFullTestSetup();
        using (store)
        {
            graph.AddOrUpdateEntity("Project Memory", EntityType.Project, ["mixedfilterneedle project observation"]);
            graph.AddOrUpdateEntity("Rule Memory", EntityType.Rule, ["mixedfilterneedle rule observation"]);
            store.IndexInFts("entity", "Project Memory", "Project Memory", "mixedfilterneedle project observation", "Project");
            store.IndexInFts("entity", "Rule Memory", "Rule Memory", "mixedfilterneedle rule observation", "Rule");
            store.AddDecision(new DecisionEntry
            {
                Title = "Mixed filter decision",
                Decision = "mixedfilterneedle decision content",
                Rationale = "Decision rows should be included alongside selected entity types",
                Tags = "mixedfilterneedle"
            });

            var result = registry.Execute("memory_search", ParseArgs("""
                {"query": "mixedfilterneedle", "types": ["decision", "Rule"]}
                """));

            Assert.False(result.IsError);
            var text = result.Content[0].Text;
            Assert.Contains("Mixed filter decision", text);
            Assert.Contains("Rule Memory", text);
            Assert.DoesNotContain("Project Memory", text);
            Assert.Contains("\"searchMode\":\"fts5\"", text);
        }
    }

    [Fact]
    public void Search_MixedSourceAndEntityTypeFiltersPushSourceTypesBeforeFtsLimit()
    {
        var (graph, registry, store) = CreateFullTestSetup();
        using (store)
        {
            for (var i = 0; i < 225; i++)
            {
                store.IndexInFts(
                    "reflexion",
                    i.ToString(),
                    $"Excluded reflexion {i:D3}",
                    "mixedlimitneedle excluded reflexion content",
                    "mixedlimitneedle");
            }

            graph.AddOrUpdateEntity("High Volume Rule", EntityType.Rule, ["mixedlimitneedle rule observation"]);
            store.IndexInFts("entity", "High Volume Rule", "High Volume Rule", "mixedlimitneedle rule observation", "Rule");
            store.AddDecision(new DecisionEntry
            {
                Title = "High volume mixed decision",
                Decision = "mixedlimitneedle decision content",
                Rationale = "Decision rows should not be hidden behind excluded FTS rows",
                Tags = "mixedlimitneedle"
            });

            var result = registry.Execute("memory_search", ParseArgs("""
                {"query": "mixedlimitneedle", "types": ["decision", "Rule"]}
                """));

            Assert.False(result.IsError);
            var text = result.Content[0].Text;
            Assert.Contains("High volume mixed decision", text);
            Assert.Contains("High Volume Rule", text);
            Assert.DoesNotContain("Excluded reflexion 000", text);
            Assert.Contains("\"searchMode\":\"fts5\"", text);
        }
    }
}
