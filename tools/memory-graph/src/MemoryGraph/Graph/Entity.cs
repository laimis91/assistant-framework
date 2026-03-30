namespace MemoryGraph.Graph;

/// <summary>
/// Types of entities in the knowledge graph.
/// </summary>
public enum EntityType
{
    Project,      // a codebase / repository
    Technology,   // framework, library, tool (EF Core, WPF, ASP.NET Core)
    Pattern,      // architectural decision (Clean Architecture, CQRS, guard clauses)
    Preference,   // user coding preference (var usage, naming style)
    Insight,      // learned fact from a past session
    Convention,   // project-specific convention (test naming, folder structure)
    Rule          // behavioral mandate or correction (always enforced, highest priority)
}

/// <summary>
/// A node in the knowledge graph representing a concept, project, or fact.
/// </summary>
public sealed class Entity
{
    public required string Name { get; init; }
    public required EntityType Type { get; init; }
    public List<string> Observations { get; init; } = [];
    public string? SourceFile { get; init; }
    public DateTime CreatedAt { get; init; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Merges new observations into this entity, returning count of new ones added.
    /// </summary>
    public int MergeObservations(IEnumerable<string> newObservations)
    {
        var added = 0;
        foreach (var obs in newObservations)
        {
            if (!Observations.Contains(obs, StringComparer.OrdinalIgnoreCase))
            {
                Observations.Add(obs);
                added++;
            }
        }

        if (added > 0)
        {
            UpdatedAt = DateTime.UtcNow;
        }

        return added;
    }
}
