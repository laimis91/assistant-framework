using System.Text.Json;
using MemoryGraph.Tools;
using Xunit;

namespace MemoryGraph.Tests;

public sealed class MemorySignalToolTests : IDisposable
{
    private readonly string _memoryDir;
    private readonly MemorySignalTool _tool;

    public MemorySignalToolTests()
    {
        _memoryDir = Path.Combine(Path.GetTempPath(), $"memory-signal-test-{Guid.NewGuid()}");
        Directory.CreateDirectory(_memoryDir);
        _tool = new MemorySignalTool(_memoryDir);
    }

    public void Dispose()
    {
        if (Directory.Exists(_memoryDir))
        {
            Directory.Delete(_memoryDir, recursive: true);
        }
    }

    [Fact]
    public void GetDefinition_UsesClosedSchemaWithoutRawDetailField()
    {
        var schema = _tool.GetDefinition().InputSchema;

        Assert.False(schema.GetProperty("additionalProperties").GetBoolean());
        Assert.False(schema.GetProperty("properties").TryGetProperty("detail", out _));
        Assert.Equal(["type", "project"], schema.GetProperty("required")
            .EnumerateArray().Select(item => item.GetString()!).ToArray());
        Assert.Equal(["correction", "pivot", "frustration", "approval"],
            schema.GetProperty("properties").GetProperty("type").GetProperty("enum")
                .EnumerateArray().Select(item => item.GetString()!).ToArray());
    }

    [Fact]
    public void Execute_RecordsOnlyTimestampTypeAndProject()
    {
        var result = _tool.Execute(ParseArgs("""{"type":"correction","project":"AssistantFramework"}"""));

        Assert.False(result.IsError);
        var line = Assert.Single(File.ReadAllLines(Path.Combine(_memoryDir, "signals.jsonl")));
        using var document = JsonDocument.Parse(line);
        var root = document.RootElement;
        Assert.Equal(3, root.EnumerateObject().Count());
        Assert.True(root.TryGetProperty("ts", out _));
        Assert.Equal("correction", root.GetProperty("type").GetString());
        Assert.Equal("AssistantFramework", root.GetProperty("project").GetString());
        Assert.DoesNotContain("detail", line, StringComparison.OrdinalIgnoreCase);
    }

    [Theory]
    [InlineData("unknown", "AssistantFramework")]
    [InlineData("correction", "")]
    [InlineData("correction", "raw user correction text")]
    [InlineData("correction", "/Users/private/project")]
    public void Execute_RejectsInvalidBoundedInputs(string type, string project)
    {
        var result = _tool.Execute(ParseArgs(JsonSerializer.Serialize(new { type, project })));

        Assert.True(result.IsError);
        Assert.False(File.Exists(Path.Combine(_memoryDir, "signals.jsonl")));
    }

    [Fact]
    public void Execute_RejectsOversizedProject()
    {
        var result = _tool.Execute(ParseArgs(JsonSerializer.Serialize(new
        {
            type = "pivot",
            project = new string('x', 129)
        })));

        Assert.True(result.IsError);
        Assert.False(File.Exists(Path.Combine(_memoryDir, "signals.jsonl")));
    }

    [Fact]
    public void Execute_RotatesSignalFileToBoundGrowth()
    {
        for (var index = 0; index < 505; index++)
        {
            var result = _tool.Execute(ParseArgs("""{"type":"approval","project":"AssistantFramework"}"""));
            Assert.False(result.IsError);
        }

        var lines = File.ReadAllLines(Path.Combine(_memoryDir, "signals.jsonl"));
        Assert.InRange(lines.Length, 300, 500);
    }

    [Fact]
    public void Execute_RejectsBrokenSymbolicLinkWithoutCreatingExternalTarget()
    {
        var externalTarget = Path.Combine(Path.GetTempPath(), $"memory-signal-external-{Guid.NewGuid()}.jsonl");
        var signalsFile = Path.Combine(_memoryDir, "signals.jsonl");
        File.CreateSymbolicLink(signalsFile, externalTarget);
        try
        {
            var result = _tool.Execute(ParseArgs("""{"type":"correction","project":"AssistantFramework"}"""));

            Assert.True(result.IsError);
            Assert.False(File.Exists(externalTarget));
        }
        finally
        {
            if (File.Exists(externalTarget))
            {
                File.Delete(externalTarget);
            }
        }
    }

    private static JsonElement ParseArgs(string json)
    {
        using var document = JsonDocument.Parse(json);
        return document.RootElement.Clone();
    }
}
