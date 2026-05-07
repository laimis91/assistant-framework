using MemoryGraph.Storage;

namespace MemoryGraph.Tools;

public sealed partial class MemoryDoctorTool
{
    private object BuildRuntime(GraphEntityFtsDiagnostics? ftsDiagnostics, List<string> warnings)
    {
        return new
        {
            memoryDir = _memoryDir,
            startup = _startupMetrics is null
                ? null
                : new
                {
                    _startupMetrics.GraphFile,
                    _startupMetrics.DatabasePath,
                    _startupMetrics.SkippedGraphLines,
                    _startupMetrics.IndexedGraphEntities,
                    _startupMetrics.PrunedGraphEntityRows,
                    _startupMetrics.Reconciliation
                },
            files = BuildRuntimeFileMetadata(warnings),
            freshness = BuildFreshness(ftsDiagnostics, warnings)
        };
    }

    private void AddLocalStoreWarnings(
        List<string> warnings,
        int graphEntityCount,
        int graphRelationCount,
        MemoryStats? storeStats,
        GraphEntityFtsDiagnostics? ftsDiagnostics)
    {
        if (storeStats is not null && graphEntityCount == 0 && HasNoRelationalMemoryRows(storeStats))
        {
            warnings.Add(
                $"Memory store appears empty: no graph entities, relational memory rows, or FTS rows were found. Memory is local to memoryDir '{DescribeMemoryDir()}'; another PC must have, import, or copy the memory store (memory.db or legacy graph.jsonl) before memory_context or memory_search can retrieve prior data.");
        }

        if (_startupMetrics is null || File.Exists(_startupMetrics.GraphFile))
        {
            return;
        }

        var graphEntityFtsRows = ftsDiagnostics?.EntityRows ?? 0;
        if (graphEntityCount == 0 && graphRelationCount == 0 && graphEntityFtsRows == 0)
        {
            warnings.Add(
                $"Legacy graph.jsonl is missing at '{_startupMetrics.GraphFile}' and memory.db has no retrievable graph context. Memory is local to memoryDir '{DescribeMemoryDir()}'; copy or import memory.db or legacy graph.jsonl from the machine that contains the memory data.");
        }
    }

    private static bool HasNoRelationalMemoryRows(MemoryStats storeStats)
    {
        return storeStats.Reflexions == 0 &&
               storeStats.Decisions == 0 &&
               storeStats.StrategyLessons == 0 &&
               storeStats.CalibrationEntries == 0 &&
               storeStats.FtsEntries == 0;
    }

    private string DescribeMemoryDir()
    {
        return string.IsNullOrWhiteSpace(_memoryDir) ? "(unknown)" : _memoryDir;
    }

    private List<RuntimeFileMetadata> BuildRuntimeFileMetadata(List<string> warnings)
    {
        var files = new List<RuntimeFileMetadata>();
        if (_startupMetrics is null)
        {
            return files;
        }

        AddRuntimeFileMetadata(files, _startupMetrics.GraphFile, warnings);
        AddRuntimeFileMetadata(files, _startupMetrics.DatabasePath, warnings);
        return files;
    }

    private static void AddRuntimeFileMetadata(List<RuntimeFileMetadata> files, string path, List<string> warnings)
    {
        try
        {
            files.Add(new RuntimeFileMetadata(
                path,
                File.Exists(path),
                File.Exists(path) ? File.GetLastWriteTimeUtc(path).ToString("O") : null,
                null));
        }
        catch (Exception ex)
        {
            warnings.Add($"Runtime file metadata unavailable for '{path}': {ex.GetType().Name}: {ex.Message}");
            files.Add(new RuntimeFileMetadata(path, false, null, ex.GetType().Name));
        }
    }

    private static object BuildFreshness(GraphEntityFtsDiagnostics? ftsDiagnostics, List<string> warnings)
    {
        try
        {
            if (ftsDiagnostics is null)
            {
                return new { status = "unknown", reason = "FTS diagnostics unavailable" };
            }

            return new
            {
                status = ftsDiagnostics.StaleEntityRows == 0 ? "fresh" : "staleFtsRowsDetected",
                ftsDiagnostics.StaleEntityRows
            };
        }
        catch (Exception ex)
        {
            warnings.Add($"Runtime freshness unavailable: {ex.GetType().Name}: {ex.Message}");
            return new { status = "unknown", reason = ex.GetType().Name };
        }
    }

    private sealed record RuntimeFileMetadata(string Path, bool Exists, string? LastWriteUtc, string? Error);
}
