namespace MemoryGraph.Graph;

internal interface IKnowledgeGraphRepository
{
    int EntityCount { get; }
    int RelationCount { get; }

    int Load();
    void SaveIfDirty();

    Entity? GetEntity(string name);
    IReadOnlyCollection<Entity> GetAllEntities();
    IEnumerable<Entity> GetEntitiesByType(EntityType type);
    (bool Created, int NewObservations) AddOrUpdateEntity(
        string name,
        EntityType type,
        List<string> observations,
        string? sourceFile = null);
    (bool Removed, int RelationsRemoved) RemoveEntity(string name);

    IReadOnlyList<Relation> GetAllRelations();
    IEnumerable<Relation> GetRelationsFrom(string name);
    IEnumerable<Relation> GetRelationsTo(string name);
    IEnumerable<Relation> GetRelationsFor(string name);
    bool AddRelation(string from, string to, RelationType type, string? detail = null);
    bool RemoveRelation(string from, string to, RelationType type);

    List<Entity> FindByAlias(string alias);
    List<Entity> Search(string query, EntityType[]? types = null);
}
