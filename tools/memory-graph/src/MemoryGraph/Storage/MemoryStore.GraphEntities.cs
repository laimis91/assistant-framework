using MemoryGraph.Graph;
using Microsoft.Data.Sqlite;

namespace MemoryGraph.Storage;

public sealed partial class MemoryStore
{
    public GraphEntityMutationResult AddOrUpdateGraphEntity(
        string name,
        EntityType type,
        IEnumerable<string> observations,
        string? sourceFile = null,
        DateTime? createdAt = null,
        DateTime? updatedAt = null)
    {
        using var transaction = _db.BeginTransaction();
        var result = AddOrUpdateGraphEntityCore(name, type, observations, sourceFile, createdAt, updatedAt, transaction);
        transaction.Commit();

        var entity = GetGraphEntity(name);
        if (entity is not null)
        {
            IndexGraphEntity(entity);
        }

        return result;
    }

    public Entity? GetGraphEntity(string name)
    {
        var id = GetGraphEntityId(name);
        return id is null ? null : ReadGraphEntity(id.Value);
    }

    public List<Entity> GetAllGraphEntities()
    {
        using var cmd = _db.CreateCommand();
        cmd.CommandText = "SELECT id FROM graph_entities ORDER BY name COLLATE NOCASE";

        var ids = new List<long>();
        using (var reader = cmd.ExecuteReader())
        {
            while (reader.Read())
            {
                ids.Add(reader.GetInt64(0));
            }
        }

        return ids.Select(id => ReadGraphEntity(id)).OfType<Entity>().ToList();
    }

    public List<Entity> GetGraphEntitiesByType(EntityType type)
    {
        using var cmd = _db.CreateCommand();
        cmd.CommandText = """
            SELECT id FROM graph_entities
            WHERE type = @type
            ORDER BY name COLLATE NOCASE
            """;
        cmd.Parameters.AddWithValue("@type", type.ToString());

        var ids = new List<long>();
        using (var reader = cmd.ExecuteReader())
        {
            while (reader.Read())
            {
                ids.Add(reader.GetInt64(0));
            }
        }

        return ids.Select(id => ReadGraphEntity(id)).OfType<Entity>().ToList();
    }

    public GraphEntityRemovalResult RemoveGraphEntity(string name)
    {
        using var transaction = _db.BeginTransaction();
        var id = GetGraphEntityId(name, transaction);
        if (id is null)
        {
            transaction.Commit();
            return new GraphEntityRemovalResult { Removed = false, RelationsRemoved = 0 };
        }

        var relationsRemoved = CountGraphRelationsFor(id.Value, transaction);

        using (var deleteCmd = _db.CreateCommand())
        {
            deleteCmd.Transaction = transaction;
            deleteCmd.CommandText = "DELETE FROM graph_entities WHERE id = @id";
            deleteCmd.Parameters.AddWithValue("@id", id.Value);
            deleteCmd.ExecuteNonQuery();
        }

        transaction.Commit();

        using var ftsCmd = _db.CreateCommand();
        ftsCmd.CommandText = "DELETE FROM memory_fts WHERE source_type = 'entity' AND source_id = @name COLLATE NOCASE";
        ftsCmd.Parameters.AddWithValue("@name", name);
        ftsCmd.ExecuteNonQuery();

        return new GraphEntityRemovalResult { Removed = true, RelationsRemoved = relationsRemoved };
    }

    private GraphEntityMutationResult AddOrUpdateGraphEntityCore(
        string name,
        EntityType type,
        IEnumerable<string> observations,
        string? sourceFile,
        DateTime? createdAt,
        DateTime? updatedAt,
        SqliteTransaction transaction)
    {
        var existingId = GetGraphEntityId(name, transaction);
        if (existingId is null)
        {
            using var insertCmd = _db.CreateCommand();
            insertCmd.Transaction = transaction;
            insertCmd.CommandText = """
                INSERT INTO graph_entities (name, type, source_file, created_at, updated_at)
                VALUES (@name, @type, @sourceFile, @createdAt, @updatedAt);
                SELECT last_insert_rowid();
                """;
            insertCmd.Parameters.AddWithValue("@name", name);
            insertCmd.Parameters.AddWithValue("@type", type.ToString());
            insertCmd.Parameters.AddWithValue("@sourceFile", (object?)sourceFile ?? DBNull.Value);
            insertCmd.Parameters.AddWithValue("@createdAt", FormatDate(createdAt ?? DateTime.UtcNow));
            insertCmd.Parameters.AddWithValue("@updatedAt", FormatDate(updatedAt ?? createdAt ?? DateTime.UtcNow));

            var entityId = (long)insertCmd.ExecuteScalar()!;
            var added = AddGraphObservations(entityId, observations, transaction);
            return new GraphEntityMutationResult { Created = true, NewObservations = added };
        }

        var newObservations = AddGraphObservations(existingId.Value, observations, transaction);
        var existingUpdatedAt = GetGraphEntityUpdatedAt(existingId.Value, transaction);
        var nextUpdatedAt = SelectGraphUpdatedAt(existingUpdatedAt, updatedAt, newObservations > 0);
        var timestampChanged = nextUpdatedAt.ToUniversalTime() > existingUpdatedAt.ToUniversalTime();
        var entityChanged = newObservations > 0 || timestampChanged;

        using var updateCmd = _db.CreateCommand();
        updateCmd.Transaction = transaction;
        updateCmd.CommandText = """
            UPDATE graph_entities
            SET updated_at = @updatedAt,
                source_file = COALESCE(source_file, @sourceFile)
            WHERE id = @id
            """;
        updateCmd.Parameters.AddWithValue("@updatedAt", FormatDate(nextUpdatedAt));
        updateCmd.Parameters.AddWithValue("@sourceFile", (object?)sourceFile ?? DBNull.Value);
        updateCmd.Parameters.AddWithValue("@id", existingId.Value);
        updateCmd.ExecuteNonQuery();

        return new GraphEntityMutationResult
        {
            Created = false,
            Updated = entityChanged,
            NewObservations = newObservations
        };
    }

    private static DateTime SelectGraphUpdatedAt(DateTime existingUpdatedAt, DateTime? importedUpdatedAt, bool hasNewObservations)
    {
        if (importedUpdatedAt.HasValue)
        {
            var importedUtc = importedUpdatedAt.Value.ToUniversalTime();
            return importedUtc > existingUpdatedAt.ToUniversalTime()
                ? importedUtc
                : existingUpdatedAt;
        }

        return hasNewObservations
            ? DateTime.UtcNow
            : existingUpdatedAt;
    }

    private int AddGraphObservations(long entityId, IEnumerable<string> observations, SqliteTransaction transaction)
    {
        var added = 0;
        foreach (var observation in observations)
        {
            using var cmd = _db.CreateCommand();
            cmd.Transaction = transaction;
            cmd.CommandText = """
                INSERT OR IGNORE INTO graph_observations (entity_id, observation)
                VALUES (@entityId, @observation)
                """;
            cmd.Parameters.AddWithValue("@entityId", entityId);
            cmd.Parameters.AddWithValue("@observation", observation);
            added += cmd.ExecuteNonQuery();
        }

        return added;
    }

    private long? GetGraphEntityId(string name, SqliteTransaction? transaction = null)
    {
        using var cmd = _db.CreateCommand();
        cmd.Transaction = transaction;
        cmd.CommandText = "SELECT id FROM graph_entities WHERE name = @name COLLATE NOCASE";
        cmd.Parameters.AddWithValue("@name", name);
        var result = cmd.ExecuteScalar();
        return result is null || result == DBNull.Value ? null : Convert.ToInt64(result);
    }

    private DateTime GetGraphEntityUpdatedAt(long id, SqliteTransaction transaction)
    {
        using var cmd = _db.CreateCommand();
        cmd.Transaction = transaction;
        cmd.CommandText = "SELECT updated_at FROM graph_entities WHERE id = @id";
        cmd.Parameters.AddWithValue("@id", id);
        return ParseDate((string)cmd.ExecuteScalar()!);
    }

    private Entity? ReadGraphEntity(long id, SqliteTransaction? transaction = null)
    {
        using var cmd = _db.CreateCommand();
        cmd.Transaction = transaction;
        cmd.CommandText = """
            SELECT name, type, source_file, created_at, updated_at
            FROM graph_entities
            WHERE id = @id
            """;
        cmd.Parameters.AddWithValue("@id", id);

        string name;
        EntityType type;
        string? sourceFile;
        DateTime createdAt;
        DateTime updatedAt;

        using (var reader = cmd.ExecuteReader())
        {
            if (!reader.Read())
            {
                return null;
            }

            name = reader.GetString(0);
            type = Enum.Parse<EntityType>(reader.GetString(1));
            sourceFile = reader.IsDBNull(2) ? null : reader.GetString(2);
            createdAt = ParseDate(reader.GetString(3));
            updatedAt = ParseDate(reader.GetString(4));
        }

        var observations = new List<string>();
        using (var obsCmd = _db.CreateCommand())
        {
            obsCmd.Transaction = transaction;
            obsCmd.CommandText = """
                SELECT observation
                FROM graph_observations
                WHERE entity_id = @id
                ORDER BY id
                """;
            obsCmd.Parameters.AddWithValue("@id", id);

            using var obsReader = obsCmd.ExecuteReader();
            while (obsReader.Read())
            {
                observations.Add(obsReader.GetString(0));
            }
        }

        return new Entity
        {
            Name = name,
            Type = type,
            Observations = observations,
            SourceFile = sourceFile,
            CreatedAt = createdAt,
            UpdatedAt = updatedAt
        };
    }

    private Entity? ReadGraphEntityByName(string name, SqliteTransaction transaction)
    {
        var id = GetGraphEntityId(name, transaction);
        return id is null ? null : ReadGraphEntity(id.Value, transaction);
    }
}
