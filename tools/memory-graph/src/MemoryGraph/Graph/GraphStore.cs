using System.Text.Json;
using System.Text.Json.Serialization;

namespace MemoryGraph.Graph;

/// <summary>
/// Reads and writes the graph to a JSONL file.
/// Each line is a JSON object with a "kind" discriminator ("entity" or "relation").
/// </summary>
public sealed class GraphStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    private readonly string _filePath;

    public GraphStore(string filePath)
    {
        _filePath = filePath;
    }

    /// <summary>
    /// Loads all entities and relations from the JSONL file.
    /// Returns empty collections if the file doesn't exist.
    /// </summary>
    public (List<Entity> Entities, List<Relation> Relations, int SkippedLines) Load()
    {
        var entities = new List<Entity>();
        var relations = new List<Relation>();
        var skipped = 0;

        if (!File.Exists(_filePath))
        {
            return (entities, relations, 0);
        }

        foreach (var line in File.ReadLines(_filePath))
        {
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            try
            {
                using var doc = JsonDocument.Parse(line);
                if (!doc.RootElement.TryGetProperty("kind", out var kindElement))
                {
                    skipped++;
                    continue; // skip records without a kind discriminator
                }

                var kind = kindElement.GetString();

                switch (kind)
                {
                    case "entity":
                        var entity = JsonSerializer.Deserialize<EntityRecord>(line, JsonOptions);
                        if (entity is not null)
                        {
                            entities.Add(entity.ToEntity());
                        }
                        break;

                    case "relation":
                        var relation = JsonSerializer.Deserialize<RelationRecord>(line, JsonOptions);
                        if (relation is not null)
                        {
                            relations.Add(relation.ToRelation());
                        }
                        break;
                }
            }
            catch (Exception)
            {
                skipped++;
                // Skip malformed lines — don't crash on corrupt data
                // Catches JsonException, null fields in deserialized records, etc.
            }
        }

        return (entities, relations, skipped);
    }

    /// <summary>
    /// Saves the entire graph to the JSONL file (full rewrite).
    /// </summary>
    public void Save(IEnumerable<Entity> entities, IEnumerable<Relation> relations)
    {
        var dir = Path.GetDirectoryName(_filePath);
        if (dir is not null && !Directory.Exists(dir))
        {
            Directory.CreateDirectory(dir);
        }

        // Write to temp file then rename for atomic save — avoids corrupt/empty file on crash
        var tempPath = _filePath + ".tmp";

        using (var writer = new StreamWriter(tempPath, append: false))
        {
            foreach (var entity in entities)
            {
                var record = EntityRecord.FromEntity(entity);
                writer.WriteLine(JsonSerializer.Serialize(record, JsonOptions));
            }

            foreach (var relation in relations)
            {
                var record = RelationRecord.FromRelation(relation);
                writer.WriteLine(JsonSerializer.Serialize(record, JsonOptions));
            }
        }

        try
        {
            File.Move(tempPath, _filePath, overwrite: true);
        }
        catch
        {
            // Clean up temp file on failure to avoid accumulating stale files
            try { File.Delete(tempPath); } catch { /* best effort */ }
            throw;
        }
    }

    // ── Serialization records ──────────────────────────────────────

    private sealed record EntityRecord(
        string Kind,
        string Name,
        EntityType Type,
        List<string> Observations,
        string? SourceFile,
        DateTime CreatedAt,
        DateTime UpdatedAt)
    {
        public Entity ToEntity() => new()
        {
            Name = Name,
            Type = Type,
            Observations = Observations ?? [],
            SourceFile = SourceFile,
            CreatedAt = CreatedAt,
            UpdatedAt = UpdatedAt
        };

        public static EntityRecord FromEntity(Entity e) => new(
            Kind: "entity",
            Name: e.Name,
            Type: e.Type,
            Observations: e.Observations,
            SourceFile: e.SourceFile,
            CreatedAt: e.CreatedAt,
            UpdatedAt: e.UpdatedAt);
    }

    private sealed record RelationRecord(
        string Kind,
        string From,
        string To,
        RelationType Type,
        string? Detail,
        DateTime CreatedAt)
    {
        public Relation ToRelation() => new()
        {
            From = From,
            To = To,
            Type = Type,
            Detail = Detail,
            CreatedAt = CreatedAt
        };

        public static RelationRecord FromRelation(Relation r) => new(
            Kind: "relation",
            From: r.From,
            To: r.To,
            Type: r.Type,
            Detail: r.Detail,
            CreatedAt: r.CreatedAt);
    }
}
