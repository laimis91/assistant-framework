using System.Text.Json;
using MemoryGraph.Server;
using MemoryGraph.Storage;

namespace MemoryGraph.Tools;

/// <summary>
/// memory_decide — Record an architectural or design decision with rationale.
/// Queryable later: "Why did we choose X?"
/// </summary>
public sealed class MemoryDecideTool : IMemoryTool
{
    private readonly MemoryStore _store;

    public string Name => "memory_decide";

    public MemoryDecideTool(MemoryStore store)
    {
        _store = store;
    }

    public ToolDefinition GetDefinition() => new()
    {
        Name = Name,
        Description = "Record a decision with its rationale, alternatives considered, and constraints. " +
                      "Use this to build a decision journal that can be queried later (e.g., 'Why did we choose X?').",
        InputSchema = ToolHelpers.ParseSchema("""
        {
            "type": "object",
            "properties": {
                "title": {
                    "type": "string",
                    "description": "Short title for the decision (e.g., 'Use Redis for caching')"
                },
                "decision": {
                    "type": "string",
                    "description": "What was decided"
                },
                "rationale": {
                    "type": "string",
                    "description": "Why this was chosen"
                },
                "alternatives": {
                    "type": "string",
                    "description": "Other options that were considered and why they were rejected"
                },
                "constraints": {
                    "type": "string",
                    "description": "Constraints that influenced the decision"
                },
                "project": {
                    "type": "string",
                    "description": "Project this decision applies to"
                },
                "tags": {
                    "type": "string",
                    "description": "Comma-separated tags (e.g., 'caching, performance, infrastructure')"
                }
            },
            "required": ["title", "decision", "rationale"]
        }
        """)
    };

    public ToolCallResult Execute(JsonElement arguments)
    {
        var entry = new DecisionEntry
        {
            Title = ToolHelpers.GetRequiredString(arguments, "title"),
            Decision = ToolHelpers.GetRequiredString(arguments, "decision"),
            Rationale = ToolHelpers.GetRequiredString(arguments, "rationale"),
            Alternatives = ToolHelpers.GetString(arguments, "alternatives"),
            Constraints = ToolHelpers.GetString(arguments, "constraints"),
            Project = ToolHelpers.GetString(arguments, "project"),
            Tags = ToolHelpers.GetString(arguments, "tags")
        };

        var id = _store.AddDecision(entry);

        return ToolHelpers.Success(new
        {
            decisionId = id,
            message = $"Decision recorded: '{entry.Title}'"
        });
    }
}
