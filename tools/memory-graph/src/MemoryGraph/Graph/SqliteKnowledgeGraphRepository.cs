using MemoryGraph.Storage;

namespace MemoryGraph.Graph;

/// <summary>
/// SQLite-backed graph repository used by the additive DB-authoritative bridge.
/// </summary>
internal sealed class SqliteKnowledgeGraphRepository : IKnowledgeGraphRepository
{
    private readonly MemoryStore _store;

    public SqliteKnowledgeGraphRepository(MemoryStore store)
    {
        _store = store;
    }

    public int EntityCount => _store.GetAllGraphEntities().Count;
    public int RelationCount => _store.GetAllGraphRelations().Count;

    public int Load() => 0;

    public void SaveIfDirty()
    {
        // MemoryStore graph operations persist immediately.
    }

    public Entity? GetEntity(string name) => _store.GetGraphEntity(name);

    public IReadOnlyCollection<Entity> GetAllEntities() => _store.GetAllGraphEntities();

    public IEnumerable<Entity> GetEntitiesByType(EntityType type) => _store.GetGraphEntitiesByType(type);

    public (bool Created, int NewObservations) AddOrUpdateEntity(
        string name,
        EntityType type,
        List<string> observations,
        string? sourceFile = null)
    {
        var result = _store.AddOrUpdateGraphEntity(name, type, observations, sourceFile);
        return (result.Created, result.NewObservations);
    }

    public (bool Removed, int RelationsRemoved) RemoveEntity(string name)
    {
        var result = _store.RemoveGraphEntity(name);
        return (result.Removed, result.RelationsRemoved);
    }

    public IReadOnlyList<Relation> GetAllRelations() => _store.GetAllGraphRelations();

    public IEnumerable<Relation> GetRelationsFrom(string name) => _store.GetGraphRelationsFrom(name);

    public IEnumerable<Relation> GetRelationsTo(string name) => _store.GetGraphRelationsTo(name);

    public IEnumerable<Relation> GetRelationsFor(string name) => _store.GetGraphRelationsFor(name);

    public bool AddRelation(string from, string to, RelationType type, string? detail = null)
    {
        if (_store.GetGraphEntity(from) is null || _store.GetGraphEntity(to) is null)
        {
            return false;
        }

        return _store.AddGraphRelation(from, to, type, detail);
    }

    public bool RemoveRelation(string from, string to, RelationType type) => _store.RemoveGraphRelation(from, to, type);

    public List<Entity> FindByAlias(string alias)
    {
        return KnowledgeGraphQueries.FindByAlias(_store.GetAllGraphEntities(), alias);
    }

    public List<Entity> Search(string query, EntityType[]? types = null)
    {
        return KnowledgeGraphQueries.Search(_store.GetAllGraphEntities(), query, types);
    }
}
