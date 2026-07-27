using System.Text;
using System.Text.Json;
using MemoryGraph.Server;

namespace MemoryGraph.Tools;

/// <summary>
/// memory_signal — Record a bounded, privacy-safe learning signal.
/// Raw prompt text and free-form details are intentionally excluded.
/// </summary>
public sealed class MemorySignalTool : IMemoryTool
{
    private const int MaximumProjectLength = 128;
    private const int RotationThreshold = 500;
    private const int RetainedSignals = 300;
    private static readonly HashSet<string> AllowedTypes =
        ["correction", "pivot", "frustration", "approval"];
    private static readonly object FileLock = new();
    private readonly string _memoryDir;

    public MemorySignalTool(string memoryDir)
    {
        _memoryDir = memoryDir;
    }

    public string Name => "memory_signal";

    public ToolDefinition GetDefinition() => new()
    {
        Name = Name,
        Description = "Record one privacy-safe learning signal for later trend analysis. " +
                      "Only a fixed signal type and bounded project identifier are stored; " +
                      "never send raw prompt, correction, secret, PII, or free-form detail text.",
        InputSchema = ToolHelpers.ParseSchema("""
        {
            "type": "object",
            "properties": {
                "type": {
                    "type": "string",
                    "enum": ["correction", "pivot", "frustration", "approval"],
                    "description": "Fixed learning-signal category"
                },
                "project": {
                    "type": "string",
                    "minLength": 1,
                    "maxLength": 128,
                    "pattern": "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$",
                    "description": "Bounded project slug, never user prompt text"
                }
            },
            "required": ["type", "project"],
            "additionalProperties": false
        }
        """)
    };

    public ToolCallResult Execute(JsonElement arguments)
    {
        var type = ToolHelpers.GetString(arguments, "type");
        var project = ToolHelpers.GetString(arguments, "project");

        if (type is null || !AllowedTypes.Contains(type))
        {
            return ToolHelpers.Error("type must be one of: correction, pivot, frustration, approval");
        }

        if (string.IsNullOrWhiteSpace(project)
            || project.Length > MaximumProjectLength
            || !char.IsAsciiLetterOrDigit(project[0])
            || project.Any(character =>
                !char.IsAsciiLetterOrDigit(character)
                && character is not '.' and not '_' and not '-'))
        {
            return ToolHelpers.Error("project must be a 1-128 character ASCII slug");
        }

        Directory.CreateDirectory(_memoryDir);
        var signalsFile = Path.Combine(_memoryDir, "signals.jsonl");
        if (File.Exists(signalsFile) && new FileInfo(signalsFile).LinkTarget is not null)
        {
            return ToolHelpers.Error("signals.jsonl must not be a symbolic link");
        }

        var signal = JsonSerializer.Serialize(new Dictionary<string, string>
        {
            ["ts"] = DateTime.UtcNow.ToString("O"),
            ["type"] = type,
            ["project"] = project
        });

        lock (FileLock)
        {
            File.AppendAllText(signalsFile, signal + Environment.NewLine, new UTF8Encoding(false));
            RotateIfNeeded(signalsFile);
        }

        return ToolHelpers.Success(new { recorded = true, type, project });
    }

    private static void RotateIfNeeded(string signalsFile)
    {
        var lines = File.ReadAllLines(signalsFile);
        if (lines.Length <= RotationThreshold)
        {
            return;
        }

        var temporaryFile = signalsFile + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllLines(temporaryFile, lines[^RetainedSignals..], new UTF8Encoding(false));
            File.Move(temporaryFile, signalsFile, overwrite: true);
        }
        finally
        {
            if (File.Exists(temporaryFile))
            {
                File.Delete(temporaryFile);
            }
        }
    }
}
