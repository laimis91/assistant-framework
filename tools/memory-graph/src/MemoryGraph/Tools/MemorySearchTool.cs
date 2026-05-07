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
    private const int SearchResultLimit = 20;
    private const int MaxFtsFetchLimit = 200;

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
                    "description": "Optional filter by source type: entity, reflexion, decision, strategy. Or entity types: Project, Technology, Pattern, Preference, Insight, Convention, Rule"
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
        var filters = SearchFilters.Create(typeNames);

        // Try FTS5 search first if store is available
        if (_store is not null)
        {
            try
            {
                var ftsResults = SearchFtsWithLiveEntities(query, filters);

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
        if (!filters.CanReturnEntities)
        {
            return ToolHelpers.Success(new { results = Array.Empty<object>(), searchMode = "graph" });
        }

        var types = filters.GetGraphEntityTypeFilter();
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

    private List<FtsResult> SearchFtsWithLiveEntities(string query, SearchFilters filters)
    {
        if (_store is null)
        {
            return [];
        }

        var sourceTypeFilter = filters.GetStoreSourceTypeFilter();
        var entityTypeFilter = filters.GetStoreEntityTypeFilter();
        var fetchLimit = SearchResultLimit;
        while (true)
        {
            var fetched = sourceTypeFilter is null && entityTypeFilter is null
                ? _store.Search(query, limit: fetchLimit)
                : _store.Search(query, sourceTypeFilter ?? [], entityTypeFilter ?? [], fetchLimit);
            var liveResults = fetched
                .Where(r => MatchesFilters(r, filters))
                .Take(SearchResultLimit)
                .ToList();

            if (liveResults.Count >= SearchResultLimit ||
                fetched.Count < fetchLimit ||
                fetchLimit >= MaxFtsFetchLimit)
            {
                return liveResults;
            }

            fetchLimit = Math.Min(fetchLimit * 2, MaxFtsFetchLimit);
        }
    }

    private bool MatchesFilters(FtsResult result, SearchFilters filters)
    {
        if (!filters.HasFilters)
        {
            return result.SourceType != "entity" || GetLiveEntityForFtsRow(result) is not null;
        }

        if (filters.SourceTypes.Contains(result.SourceType))
        {
            return result.SourceType != "entity" || GetLiveEntityForFtsRow(result) is not null;
        }

        if (result.SourceType != "entity")
        {
            return false;
        }

        var entity = GetLiveEntityForFtsRow(result);
        return entity is not null && filters.EntityTypes.Contains(entity.Type);
    }

    private Entity? GetLiveEntityForFtsRow(FtsResult result)
    {
        var entity = _graph.GetEntity(result.SourceId);
        return entity is not null && entity.Name.Equals(result.SourceId, StringComparison.Ordinal)
            ? entity
            : null;
    }

    private sealed class SearchFilters
    {
        private SearchFilters(HashSet<string> sourceTypes, HashSet<EntityType> entityTypes)
        {
            SourceTypes = sourceTypes;
            EntityTypes = entityTypes;
        }

        public HashSet<string> SourceTypes { get; }
        public HashSet<EntityType> EntityTypes { get; }
        public bool HasFilters => SourceTypes.Count > 0 || EntityTypes.Count > 0;
        public bool CanReturnEntities => SourceTypes.Count == 0 || SourceTypes.Contains("entity") || EntityTypes.Count > 0;

        public static SearchFilters Create(IEnumerable<string> typeNames)
        {
            var sourceTypes = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var entityTypes = new HashSet<EntityType>();

            foreach (var typeName in typeNames)
            {
                var sourceType = typeName.ToLowerInvariant();
                if (sourceType is "entity" or "reflexion" or "decision" or "strategy")
                {
                    sourceTypes.Add(sourceType);
                    continue;
                }

                if (Enum.TryParse<EntityType>(typeName, ignoreCase: true, out var entityType))
                {
                    entityTypes.Add(entityType);
                }
            }

            return new SearchFilters(sourceTypes, entityTypes);
        }

        public IReadOnlyList<string>? GetStoreSourceTypeFilter()
        {
            if (!HasFilters)
            {
                return null;
            }

            var sourceTypes = SourceTypes.ToHashSet(StringComparer.OrdinalIgnoreCase);
            if (EntityTypes.Count > 0)
            {
                sourceTypes.Add("entity");
            }

            return sourceTypes.Count > 0
                ? sourceTypes.OrderBy(sourceType => sourceType, StringComparer.OrdinalIgnoreCase).ToList()
                : null;
        }

        public IReadOnlyList<string>? GetStoreEntityTypeFilter()
        {
            if (EntityTypes.Count == 0 || SourceTypes.Contains("entity"))
            {
                return null;
            }

            return EntityTypes
                .Select(entityType => entityType.ToString())
                .OrderBy(entityType => entityType, StringComparer.OrdinalIgnoreCase)
                .ToList();
        }

        public EntityType[]? GetGraphEntityTypeFilter()
        {
            if (SourceTypes.Contains("entity"))
            {
                return null;
            }

            return EntityTypes.Count > 0 ? EntityTypes.ToArray() : null;
        }
    }
}
