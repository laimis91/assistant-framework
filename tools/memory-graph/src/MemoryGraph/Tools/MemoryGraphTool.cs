using System.Text.Json;
using MemoryGraph.Graph;
using MemoryGraph.Server;

namespace MemoryGraph.Tools;

/// <summary>
/// memory_graph — return the full graph for debugging and overview.
/// </summary>
public sealed class MemoryGraphTool : IMemoryTool
{
    private readonly KnowledgeGraph _graph;

    public string Name => "memory_graph";

    public MemoryGraphTool(KnowledgeGraph graph)
    {
        _graph = graph;
    }

    public ToolDefinition GetDefinition() => new()
    {
        Name = Name,
        Description = "Return the full knowledge graph: all entities, relations, and statistics. Useful for debugging and getting an overview of what's stored.",
        InputSchema = ToolHelpers.ParseSchema("""
        {
            "type": "object",
            "properties": {}
        }
        """)
    };

    public ToolCallResult Execute(JsonElement arguments)
    {
        var entities = _graph.GetAllEntities().Select(e => new
        {
            e.Name,
            type = e.Type.ToString(),
            e.Observations,
            e.SourceFile,
            createdAt = e.CreatedAt.ToString("o"),
            updatedAt = e.UpdatedAt.ToString("o")
        }).ToList();

        var relations = _graph.GetAllRelations().Select(r => new
        {
            r.From,
            r.To,
            type = r.Type.ToString(),
            r.Detail,
            createdAt = r.CreatedAt.ToString("o")
        }).ToList();

        return ToolHelpers.Success(new
        {
            entities,
            relations,
            stats = new
            {
                entities = _graph.EntityCount,
                relations = _graph.RelationCount
            }
        });
    }
}
