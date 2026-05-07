namespace MemoryGraph.Graph;

internal sealed partial class ProjectIdentityResolver
{
    private readonly KnowledgeGraph _graph;

    public ProjectIdentityResolver(KnowledgeGraph graph)
    {
        _graph = graph;
    }

    public ProjectResolution ResolveForContext(string? projectName, string? originalProjectName, string? path)
    {
        var explicitProjectName = NormalizeName(originalProjectName);
        var pathCandidates = BuildPathCandidates(path).ToList();
        var lookupCandidates = BuildLookupCandidates(projectName, originalProjectName, pathCandidates).ToList();
        var normalizedPath = NormalizePath(path);

        if (explicitProjectName is not null)
        {
            var explicitWarnings = BuildExplicitProjectWarnings(normalizedPath, pathCandidates, lookupCandidates);
            var exactExplicitProject = _graph.GetEntity(explicitProjectName);
            if (exactExplicitProject?.Type == EntityType.Project)
            {
                return ProjectResolution.Found(
                    exactExplicitProject,
                    "explicitProject",
                    explicitProjectName,
                    pathCandidates,
                    lookupCandidates,
                    explicitWarnings);
            }

            var explicitAliasMatch = ResolveByAlias(
                explicitProjectName,
                "explicitAlias",
                pathCandidates,
                lookupCandidates,
                explicitWarnings);
            if (explicitAliasMatch.Entity is not null || explicitAliasMatch.IsAmbiguous)
            {
                return explicitAliasMatch;
            }
        }

        if (!string.IsNullOrEmpty(normalizedPath))
        {
            var pathMatch = ResolveByProjectPath(normalizedPath, pathCandidates, lookupCandidates);
            if (pathMatch.Entity is not null || pathMatch.IsAmbiguous)
            {
                return pathMatch;
            }
        }

        var pathCandidateMatch = ResolveByPathCandidatePriority(normalizedPath, pathCandidates, lookupCandidates);
        if (pathCandidateMatch is not null)
        {
            return pathCandidateMatch;
        }

        foreach (var candidate in lookupCandidates)
        {
            var exact = _graph.GetEntity(candidate);
            if (exact?.Type == EntityType.Project)
            {
                var resolvedBy = pathCandidates.Contains(candidate, StringComparer.OrdinalIgnoreCase)
                    ? "pathCandidateExact"
                    : "candidateExact";
                return ProjectResolution.Found(exact, resolvedBy, candidate, pathCandidates, lookupCandidates);
            }
        }

        foreach (var candidate in lookupCandidates)
        {
            var resolvedBy = pathCandidates.Contains(candidate, StringComparer.OrdinalIgnoreCase)
                ? "pathCandidateAlias"
                : "alias";
            var aliasMatch = ResolveByAlias(candidate, resolvedBy, pathCandidates, lookupCandidates);
            if (aliasMatch.Entity is not null || aliasMatch.IsAmbiguous)
            {
                return aliasMatch;
            }
        }

        foreach (var candidate in lookupCandidates)
        {
            var matches = _graph.GetEntitiesByType(EntityType.Project)
                .Where(e => e.Name.Contains(candidate, StringComparison.OrdinalIgnoreCase))
                .ToList();
            if (matches.Count == 1)
            {
                return ProjectResolution.Found(matches[0], "fuzzyFallback", candidate, pathCandidates, lookupCandidates);
            }

            if (matches.Count > 1)
            {
                return ProjectResolution.Ambiguous(
                    ProjectResolutionFailureKind.AmbiguousName,
                    candidate,
                    matches,
                    "fuzzyFallback",
                    pathCandidates,
                    lookupCandidates);
            }
        }

        return ProjectResolution.NotFound(lookupCandidates.FirstOrDefault() ?? "", pathCandidates, lookupCandidates);
    }

    private ProjectResolution? ResolveByPathCandidatePriority(
        string? normalizedPath,
        IReadOnlyList<string> pathCandidates,
        IReadOnlyList<string> lookupCandidates)
    {
        foreach (var candidate in OrderPathCandidatesBySpecificity(normalizedPath, pathCandidates))
        {
            var exact = _graph.GetEntity(candidate);
            if (exact?.Type == EntityType.Project)
            {
                return ProjectResolution.Found(exact, "pathCandidateExact", candidate, pathCandidates, lookupCandidates);
            }

            var aliasMatch = ResolveByAlias(candidate, "pathCandidateAlias", pathCandidates, lookupCandidates);
            if (aliasMatch.Entity is not null || aliasMatch.IsAmbiguous)
            {
                return aliasMatch;
            }
        }

        return null;
    }

    public ProjectResolution ResolveProjectTarget(string target)
    {
        var normalizedTarget = NormalizeName(target);
        if (normalizedTarget is null)
        {
            return ProjectResolution.NotFound(target);
        }

        var exact = _graph.GetEntity(normalizedTarget);
        var aliasMatch = ResolveByAlias(normalizedTarget, "projectTargetAlias", [], []);
        if (aliasMatch.Entity is not null)
        {
            return aliasMatch;
        }

        if (aliasMatch.IsAmbiguous)
        {
            return exact is not null && exact.Type == EntityType.Project
                ? ProjectResolution.Found(exact, "projectTargetExact", normalizedTarget)
                : aliasMatch;
        }

        return exact is not null && exact.Type == EntityType.Project
            ? ProjectResolution.Found(exact, "projectTargetExact", normalizedTarget)
            : ProjectResolution.NotFound(normalizedTarget);
    }

    public string CanonicalizeProjectNameForWrite(string project)
    {
        var normalizedProject = NormalizeName(project);
        if (normalizedProject is null)
        {
            return project;
        }

        var resolution = ResolveProjectTarget(normalizedProject);
        return resolution.Entity?.Name ?? normalizedProject;
    }

    private List<string> BuildExplicitProjectWarnings(
        string? normalizedPath,
        IReadOnlyList<string> pathCandidates,
        IReadOnlyList<string> lookupCandidates)
    {
        var warnings = new List<string>();
        if (string.IsNullOrEmpty(normalizedPath))
        {
            return warnings;
        }

        var pathResolution = ResolveByProjectPath(normalizedPath, pathCandidates, lookupCandidates);
        if (pathResolution.IsAmbiguous)
        {
            warnings.Add($"Path metadata is ambiguous for '{normalizedPath}': {string.Join(", ", pathResolution.AmbiguousMatches)}.");
        }

        return warnings;
    }

    private ProjectResolution ResolveByProjectPath(
        string normalizedPath,
        IReadOnlyList<string> pathCandidates,
        IReadOnlyList<string> lookupCandidates)
    {
        var pathMatches = _graph.GetEntitiesByType(EntityType.Project)
            .Where(e => MatchesProjectPath(e, normalizedPath))
            .ToList();

        if (pathMatches.Count == 1)
        {
            return ProjectResolution.Found(pathMatches[0], "pathMetadata", normalizedPath, pathCandidates, lookupCandidates);
        }

        return pathMatches.Count > 1
            ? ProjectResolution.Ambiguous(
                ProjectResolutionFailureKind.AmbiguousPath,
                normalizedPath,
                pathMatches,
                "pathMetadata",
                pathCandidates,
                lookupCandidates)
            : ProjectResolution.NotFound(normalizedPath, pathCandidates, lookupCandidates);
    }

    private ProjectResolution ResolveByAlias(
        string alias,
        string resolvedBy,
        IReadOnlyList<string> pathCandidates,
        IReadOnlyList<string> lookupCandidates,
        IReadOnlyList<string>? warnings = null)
    {
        var aliasMatches = _graph.FindByAlias(alias);
        if (aliasMatches.Count == 1)
        {
            return ProjectResolution.Found(aliasMatches[0], resolvedBy, alias, pathCandidates, lookupCandidates, warnings);
        }

        return aliasMatches.Count > 1
            ? ProjectResolution.Ambiguous(
                ProjectResolutionFailureKind.AmbiguousAlias,
                alias,
                aliasMatches,
                resolvedBy,
                pathCandidates,
                lookupCandidates,
                warnings)
            : ProjectResolution.NotFound(alias, pathCandidates, lookupCandidates, warnings);
    }
}
