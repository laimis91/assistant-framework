namespace MemoryGraph.Graph;

/// <summary>
/// In-memory knowledge graph with CRUD operations.
/// Thread-safe for single-threaded MCP server usage (stdio is sequential).
/// </summary>
public sealed class KnowledgeGraph
{
    private readonly Dictionary<string, Entity> _entities = new(StringComparer.OrdinalIgnoreCase);
    private readonly List<Relation> _relations = [];
    private readonly GraphStore _store;
    private bool _dirty;

    public KnowledgeGraph(GraphStore store)
    {
        _store = store;
    }

    public int EntityCount => _entities.Count;
    public int RelationCount => _relations.Count;

    // ── Load / Save ────────────────────────────────────────────────

    /// <summary>
    /// Loads the graph from persistent storage.
    /// Returns the number of malformed lines skipped.
    /// </summary>
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

    /// <summary>
    /// Persists the graph if any changes were made since last save.
    /// </summary>
    public void SaveIfDirty()
    {
        if (!_dirty)
        {
            return;
        }

        _store.Save(_entities.Values, _relations);
        _dirty = false;
    }

    // ── Entity operations ──────────────────────────────────────────

    public Entity? GetEntity(string name)
    {
        return _entities.TryGetValue(name, out var entity) ? entity : null;
    }

    public IReadOnlyCollection<Entity> GetAllEntities() => _entities.Values;

    public IEnumerable<Entity> GetEntitiesByType(EntityType type)
    {
        return _entities.Values.Where(e => e.Type == type);
    }

    /// <summary>
    /// Adds a new entity or merges observations into an existing one.
    /// When merging, only observations are added — Type and SourceFile are immutable once set.
    /// Returns (created, newObservationCount).
    /// </summary>
    public (bool Created, int NewObservations) AddOrUpdateEntity(
        string name, EntityType type, List<string> observations, string? sourceFile = null)
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

    /// <summary>
    /// Removes an entity and all its relations.
    /// Returns the number of relations removed.
    /// </summary>
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

    // ── Relation operations ────────────────────────────────────────

    public IReadOnlyList<Relation> GetAllRelations() => _relations;

    /// <summary>
    /// Gets all relations where the given entity is the source.
    /// </summary>
    public IEnumerable<Relation> GetRelationsFrom(string name)
    {
        return _relations.Where(r => r.From.Equals(name, StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>
    /// Gets all relations where the given entity is the target.
    /// </summary>
    public IEnumerable<Relation> GetRelationsTo(string name)
    {
        return _relations.Where(r => r.To.Equals(name, StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>
    /// Gets all relations involving the given entity (from or to).
    /// </summary>
    public IEnumerable<Relation> GetRelationsFor(string name)
    {
        return _relations.Where(r =>
            r.From.Equals(name, StringComparison.OrdinalIgnoreCase) ||
            r.To.Equals(name, StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>
    /// Adds a relation if it doesn't already exist (deduped by from+to+type).
    /// </summary>
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

    /// <summary>
    /// Removes a specific relation by from+to+type.
    /// </summary>
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

    // ── Search ─────────────────────────────────────────────────────

    /// <summary>
    /// Searches entities by text match against name and observations.
    /// Optionally filters by entity type.
    /// </summary>
    public List<Entity> Search(string query, EntityType[]? types = null)
    {
        var results = new List<Entity>();

        foreach (var entity in _entities.Values)
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
