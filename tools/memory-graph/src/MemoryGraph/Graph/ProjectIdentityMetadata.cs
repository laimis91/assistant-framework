namespace MemoryGraph.Graph;

internal sealed partial class ProjectIdentityResolver
{
    private const string AliasObservationPrefix = "Aliases:";

    private static readonly string[] PathObservationPrefixes =
    [
        "Path:",
        "Paths:",
        "RepoPath:",
        "RepoPaths:",
        "ProjectPath:",
        "ProjectPaths:"
    ];

    public static IEnumerable<string> BuildPathCandidates(string? path)
    {
        var normalizedPath = NormalizePath(path);
        if (string.IsNullOrEmpty(normalizedPath))
        {
            return [];
        }

        var candidates = new List<string>();
        var leafName = Path.GetFileName(normalizedPath);
        AddCandidate(candidates, leafName);

        var parentDirectory = Path.GetDirectoryName(normalizedPath);
        if (!string.IsNullOrEmpty(parentDirectory))
        {
            var parentName = Path.GetFileName(parentDirectory);
            AddCandidate(candidates, parentName);
            AddSlashCandidate(candidates, parentName, leafName);

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

    public static List<Entity> FindProjectsByAlias(IEnumerable<Entity> entities, string alias)
    {
        var normalizedAlias = NormalizeName(alias);
        if (normalizedAlias is null)
        {
            return [];
        }

        return entities
            .Where(e => e.Type == EntityType.Project)
            .Where(e => GetAliases(e).Any(a => a.Equals(normalizedAlias, StringComparison.OrdinalIgnoreCase)))
            .ToList();
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

    public static IEnumerable<string> GetObservedPaths(Entity entity)
    {
        if (!string.IsNullOrEmpty(entity.SourceFile))
        {
            yield return entity.SourceFile;
        }

        foreach (var observation in entity.Observations)
        {
            foreach (var path in ExtractObservedPaths(observation))
            {
                yield return path;
            }
        }
    }

    public static IEnumerable<string> ExtractObservedPaths(string observation)
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

    public static IReadOnlyList<string> GetAliases(Entity entity)
    {
        var aliases = new List<string>();
        foreach (var observation in entity.Observations)
        {
            if (!observation.StartsWith(AliasObservationPrefix, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            aliases.AddRange(observation[AliasObservationPrefix.Length..]
                .Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries));
        }

        return aliases;
    }

    private static bool PathsEqual(string candidatePath, string targetPath)
    {
        var normalizedCandidate = NormalizePath(candidatePath);
        return !string.IsNullOrEmpty(normalizedCandidate) &&
               normalizedCandidate.Equals(targetPath, StringComparison.OrdinalIgnoreCase);
    }

    public static string? NormalizePath(string? path)
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

    private static string? NormalizeName(string? value)
    {
        return string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    }

    private static IEnumerable<string> BuildLookupCandidates(
        string? projectName,
        string? originalProjectName,
        IReadOnlyList<string> pathCandidates)
    {
        var candidates = new List<string>();
        AddCandidate(candidates, projectName);
        AddCandidate(candidates, originalProjectName);

        foreach (var candidate in pathCandidates)
        {
            AddCandidate(candidates, candidate);
        }

        return candidates;
    }

    private static IEnumerable<string> OrderPathCandidatesBySpecificity(
        string? normalizedPath,
        IReadOnlyList<string> pathCandidates)
    {
        var candidates = new List<string>();
        if (!string.IsNullOrEmpty(normalizedPath))
        {
            var leafName = Path.GetFileName(normalizedPath);
            var parentDirectory = Path.GetDirectoryName(normalizedPath);
            if (!string.IsNullOrEmpty(parentDirectory))
            {
                AddSlashCandidate(candidates, Path.GetFileName(parentDirectory), leafName);
            }
        }

        foreach (var candidate in pathCandidates)
        {
            AddCandidate(candidates, candidate);
        }

        return candidates;
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

    private static void AddSlashCandidate(List<string> candidates, string? parentName, string? leafName)
    {
        if (string.IsNullOrWhiteSpace(parentName) || string.IsNullOrWhiteSpace(leafName))
        {
            return;
        }

        AddCandidate(candidates, $"{parentName}/{leafName}");
    }
}
