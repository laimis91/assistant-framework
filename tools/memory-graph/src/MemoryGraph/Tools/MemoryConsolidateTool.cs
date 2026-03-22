using System.Text.Json;
using MemoryGraph.Server;
using MemoryGraph.Storage;

namespace MemoryGraph.Tools;

/// <summary>
/// memory_consolidate — Trigger memory consolidation: decay stale lessons, archive low-confidence ones.
/// </summary>
public sealed class MemoryConsolidateTool : IMemoryTool
{
    private readonly MemoryStore _store;

    public string Name => "memory_consolidate";

    public MemoryConsolidateTool(MemoryStore store)
    {
        _store = store;
    }

    public ToolDefinition GetDefinition() => new()
    {
        Name = Name,
        Description = "Trigger memory consolidation. Decays strategy lessons not reinforced in 90+ days " +
                      "and archives (deletes) lessons with very low confidence. " +
                      "Call periodically to keep memory clean and relevant.",
        InputSchema = ToolHelpers.ParseSchema("""
        {
            "type": "object",
            "properties": {},
            "additionalProperties": false
        }
        """)
    };

    public ToolCallResult Execute(JsonElement arguments)
    {
        var (decayed, archived) = _store.ConsolidateStrategyLessons();

        return ToolHelpers.Success(new
        {
            decayed,
            archived,
            message = $"Consolidation complete: {decayed} lessons decayed, {archived} archived"
        });
    }
}
