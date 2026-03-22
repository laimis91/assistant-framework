namespace MemoryGraph.Graph;

/// <summary>
/// Types of relationships between entities.
/// </summary>
public enum RelationType
{
    // Project relationships
    DependsOn,      // Project A depends on Project B (API calls, shared libs)
    ManagedBy,      // Project A is managed/configured by Project B
    SharedWith,     // Projects share a component (shared DB, common lib)

    // Project <-> Technology
    Uses,           // Project uses Technology

    // Project <-> Pattern
    Follows,        // Project follows Pattern

    // Project <-> Convention
    HasConvention,  // Project has Convention

    // Insight <-> Project/Technology
    AppliesTo,      // Insight applies to Project or Technology

    // Preference scope
    ScopedTo        // Preference scoped to Project (vs global)
}

/// <summary>
/// A directed edge in the knowledge graph connecting two entities.
/// </summary>
public sealed class Relation
{
    public required string From { get; init; }
    public required string To { get; init; }
    public required RelationType Type { get; init; }
    public string? Detail { get; init; }
    public DateTime CreatedAt { get; init; } = DateTime.UtcNow;
}
