using System.Text.Json;
using MemoryGraph.Graph;
using MemoryGraph.Server;

namespace MemoryGraph.Tools;

/// <summary>
/// memory_add_relation — connect two entities with a typed relationship.
/// Deduplicates by (from, to, type).
/// </summary>
public sealed class MemoryAddRelationTool : IMemoryTool
{
    private readonly KnowledgeGraph _graph;

    public string Name => "memory_add_relation";

    public MemoryAddRelationTool(KnowledgeGraph graph)
    {
        _graph = graph;
    }

    public ToolDefinition GetDefinition() => new()
    {
        Name = Name,
        Description = "Create a relationship between two entities. Duplicates (same from, to, and type) are ignored.",
        InputSchema = ToolHelpers.ParseSchema("""
        {
            "type": "object",
            "properties": {
                "from": {
                    "type": "string",
                    "description": "Source entity name"
                },
                "to": {
                    "type": "string",
                    "description": "Target entity name"
                },
                "type": {
                    "type": "string",
                    "description": "Relation type: DependsOn, ManagedBy, SharedWith, Uses, Follows, HasConvention, AppliesTo, ScopedTo"
                },
                "detail": {
                    "type": "string",
                    "description": "Optional context about this relationship"
                }
            },
            "required": ["from", "to", "type"]
        }
        """)
    };

    public ToolCallResult Execute(JsonElement arguments)
    {
        var from = ToolHelpers.GetRequiredString(arguments, "from");
        var to = ToolHelpers.GetRequiredString(arguments, "to");
        var typeName = ToolHelpers.GetRequiredString(arguments, "type");
        var detail = ToolHelpers.GetString(arguments, "detail");

        if (!Enum.TryParse<RelationType>(typeName, ignoreCase: true, out var relationType))
        {
            return ToolHelpers.Error($"Invalid relation type: {typeName}. Valid types: {string.Join(", ", Enum.GetNames<RelationType>())}");
        }

        if (_graph.GetEntity(from) is null)
        {
            return ToolHelpers.Error($"Entity not found: '{from}'. Create it first with memory_add_entity.");
        }

        if (_graph.GetEntity(to) is null)
        {
            return ToolHelpers.Error($"Entity not found: '{to}'. Create it first with memory_add_entity.");
        }

        var created = _graph.AddRelation(from, to, relationType, detail);
        _graph.SaveIfDirty();

        return created
            ? ToolHelpers.Success(new { created = true })
            : ToolHelpers.Success(new { exists = true });
    }
}
