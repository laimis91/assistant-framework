using System.Text.Json;
using MemoryGraph.Graph;
using MemoryGraph.Server;
using MemoryGraph.Storage;

namespace MemoryGraph.Tools;

/// <summary>
/// memory_search — full-text search across all memory content.
/// Uses FTS5 when available for ranked results, falls back to in-memory graph search.
/// </summary>
public sealed class MemorySearchTool : IMemoryTool
{
    private readonly KnowledgeGraph _graph;
    private readonly MemoryStore? _store;

    public string Name => "memory_search";

    public MemorySearchTool(KnowledgeGraph graph, MemoryStore? store = null)
    {
        _graph = graph;
        _store = store;
    }

    public ToolDefinition GetDefinition() => new()
    {
        Name = Name,
        Description = "Search all memory content: entities, reflexions, decisions, strategy lessons. " +
                      "Uses FTS5 full-text search for ranked results. " +
                      "Optionally filter by source type (entity, reflexion, decision, strategy).",
        InputSchema = ToolHelpers.ParseSchema("""
        {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Search text — supports FTS5 syntax (AND, OR, NOT, phrases in quotes)"
                },
                "types": {
                    "type": "array",
                    "items": { "type": "string" },
                    "description": "Optional filter by source type: entity, reflexion, decision, strategy. Or entity types: Project, Technology, Pattern, Preference, Insight, Convention"
                }
            },
            "required": ["query"]
        }
        """)
    };

    public ToolCallResult Execute(JsonElement arguments)
    {
        var query = ToolHelpers.GetRequiredString(arguments, "query");
        var typeNames = ToolHelpers.GetStringArray(arguments, "types");

        // Try FTS5 search first if store is available
        if (_store is not null)
        {
            try
            {
                string? sourceTypeFilter = null;
                if (typeNames.Count == 1)
                {
                    var t = typeNames[0].ToLowerInvariant();
                    if (t is "entity" or "reflexion" or "decision" or "strategy")
                    {
                        sourceTypeFilter = t;
                    }
                }

                var ftsResults = _store.Search(query, sourceTypeFilter);

                if (ftsResults.Count > 0)
                {
                    // Enrich entity results with relations from the graph
                    var results = ftsResults.Select(r =>
                    {
                        object? relations = null;
                        if (r.SourceType == "entity")
                        {
                            relations = _graph.GetRelationsFor(r.SourceId).Select(rel => new
                            {
                                rel.From,
                                rel.To,
                                type = rel.Type.ToString(),
                                rel.Detail
                            }).ToList();
                        }

                        return new
                        {
                            r.SourceType,
                            r.SourceId,
                            r.Title,
                            r.Snippet,
                            relations
                        };
                    }).ToList();

                    return ToolHelpers.Success(new { results, searchMode = "fts5" });
                }
            }
            catch (Exception ex)
            {
                // FTS5 query syntax error — fall back to graph search
                Console.Error.WriteLine($"[memory-graph] FTS5 query failed ({ex.GetType().Name}: {ex.Message}), falling back to graph search");
            }
        }

        // Fallback: in-memory graph search
        EntityType[]? types = null;
        if (typeNames.Count > 0)
        {
            types = typeNames
                .Select(t => Enum.TryParse<EntityType>(t, ignoreCase: true, out var et) ? (EntityType?)et : null)
                .Where(t => t.HasValue)
                .Select(t => t!.Value)
                .ToArray();
        }

        var entities = _graph.Search(query, types);

        var graphResults = entities.Select(e => new
        {
            sourceType = "entity",
            sourceId = e.Name,
            title = e.Name,
            snippet = string.Join("; ", e.Observations.Take(3)),
            relations = (object)_graph.GetRelationsFor(e.Name).Select(r => new
            {
                r.From,
                r.To,
                type = r.Type.ToString(),
                r.Detail
            }).ToList()
        }).ToList();

        return ToolHelpers.Success(new { results = graphResults, searchMode = "graph" });
    }
}
