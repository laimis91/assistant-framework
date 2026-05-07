using System.Text.Json;
using MemoryGraph.Graph;
using Xunit;

namespace MemoryGraph.Tests;

public sealed class MemoryDoctorToolIntegrationTests : ToolIntegrationTestBase
{
    [Fact]
    public void Doctor_ReportsProjectAliasAndFtsIssues()
    {
        var (graph, registry, store) = CreateFullTestSetup();
        using (store)
        {
            graph.AddOrUpdateEntity(
                "Assistant Framework",
                EntityType.Project,
                ["Aliases: V1", "ProjectPath: /repo/Assistant/V1", "Canonical project"]);
            graph.AddOrUpdateEntity("V1", EntityType.Project, ["ProjectPath: /repo/Assistant/V1", "Legacy duplicate project"]);
            store.IndexInFts("entity", "OrphanProject", "OrphanProject", "doctor orphan searchable content", "Project");

            var result = registry.Execute("memory_doctor", ParseArgs("{}"));

            Assert.False(result.IsError);
            using var document = JsonDocument.Parse(result.Content[0].Text);
            var root = document.RootElement;
            Assert.Equal("issuesFound", root.GetProperty("summary").GetProperty("status").GetString());
            Assert.Equal(1, root.GetProperty("projectIssues").GetProperty("splitProjectCandidateCount").GetInt32());
            Assert.Equal(1, root.GetProperty("pathIssues").GetProperty("duplicatePathCount").GetInt32());
            Assert.Equal(1, root.GetProperty("ftsIssues").GetProperty("staleEntityRows").GetInt32());
            Assert.Contains("OrphanProject", result.Content[0].Text);
        }
    }

    [Fact]
    public void Doctor_DoesNotMutateGraphOrFts()
    {
        var (graph, registry, store) = CreateFullTestSetup();
        using (store)
        {
            graph.AddOrUpdateEntity("RealProject", EntityType.Project, ["real entity"]);
            store.IndexInFts("entity", "OrphanProject", "OrphanProject", "doctor mutate orphan", "Project");
            var beforeEntities = graph.EntityCount;
            var beforeRelations = graph.RelationCount;
            var beforeFtsEntries = store.GetStats().FtsEntries;
            var beforeStaleRows = store.CountStaleGraphEntityFtsRows(graph.GetAllEntities().Select(e => e.Name));

            var result = registry.Execute("memory_doctor", ParseArgs("{}"));

            Assert.False(result.IsError);
            Assert.Equal(beforeEntities, graph.EntityCount);
            Assert.Equal(beforeRelations, graph.RelationCount);
            Assert.Equal(beforeFtsEntries, store.GetStats().FtsEntries);
            Assert.Equal(beforeStaleRows, store.CountStaleGraphEntityFtsRows(graph.GetAllEntities().Select(e => e.Name)));
        }
    }

    [Fact]
    public void Doctor_ReturnsRuntimeMetadata()
    {
        var (_, registry, store) = CreateFullTestSetup();
        using (store)
        {
            var result = registry.Execute("memory_doctor", ParseArgs("{}"));

            Assert.False(result.IsError);
            using var document = JsonDocument.Parse(result.Content[0].Text);
            var root = document.RootElement;
            Assert.True(root.GetProperty("summary").GetProperty("readOnly").GetBoolean());
            Assert.True(root.GetProperty("runtime").TryGetProperty("freshness", out var freshness));
            Assert.NotEqual(JsonValueKind.Undefined, freshness.GetProperty("status").ValueKind);
        }
    }

    [Fact]
    public void Doctor_ReturnsAllDiagnosticSections()
    {
        var (_, registry, store) = CreateFullTestSetup();
        using (store)
        {
            var result = registry.Execute("memory_doctor", ParseArgs("{}"));

            Assert.False(result.IsError);
            using var document = JsonDocument.Parse(result.Content[0].Text);
            var root = document.RootElement;
            Assert.True(root.TryGetProperty("summary", out _));
            Assert.True(root.TryGetProperty("counts", out _));
            Assert.True(root.TryGetProperty("projectIssues", out _));
            Assert.True(root.TryGetProperty("aliasIssues", out _));
            Assert.True(root.TryGetProperty("pathIssues", out _));
            Assert.True(root.TryGetProperty("relationIssues", out _));
            Assert.True(root.TryGetProperty("ftsIssues", out _));
            Assert.True(root.TryGetProperty("runtime", out _));
            Assert.True(root.TryGetProperty("warnings", out _));
        }
    }
}
