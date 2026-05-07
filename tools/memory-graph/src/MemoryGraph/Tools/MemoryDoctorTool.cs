using System.Text.Json;
using MemoryGraph.Graph;
using MemoryGraph.Server;
using MemoryGraph.Storage;

namespace MemoryGraph.Tools;

/// <summary>
/// memory_doctor - read-only diagnostics for graph identity, relations, FTS, and runtime metadata.
/// </summary>
public sealed partial class MemoryDoctorTool : IMemoryTool
{
    private readonly KnowledgeGraph _graph;
    private readonly MemoryStore? _store;
    private readonly string? _memoryDir;
    private readonly MemoryGraphStartupMetrics? _startupMetrics;

    public string Name => "memory_doctor";

    public MemoryDoctorTool(
        KnowledgeGraph graph,
        MemoryStore? store = null,
        string? memoryDir = null,
        MemoryGraphStartupMetrics? startupMetrics = null)
    {
        _graph = graph;
        _store = store;
        _memoryDir = memoryDir;
        _startupMetrics = startupMetrics;
    }

    public ToolDefinition GetDefinition() => new()
    {
        Name = Name,
        Description = "Read-only memory system diagnostics: project identity, aliases, paths, relations, FTS health, and runtime metadata.",
        InputSchema = ToolHelpers.ParseSchema("""
        {
            "type": "object",
            "properties": {}
        }
        """)
    };

    public ToolCallResult Execute(JsonElement arguments)
    {
        var warnings = new List<string>();
        var entities = _graph.GetAllEntities().ToList();
        var projects = entities.Where(e => e.Type == EntityType.Project).ToList();
        var relations = _graph.GetAllRelations().ToList();

        var projectNameSet = projects
            .Select(p => p.Name)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var splitProjectCandidates = FindSplitProjectCandidates(projects, projectNameSet);
        var duplicateAliases = FindDuplicateAliases(projects);
        var duplicatePaths = FindDuplicatePaths(projects);
        var danglingRelations = FindDanglingRelations(relations, entities);
        var selfRelations = relations
            .Where(r => r.From.Equals(r.To, StringComparison.OrdinalIgnoreCase))
            .Select(r => new RelationIssue(r.From, r.To, r.Type.ToString(), "selfRelation"))
            .ToList();

        var storeStats = GetStoreStats(warnings);
        var ftsDiagnostics = GetFtsDiagnostics(entities, warnings);
        AddLocalStoreWarnings(warnings, entities.Count, relations.Count, storeStats, ftsDiagnostics);

        var ftsIssueCount = ftsDiagnostics?.StaleEntityRows ?? 0;
        var issueCount = splitProjectCandidates.Count +
                         duplicateAliases.Count +
                         duplicatePaths.Count +
                         danglingRelations.Count +
                         selfRelations.Count +
                         ftsIssueCount;
        var runtime = BuildRuntime(ftsDiagnostics, warnings);
        var warningCount = warnings.Count;

        return ToolHelpers.Success(new
        {
            summary = new
            {
                status = issueCount == 0
                    ? (warningCount == 0 ? "ok" : "warnings")
                    : "issuesFound",
                readOnly = true,
                issueCount,
                warningCount
            },
            counts = new
            {
                entities = entities.Count,
                projects = projects.Count,
                relations = relations.Count,
                memory = storeStats is null
                    ? null
                    : new
                    {
                        storeStats.Reflexions,
                        storeStats.Decisions,
                        storeStats.StrategyLessons,
                        storeStats.CalibrationEntries,
                        storeStats.FtsEntries
                    }
            },
            projectIssues = new
            {
                splitProjectCandidateCount = splitProjectCandidates.Count,
                splitProjectCandidates
            },
            aliasIssues = new
            {
                duplicateAliasCount = duplicateAliases.Count,
                duplicateAliases,
                aliasesMatchingProjectNames = splitProjectCandidates
            },
            pathIssues = new
            {
                duplicatePathCount = duplicatePaths.Count,
                duplicatePaths
            },
            relationIssues = new
            {
                danglingRelationCount = danglingRelations.Count,
                danglingRelations,
                selfRelationCount = selfRelations.Count,
                selfRelations
            },
            ftsIssues = BuildFtsIssues(ftsDiagnostics),
            runtime,
            warnings
        });
    }

}
