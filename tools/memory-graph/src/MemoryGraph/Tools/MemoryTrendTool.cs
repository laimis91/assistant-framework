using System.Text.Json;
using MemoryGraph.Server;
using MemoryGraph.Storage;

namespace MemoryGraph.Tools;

/// <summary>
/// memory_trend — Surface actionable trends from calibration data and learning signals.
/// Part of the continuous learning loop: signals are captured by hooks, trends are surfaced here.
/// </summary>
public sealed class MemoryTrendTool : IMemoryTool
{
    private readonly MemoryStore _store;
    private readonly string _memoryDir;

    public string Name => "memory_trend";

    public MemoryTrendTool(MemoryStore store, string memoryDir)
    {
        _store = store;
        _memoryDir = memoryDir;
    }

    public ToolDefinition GetDefinition() => new()
    {
        Name = Name,
        Description = "Surface actionable trends from calibration data and learning signals. " +
                      "Shows patterns like 'you underestimate 70% of dotnet-api tasks' or " +
                      "'3 corrections in last session about X'. " +
                      "Call during pre-task lesson recall or when user asks about performance patterns.",
        InputSchema = ToolHelpers.ParseSchema("""
        {
            "type": "object",
            "properties": {
                "projectType": {
                    "type": "string",
                    "description": "Optional: filter trends to a specific project type"
                },
                "project": {
                    "type": "string",
                    "description": "Optional: filter signal trends to a specific project"
                },
                "signalDays": {
                    "type": "integer",
                    "description": "How many days of signals to analyze (default: 30)"
                }
            },
            "additionalProperties": false
        }
        """)
    };

    public ToolCallResult Execute(JsonElement arguments)
    {
        var projectType = ToolHelpers.GetString(arguments, "projectType");
        var project = ToolHelpers.GetString(arguments, "project");
        var signalDays = 30;
        if (arguments.TryGetProperty("signalDays", out var sd))
        {
            signalDays = sd.GetInt32();
        }

        // 1. Calibration trends
        var calibration = _store.GetCalibrationStats(projectType);
        var calibrationTrends = new List<string>();

        foreach (var (type, stats) in calibration.ByType)
        {
            if (stats.Total < 3) continue; // Not enough data

            var rate = stats.AccuracyRate;
            if (rate < 0.5)
            {
                var suffix = projectType is not null ? $" for {projectType} tasks" : "";
                calibrationTrends.Add(
                    $"{type} accuracy is {rate:P0} ({stats.Accurate}/{stats.Total}){suffix} — " +
                    $"consider adjusting your {type} approach");
            }
            else if (rate < 0.7)
            {
                calibrationTrends.Add(
                    $"{type} accuracy is {rate:P0} ({stats.Accurate}/{stats.Total}) — below target");
            }
        }

        // 2. Signal trends from JSONL file
        var signalSummary = ReadSignalTrends(project, signalDays);

        // 3. Lesson staleness check
        var staleCount = _store.GetStaleLessonCount(90);

        var result = new
        {
            calibrationTrends = calibrationTrends.Count > 0 ? calibrationTrends : null,
            signals = signalSummary,
            staleLessons = staleCount > 0
                ? $"{staleCount} lessons not reinforced in 90+ days — consider running memory_consolidate"
                : null,
            recommendation = GenerateRecommendation(calibrationTrends, signalSummary)
        };

        return ToolHelpers.Success(result);
    }

    private SignalSummary? ReadSignalTrends(string? projectFilter, int days)
    {
        var signalsFile = Path.Combine(_memoryDir, "signals.jsonl");
        if (!File.Exists(signalsFile)) return null;

        string[] lines;
        try
        {
            lines = File.ReadAllLines(signalsFile);
        }
        catch (IOException)
        {
            // File may be locked or rotated by the learning-signals hook
            return null;
        }

        var cutoff = DateTime.UtcNow.AddDays(-days);
        var signals = ParseSignalEntries(lines, cutoff, projectFilter);

        if (signals.Count == 0) return null;

        var byType = signals.GroupBy(s => s.Type)
            .ToDictionary(g => g.Key, g => g.Count());

        // Find recurring correction themes (same detail prefix appearing 2+ times)
        var correctionThemes = signals
            .Where(s => s.Type == "correction" && s.Detail is not null)
            .GroupBy(s => s.Detail![..Math.Min(50, s.Detail!.Length)])
            .Where(g => g.Count() >= 2)
            .Select(g => new { theme = g.Key, count = g.Count() })
            .ToList();

        return new SignalSummary
        {
            TotalSignals = signals.Count,
            ByType = byType,
            DaysCovered = days,
            RecurringThemes = correctionThemes.Count > 0
                ? correctionThemes.Select(t => $"\"{t.theme}...\" ({t.count}x)").ToList()
                : null
        };
    }

    private static List<SignalEntry> ParseSignalEntries(string[] lines, DateTime cutoff, string? projectFilter)
    {
        var signals = new List<SignalEntry>();

        foreach (var line in lines)
        {
            if (string.IsNullOrWhiteSpace(line)) continue;
            try
            {
                using var doc = JsonDocument.Parse(line);
                var root = doc.RootElement;
                var ts = root.GetProperty("ts").GetString();
                var type = root.GetProperty("type").GetString();
                var proj = root.TryGetProperty("project", out var p) ? p.GetString() : null;
                var detail = root.TryGetProperty("detail", out var d) ? d.GetString() : null;

                if (ts is null || type is null) continue;

                var timestamp = DateTime.Parse(ts, null, System.Globalization.DateTimeStyles.RoundtripKind);
                if (timestamp < cutoff) continue;
                if (projectFilter is not null && proj != projectFilter) continue;

                signals.Add(new SignalEntry { Timestamp = timestamp, Type = type, Project = proj, Detail = detail });
            }
            catch
            {
                // Skip malformed lines
            }
        }

        return signals;
    }

    private static string? GenerateRecommendation(List<string> calibrationTrends, SignalSummary? signals)
    {
        var parts = new List<string>();

        if (calibrationTrends.Count > 0)
        {
            parts.Add("Calibration data shows systematic bias — review estimation approach");
        }

        if (signals is not null)
        {
            if (signals.ByType.TryGetValue("correction", out var corrections) && corrections >= 3)
            {
                parts.Add($"{corrections} corrections detected — check if a feedback rule should be created");
            }

            if (signals.ByType.TryGetValue("frustration", out var frustrations) && frustrations >= 2)
            {
                parts.Add($"{frustrations} frustration signals — review if instructions are being followed");
            }
        }

        return parts.Count > 0 ? string.Join(". ", parts) : null;
    }

    private class SignalEntry
    {
        public DateTime Timestamp { get; init; }
        public string Type { get; init; } = "";
        public string? Project { get; init; }
        public string? Detail { get; init; }
    }

    private class SignalSummary
    {
        public int TotalSignals { get; init; }
        public Dictionary<string, int> ByType { get; init; } = new();
        public int DaysCovered { get; init; }
        public List<string>? RecurringThemes { get; init; }
    }
}
