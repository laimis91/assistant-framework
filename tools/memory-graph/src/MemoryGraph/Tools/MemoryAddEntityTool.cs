using System.Text.Json;
using MemoryGraph.Graph;
using MemoryGraph.Server;

namespace MemoryGraph.Tools;

/// <summary>
/// memory_add_entity — create or update an entity in the knowledge graph.
/// If the entity exists, new observations are merged (deduped).
/// </summary>
public sealed class MemoryAddEntityTool : IMemoryTool
{
    private readonly KnowledgeGraph _graph;

    public string Name => "memory_add_entity";

    public MemoryAddEntityTool(KnowledgeGraph graph)
    {
        _graph = graph;
    }

    public ToolDefinition GetDefinition() => new()
    {
        Name = Name,
        Description = "Create a new entity or add observations to an existing one. Observations are atomic facts about the entity. Duplicate observations are ignored.",
        InputSchema = ToolHelpers.ParseSchema("""
        {
            "type": "object",
            "properties": {
                "name": {
                    "type": "string",
                    "description": "Entity name (unique identifier)"
                },
                "type": {
                    "type": "string",
                    "description": "Entity type: Project, Technology, Pattern, Preference, Insight, Convention, Rule"
                },
                "observations": {
                    "type": "array",
                    "items": { "type": "string" },
                    "description": "Atomic facts about this entity"
                }
            },
            "required": ["name", "type", "observations"]
        }
        """)
    };

    public ToolCallResult Execute(JsonElement arguments)
    {
        var name = ToolHelpers.GetRequiredString(arguments, "name");
        var typeName = ToolHelpers.GetRequiredString(arguments, "type");
        var observations = ToolHelpers.GetStringArray(arguments, "observations");

        if (!Enum.TryParse<EntityType>(typeName, ignoreCase: true, out var entityType))
        {
            return ToolHelpers.Error($"Invalid entity type: {typeName}. Valid types: {string.Join(", ", Enum.GetNames<EntityType>())}");
        }

        var (created, newObservations) = _graph.AddOrUpdateEntity(name, entityType, observations);
        _graph.SaveIfDirty();

        if (created)
        {
            return ToolHelpers.Success(new { created = true });
        }

        return ToolHelpers.Success(new { updated = true, newObservations });
    }
}
