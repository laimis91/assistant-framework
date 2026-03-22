using System.Text.Json;
using MemoryGraph.Server;
using MemoryGraph.Storage;

namespace MemoryGraph.Tools;

/// <summary>
/// memory_pattern — Record a recurring pattern observed in a project type.
/// Patterns are stored as strategy lessons and reinforced when re-observed.
/// </summary>
public sealed class MemoryPatternTool : IMemoryTool
{
    private readonly MemoryStore _store;

    public string Name => "memory_pattern";

    public MemoryPatternTool(MemoryStore store)
    {
        _store = store;
    }

    public ToolDefinition GetDefinition() => new()
    {
        Name = Name,
        Description = "Record a recurring pattern observed in a project type. " +
                      "If the pattern already exists, it gets reinforced (confidence increases). " +
                      "Patterns are recalled during the Discover phase of future tasks.",
        InputSchema = ToolHelpers.ParseSchema("""
        {
            "type": "object",
            "properties": {
                "projectType": {
                    "type": "string",
                    "description": "Project type where this pattern was observed (e.g., dotnet-api, blazor, unity)"
                },
                "phase": {
                    "type": "string",
                    "description": "Which workflow phase this pattern applies to (discover, plan, build, review, general)"
                },
                "pattern": {
                    "type": "string",
                    "description": "The pattern observed (e.g., 'Services in this project always implement IDisposable')"
                },
                "confidence": {
                    "type": "number",
                    "description": "Initial confidence 0.0-1.0 (default: 0.5). Use 1.0 for confirmed patterns, 0.3 for tentative."
                }
            },
            "required": ["projectType", "phase", "pattern"]
        }
        """)
    };

    public ToolCallResult Execute(JsonElement arguments)
    {
        var projectType = ToolHelpers.GetRequiredString(arguments, "projectType");
        var phase = ToolHelpers.GetRequiredString(arguments, "phase");
        var pattern = ToolHelpers.GetRequiredString(arguments, "pattern");

        var confidence = 0.5;
        if (arguments.TryGetProperty("confidence", out var confEl))
        {
            confidence = confEl.GetDouble();
        }

        var id = _store.AddStrategyLesson(new StrategyLesson
        {
            ProjectType = projectType,
            Phase = phase,
            Lesson = pattern,
            Confidence = confidence
        });

        // Check if it was reinforced vs new
        var lessons = _store.GetStrategyLessons(projectType, phase);
        var lesson = lessons.FirstOrDefault(l => l.Id == id);
        var reinforced = lesson is not null && lesson.ReinforcementCount > 1;

        return ToolHelpers.Success(new
        {
            lessonId = id,
            reinforced,
            confidence = lesson?.Confidence ?? confidence,
            reinforcementCount = lesson?.ReinforcementCount ?? 1,
            message = reinforced
                ? $"Pattern reinforced (confidence: {lesson!.Confidence:F1}, seen {lesson.ReinforcementCount}x)"
                : $"New pattern recorded for {projectType}/{phase}"
        });
    }
}
