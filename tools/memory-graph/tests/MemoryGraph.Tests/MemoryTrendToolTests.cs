using System.Text.Json;
using MemoryGraph.Storage;
using MemoryGraph.Tools;
using Xunit;

namespace MemoryGraph.Tests;

public sealed class MemoryTrendToolTests : IDisposable
{
    private readonly string _memoryDir;
    private readonly string _dbPath;
    private readonly MemoryStore _store;
    private readonly MemoryTrendTool _tool;

    public MemoryTrendToolTests()
    {
        _memoryDir = Path.Combine(Path.GetTempPath(), $"memory-trend-test-{Guid.NewGuid()}");
        Directory.CreateDirectory(_memoryDir);
        _dbPath = Path.Combine(_memoryDir, "memory.db");
        _store = new MemoryStore(_dbPath);
        _tool = new MemoryTrendTool(_store, _memoryDir);
    }

    public void Dispose()
    {
        _store.Dispose();
        if (Directory.Exists(_memoryDir))
        {
            Directory.Delete(_memoryDir, recursive: true);
        }
    }

    private static JsonElement ParseArgs(string json)
    {
        using var doc = JsonDocument.Parse(json);
        return doc.RootElement.Clone();
    }

    [Fact]
    public void Execute_NoData_ReturnsEmptyResult()
    {
        var result = _tool.Execute(ParseArgs("{}"));

        Assert.False(result.IsError);
        var text = result.Content[0].Text;
        // Should not contain calibrationTrends or signals when there's no data
        Assert.DoesNotContain("calibrationTrends", text);
    }

    [Fact]
    public void Execute_NoSignalsFile_OmitsSignals()
    {
        var result = _tool.Execute(ParseArgs("{}"));

        Assert.False(result.IsError);
        var text = result.Content[0].Text;
        // WhenWritingNull omits null properties entirely
        Assert.DoesNotContain("signals", text);
    }

    [Fact]
    public void Execute_WithSignalsFile_ReturnsSignalSummary()
    {
        var signalsFile = Path.Combine(_memoryDir, "signals.jsonl");
        var now = DateTime.UtcNow.ToString("O");
        File.WriteAllLines(signalsFile, new[]
        {
            $"{{\"ts\":\"{now}\",\"type\":\"correction\",\"project\":\"TestProj\",\"detail\":\"wrong approach\"}}",
            $"{{\"ts\":\"{now}\",\"type\":\"correction\",\"project\":\"TestProj\",\"detail\":\"wrong approach again\"}}",
            $"{{\"ts\":\"{now}\",\"type\":\"approval\",\"project\":\"TestProj\",\"detail\":\"good job\"}}"
        });

        var result = _tool.Execute(ParseArgs("{}"));

        Assert.False(result.IsError);
        var text = result.Content[0].Text;
        Assert.Contains("totalSignals", text);
        Assert.Contains("3", text); // 3 signals total
    }

    [Fact]
    public void Execute_WithProjectFilter_FiltersSignals()
    {
        var signalsFile = Path.Combine(_memoryDir, "signals.jsonl");
        var now = DateTime.UtcNow.ToString("O");
        File.WriteAllLines(signalsFile, new[]
        {
            $"{{\"ts\":\"{now}\",\"type\":\"correction\",\"project\":\"ProjA\",\"detail\":\"fix A\"}}",
            $"{{\"ts\":\"{now}\",\"type\":\"correction\",\"project\":\"ProjB\",\"detail\":\"fix B\"}}"
        });

        var result = _tool.Execute(ParseArgs("""{"project": "ProjA"}"""));

        Assert.False(result.IsError);
        var text = result.Content[0].Text;
        Assert.Contains("totalSignals", text);
        // Should only include ProjA signals
        using var doc = JsonDocument.Parse(text);
        var totalSignals = doc.RootElement.GetProperty("signals").GetProperty("totalSignals").GetInt32();
        Assert.Equal(1, totalSignals);
    }

    [Fact]
    public void Execute_OldSignals_FilteredByDays()
    {
        var signalsFile = Path.Combine(_memoryDir, "signals.jsonl");
        var old = DateTime.UtcNow.AddDays(-60).ToString("O");
        var recent = DateTime.UtcNow.ToString("O");
        File.WriteAllLines(signalsFile, new[]
        {
            $"{{\"ts\":\"{old}\",\"type\":\"correction\",\"project\":\"Proj\",\"detail\":\"old fix\"}}",
            $"{{\"ts\":\"{recent}\",\"type\":\"approval\",\"project\":\"Proj\",\"detail\":\"new good\"}}"
        });

        var result = _tool.Execute(ParseArgs("""{"signalDays": 30}"""));

        Assert.False(result.IsError);
        var text = result.Content[0].Text;
        using var doc = JsonDocument.Parse(text);
        var totalSignals = doc.RootElement.GetProperty("signals").GetProperty("totalSignals").GetInt32();
        Assert.Equal(1, totalSignals); // Only the recent one
    }

    [Fact]
    public void Execute_LowCalibrationAccuracy_SurfacesTrend()
    {
        // Add calibration data with low accuracy
        _store.AddCalibration("size", "small", "large", false, "dotnet-api");
        _store.AddCalibration("size", "small", "large", false, "dotnet-api");
        _store.AddCalibration("size", "medium", "medium", true, "dotnet-api");
        _store.AddCalibration("size", "small", "large", false, "dotnet-api");

        var result = _tool.Execute(ParseArgs("""{"projectType": "dotnet-api"}"""));

        Assert.False(result.IsError);
        var text = result.Content[0].Text;
        Assert.Contains("calibrationTrends", text);
        Assert.Contains("size", text);
    }

    [Fact]
    public void Execute_HighCalibrationAccuracy_NoTrends()
    {
        // Add calibration data with high accuracy
        _store.AddCalibration("size", "small", "small", true, "dotnet-api");
        _store.AddCalibration("size", "medium", "medium", true, "dotnet-api");
        _store.AddCalibration("size", "large", "large", true, "dotnet-api");

        var result = _tool.Execute(ParseArgs("""{"projectType": "dotnet-api"}"""));

        Assert.False(result.IsError);
        var text = result.Content[0].Text;
        // WhenWritingNull omits null properties — no calibrationTrends means no issues
        Assert.DoesNotContain("calibrationTrends", text);
    }

    [Fact]
    public void Execute_MalformedSignalLines_Skipped()
    {
        var signalsFile = Path.Combine(_memoryDir, "signals.jsonl");
        var now = DateTime.UtcNow.ToString("O");
        File.WriteAllLines(signalsFile, new[]
        {
            "not json at all",
            "",
            $"{{\"ts\":\"{now}\",\"type\":\"approval\",\"project\":\"Proj\",\"detail\":\"good\"}}"
        });

        var result = _tool.Execute(ParseArgs("{}"));

        Assert.False(result.IsError);
        var text = result.Content[0].Text;
        using var doc = JsonDocument.Parse(text);
        var totalSignals = doc.RootElement.GetProperty("signals").GetProperty("totalSignals").GetInt32();
        Assert.Equal(1, totalSignals); // Only the valid line
    }
}
