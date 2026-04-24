namespace MemoryGraph.Graph;

internal static class KnowledgeGraphQueries
{
    public static List<Entity> FindByAlias(IEnumerable<Entity> entities, string alias)
    {
        const string prefix = "Aliases:";
        var results = new List<Entity>();

        foreach (var entity in entities)
        {
            if (entity.Type != EntityType.Project)
            {
                continue;
            }

            foreach (var obs in entity.Observations)
            {
                if (!obs.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                var aliasList = obs[prefix.Length..].Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
                if (aliasList.Any(a => a.Equals(alias, StringComparison.OrdinalIgnoreCase)))
                {
                    results.Add(entity);
                    break;
                }
            }
        }

        return results;
    }

    public static List<Entity> Search(IEnumerable<Entity> entities, string query, EntityType[]? types = null)
    {
        var results = new List<Entity>();

        foreach (var entity in entities)
        {
            if (types is not null && !types.Contains(entity.Type))
            {
                continue;
            }

            if (entity.Name.Contains(query, StringComparison.OrdinalIgnoreCase))
            {
                results.Add(entity);
                continue;
            }

            if (entity.Observations.Any(o => o.Contains(query, StringComparison.OrdinalIgnoreCase)))
            {
                results.Add(entity);
            }
        }

        return results;
    }
}
