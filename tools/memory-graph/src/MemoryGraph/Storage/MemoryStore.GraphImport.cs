using System.Security.Cryptography;
using Microsoft.Data.Sqlite;

namespace MemoryGraph.Storage;

public sealed partial class MemoryStore
{
    public JsonlImportResult ImportGraphJsonl(string filePath)
    {
        var sourcePath = Path.GetFullPath(filePath);
        var fileInfo = new FileInfo(sourcePath);
        if (!fileInfo.Exists)
        {
            throw new FileNotFoundException("Graph JSONL file not found.", sourcePath);
        }

        var fileHash = ComputeSha256(sourcePath);
        var unchanged = GetUnchangedJsonlImport(sourcePath, fileHash, fileInfo.Length);
        if (unchanged is not null)
        {
            unchanged.NoOp = true;
            return unchanged;
        }

        var result = new JsonlImportResult
        {
            SourcePath = sourcePath,
            FileHash = fileHash,
            FileLength = fileInfo.Length
        };

        var stagedImport = JsonlGraphImportReader.Read(sourcePath, result);
        CommitJsonlImport(stagedImport, result);

        return result;
    }

    private void CommitJsonlImport(JsonlImportStage stagedImport, JsonlImportResult result)
    {
        using var transaction = _db.BeginTransaction();
        foreach (var record in stagedImport.EntityRecords)
        {
            ImportEntityRecord(record, result, transaction);
        }

        foreach (var record in stagedImport.RelationRecords)
        {
            ImportRelationRecord(record, result, transaction);
        }

        RecordJsonlImport(result, transaction);
        transaction.Commit();
    }

    private void ImportEntityRecord(JsonlEntityRecord record, JsonlImportResult result, SqliteTransaction transaction)
    {
        var name = record.Name ?? throw new InvalidOperationException("JSONL entity record was not staged correctly.");
        var type = record.Type ?? throw new InvalidOperationException("JSONL entity record was not staged correctly.");

        result.EntitiesRead++;
        var mutation = AddOrUpdateGraphEntityCore(
            name,
            type,
            record.Observations ?? [],
            record.SourceFile,
            record.CreatedAt,
            record.UpdatedAt,
            transaction);

        if (mutation.Created)
        {
            result.EntitiesCreated++;
        }
        else if (mutation.Updated)
        {
            result.EntitiesUpdated++;
        }

        result.ObservationsAdded += mutation.NewObservations;
        var entity = ReadGraphEntityByName(name, transaction);
        if (entity is not null)
        {
            IndexGraphEntity(entity, transaction);
        }
    }

    private void ImportRelationRecord(JsonlRelationRecord record, JsonlImportResult result, SqliteTransaction transaction)
    {
        var from = record.From ?? throw new InvalidOperationException("JSONL relation record was not staged correctly.");
        var to = record.To ?? throw new InvalidOperationException("JSONL relation record was not staged correctly.");
        var type = record.Type ?? throw new InvalidOperationException("JSONL relation record was not staged correctly.");

        result.RelationsRead++;
        switch (AddGraphRelationCore(from, to, type, record.Detail, record.CreatedAt, transaction))
        {
            case GraphRelationMutationResult.Created:
                result.RelationsCreated++;
                break;
            case GraphRelationMutationResult.Deduplicated:
                result.RelationsDeduplicated++;
                break;
            case GraphRelationMutationResult.MissingEndpoint:
                result.RelationsSkipped++;
                break;
        }
    }

    private JsonlImportResult? GetUnchangedJsonlImport(string sourcePath, string fileHash, long fileLength)
    {
        using var cmd = _db.CreateCommand();
        cmd.CommandText = """
            SELECT id, lines_read, skipped_lines, entities_read, entities_created, entities_updated,
                   observations_added, relations_read, relations_created, relations_deduplicated,
                   relations_skipped
            FROM jsonl_imports
            WHERE source_path = @sourcePath COLLATE NOCASE
              AND file_hash = @fileHash
              AND file_length = @fileLength
            """;
        cmd.Parameters.AddWithValue("@sourcePath", sourcePath);
        cmd.Parameters.AddWithValue("@fileHash", fileHash);
        cmd.Parameters.AddWithValue("@fileLength", fileLength);

        using var reader = cmd.ExecuteReader();
        if (!reader.Read())
        {
            return null;
        }

        return new JsonlImportResult
        {
            NoOp = true,
            ImportId = reader.GetInt64(0),
            SourcePath = sourcePath,
            FileHash = fileHash,
            FileLength = fileLength,
            LinesRead = reader.GetInt32(1),
            SkippedLines = reader.GetInt32(2),
            EntitiesRead = reader.GetInt32(3),
            EntitiesCreated = reader.GetInt32(4),
            EntitiesUpdated = reader.GetInt32(5),
            ObservationsAdded = reader.GetInt32(6),
            RelationsRead = reader.GetInt32(7),
            RelationsCreated = reader.GetInt32(8),
            RelationsDeduplicated = reader.GetInt32(9),
            RelationsSkipped = reader.GetInt32(10)
        };
    }

    private void RecordJsonlImport(JsonlImportResult result, SqliteTransaction transaction)
    {
        using var cmd = _db.CreateCommand();
        cmd.Transaction = transaction;
        cmd.CommandText = """
            INSERT INTO jsonl_imports (
                source_path, file_hash, file_length, lines_read, skipped_lines,
                entities_read, entities_created, entities_updated, observations_added,
                relations_read, relations_created, relations_deduplicated, relations_skipped)
            VALUES (
                @sourcePath, @fileHash, @fileLength, @linesRead, @skippedLines,
                @entitiesRead, @entitiesCreated, @entitiesUpdated, @observationsAdded,
                @relationsRead, @relationsCreated, @relationsDeduplicated, @relationsSkipped)
            ON CONFLICT(source_path) DO UPDATE SET
                file_hash = excluded.file_hash,
                file_length = excluded.file_length,
                lines_read = excluded.lines_read,
                skipped_lines = excluded.skipped_lines,
                entities_read = excluded.entities_read,
                entities_created = excluded.entities_created,
                entities_updated = excluded.entities_updated,
                observations_added = excluded.observations_added,
                relations_read = excluded.relations_read,
                relations_created = excluded.relations_created,
                relations_deduplicated = excluded.relations_deduplicated,
                relations_skipped = excluded.relations_skipped,
                imported_at = datetime('now')
            RETURNING id
            """;
        cmd.Parameters.AddWithValue("@sourcePath", result.SourcePath);
        cmd.Parameters.AddWithValue("@fileHash", result.FileHash);
        cmd.Parameters.AddWithValue("@fileLength", result.FileLength);
        cmd.Parameters.AddWithValue("@linesRead", result.LinesRead);
        cmd.Parameters.AddWithValue("@skippedLines", result.SkippedLines);
        cmd.Parameters.AddWithValue("@entitiesRead", result.EntitiesRead);
        cmd.Parameters.AddWithValue("@entitiesCreated", result.EntitiesCreated);
        cmd.Parameters.AddWithValue("@entitiesUpdated", result.EntitiesUpdated);
        cmd.Parameters.AddWithValue("@observationsAdded", result.ObservationsAdded);
        cmd.Parameters.AddWithValue("@relationsRead", result.RelationsRead);
        cmd.Parameters.AddWithValue("@relationsCreated", result.RelationsCreated);
        cmd.Parameters.AddWithValue("@relationsDeduplicated", result.RelationsDeduplicated);
        cmd.Parameters.AddWithValue("@relationsSkipped", result.RelationsSkipped);
        result.ImportId = (long)cmd.ExecuteScalar()!;
    }

    private static string ComputeSha256(string filePath)
    {
        using var stream = File.OpenRead(filePath);
        var bytes = SHA256.HashData(stream);
        return Convert.ToHexString(bytes).ToLowerInvariant();
    }
}
