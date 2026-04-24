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
        registry.Register(new MemoryReflectTool(memoryStore, graph));
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

    // ── Alias Resolution Tests ──────────────────────────────────────────────

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
    public void Reflect_CreatesGraphProjectInsightAndAppliesToRelation()
    {
        var (graph, registry, store) = CreateFullTestSetup();
        using (store)
        {
            var result = registry.Execute("memory_reflect", ParseArgs("""
                {
                    "task": "Fix cache invalidation",
                    "project": "API",
                    "projectType": "dotnet-api",
                    "lessons": ["Always test cache invalidation by project"],
                    "firstAttemptSuccess": true
                }
                """));

            Assert.False(result.IsError);

            var project = graph.GetEntity("API");
            Assert.NotNull(project);
            Assert.Equal(EntityType.Project, project.Type);

            var insight = graph.GetEntitiesByType(EntityType.Insight).Single();
            Assert.Contains("Always test cache invalidation by project", insight.Observations);
            Assert.Contains(graph.GetRelationsFrom(insight.Name), r =>
                r.To == "API" && r.Type == RelationType.AppliesTo);
        }
    }

    [Fact]
    public void Search_DoesNotReturnOrphanFtsEntity()
    {
        var (graph, registry, store) = CreateFullTestSetup();
        using (store)
        {
            graph.AddOrUpdateEntity("RealProject", EntityType.Project, ["real entity"]);
            store.IndexInFts("entity", "OrphanProject", "OrphanProject", "orphan searchable content", "Project");

            var result = registry.Execute("memory_search", ParseArgs("""
                {"query": "orphan"}
                """));

            Assert.False(result.IsError);
            Assert.DoesNotContain("OrphanProject", result.Content[0].Text);
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

    // ── Rule Entity Tests ────────────────────────────────────────────────

    [Fact]
    public void AddEntity_Rule_CreatesWithCorrectType()
    {
        var (graph, registry) = CreateTestSetup();

        var result = registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "Never skip tests", "type": "Rule", "observations": ["Always write tests before moving to next feature"]}
            """));
        Assert.False(result.IsError);
        Assert.Contains("created", result.Content[0].Text);

        var entity = graph.GetEntity("Never skip tests");
        Assert.NotNull(entity);
        Assert.Equal(EntityType.Rule, entity.Type);
        Assert.Contains("Always write tests before moving to next feature", entity.Observations);
    }

    [Fact]
    public void Context_ReturnsRulesInOutput()
    {
        var (_, registry) = CreateTestSetup();

        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "MyApp", "type": "Project", "observations": ["A test project"]}
            """));
        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "No force push", "type": "Rule", "observations": ["Never use git push --force on main"]}
            """));

        var result = registry.Execute("memory_context", ParseArgs("""
            {"project": "MyApp"}
            """));
        Assert.False(result.IsError);

        var text = result.Content[0].Text;
        Assert.Contains("rules", text);
        Assert.Contains("No force push", text);
        Assert.Contains("Never use git push --force on main", text);
    }

    [Fact]
    public void Context_RulesAreGlobal_AppearForAllProjects()
    {
        var (_, registry) = CreateTestSetup();

        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "ProjectAlpha", "type": "Project", "observations": ["First project"]}
            """));
        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "ProjectBeta", "type": "Project", "observations": ["Second project"]}
            """));
        registry.Execute("memory_add_entity", ParseArgs("""
            {"name": "Always use structured logging", "type": "Rule", "observations": ["Use ILogger with message templates, never string interpolation"]}
            """));

        // Rule should appear in context for ProjectAlpha
        var resultAlpha = registry.Execute("memory_context", ParseArgs("""
            {"project": "ProjectAlpha"}
            """));
        Assert.False(resultAlpha.IsError);
        var textAlpha = resultAlpha.Content[0].Text;
        Assert.Contains("Always use structured logging", textAlpha);

        // Same rule should appear in context for ProjectBeta
        var resultBeta = registry.Execute("memory_context", ParseArgs("""
            {"project": "ProjectBeta"}
            """));
        Assert.False(resultBeta.IsError);
        var textBeta = resultBeta.Content[0].Text;
        Assert.Contains("Always use structured logging", textBeta);
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
