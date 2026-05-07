namespace MemoryGraph.Graph;

internal sealed record ProjectResolution(
    Entity? Entity,
    ProjectResolutionFailureKind FailureKind,
    string Query,
    IReadOnlyList<string> AmbiguousMatches,
    string ResolvedBy,
    IReadOnlyList<string> PathCandidates,
    IReadOnlyList<string> LookupCandidates,
    IReadOnlyList<string> Warnings)
{
    public bool IsAmbiguous => AmbiguousMatches.Count > 0;

    public static ProjectResolution Found(
        Entity entity,
        string resolvedBy = "exact",
        string? query = null,
        IReadOnlyList<string>? pathCandidates = null,
        IReadOnlyList<string>? lookupCandidates = null,
        IReadOnlyList<string>? warnings = null) =>
        new(
            entity,
            ProjectResolutionFailureKind.None,
            query ?? entity.Name,
            [],
            resolvedBy,
            pathCandidates ?? [],
            lookupCandidates ?? [],
            warnings ?? []);

    public static ProjectResolution NotFound(
        string query,
        IReadOnlyList<string>? pathCandidates = null,
        IReadOnlyList<string>? lookupCandidates = null,
        IReadOnlyList<string>? warnings = null) =>
        new(
            null,
            ProjectResolutionFailureKind.NotFound,
            query,
            [],
            "notFound",
            pathCandidates ?? [],
            lookupCandidates ?? [],
            warnings ?? []);

    public static ProjectResolution Ambiguous(
        ProjectResolutionFailureKind kind,
        string query,
        IEnumerable<Entity> matches,
        string resolvedBy,
        IReadOnlyList<string>? pathCandidates = null,
        IReadOnlyList<string>? lookupCandidates = null,
        IReadOnlyList<string>? warnings = null)
    {
        var ambiguousMatches = matches.Select(e => e.Name).OrderBy(n => n, StringComparer.OrdinalIgnoreCase).ToList();
        var allWarnings = new List<string>(warnings ?? []);
        allWarnings.Add($"Ambiguous {kind}: '{query}' matched {ambiguousMatches.Count} projects.");

        return new ProjectResolution(
            null,
            kind,
            query,
            ambiguousMatches,
            resolvedBy,
            pathCandidates ?? [],
            lookupCandidates ?? [],
            allWarnings);
    }
}

internal enum ProjectResolutionFailureKind
{
    None,
    NotFound,
    AmbiguousName,
    AmbiguousAlias,
    AmbiguousPath
}
