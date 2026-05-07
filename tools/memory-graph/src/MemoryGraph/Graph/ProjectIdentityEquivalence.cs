namespace MemoryGraph.Graph;

internal sealed partial class ProjectIdentityResolver
{
    public HashSet<string> GetEquivalentProjectNames(Entity project)
    {
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { project.Name };

        foreach (var candidate in _graph.GetEntitiesByType(EntityType.Project))
        {
            if (candidate.Name.Equals(project.Name, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            if (HasUnambiguousDirectAlias(project, candidate) ||
                HasUnambiguousDirectAlias(candidate, project))
            {
                names.Add(candidate.Name);
            }
        }

        return names;
    }

    private bool HasUnambiguousDirectAlias(Entity aliasOwner, Entity namedProject)
    {
        if (!GetAliases(aliasOwner).Any(a => a.Equals(namedProject.Name, StringComparison.OrdinalIgnoreCase)))
        {
            return false;
        }

        var matches = _graph.FindByAlias(namedProject.Name);
        return matches.Count == 1 &&
               matches[0].Name.Equals(aliasOwner.Name, StringComparison.OrdinalIgnoreCase);
    }
}
