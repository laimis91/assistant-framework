using MemoryGraph.Storage;

namespace MemoryGraph.Graph;

/// <summary>
/// Knowledge graph facade with CRUD operations.
/// </summary>
public sealed class KnowledgeGraph
{
    private readonly IKnowledgeGraphRepository _repository;

    public KnowledgeGraph(GraphStore store)
        : this(new JsonlKnowledgeGraphRepository(store))
    {
    }

    public KnowledgeGraph(MemoryStore store)
        : this(new SqliteKnowledgeGraphRepository(store))
    {
    }

    private KnowledgeGraph(IKnowledgeGraphRepository repository)
    {
        _repository = repository;
    }

    public int EntityCount => _repository.EntityCount;
    public int RelationCount => _repository.RelationCount;

    // ── Load / Save ────────────────────────────────────────────────

    /// <summary>
    /// Loads the graph from persistent storage.
    /// Returns the number of malformed lines skipped.
    /// </summary>
    public int Load() => _repository.Load();

    /// <summary>
    /// Persists the graph if any changes were made since last save.
    /// </summary>
    public void SaveIfDirty() => _repository.SaveIfDirty();

    // ── Entity operations ──────────────────────────────────────────

    public Entity? GetEntity(string name) => _repository.GetEntity(name);

    public IReadOnlyCollection<Entity> GetAllEntities() => _repository.GetAllEntities();

    public IEnumerable<Entity> GetEntitiesByType(EntityType type) => _repository.GetEntitiesByType(type);

    /// <summary>
    /// Adds a new entity or merges observations into an existing one.
    /// When merging, only observations are added — Type and SourceFile are immutable once set.
    /// Returns (created, newObservationCount).
    /// </summary>
    public (bool Created, int NewObservations) AddOrUpdateEntity(
        string name, EntityType type, List<string> observations, string? sourceFile = null) =>
        _repository.AddOrUpdateEntity(name, type, observations, sourceFile);

    /// <summary>
    /// Removes an entity and all its relations.
    /// Returns the number of relations removed.
    /// </summary>
    public (bool Removed, int RelationsRemoved) RemoveEntity(string name) => _repository.RemoveEntity(name);

    // ── Relation operations ────────────────────────────────────────

    public IReadOnlyList<Relation> GetAllRelations() => _repository.GetAllRelations();

    /// <summary>
    /// Gets all relations where the given entity is the source.
    /// </summary>
    public IEnumerable<Relation> GetRelationsFrom(string name) => _repository.GetRelationsFrom(name);

    /// <summary>
    /// Gets all relations where the given entity is the target.
    /// </summary>
    public IEnumerable<Relation> GetRelationsTo(string name) => _repository.GetRelationsTo(name);

    /// <summary>
    /// Gets all relations involving the given entity (from or to).
    /// </summary>
    public IEnumerable<Relation> GetRelationsFor(string name) => _repository.GetRelationsFor(name);

    /// <summary>
    /// Adds a relation if it doesn't already exist (deduped by from+to+type).
    /// </summary>
    public bool AddRelation(string from, string to, RelationType type, string? detail = null) =>
        _repository.AddRelation(from, to, type, detail);

    /// <summary>
    /// Removes a specific relation by from+to+type.
    /// </summary>
    public bool RemoveRelation(string from, string to, RelationType type) => _repository.RemoveRelation(from, to, type);

    // ── Alias resolution ──────────────────────────────────────────

    /// <summary>
    /// Searches Project entities for an "Aliases:" observation that contains the query.
    /// Returns matching entities (expects 0 or 1 in practice).
    /// </summary>
    public List<Entity> FindByAlias(string alias) => _repository.FindByAlias(alias);

    // ── Search ─────────────────────────────────────────────────────

    /// <summary>
    /// Searches entities by text match against name and observations.
    /// Optionally filters by entity type.
    /// </summary>
    public List<Entity> Search(string query, EntityType[]? types = null) => _repository.Search(query, types);
}
