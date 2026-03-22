using System.Text.Json;
using MemoryGraph.Graph;
using MemoryGraph.Server;
using MemoryGraph.Storage;

namespace MemoryGraph.Tools;

/// <summary>
/// memory_stats — Dashboard showing memory system health: counts, calibration accuracy, staleness.
/// </summary>
public sealed class MemoryStatsTool : IMemoryTool
{
    private readonly KnowledgeGraph _graph;
    private readonly MemoryStore _store;

    public string Name => "memory_stats";

    public MemoryStatsTool(KnowledgeGraph graph, MemoryStore store)
    {
        _graph = graph;
        _store = store;
    }

    public ToolDefinition GetDefinition() => new()
    {
        Name = Name,
        Description = "Get memory system statistics: entity/relation counts, reflexion count, strategy lessons, " +
                      "calibration accuracy, and FTS index size. Useful for monitoring memory health.",
        InputSchema = ToolHelpers.ParseSchema("""
        {
            "type": "object",
            "properties": {
                "projectType": {
                    "type": "string",
                    "description": "Optional: filter calibration stats to a specific project type"
                }
            }
        }
        """)
    };

    public ToolCallResult Execute(JsonElement arguments)
    {
        var projectType = ToolHelpers.GetString(arguments, "projectType");

        var storeStats = _store.GetStats();
        var calibration = _store.GetCalibrationStats(projectType);

        var calibrationSummary = calibration.ByType.ToDictionary(
            kv => kv.Key,
            kv => new { kv.Value.Total, kv.Value.Accurate, accuracyRate = $"{kv.Value.AccuracyRate:P0}" }
        );

        return ToolHelpers.Success(new
        {
            graph = new
            {
                entities = _graph.EntityCount,
                relations = _graph.RelationCount
            },
            memory = new
            {
                storeStats.Reflexions,
                storeStats.Decisions,
                storeStats.StrategyLessons,
                storeStats.CalibrationEntries,
                storeStats.FtsEntries
            },
            calibration = calibrationSummary.Count > 0 ? calibrationSummary : null
        });
    }
}
