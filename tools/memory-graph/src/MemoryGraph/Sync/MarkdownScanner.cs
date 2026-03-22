using MemoryGraph.Graph;

namespace MemoryGraph.Sync;

/// <summary>
/// Scans markdown files in the memory directory and extracts entities/relations.
/// Merges extracted data into the knowledge graph (markdown is source of truth for conflicts).
/// </summary>
public sealed class MarkdownScanner
{
    private readonly string _memoryDir;
    private readonly KnowledgeGraph _graph;
    private readonly bool _verbose;

    public MarkdownScanner(string memoryDir, KnowledgeGraph graph, bool verbose = false)
    {
        _memoryDir = memoryDir;
        _graph = graph;
        _verbose = verbose;
    }

    /// <summary>
    /// Scans all markdown files and merges extracted entities into the graph.
    /// Returns count of entities and relations added/updated.
    /// </summary>
    public (int EntitiesProcessed, int RelationsProcessed) Scan()
    {
        if (!Directory.Exists(_memoryDir))
        {
            Log($"Memory directory not found: {_memoryDir}");
            return (0, 0);
        }

        var entitiesProcessed = 0;
        var relationsProcessed = 0;

        // Scan insights/*.md
        var insightsDir = Path.Combine(_memoryDir, "insights");
        if (Directory.Exists(insightsDir))
        {
            foreach (var file in Directory.GetFiles(insightsDir, "*.md"))
            {
                try
                {
                    // Refresh snapshot each iteration so newly merged entities are available for cross-referencing
                    var existingEntities = _graph.GetAllEntities();
                    var content = File.ReadAllText(file);
                    var relativePath = Path.GetRelativePath(_memoryDir, file);
                    var result = EntityExtractor.ExtractFromInsight(content, relativePath, existingEntities);
                    var (e, r) = MergeResults(result);
                    entitiesProcessed += e;
                    relationsProcessed += r;
                    Log($"Scanned {relativePath}: {e} entities, {r} relations");
                }
                catch (Exception ex)
                {
                    Log($"Skipping {Path.GetFileName(file)}: {ex.Message}");
                }
            }
        }

        // Scan user/*.md (all user preference files, not just profile.md)
        var userDir = Path.Combine(_memoryDir, "user");
        if (Directory.Exists(userDir))
        {
            foreach (var file in Directory.GetFiles(userDir, "*.md"))
            {
                try
                {
                    var content = File.ReadAllText(file);
                    var relativePath = Path.GetRelativePath(_memoryDir, file);
                    var result = EntityExtractor.ExtractFromProfile(content, relativePath);
                    var (e, r) = MergeResults(result);
                    entitiesProcessed += e;
                    relationsProcessed += r;
                    Log($"Scanned {relativePath}: {e} entities, {r} relations");
                }
                catch (Exception ex)
                {
                    Log($"Skipping {Path.GetFileName(file)}: {ex.Message}");
                }
            }
        }

        // Scan feedback/*.md
        var feedbackDir = Path.Combine(_memoryDir, "feedback");
        if (Directory.Exists(feedbackDir))
        {
            foreach (var file in Directory.GetFiles(feedbackDir, "*.md"))
            {
                try
                {
                    var content = File.ReadAllText(file);
                    var relativePath = Path.GetRelativePath(_memoryDir, file);
                    var result = EntityExtractor.ExtractFromFeedback(content, relativePath);
                    var (e, r) = MergeResults(result);
                    entitiesProcessed += e;
                    relationsProcessed += r;
                    Log($"Scanned {relativePath}: {e} entities, {r} relations");
                }
                catch (Exception ex)
                {
                    Log($"Skipping {Path.GetFileName(file)}: {ex.Message}");
                }
            }
        }

        _graph.SaveIfDirty();

        return (entitiesProcessed, relationsProcessed);
    }

    private (int Entities, int Relations) MergeResults(ExtractionResult result)
    {
        var entities = 0;
        var relations = 0;

        foreach (var entity in result.Entities)
        {
            _graph.AddOrUpdateEntity(entity.Name, entity.Type, entity.Observations, entity.SourceFile);
            entities++;
        }

        foreach (var relation in result.Relations)
        {
            // Only add relations where both endpoints exist in the graph
            if (_graph.GetEntity(relation.From) is null || _graph.GetEntity(relation.To) is null)
            {
                continue;
            }

            if (_graph.AddRelation(relation.From, relation.To, relation.Type, relation.Detail))
            {
                relations++;
            }
        }

        return (entities, relations);
    }

    private void Log(string message)
    {
        if (_verbose)
        {
            Console.Error.WriteLine($"[memory-graph:sync] {message}");
        }
    }
}
