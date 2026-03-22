using System.Text.Json;
using MemoryGraph.Graph;
using MemoryGraph.Server;

namespace MemoryGraph.Tools;

/// <summary>
/// memory_remove_entity — delete an entity and all its relations.
/// </summary>
public sealed class MemoryRemoveEntityTool : IMemoryTool
{
    private readonly KnowledgeGraph _graph;

    public string Name => "memory_remove_entity";

    public MemoryRemoveEntityTool(KnowledgeGraph graph)
    {
        _graph = graph;
    }

    public ToolDefinition GetDefinition() => new()
    {
        Name = Name,
        Description = "Remove an entity and all its relations from the knowledge graph.",
        InputSchema = ToolHelpers.ParseSchema("""
        {
            "type": "object",
            "properties": {
                "name": {
                    "type": "string",
                    "description": "Name of the entity to remove"
                }
            },
            "required": ["name"]
        }
        """)
    };

    public ToolCallResult Execute(JsonElement arguments)
    {
        var name = ToolHelpers.GetRequiredString(arguments, "name");

        var (removed, relationsRemoved) = _graph.RemoveEntity(name);
        _graph.SaveIfDirty();

        if (!removed)
        {
            return ToolHelpers.Error($"Entity not found: {name}");
        }

        return ToolHelpers.Success(new { removed = true, relationsRemoved });
    }
}

/// <summary>
/// memory_remove_relation — delete a specific relation by from+to+type.
/// </summary>
public sealed class MemoryRemoveRelationTool : IMemoryTool
{
    private readonly KnowledgeGraph _graph;

    public string Name => "memory_remove_relation";

    public MemoryRemoveRelationTool(KnowledgeGraph graph)
    {
        _graph = graph;
    }

    public ToolDefinition GetDefinition() => new()
    {
        Name = Name,
        Description = "Remove a specific relationship between two entities.",
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
                    "description": "Relation type to remove"
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

        if (!Enum.TryParse<RelationType>(typeName, ignoreCase: true, out var relationType))
        {
            return ToolHelpers.Error($"Invalid relation type: {typeName}");
        }

        var removed = _graph.RemoveRelation(from, to, relationType);
        _graph.SaveIfDirty();

        return removed
            ? ToolHelpers.Success(new { removed = true })
            : ToolHelpers.Error($"Relation not found: {from} -> {to} ({typeName})");
    }
}
