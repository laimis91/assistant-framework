using System.Text.Json;
using MemoryGraph.Server;

namespace MemoryGraph.Tools;

/// <summary>
/// Shared helpers for building tool definitions and results.
/// </summary>
internal static class ToolHelpers
{
    private static readonly JsonSerializerOptions SerializeOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = false,
        DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull
    };

    /// <summary>
    /// Parses an input schema from a JSON string.
    /// </summary>
    public static JsonElement ParseSchema(string json)
    {
        using var doc = JsonDocument.Parse(json);
        return doc.RootElement.Clone();
    }

    /// <summary>
    /// Creates a successful tool result with JSON content.
    /// </summary>
    public static ToolCallResult Success(object result)
    {
        var json = JsonSerializer.Serialize(result, SerializeOptions);
        return new ToolCallResult
        {
            Content = [new ToolContent { Text = json }]
        };
    }

    /// <summary>
    /// Creates an error tool result.
    /// </summary>
    public static ToolCallResult Error(string message)
    {
        return new ToolCallResult
        {
            Content = [new ToolContent { Text = message }],
            IsError = true
        };
    }

    /// <summary>
    /// Gets an optional string property from arguments.
    /// </summary>
    public static string? GetString(JsonElement args, string property)
    {
        return args.TryGetProperty(property, out var value) ? value.GetString() : null;
    }

    /// <summary>
    /// Gets a required string property from arguments.
    /// </summary>
    public static string GetRequiredString(JsonElement args, string property)
    {
        return GetString(args, property)
            ?? throw new ArgumentException($"Missing required parameter: {property}");
    }

    /// <summary>
    /// Gets an optional string array from arguments.
    /// </summary>
    public static List<string> GetStringArray(JsonElement args, string property)
    {
        if (!args.TryGetProperty(property, out var value) || value.ValueKind != JsonValueKind.Array)
        {
            return [];
        }

        return value.EnumerateArray()
            .Select(e => e.GetString())
            .Where(s => s is not null)
            .Cast<string>()
            .ToList();
    }

}
