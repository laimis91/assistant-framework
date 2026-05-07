using System.Text.Json;
using MemoryGraph.Graph;
using Xunit;

namespace MemoryGraph.Tests;

public sealed class MemoryContextToolIntegrationTests : ToolIntegrationTestBase
{
    [Fact]
    public void Context_FindsByAlias_WhenExactNameFails()
    {
        var (_, registry) = CreateTestSetup();

        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "Assistant Framework", "type": "Project", "observations": ["Aliases: Assistant, assistant-framework", "AI coding agent enhancement framework"]}
            """));

        var result = registry.Execute("memory_context", ParseArgs("""
            {"project": "assistant-framework"}
            """));
        Assert.False(result.IsError);
        var text = result.Content[0].Text;
        Assert.Contains("Assistant Framework", text);
        Assert.Contains("AI coding agent enhancement framework", text);
    }

    [Fact]
    public void Context_FindsByAlias_FromPath()
    {
        var (_, registry) = CreateTestSetup();

        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "s-Planner", "type": "Project", "observations": ["Aliases: NaviPlanner, NaviPlannerWPF, navi-planner-wpf", "WPF desktop app"]}
            """));

        // Path auto-detects "navi-planner-wpf" which should resolve via alias
        var result = registry.Execute("memory_context", ParseArgs("""
            {"path": "/Users/dev/Projects/navi-planner-wpf"}
            """));
        Assert.False(result.IsError);
        var text = result.Content[0].Text;
        Assert.Contains("s-Planner", text);
        Assert.Contains("WPF desktop app", text);
    }

    [Fact]
    public void Context_FindsByParentLeafAlias_FromPath()
    {
        var (graph, registry) = CreateTestSetup();

        graph.AddOrUpdateEntity("Assistant Framework", EntityType.Project, ["Aliases: Assistant/V1", "Canonical project"]);
        graph.AddOrUpdateEntity("Assistant Dashboard", EntityType.Project, ["Another Assistant project"]);

        var result = registry.Execute("memory_context", ParseArgs("""
            {"path": "/repo/Assistant/V1"}
            """));

        Assert.False(result.IsError);
        using var document = JsonDocument.Parse(result.Content[0].Text);
        var root = document.RootElement;
        Assert.Equal("Assistant Framework", root.GetProperty("resolvedProject").GetString());
        Assert.Equal("pathCandidateAlias", root.GetProperty("resolvedBy").GetString());
        Assert.Contains(root.GetProperty("pathCandidates").EnumerateArray(), candidate =>
            candidate.GetString() == "Assistant/V1");
    }

    [Fact]
    public void Context_PrefersParentLeafAliasOverLegacyLeafExact_FromPath()
    {
        var (graph, registry) = CreateTestSetup();

        graph.AddOrUpdateEntity("Assistant Framework", EntityType.Project, ["Aliases: Assistant/V1", "Canonical project"]);
        graph.AddOrUpdateEntity("V1", EntityType.Project, ["Legacy basename duplicate"]);

        var result = registry.Execute("memory_context", ParseArgs("""
            {"path": "/repo/Assistant/V1"}
            """));

        Assert.False(result.IsError);
        using var document = JsonDocument.Parse(result.Content[0].Text);
        var root = document.RootElement;
        Assert.Equal("Assistant Framework", root.GetProperty("resolvedProject").GetString());
        Assert.Equal("pathCandidateAlias", root.GetProperty("resolvedBy").GetString());
        Assert.Contains("Canonical project", result.Content[0].Text);
        Assert.DoesNotContain("Legacy basename duplicate", result.Content[0].Text);
    }

    [Fact]
    public void Context_FindsProjectFromRepoRootPath_UsingParentSegment()
    {
        var (_, registry) = CreateTestSetup();

        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "Assistant Framework", "type": "Project", "observations": ["AI coding agent enhancement framework"]}
            """));

        var result = registry.Execute("memory_context", ParseArgs("""
            {"path": "/Users/laimis/Developer/Projects/Assistant/V1"}
            """));
        Assert.False(result.IsError);
        var text = result.Content[0].Text;
        Assert.Contains("Assistant Framework", text);
        Assert.Contains("AI coding agent enhancement framework", text);
    }

    [Fact]
    public void Context_FindsProjectFromObservedPathMetadata()
    {
        var (_, registry) = CreateTestSetup();

        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "Assistant Framework", "type": "Project", "observations": ["Path: /Users/laimis/Developer/Projects/Assistant/V1", "AI coding agent enhancement framework"]}
            """));

        var result = registry.Execute("memory_context", ParseArgs("""
            {"path": "/Users/laimis/Developer/Projects/Assistant/V1"}
            """));
        Assert.False(result.IsError);
        var text = result.Content[0].Text;
        Assert.Contains("Assistant Framework", text);
        Assert.Contains("AI coding agent enhancement framework", text);
    }

    [Fact]
    public void Context_PathMetadataTakesPrecedenceOverFuzzyNameAmbiguity()
    {
        var (_, registry) = CreateTestSetup();

        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "Assistant Dashboard", "type": "Project", "observations": ["Blazor admin panel"]}
            """));
        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "Assistant Framework", "type": "Project", "observations": ["Path: /Users/laimis/Developer/Projects/Assistant/V1", "AI coding agent enhancement framework"]}
            """));

        var result = registry.Execute("memory_context", ParseArgs("""
            {"path": "/Users/laimis/Developer/Projects/Assistant/V1"}
            """));
        Assert.False(result.IsError);
        var text = result.Content[0].Text;
        Assert.DoesNotContain("Ambiguous project name", text);
        Assert.Contains("Assistant Framework", text);
        Assert.Contains("AI coding agent enhancement framework", text);
    }

    [Fact]
    public void Context_PathMetadataTakesPrecedenceOverExactBasenameProject()
    {
        var (graph, registry) = CreateTestSetup();
        const string projectPath = "/Users/laimis/Developer/Projects/Assistant/V1";

        graph.AddOrUpdateEntity("V1", EntityType.Project, ["Legacy basename duplicate"]);
        graph.AddOrUpdateEntity(
            "Assistant Framework",
            EntityType.Project,
            ["ProjectPath: /Users/laimis/Developer/Projects/Assistant/V1", "AI coding agent enhancement framework"],
            sourceFile: projectPath);

        var result = registry.Execute("memory_context", ParseArgs("""
            {"path": "/Users/laimis/Developer/Projects/Assistant/V1"}
            """));

        Assert.False(result.IsError);
        var text = result.Content[0].Text;
        Assert.Contains("Assistant Framework", text);
        Assert.Contains("AI coding agent enhancement framework", text);
        Assert.DoesNotContain("Legacy basename duplicate", text);
    }

    [Fact]
    public void Context_ReturnsResolutionExplainability()
    {
        var (graph, registry) = CreateTestSetup();

        graph.AddOrUpdateEntity(
            "Assistant Framework",
            EntityType.Project,
            ["Aliases: V1", "ProjectPath: /repo/Assistant/V1", "Canonical project"]);
        graph.AddOrUpdateEntity("V1", EntityType.Project, ["Legacy duplicate project"]);

        var result = registry.Execute("memory_context", ParseArgs("""
            {"path": "/repo/Assistant/V1"}
            """));

        Assert.False(result.IsError);
        using var document = JsonDocument.Parse(result.Content[0].Text);
        var root = document.RootElement;
        Assert.Equal("Assistant Framework", root.GetProperty("resolvedProject").GetString());
        Assert.Equal("pathMetadata", root.GetProperty("resolvedBy").GetString());
        Assert.Contains(root.GetProperty("pathCandidates").EnumerateArray(), candidate =>
            candidate.GetString() == "V1");
        Assert.Contains(root.GetProperty("equivalentProjectsIncluded").EnumerateArray(), project =>
            project.GetString() == "V1");
        Assert.Empty(root.GetProperty("warnings").EnumerateArray());
    }

    [Fact]
    public void Context_ReturnsExplicitAliasResolutionExplainability()
    {
        var (graph, registry) = CreateTestSetup();

        graph.AddOrUpdateEntity("Assistant Framework", EntityType.Project, ["Aliases: V1", "Canonical project"]);

        var result = registry.Execute("memory_context", ParseArgs("""
            {"project": "V1"}
            """));

        Assert.False(result.IsError);
        using var document = JsonDocument.Parse(result.Content[0].Text);
        var root = document.RootElement;
        Assert.Equal("Assistant Framework", root.GetProperty("resolvedProject").GetString());
        Assert.Equal("explicitAlias", root.GetProperty("resolvedBy").GetString());
    }

    [Fact]
    public void Context_ExplicitProjectTakesPrecedenceOverMismatchedPathMetadata()
    {
        var (graph, registry) = CreateTestSetup();

        graph.AddOrUpdateEntity("ProjectA", EntityType.Project, ["Explicit project context"]);
        graph.AddOrUpdateEntity("ProjectB", EntityType.Project, ["ProjectPath: /repo/ProjectB", "Path metadata context"]);

        var result = registry.Execute("memory_context", ParseArgs("""
            {"project": "ProjectA", "path": "/repo/ProjectB"}
            """));

        Assert.False(result.IsError);
        var text = result.Content[0].Text;
        using var document = JsonDocument.Parse(text);
        Assert.Equal("ProjectA", document.RootElement.GetProperty("project").GetProperty("name").GetString());
        Assert.Contains("Explicit project context", text);
        Assert.DoesNotContain("Path metadata context", text);
    }

    [Fact]
    public void Context_ExplicitProjectAliasTakesPrecedenceOverMismatchedPathMetadata()
    {
        var (graph, registry) = CreateTestSetup();

        graph.AddOrUpdateEntity("Assistant Framework", EntityType.Project, ["Aliases: V1", "Alias project context"]);
        graph.AddOrUpdateEntity("Other Project", EntityType.Project, ["ProjectPath: /repo/Other", "Path metadata context"]);

        var result = registry.Execute("memory_context", ParseArgs("""
            {"project": "V1", "path": "/repo/Other"}
            """));

        Assert.False(result.IsError);
        var text = result.Content[0].Text;
        Assert.Contains("Assistant Framework", text);
        Assert.Contains("Alias project context", text);
        Assert.DoesNotContain("Other Project", text);
        Assert.DoesNotContain("Path metadata context", text);
    }

    [Fact]
    public void Context_IncludesInsightsAppliedToEquivalentProjectAliases()
    {
        var (graph, registry) = CreateTestSetup();

        graph.AddOrUpdateEntity("Assistant Framework", EntityType.Project, ["Aliases: V1", "Canonical project"]);
        graph.AddOrUpdateEntity("V1", EntityType.Project, ["Legacy duplicate project"]);
        graph.AddOrUpdateEntity("legacy-split-insight", EntityType.Insight, ["Legacy split insight should be visible"]);
        graph.AddRelation("legacy-split-insight", "V1", RelationType.AppliesTo);

        var result = registry.Execute("memory_context", ParseArgs("""
            {"project": "Assistant Framework"}
            """));

        Assert.False(result.IsError);
        var text = result.Content[0].Text;
        Assert.Contains("Assistant Framework", text);
        Assert.Contains("Legacy split insight should be visible", text);
    }

    [Fact]
    public void Context_IncludesRelationsAndScopedPreferencesFromEquivalentProjectAliases()
    {
        var (graph, registry) = CreateTestSetup();

        graph.AddOrUpdateEntity("Assistant Framework", EntityType.Project, ["Aliases: V1", "Canonical project"]);
        graph.AddOrUpdateEntity("V1", EntityType.Project, ["Legacy duplicate project"]);
        graph.AddOrUpdateEntity("API", EntityType.Project, ["HTTP API"]);
        graph.AddOrUpdateEntity(".NET", EntityType.Technology, ["Runtime"]);
        graph.AddOrUpdateEntity("Legacy scoped preference", EntityType.Preference, ["Visible from legacy project scope"]);
        graph.AddRelation("V1", "API", RelationType.DependsOn, "HTTP calls");
        graph.AddRelation("Assistant Framework", "API", RelationType.DependsOn, "HTTP calls");
        graph.AddRelation("V1", ".NET", RelationType.Uses);
        graph.AddRelation("Assistant Framework", ".NET", RelationType.Uses);
        graph.AddRelation("Legacy scoped preference", "V1", RelationType.ScopedTo);

        var result = registry.Execute("memory_context", ParseArgs("""
            {"project": "Assistant Framework"}
            """));

        Assert.False(result.IsError);
        using var document = JsonDocument.Parse(result.Content[0].Text);
        var root = document.RootElement;

        var matchingDependencies = root.GetProperty("dependencies")
            .EnumerateArray()
            .Where(dependency => dependency.GetProperty("project").GetString() == "API")
            .ToList();
        Assert.Single(matchingDependencies);
        Assert.Equal("DependsOn", matchingDependencies[0].GetProperty("relation").GetString());

        Assert.Single(root.GetProperty("technologies").EnumerateArray(), technology =>
            technology.GetString() == ".NET");
        Assert.Contains(root.GetProperty("preferences").EnumerateArray(), preference =>
            preference.GetProperty("name").GetString() == "Legacy scoped preference");
        Assert.Contains(root.GetProperty("equivalentProjectsIncluded").EnumerateArray(), project =>
            project.GetString() == "V1");
    }

    [Fact]
    public void Context_DoesNotIncludeInsightsFromSharedAmbiguousAlias()
    {
        var (graph, registry) = CreateTestSetup();

        graph.AddOrUpdateEntity("ProjectA", EntityType.Project, ["Aliases: shared-name", "Project A"]);
        graph.AddOrUpdateEntity("ProjectB", EntityType.Project, ["Aliases: shared-name", "Project B"]);
        graph.AddOrUpdateEntity("project-b-insight", EntityType.Insight, ["ProjectB-only ambiguous alias insight"]);
        graph.AddRelation("project-b-insight", "ProjectB", RelationType.AppliesTo);

        var result = registry.Execute("memory_context", ParseArgs("""
            {"project": "ProjectA"}
            """));

        Assert.False(result.IsError);
        var text = result.Content[0].Text;
        Assert.Contains("ProjectA", text);
        Assert.DoesNotContain("ProjectB-only ambiguous alias insight", text);
    }

    [Fact]
    public void Context_NormalizesWindowsStylePaths_ForObservedMetadata()
    {
        var (_, registry) = CreateTestSetup();

        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "Assistant Framework", "type": "Project", "observations": ["ProjectPath: C:\\Users\\laimis\\Developer\\Projects\\Assistant\\V1", "AI coding agent enhancement framework"]}
            """));

        var result = registry.Execute("memory_context", ParseArgs("""
            {"path": "C:/Users/laimis/Developer/Projects/Assistant/V1/"}
            """));
        Assert.False(result.IsError);
        var text = result.Content[0].Text;
        Assert.Contains("Assistant Framework", text);
        Assert.Contains("AI coding agent enhancement framework", text);
    }

    [Fact]
    public void Context_AliasIsCaseInsensitive()
    {
        var (_, registry) = CreateTestSetup();

        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "MyProject", "type": "Project", "observations": ["Aliases: my-proj, MYPROJ"]}
            """));

        var result = registry.Execute("memory_context", ParseArgs("""
            {"project": "myproj"}
            """));
        Assert.False(result.IsError);
        Assert.Contains("MyProject", result.Content[0].Text);
    }

    [Fact]
    public void Context_AmbiguousAlias_ReturnsAmbiguousMatches()
    {
        var (_, registry) = CreateTestSetup();

        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "ProjectA", "type": "Project", "observations": ["Aliases: shared-name"]}
            """));
        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "ProjectB", "type": "Project", "observations": ["Aliases: shared-name"]}
            """));

        var result = registry.Execute("memory_context", ParseArgs("""
            {"project": "shared-name"}
            """));
        Assert.False(result.IsError);
        var text = result.Content[0].Text;
        Assert.Contains("Ambiguous alias", text);
        Assert.Contains("ProjectA", text);
        Assert.Contains("ProjectB", text);
    }

    [Fact]
    public void Context_NoAlias_StillReturnsAvailableProjects()
    {
        var (_, registry) = CreateTestSetup();

        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "RealProject", "type": "Project", "observations": ["Aliases: real-proj"]}
            """));

        var result = registry.Execute("memory_context", ParseArgs("""
            {"project": "completely-unknown"}
            """));
        Assert.False(result.IsError);
        var text = result.Content[0].Text;
        Assert.Contains("No project found", text);
        Assert.Contains("RealProject", text);
    }
}
