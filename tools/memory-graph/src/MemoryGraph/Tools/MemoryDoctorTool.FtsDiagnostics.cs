using MemoryGraph.Graph;
using MemoryGraph.Storage;

namespace MemoryGraph.Tools;

public sealed partial class MemoryDoctorTool
{
    private MemoryStats? GetStoreStats(List<string> warnings)
    {
        if (_store is null)
        {
            return null;
        }

        try
        {
            return _store.GetStats();
        }
        catch (Exception ex)
        {
            warnings.Add($"Store stats unavailable: {ex.GetType().Name}: {ex.Message}");
            return null;
        }
    }

    private GraphEntityFtsDiagnostics? GetFtsDiagnostics(List<Entity> entities, List<string> warnings)
    {
        if (_store is null)
        {
            warnings.Add("FTS diagnostics unavailable: no MemoryStore was provided.");
            return null;
        }

        try
        {
            return _store.GetGraphEntityFtsDiagnostics(entities.Select(e => e.Name));
        }
        catch (Exception ex)
        {
            warnings.Add($"FTS diagnostics unavailable: {ex.GetType().Name}: {ex.Message}");
            return null;
        }
    }

    private static object BuildFtsIssues(GraphEntityFtsDiagnostics? diagnostics)
    {
        if (diagnostics is null)
        {
            return new
            {
                available = false,
                staleEntityRows = (int?)null,
                orphanEntityRows = (int?)null,
                nonCanonicalEntityRows = (int?)null,
                staleRows = Array.Empty<GraphEntityFtsIssue>()
            };
        }

        return new
        {
            available = true,
            diagnostics.EntityRows,
            diagnostics.StaleEntityRows,
            diagnostics.OrphanEntityRows,
            diagnostics.NonCanonicalEntityRows,
            staleRows = diagnostics.StaleRows.Take(50).ToList()
        };
    }
}
