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
    private static readonly string[] PathObservationPrefixes =
    [
        "Path:",
        "Paths:",
        "RepoPath:",
        "RepoPaths:",
        "ProjectPath:",
        "ProjectPaths:"
    ];

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
        var originalProjectName = projectName;
        var normalizedPath = NormalizePath(path);

        if (string.IsNullOrEmpty(projectName))
        {
            projectName = BuildPathCandidates(path).FirstOrDefault();
            if (string.IsNullOrEmpty(projectName))
            {
                return ToolHelpers.Error("Either 'project' or 'path' is required");
            }
        }

        var entity = _graph.GetEntity(projectName);
        if (entity is null)
        {
            var candidates = BuildLookupCandidates(projectName, originalProjectName, path).ToList();
            var resolution = ResolveProject(candidates, normalizedPath);
            if (resolution.Entity is null)
            {
                return resolution.ErrorResult!;
            }

            entity = resolution.Entity;
            projectName = entity.Name;
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

    private ResolutionResult ResolveProject(List<string> candidates, string? normalizedPath)
    {
        foreach (var candidate in candidates)
        {
            var exact = _graph.GetEntity(candidate);
            if (exact?.Type == EntityType.Project)
            {
                return new ResolutionResult(exact, null);
            }
        }

        if (!string.IsNullOrEmpty(normalizedPath))
        {
            var exactPathMatch = ResolveByProjectPath(normalizedPath);
            if (exactPathMatch.Entity is not null || exactPathMatch.ErrorResult is not null)
            {
                return exactPathMatch;
            }
        }

        foreach (var candidate in candidates)
        {
            var matches = _graph.GetEntitiesByType(EntityType.Project)
                .Where(e => e.Name.Contains(candidate, StringComparison.OrdinalIgnoreCase))
                .ToList();
            if (matches.Count == 1)
            {
                return new ResolutionResult(matches[0], null);
            }

            if (matches.Count > 1)
            {
                return new ResolutionResult(null, ToolHelpers.Success(new
                {
                    found = false,
                    message = $"Ambiguous project name '{candidate}' — {matches.Count} matches found",
                    ambiguousMatches = matches.Select(e => e.Name).OrderBy(n => n, StringComparer.OrdinalIgnoreCase).ToList()
                }));
            }
        }

        foreach (var candidate in candidates)
        {
            var aliasMatches = _graph.FindByAlias(candidate);
            if (aliasMatches.Count == 1)
            {
                return new ResolutionResult(aliasMatches[0], null);
            }

            if (aliasMatches.Count > 1)
            {
                return new ResolutionResult(null, ToolHelpers.Success(new
                {
                    found = false,
                    message = $"Ambiguous alias '{candidate}' — {aliasMatches.Count} projects match",
                    ambiguousMatches = aliasMatches.Select(e => e.Name).OrderBy(n => n, StringComparer.OrdinalIgnoreCase).ToList()
                }));
            }
        }

        return new ResolutionResult(null, ToolHelpers.Success(new
        {
            found = false,
            message = $"No project found matching '{candidates.First()}'",
            availableProjects = _graph.GetEntitiesByType(EntityType.Project)
                .Select(e => e.Name).OrderBy(n => n, StringComparer.OrdinalIgnoreCase).ToList()
        }));
    }

    private static IEnumerable<string> BuildLookupCandidates(string? projectName, string? originalProjectName, string? path)
    {
        var candidates = new List<string>();
        AddCandidate(candidates, projectName);
        AddCandidate(candidates, originalProjectName);

        foreach (var candidate in BuildPathCandidates(path))
        {
            AddCandidate(candidates, candidate);
        }

        return candidates;
    }

    private static IEnumerable<string> BuildPathCandidates(string? path)
    {
        var normalizedPath = NormalizePath(path);
        if (string.IsNullOrEmpty(normalizedPath))
        {
            return [];
        }

        var candidates = new List<string>();
        AddCandidate(candidates, Path.GetFileName(normalizedPath));

        var parentDirectory = Path.GetDirectoryName(normalizedPath);
        if (!string.IsNullOrEmpty(parentDirectory))
        {
            var parentName = Path.GetFileName(parentDirectory);
            AddCandidate(candidates, parentName);

            var grandParentDirectory = Path.GetDirectoryName(parentDirectory);
            if (!string.IsNullOrEmpty(grandParentDirectory))
            {
                AddCandidate(candidates, Path.Combine(Path.GetFileName(grandParentDirectory), parentName));
            }
        }

        foreach (var segment in normalizedPath.Split(Path.DirectorySeparatorChar, StringSplitOptions.RemoveEmptyEntries))
        {
            AddCandidate(candidates, segment);
        }

        return candidates;
    }

    private ResolutionResult ResolveByProjectPath(string normalizedPath)
    {
        var pathMatches = _graph.GetEntitiesByType(EntityType.Project)
            .Where(e => MatchesProjectPath(e, normalizedPath))
            .ToList();

        if (pathMatches.Count == 1)
        {
            return new ResolutionResult(pathMatches[0], null);
        }

        if (pathMatches.Count > 1)
        {
            return new ResolutionResult(null, ToolHelpers.Success(new
            {
                found = false,
                message = $"Ambiguous project path '{normalizedPath}' — {pathMatches.Count} matches found",
                ambiguousMatches = pathMatches.Select(e => e.Name).OrderBy(n => n, StringComparer.OrdinalIgnoreCase).ToList()
            }));
        }

        return new ResolutionResult(null, null);
    }

    private static bool MatchesProjectPath(Entity entity, string normalizedPath)
    {
        if (!string.IsNullOrEmpty(entity.SourceFile) &&
            PathsEqual(entity.SourceFile, normalizedPath))
        {
            return true;
        }

        foreach (var observation in entity.Observations)
        {
            foreach (var pathValue in ExtractObservedPaths(observation))
            {
                if (PathsEqual(pathValue, normalizedPath))
                {
                    return true;
                }
            }
        }

        return false;
    }

    private static IEnumerable<string> ExtractObservedPaths(string observation)
    {
        foreach (var prefix in PathObservationPrefixes)
        {
            if (!observation.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            foreach (var candidate in observation[prefix.Length..].Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries))
            {
                yield return candidate;
            }
        }
    }

    private static bool PathsEqual(string candidatePath, string targetPath)
    {
        var normalizedCandidate = NormalizePath(candidatePath);
        return !string.IsNullOrEmpty(normalizedCandidate) &&
               normalizedCandidate.Equals(targetPath, StringComparison.OrdinalIgnoreCase);
    }

    private static string? NormalizePath(string? path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return null;
        }

        var normalized = path.Trim()
            .Replace('\\', '/')
            .TrimEnd('/');

        return normalized.Replace('/', Path.DirectorySeparatorChar);
    }

    private static void AddCandidate(List<string> candidates, string? candidate)
    {
        if (string.IsNullOrWhiteSpace(candidate))
        {
            return;
        }

        if (!candidates.Contains(candidate, StringComparer.OrdinalIgnoreCase))
        {
            candidates.Add(candidate);
        }
    }

    private sealed record ResolutionResult(Entity? Entity, ToolCallResult? ErrorResult);
}
