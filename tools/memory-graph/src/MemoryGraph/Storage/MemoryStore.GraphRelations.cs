using MemoryGraph.Graph;
using Microsoft.Data.Sqlite;

namespace MemoryGraph.Storage;

public sealed partial class MemoryStore
{
    public bool AddGraphRelation(string from, string to, RelationType type, string? detail = null, DateTime? createdAt = null)
    {
        using var transaction = _db.BeginTransaction();
        var fromId = GetGraphEntityId(from, transaction);
        if (fromId is null)
        {
            throw new KeyNotFoundException($"Entity not found: '{from}'. Create it first with memory_add_entity.");
        }

        var toId = GetGraphEntityId(to, transaction);
        if (toId is null)
        {
            throw new KeyNotFoundException($"Entity not found: '{to}'. Create it first with memory_add_entity.");
        }

        using var cmd = _db.CreateCommand();
        cmd.Transaction = transaction;
        cmd.CommandText = """
            INSERT OR IGNORE INTO graph_relations (from_entity_id, to_entity_id, type, detail, created_at)
            VALUES (@from, @to, @type, @detail, @createdAt)
            """;
        cmd.Parameters.AddWithValue("@from", fromId.Value);
        cmd.Parameters.AddWithValue("@to", toId.Value);
        cmd.Parameters.AddWithValue("@type", type.ToString());
        cmd.Parameters.AddWithValue("@detail", (object?)detail ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@createdAt", FormatDate(createdAt ?? DateTime.UtcNow));
        var added = cmd.ExecuteNonQuery() > 0;

        transaction.Commit();
        return added;
    }

    public bool RemoveGraphRelation(string from, string to, RelationType type)
    {
        using var transaction = _db.BeginTransaction();
        var fromId = GetGraphEntityId(from, transaction);
        var toId = GetGraphEntityId(to, transaction);
        if (fromId is null || toId is null)
        {
            transaction.Commit();
            return false;
        }

        using var cmd = _db.CreateCommand();
        cmd.Transaction = transaction;
        cmd.CommandText = """
            DELETE FROM graph_relations
            WHERE from_entity_id = @from AND to_entity_id = @to AND type = @type
            """;
        cmd.Parameters.AddWithValue("@from", fromId.Value);
        cmd.Parameters.AddWithValue("@to", toId.Value);
        cmd.Parameters.AddWithValue("@type", type.ToString());
        var removed = cmd.ExecuteNonQuery() > 0;

        transaction.Commit();
        return removed;
    }

    public List<Relation> GetAllGraphRelations()
    {
        using var cmd = _db.CreateCommand();
        cmd.CommandText = """
            SELECT f.name, t.name, r.type, r.detail, r.created_at
            FROM graph_relations r
            JOIN graph_entities f ON f.id = r.from_entity_id
            JOIN graph_entities t ON t.id = r.to_entity_id
            ORDER BY f.name COLLATE NOCASE, t.name COLLATE NOCASE, r.type
            """;
        return ReadGraphRelations(cmd);
    }

    public List<Relation> GetGraphRelationsFrom(string name)
    {
        using var cmd = _db.CreateCommand();
        cmd.CommandText = """
            SELECT f.name, t.name, r.type, r.detail, r.created_at
            FROM graph_relations r
            JOIN graph_entities f ON f.id = r.from_entity_id
            JOIN graph_entities t ON t.id = r.to_entity_id
            WHERE f.name = @name COLLATE NOCASE
            ORDER BY t.name COLLATE NOCASE, r.type
            """;
        cmd.Parameters.AddWithValue("@name", name);
        return ReadGraphRelations(cmd);
    }

    public List<Relation> GetGraphRelationsTo(string name)
    {
        using var cmd = _db.CreateCommand();
        cmd.CommandText = """
            SELECT f.name, t.name, r.type, r.detail, r.created_at
            FROM graph_relations r
            JOIN graph_entities f ON f.id = r.from_entity_id
            JOIN graph_entities t ON t.id = r.to_entity_id
            WHERE t.name = @name COLLATE NOCASE
            ORDER BY f.name COLLATE NOCASE, r.type
            """;
        cmd.Parameters.AddWithValue("@name", name);
        return ReadGraphRelations(cmd);
    }

    public List<Relation> GetGraphRelationsFor(string name)
    {
        using var cmd = _db.CreateCommand();
        cmd.CommandText = """
            SELECT f.name, t.name, r.type, r.detail, r.created_at
            FROM graph_relations r
            JOIN graph_entities f ON f.id = r.from_entity_id
            JOIN graph_entities t ON t.id = r.to_entity_id
            WHERE f.name = @name COLLATE NOCASE OR t.name = @name COLLATE NOCASE
            ORDER BY f.name COLLATE NOCASE, t.name COLLATE NOCASE, r.type
            """;
        cmd.Parameters.AddWithValue("@name", name);
        return ReadGraphRelations(cmd);
    }

    private int CountGraphRelationsFor(long entityId, SqliteTransaction transaction)
    {
        using var cmd = _db.CreateCommand();
        cmd.Transaction = transaction;
        cmd.CommandText = """
            SELECT COUNT(*)
            FROM graph_relations
            WHERE from_entity_id = @id OR to_entity_id = @id
            """;
        cmd.Parameters.AddWithValue("@id", entityId);
        return Convert.ToInt32(cmd.ExecuteScalar());
    }

    private List<Relation> ReadGraphRelations(SqliteCommand cmd)
    {
        var results = new List<Relation>();
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            results.Add(new Relation
            {
                From = reader.GetString(0),
                To = reader.GetString(1),
                Type = Enum.Parse<RelationType>(reader.GetString(2)),
                Detail = reader.IsDBNull(3) ? null : reader.GetString(3),
                CreatedAt = ParseDate(reader.GetString(4))
            });
        }

        return results;
    }

    private GraphRelationMutationResult AddGraphRelationCore(
        string from,
        string to,
        RelationType type,
        string? detail,
        DateTime? createdAt,
        SqliteTransaction transaction)
    {
        var fromId = GetGraphEntityId(from, transaction);
        var toId = GetGraphEntityId(to, transaction);
        if (fromId is null || toId is null)
        {
            return GraphRelationMutationResult.MissingEndpoint;
        }

        using var cmd = _db.CreateCommand();
        cmd.Transaction = transaction;
        cmd.CommandText = """
            INSERT OR IGNORE INTO graph_relations (from_entity_id, to_entity_id, type, detail, created_at)
            VALUES (@from, @to, @type, @detail, @createdAt)
            """;
        cmd.Parameters.AddWithValue("@from", fromId.Value);
        cmd.Parameters.AddWithValue("@to", toId.Value);
        cmd.Parameters.AddWithValue("@type", type.ToString());
        cmd.Parameters.AddWithValue("@detail", (object?)detail ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@createdAt", FormatDate(createdAt ?? DateTime.UtcNow));

        return cmd.ExecuteNonQuery() > 0
            ? GraphRelationMutationResult.Created
            : GraphRelationMutationResult.Deduplicated;
    }

    private enum GraphRelationMutationResult
    {
        Created,
        Deduplicated,
        MissingEndpoint
    }
}
