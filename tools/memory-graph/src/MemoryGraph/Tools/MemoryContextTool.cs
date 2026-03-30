using System.Text.Json;
using MemoryGraph.Graph;
using MemoryGraph.Server;

namespace MemoryGraph.Tools;

/// <summary>
/// memory_context — returns everything relevant for a given project.
/// The primary tool for session-start context injection.
/// </summary>
public sealed class MemoryContextTool : IMemoryTool
{
    private readonly KnowledgeGraph _graph;

    public string Name => "memory_context";

    public MemoryContextTool(KnowledgeGraph graph)
    {
        _graph = graph;
    }

    public ToolDefinition GetDefinition() => new()
    {
        Name = Name,
        Description = "Get all relevant context for a project: dependencies, technologies, patterns, conventions, preferences, rules, and recent insights. Use at session start or when switching projects.",
        InputSchema = ToolHelpers.ParseSchema("""
        {
            "type": "object",
            "properties": {
                "project": {
                    "type": "string",
                    "description": "Project name to get context for"
                },
                "path": {
                    "type": "string",
                    "description": "Project path (used to auto-detect project name if project is not specified)"
                }
            }
        }
        """)
    };

    public ToolCallResult Execute(JsonElement arguments)
    {
        var projectName = ToolHelpers.GetString(arguments, "project");
        var path = ToolHelpers.GetString(arguments, "path");

        // Auto-detect project name from path
        if (string.IsNullOrEmpty(projectName) && !string.IsNullOrEmpty(path))
        {
            projectName = Path.GetFileName(path.TrimEnd(Path.DirectorySeparatorChar));
        }

        if (string.IsNullOrEmpty(projectName))
        {
            return ToolHelpers.Error("Either 'project' or 'path' is required");
        }

        var entity = _graph.GetEntity(projectName);
        if (entity is null)
        {
            // Try fuzzy match — name-only to avoid false matches on observations
            var matches = _graph.GetEntitiesByType(EntityType.Project)
                .Where(e => e.Name.Contains(projectName, StringComparison.OrdinalIgnoreCase))
                .ToList();
            if (matches.Count == 1)
            {
                entity = matches[0];
                projectName = entity.Name;
            }
            else if (matches.Count > 1)
            {
                return ToolHelpers.Success(new
                {
                    found = false,
                    message = $"Ambiguous project name '{projectName}' — {matches.Count} matches found",
                    ambiguousMatches = matches.Select(e => e.Name).OrderBy(n => n, StringComparer.OrdinalIgnoreCase).ToList()
                });
            }
            else
            {
                // Try alias resolution — search "Aliases:" observations in Project entities
                var aliasMatches = _graph.FindByAlias(projectName);
                if (aliasMatches.Count == 1)
                {
                    entity = aliasMatches[0];
                    projectName = entity.Name;
                }
                else if (aliasMatches.Count > 1)
                {
                    return ToolHelpers.Success(new
                    {
                        found = false,
                        message = $"Ambiguous alias '{projectName}' — {aliasMatches.Count} projects match",
                        ambiguousMatches = aliasMatches.Select(e => e.Name).OrderBy(n => n, StringComparer.OrdinalIgnoreCase).ToList()
                    });
                }
                else
                {
                    return ToolHelpers.Success(new
                    {
                        found = false,
                        message = $"No project found matching '{projectName}'",
                        availableProjects = _graph.GetEntitiesByType(EntityType.Project)
                            .Select(e => e.Name).OrderBy(n => n, StringComparer.OrdinalIgnoreCase).ToList()
                    });
                }
            }
        }

        // Gather all related context
        var relationsFrom = _graph.GetRelationsFrom(projectName).ToList();
        var relationsTo = _graph.GetRelationsTo(projectName).ToList();

        var dependencies = relationsFrom
            .Where(r => r.Type is RelationType.DependsOn or RelationType.SharedWith)
            .Select(r => new { project = r.To, relation = r.Type.ToString(), detail = r.Detail })
            .ToList();

        var dependedOnBy = relationsTo
            .Where(r => r.Type is RelationType.DependsOn or RelationType.SharedWith)
            .Select(r => new { project = r.From, relation = r.Type.ToString(), detail = r.Detail })
            .ToList();

        var managedBy = relationsFrom
            .Where(r => r.Type == RelationType.ManagedBy)
            .Select(r => new { project = r.To, detail = r.Detail })
            .ToList();

        var technologies = relationsFrom
            .Where(r => r.Type == RelationType.Uses)
            .Select(r => r.To)
            .ToList();

        var patterns = relationsFrom
            .Where(r => r.Type == RelationType.Follows)
            .Select(r => r.To)
            .ToList();

        var conventions = relationsFrom
            .Where(r => r.Type == RelationType.HasConvention)
            .Select(r =>
            {
                var conv = _graph.GetEntity(r.To);
                return new { name = r.To, observations = conv?.Observations ?? [] };
            })
            .ToList();

        // Build relation lookups once to avoid O(N*R) per-entity scans
        var allRelations = _graph.GetAllRelations();

        var scopedToLookup = allRelations
            .Where(r => r.Type == RelationType.ScopedTo)
            .GroupBy(r => r.From, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(g => g.Key, g => g.Select(r => r.To).ToList(), StringComparer.OrdinalIgnoreCase);

        var appliesToLookup = allRelations
            .Where(r => r.Type == RelationType.AppliesTo)
            .GroupBy(r => r.From, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(g => g.Key, g => g.Select(r => r.To).ToList(), StringComparer.OrdinalIgnoreCase);

        // Get preferences: global (unscoped) + scoped to this project
        var preferences = _graph.GetEntitiesByType(EntityType.Preference)
            .Where(p =>
            {
                if (!scopedToLookup.TryGetValue(p.Name, out var scoped) || scoped.Count == 0)
                {
                    return true; // Global preference (no ScopedTo relations)
                }

                return scoped.Any(t => t.Equals(projectName, StringComparison.OrdinalIgnoreCase));
            })
            .Select(p => new { name = p.Name, observations = p.Observations })
            .ToList();

        // Get rules: always global, always returned (behavioral mandates)
        var rules = _graph.GetEntitiesByType(EntityType.Rule)
            .Select(r => new { name = r.Name, observations = r.Observations })
            .ToList();

        // Recent insights that apply to this project
        var insights = _graph.GetEntitiesByType(EntityType.Insight)
            .Where(i => appliesToLookup.TryGetValue(i.Name, out var targets) &&
                        targets.Any(t => t.Equals(projectName, StringComparison.OrdinalIgnoreCase)))
            .OrderByDescending(i => i.CreatedAt)
            .Take(10)
            .Select(i => new { name = i.Name, observations = i.Observations, date = i.CreatedAt.ToString("yyyy-MM-dd") })
            .ToList();

        // Also include insights that apply to any of the project's technologies
        var insightNames = new HashSet<string>(insights.Select(i => i.name), StringComparer.OrdinalIgnoreCase);
        var techInsights = _graph.GetEntitiesByType(EntityType.Insight)
            .Where(i => appliesToLookup.TryGetValue(i.Name, out var targets) &&
                        targets.Any(t => technologies.Contains(t, StringComparer.OrdinalIgnoreCase)))
            .Where(i => !insightNames.Contains(i.Name)) // avoid duplicates (case-insensitive)
            .OrderByDescending(i => i.CreatedAt)
            .Take(5)
            .Select(i => new { name = i.Name, observations = i.Observations, date = i.CreatedAt.ToString("yyyy-MM-dd") })
            .ToList();

        return ToolHelpers.Success(new
        {
            project = new { entity.Name, type = entity.Type.ToString(), entity.Observations },
            dependencies,
            dependedOnBy,
            managedBy,
            technologies,
            patterns,
            conventions,
            preferences,
            rules,
            recentInsights = insights.Concat(techInsights).ToList()
        });
    }
}
