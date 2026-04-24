namespace MemoryGraph.Graph;

/// <summary>
/// Legacy JSONL-backed graph repository retained for import/fallback support.
/// Runtime graph tools use the SQLite-backed MemoryStore repository.
/// </summary>
internal sealed class JsonlKnowledgeGraphRepository : IKnowledgeGraphRepository
{
    private readonly Dictionary<string, Entity> _entities = new(StringComparer.OrdinalIgnoreCase);
    private readonly List<Relation> _relations = [];
    private readonly GraphStore _store;
    private bool _dirty;

    public JsonlKnowledgeGraphRepository(GraphStore store)
    {
        _store = store;
    }

    public int EntityCount => _entities.Count;
    public int RelationCount => _relations.Count;

    public int Load()
    {
        _entities.Clear();
        _relations.Clear();

        var (entities, relations, skipped) = _store.Load();

        foreach (var entity in entities)
        {
            _entities[entity.Name] = entity;
        }

        foreach (var relation in relations)
        {
            _relations.Add(relation);
        }

        return skipped;
    }

    public void SaveIfDirty()
    {
        if (!_dirty)
        {
            return;
        }

        _store.Save(_entities.Values, _relations);
        _dirty = false;
    }

    public Entity? GetEntity(string name)
    {
        return _entities.TryGetValue(name, out var entity) ? entity : null;
    }

    public IReadOnlyCollection<Entity> GetAllEntities() => _entities.Values;

    public IEnumerable<Entity> GetEntitiesByType(EntityType type)
    {
        return _entities.Values.Where(e => e.Type == type);
    }

    public (bool Created, int NewObservations) AddOrUpdateEntity(
        string name,
        EntityType type,
        List<string> observations,
        string? sourceFile = null)
    {
        if (_entities.TryGetValue(name, out var existing))
        {
            var added = existing.MergeObservations(observations);
            if (added > 0) _dirty = true;
            return (false, added);
        }

        var entity = new Entity
        {
            Name = name,
            Type = type,
            Observations = new List<string>(observations),
            SourceFile = sourceFile
        };

        _entities[name] = entity;
        _dirty = true;
        return (true, observations.Count);
    }

    public (bool Removed, int RelationsRemoved) RemoveEntity(string name)
    {
        if (!_entities.Remove(name))
        {
            return (false, 0);
        }

        var removed = _relations.RemoveAll(r =>
            r.From.Equals(name, StringComparison.OrdinalIgnoreCase) ||
            r.To.Equals(name, StringComparison.OrdinalIgnoreCase));

        _dirty = true;
        return (true, removed);
    }

    public IReadOnlyList<Relation> GetAllRelations() => _relations;

    public IEnumerable<Relation> GetRelationsFrom(string name)
    {
        return _relations.Where(r => r.From.Equals(name, StringComparison.OrdinalIgnoreCase));
    }

    public IEnumerable<Relation> GetRelationsTo(string name)
    {
        return _relations.Where(r => r.To.Equals(name, StringComparison.OrdinalIgnoreCase));
    }

    public IEnumerable<Relation> GetRelationsFor(string name)
    {
        return _relations.Where(r =>
            r.From.Equals(name, StringComparison.OrdinalIgnoreCase) ||
            r.To.Equals(name, StringComparison.OrdinalIgnoreCase));
    }

    public bool AddRelation(string from, string to, RelationType type, string? detail = null)
    {
        var exists = _relations.Any(r =>
            r.From.Equals(from, StringComparison.OrdinalIgnoreCase) &&
            r.To.Equals(to, StringComparison.OrdinalIgnoreCase) &&
            r.Type == type);

        if (exists)
        {
            return false;
        }

        _relations.Add(new Relation
        {
            From = from,
            To = to,
            Type = type,
            Detail = detail
        });

        _dirty = true;
        return true;
    }

    public bool RemoveRelation(string from, string to, RelationType type)
    {
        var index = _relations.FindIndex(r =>
            r.From.Equals(from, StringComparison.OrdinalIgnoreCase) &&
            r.To.Equals(to, StringComparison.OrdinalIgnoreCase) &&
            r.Type == type);

        if (index < 0)
        {
            return false;
        }

        _relations.RemoveAt(index);
        _dirty = true;
        return true;
    }

    public List<Entity> FindByAlias(string alias)
    {
        return KnowledgeGraphQueries.FindByAlias(_entities.Values, alias);
    }

    public List<Entity> Search(string query, EntityType[]? types = null)
    {
        return KnowledgeGraphQueries.Search(_entities.Values, query, types);
    }
}
