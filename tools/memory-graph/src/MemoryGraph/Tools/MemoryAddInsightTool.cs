using System.Text.Json;
using MemoryGraph.Graph;
using MemoryGraph.Server;

namespace MemoryGraph.Tools;

/// <summary>
/// memory_add_insight — convenience tool to record a learned fact and link it to projects/technologies.
/// Creates an Insight entity and AppliesTo relations automatically.
/// </summary>
public sealed class MemoryAddInsightTool : IMemoryTool
{
    private readonly KnowledgeGraph _graph;

    public string Name => "memory_add_insight";

    public MemoryAddInsightTool(KnowledgeGraph graph)
    {
        _graph = graph;
    }

    public ToolDefinition GetDefinition() => new()
    {
        Name = Name,
        Description = "Record a learned fact or insight and link it to relevant projects or technologies. Creates an Insight entity and AppliesTo relations automatically.",
        InputSchema = ToolHelpers.ParseSchema("""
        {
            "type": "object",
            "properties": {
                "insight": {
                    "type": "string",
                    "description": "The learned fact or insight to record"
                },
                "appliesTo": {
                    "type": "array",
                    "items": { "type": "string" },
                    "description": "Names of projects or technologies this insight applies to"
                },
                "source": {
                    "type": "string",
                    "description": "Optional source identifier (e.g., task name, session ID)"
                }
            },
            "required": ["insight"]
        }
        """)
    };

    public ToolCallResult Execute(JsonElement arguments)
    {
        var insight = ToolHelpers.GetRequiredString(arguments, "insight");
        var appliesTo = ToolHelpers.GetStringArray(arguments, "appliesTo");
        var source = ToolHelpers.GetString(arguments, "source");

        // Generate a unique name from the insight text (hash suffix prevents slug collisions)
        var slug = GenerateSlug(insight);
        // Use a deterministic hash instead of string.GetHashCode() which varies across process invocations
        var hash = DeterministicHash(insight);
        var date = DateTime.UtcNow.ToString("yyyy-MM-dd");
        var name = $"insight-{date}-{slug}-{hash}";

        var observations = new List<string> { insight };
        if (!string.IsNullOrEmpty(source))
        {
            observations.Add($"Source: {source}");
        }

        _graph.AddOrUpdateEntity(name, EntityType.Insight, observations);

        var relationsCreated = 0;
        var skippedTargets = new List<string>();
        foreach (var target in appliesTo)
        {
            if (_graph.GetEntity(target) is null)
            {
                skippedTargets.Add(target);
                continue;
            }

            if (_graph.AddRelation(name, target, RelationType.AppliesTo))
            {
                relationsCreated++;
            }
        }

        _graph.SaveIfDirty();

        return ToolHelpers.Success(new { entity = name, relations = relationsCreated,
            skippedTargets = skippedTargets.Count > 0 ? skippedTargets : null });
    }

    /// <summary>
    /// FNV-1a 32-bit hash — deterministic across process invocations, unlike string.GetHashCode().
    /// </summary>
    private static string DeterministicHash(string text)
    {
        unchecked
        {
            uint hash = 2166136261;
            foreach (var c in text)
            {
                hash ^= c;
                hash *= 16777619;
            }
            return hash.ToString("x8")[..4];
        }
    }

    private static string GenerateSlug(string text)
    {
        // Take first few words, lowercase, replace non-alphanumeric with hyphens
        var words = text.Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .Take(5)
            .Select(w => new string(w.Where(c => char.IsLetterOrDigit(c) || c == '-').ToArray()))
            .Where(w => w.Length > 0)
            .Select(w => w.ToLowerInvariant());

        var slug = string.Join("-", words);
        return slug.Length > 0 ? slug : "unnamed";
    }
}
