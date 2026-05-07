using MemoryGraph.Graph;

namespace MemoryGraph.Tools;

public sealed partial class MemoryDoctorTool
{
    private static List<ProjectAliasIssue> FindSplitProjectCandidates(List<Entity> projects, HashSet<string> projectNameSet)
    {
        return projects
            .SelectMany(project => ProjectIdentityResolver.GetAliases(project)
                .Where(alias => projectNameSet.Contains(alias) &&
                                !project.Name.Equals(alias, StringComparison.OrdinalIgnoreCase))
                .Select(alias => new ProjectAliasIssue(project.Name, alias, alias)))
            .OrderBy(issue => issue.Project, StringComparer.OrdinalIgnoreCase)
            .ThenBy(issue => issue.Alias, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    private static List<DuplicateAliasIssue> FindDuplicateAliases(List<Entity> projects)
    {
        return projects
            .SelectMany(project => ProjectIdentityResolver.GetAliases(project)
                .Select(alias => new { Project = project.Name, Alias = alias }))
            .GroupBy(entry => entry.Alias, StringComparer.OrdinalIgnoreCase)
            .Select(group => new DuplicateAliasIssue(
                group.Key,
                group.Select(entry => entry.Project)
                    .Distinct(StringComparer.OrdinalIgnoreCase)
                    .OrderBy(project => project, StringComparer.OrdinalIgnoreCase)
                    .ToList()))
            .Where(issue => issue.Projects.Count > 1)
            .OrderBy(issue => issue.Alias, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    private static List<DuplicatePathIssue> FindDuplicatePaths(List<Entity> projects)
    {
        return projects
            .SelectMany(project => ProjectIdentityResolver.GetObservedPaths(project)
                .Select(ProjectIdentityResolver.NormalizePath)
                .Where(path => !string.IsNullOrEmpty(path))
                .Select(path => path!)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .Select(path => new { Project = project.Name, Path = path }))
            .GroupBy(entry => entry.Path, StringComparer.OrdinalIgnoreCase)
            .Select(group => new DuplicatePathIssue(
                group.Key,
                group.Select(entry => entry.Project)
                    .Distinct(StringComparer.OrdinalIgnoreCase)
                    .OrderBy(project => project, StringComparer.OrdinalIgnoreCase)
                    .ToList()))
            .Where(issue => issue.Projects.Count > 1)
            .OrderBy(issue => issue.Path, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    private sealed record ProjectAliasIssue(string Project, string Alias, string MatchingProject);
    private sealed record DuplicateAliasIssue(string Alias, IReadOnlyList<string> Projects);
    private sealed record DuplicatePathIssue(string Path, IReadOnlyList<string> Projects);
}
