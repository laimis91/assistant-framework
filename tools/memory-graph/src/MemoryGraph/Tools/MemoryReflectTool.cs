using System.Text.Json;
using MemoryGraph.Server;
using MemoryGraph.Storage;

namespace MemoryGraph.Tools;

/// <summary>
/// memory_reflect — Record a post-task reflexion with lessons learned.
/// Stores the reflexion and extracts strategy lessons per project type.
/// </summary>
public sealed class MemoryReflectTool : IMemoryTool
{
    private readonly MemoryStore _store;

    public string Name => "memory_reflect";

    public MemoryReflectTool(MemoryStore store)
    {
        _store = store;
    }

    public ToolDefinition GetDefinition() => new()
    {
        Name = Name,
        Description = "Record a post-task reflexion capturing what worked, what didn't, and lessons learned. " +
                      "Automatically extracts strategy lessons per project type and tracks confidence calibration.",
        InputSchema = ToolHelpers.ParseSchema("""
        {
            "type": "object",
            "properties": {
                "task": {
                    "type": "string",
                    "description": "Brief description of the completed task"
                },
                "project": {
                    "type": "string",
                    "description": "Project name"
                },
                "projectType": {
                    "type": "string",
                    "description": "Project type (e.g., dotnet-api, blazor, maui, unity, static-site)"
                },
                "taskType": {
                    "type": "string",
                    "description": "Task type (e.g., feature, bugfix, refactor, security, docs)"
                },
                "size": {
                    "type": "string",
                    "description": "Task size (small, medium, large, mega)"
                },
                "wentWell": {
                    "type": "array",
                    "items": { "type": "string" },
                    "description": "Things that worked well"
                },
                "wentWrong": {
                    "type": "array",
                    "items": { "type": "string" },
                    "description": "Things that went wrong or were slow"
                },
                "lessons": {
                    "type": "array",
                    "items": { "type": "string" },
                    "description": "Actionable lessons for future tasks"
                },
                "planAccuracy": {
                    "type": "integer",
                    "description": "How accurate was the plan? 1-5 (5 = perfectly matched reality)"
                },
                "estimateAccuracy": {
                    "type": "integer",
                    "description": "How accurate was the size estimate? 1-5"
                },
                "firstAttemptSuccess": {
                    "type": "boolean",
                    "description": "Did the first approach work without major pivots?"
                }
            },
            "required": ["task", "project"]
        }
        """)
    };

    public ToolCallResult Execute(JsonElement arguments)
    {
        var task = ToolHelpers.GetRequiredString(arguments, "task");
        var project = ToolHelpers.GetRequiredString(arguments, "project");
        var projectType = ToolHelpers.GetString(arguments, "projectType");
        var taskType = ToolHelpers.GetString(arguments, "taskType");
        var size = ToolHelpers.GetString(arguments, "size");
        var wentWell = ToolHelpers.GetStringArray(arguments, "wentWell");
        var wentWrong = ToolHelpers.GetStringArray(arguments, "wentWrong");
        var lessons = ToolHelpers.GetStringArray(arguments, "lessons");

        var planAccuracy = 3;
        if (arguments.TryGetProperty("planAccuracy", out var pa))
        {
            planAccuracy = pa.GetInt32();
        }

        var estimateAccuracy = 3;
        if (arguments.TryGetProperty("estimateAccuracy", out var ea))
        {
            estimateAccuracy = ea.GetInt32();
        }

        var firstAttempt = true;
        if (arguments.TryGetProperty("firstAttemptSuccess", out var fa))
        {
            firstAttempt = fa.GetBoolean();
        }

        var entry = new ReflexionEntry
        {
            TaskDescription = task,
            Project = project,
            ProjectType = projectType,
            TaskType = taskType,
            Size = size,
            WentWell = string.Join("\n", wentWell),
            WentWrong = string.Join("\n", wentWrong),
            Lessons = string.Join("\n", lessons),
            PlanAccuracy = planAccuracy,
            EstimateAccuracy = estimateAccuracy,
            FirstAttemptSuccess = firstAttempt
        };

        var reflexionId = _store.AddReflexion(entry);

        // Extract strategy lessons from the reflexion
        var lessonsCreated = 0;
        if (projectType is not null && lessons.Count > 0)
        {
            // Infer phase from lesson content or default to "general"
            foreach (var lesson in lessons)
            {
                var phase = InferPhase(lesson);
                _store.AddStrategyLesson(new StrategyLesson
                {
                    ProjectType = projectType,
                    Phase = phase,
                    Lesson = lesson,
                    Confidence = 0.5,
                    SourceReflexionId = reflexionId
                });
                lessonsCreated++;
            }
        }

        // Record calibration data
        if (size is not null)
        {
            _store.AddCalibration("size", size, size, estimateAccuracy >= 4, projectType);
        }
        _store.AddCalibration("plan", planAccuracy.ToString(), planAccuracy.ToString(), planAccuracy >= 4, projectType);
        _store.AddCalibration("first_attempt", firstAttempt.ToString(), firstAttempt.ToString(), firstAttempt, projectType);

        return ToolHelpers.Success(new
        {
            reflexionId,
            lessonsCreated,
            message = $"Reflexion recorded for '{task}'. {lessonsCreated} strategy lessons extracted."
        });
    }

    private static string InferPhase(string lesson)
    {
        var lower = lesson.ToLowerInvariant();
        if (lower.Contains("discover") || lower.Contains("check") || lower.Contains("verify first") || lower.Contains("ask"))
            return "discover";
        if (lower.Contains("plan") || lower.Contains("estimate") || lower.Contains("design"))
            return "plan";
        if (lower.Contains("test") || lower.Contains("build") || lower.Contains("implement") || lower.Contains("code"))
            return "build";
        if (lower.Contains("review") || lower.Contains("security") || lower.Contains("quality"))
            return "review";
        return "general";
    }
}
