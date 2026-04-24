using System.Text.Json;
using System.Text.Json.Serialization;
using MemoryGraph.Graph;

namespace MemoryGraph.Storage;

internal static class JsonlGraphImportReader
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase, allowIntegerValues: false) },
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    public static JsonlImportStage Read(string sourcePath, JsonlImportResult result)
    {
        var entityRecords = new List<JsonlEntityRecord>();
        var relationRecords = new List<JsonlRelationRecord>();
        foreach (var line in File.ReadLines(sourcePath))
        {
            StageLine(line, result, entityRecords, relationRecords);
        }

        return new JsonlImportStage(entityRecords, relationRecords);
    }

    private static void StageLine(
        string line,
        JsonlImportResult result,
        List<JsonlEntityRecord> entityRecords,
        List<JsonlRelationRecord> relationRecords)
    {
        if (string.IsNullOrWhiteSpace(line))
        {
            return;
        }

        result.LinesRead++;

        try
        {
            StageRecord(line, result, entityRecords, relationRecords);
        }
        catch (JsonException)
        {
            result.SkippedLines++;
        }
    }

    private static void StageRecord(
        string line,
        JsonlImportResult result,
        List<JsonlEntityRecord> entityRecords,
        List<JsonlRelationRecord> relationRecords)
    {
        using var doc = JsonDocument.Parse(line);
        if (doc.RootElement.ValueKind != JsonValueKind.Object
            || !doc.RootElement.TryGetProperty("kind", out var kindElement)
            || kindElement.ValueKind != JsonValueKind.String)
        {
            result.SkippedLines++;
            return;
        }

        switch (kindElement.GetString())
        {
            case "entity":
                StageEntityRecord(line, doc.RootElement, result, entityRecords);
                break;
            case "relation":
                StageRelationRecord(line, doc.RootElement, result, relationRecords);
                break;
            default:
                result.SkippedLines++;
                break;
        }
    }

    private static void StageEntityRecord(
        string line,
        JsonElement root,
        JsonlImportResult result,
        List<JsonlEntityRecord> entityRecords)
    {
        if (!HasRequiredStringProperty(root, "type")
            || !HasOptionalStringArrayProperty(root, "observations"))
        {
            result.SkippedLines++;
            return;
        }

        var entityRecord = JsonSerializer.Deserialize<JsonlEntityRecord>(line, JsonOptions);
        if (entityRecord?.Name is null || entityRecord.Type is null)
        {
            result.SkippedLines++;
            return;
        }

        entityRecords.Add(entityRecord);
    }

    private static void StageRelationRecord(
        string line,
        JsonElement root,
        JsonlImportResult result,
        List<JsonlRelationRecord> relationRecords)
    {
        if (!HasRequiredStringProperty(root, "type"))
        {
            result.SkippedLines++;
            return;
        }

        var relationRecord = JsonSerializer.Deserialize<JsonlRelationRecord>(line, JsonOptions);
        if (relationRecord?.From is null || relationRecord.To is null || relationRecord.Type is null)
        {
            result.SkippedLines++;
            return;
        }

        relationRecords.Add(relationRecord);
    }

    private static bool HasRequiredStringProperty(JsonElement root, string propertyName)
    {
        return root.TryGetProperty(propertyName, out var property)
            && property.ValueKind == JsonValueKind.String
            && property.GetString() is not null;
    }

    private static bool HasOptionalStringArrayProperty(JsonElement root, string propertyName)
    {
        if (!root.TryGetProperty(propertyName, out var property))
        {
            return true;
        }

        if (property.ValueKind != JsonValueKind.Array)
        {
            return false;
        }

        return property.EnumerateArray()
            .All(item => item.ValueKind == JsonValueKind.String && item.GetString() is not null);
    }
}

internal sealed record JsonlEntityRecord(
    string Kind,
    string? Name,
    EntityType? Type,
    List<string>? Observations,
    string? SourceFile,
    DateTime? CreatedAt,
    DateTime? UpdatedAt);

internal sealed record JsonlRelationRecord(
    string Kind,
    string? From,
    string? To,
    RelationType? Type,
    string? Detail,
    DateTime? CreatedAt);

internal sealed record JsonlImportStage(
    List<JsonlEntityRecord> EntityRecords,
    List<JsonlRelationRecord> RelationRecords);
