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
