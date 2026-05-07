using Microsoft.Data.Sqlite;

namespace MemoryGraph.Storage;

public sealed partial class MemoryStore
{
    // ── FTS5 Search ─────────────────────────────────────────────────

    public void IndexInFts(string sourceType, string sourceId, string title, string content, string tags)
    {
        IndexInFtsCore(sourceType, sourceId, title, content, tags);
    }

    private void IndexInFtsCore(
        string sourceType,
        string sourceId,
        string title,
        string content,
        string tags,
        SqliteTransaction? transaction = null)
    {
        // Remove existing entry if present
        using var delCmd = _db.CreateCommand();
        delCmd.Transaction = transaction;
        delCmd.CommandText = sourceType.Equals("entity", StringComparison.OrdinalIgnoreCase)
            ? "DELETE FROM memory_fts WHERE source_type = @type AND source_id = @id COLLATE NOCASE"
            : "DELETE FROM memory_fts WHERE source_type = @type AND source_id = @id";
        delCmd.Parameters.AddWithValue("@type", sourceType);
        delCmd.Parameters.AddWithValue("@id", sourceId);
        delCmd.ExecuteNonQuery();

        using var cmd = _db.CreateCommand();
        cmd.Transaction = transaction;
        cmd.CommandText = """
            INSERT INTO memory_fts (source_type, source_id, title, content, tags)
            VALUES (@type, @id, @title, @content, @tags)
            """;
        cmd.Parameters.AddWithValue("@type", sourceType);
        cmd.Parameters.AddWithValue("@id", sourceId);
        cmd.Parameters.AddWithValue("@title", title);
        cmd.Parameters.AddWithValue("@content", content);
        cmd.Parameters.AddWithValue("@tags", tags);
        cmd.ExecuteNonQuery();
    }

    /// <summary>
    /// Full-text search across all indexed memory content using FTS5.
    /// Returns results ranked by relevance.
    /// </summary>
    public List<FtsResult> Search(string query, string? sourceType = null, int limit = 20)
    {
        IReadOnlyList<string> sourceTypes = sourceType is null
            ? Array.Empty<string>()
            : [sourceType];

        return SearchCore(query, sourceTypes, [], limit);
    }

    /// <summary>
    /// Full-text search across selected indexed memory source types using FTS5.
    /// Returns results ranked by relevance.
    /// </summary>
    public List<FtsResult> Search(string query, IEnumerable<string> sourceTypes, int limit = 20)
    {
        var normalizedSourceTypes = NormalizeFilterTerms(sourceTypes);

        return SearchCore(query, normalizedSourceTypes, [], limit);
    }

    /// <summary>
    /// Full-text search across selected indexed source types, constraining entity rows by
    /// their indexed entity type before the FTS limit is applied.
    /// </summary>
    public List<FtsResult> Search(
        string query,
        IEnumerable<string> sourceTypes,
        IEnumerable<string> entityTypes,
        int limit = 20)
    {
        var normalizedSourceTypes = NormalizeFilterTerms(sourceTypes);
        var normalizedEntityTypes = NormalizeFilterTerms(entityTypes);

        return SearchCore(query, normalizedSourceTypes, normalizedEntityTypes, limit);
    }

    private List<FtsResult> SearchCore(
        string query,
        IReadOnlyList<string> sourceTypes,
        IReadOnlyList<string> entityTypes,
        int limit)
    {
        using var cmd = _db.CreateCommand();
        var typeFilter = BuildFtsFilter(cmd, sourceTypes, entityTypes);

        // Sanitize query for FTS5: wrap each word in quotes to handle special chars like dots
        var sanitizedQuery = SanitizeFtsQuery(query);

        cmd.CommandText = $"""
            SELECT source_type, source_id, title, snippet(memory_fts, 3, '>>>', '<<<', '...', 40) as snippet,
                   rank
            FROM memory_fts
            WHERE memory_fts MATCH @query {typeFilter}
            ORDER BY rank
            LIMIT @limit
            """;
        cmd.Parameters.AddWithValue("@query", sanitizedQuery);
        cmd.Parameters.AddWithValue("@limit", limit);

        var results = new List<FtsResult>();
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            results.Add(new FtsResult
            {
                SourceType = reader.GetString(0),
                SourceId = reader.GetString(1),
                Title = reader.GetString(2),
                Snippet = reader.GetString(3),
                Rank = reader.GetDouble(4)
            });
        }

        return results;
    }

    private static string[] NormalizeFilterTerms(IEnumerable<string> values)
    {
        return values
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    private static string BuildFtsFilter(
        SqliteCommand cmd,
        IReadOnlyList<string> sourceTypes,
        IReadOnlyList<string> entityTypes)
    {
        if (entityTypes.Count == 0)
        {
            return BuildSourceTypeFilter(cmd, sourceTypes);
        }

        if (sourceTypes.Count == 0)
        {
            return $"AND {BuildEntityTypeClause(cmd, entityTypes)}";
        }

        var nonEntitySourceTypes = sourceTypes
            .Where(sourceType => !sourceType.Equals("entity", StringComparison.OrdinalIgnoreCase))
            .ToArray();
        var clauses = new List<string>();
        if (nonEntitySourceTypes.Length > 0)
        {
            clauses.Add(BuildSourceTypePredicate(cmd, nonEntitySourceTypes));
        }

        if (sourceTypes.Contains("entity", StringComparer.OrdinalIgnoreCase))
        {
            clauses.Add(BuildEntityTypeClause(cmd, entityTypes));
        }

        return clauses.Count == 0
            ? ""
            : $"AND ({string.Join(" OR ", clauses)})";
    }

    private static string BuildSourceTypeFilter(SqliteCommand cmd, IReadOnlyList<string> sourceTypes)
    {
        if (sourceTypes.Count == 0)
        {
            return "";
        }

        return $"AND {BuildSourceTypePredicate(cmd, sourceTypes)}";
    }

    private static string BuildSourceTypePredicate(SqliteCommand cmd, IReadOnlyList<string> sourceTypes)
    {
        if (sourceTypes.Count == 1)
        {
            cmd.Parameters.AddWithValue("@type0", sourceTypes[0]);
            return "source_type = @type0";
        }

        var parameters = new List<string>();
        for (var i = 0; i < sourceTypes.Count; i++)
        {
            var parameterName = $"@type{i}";
            parameters.Add(parameterName);
            cmd.Parameters.AddWithValue(parameterName, sourceTypes[i]);
        }

        return $"source_type IN ({string.Join(", ", parameters)})";
    }

    private static string BuildEntityTypeClause(SqliteCommand cmd, IReadOnlyList<string> entityTypes)
    {
        cmd.Parameters.AddWithValue("@entitySourceType", "entity");
        return $"(source_type = @entitySourceType AND {BuildEntityTypePredicate(cmd, entityTypes)})";
    }

    private static string BuildEntityTypePredicate(SqliteCommand cmd, IReadOnlyList<string> entityTypes)
    {
        if (entityTypes.Count == 1)
        {
            cmd.Parameters.AddWithValue("@entityType0", entityTypes[0]);
            return "tags COLLATE NOCASE = @entityType0";
        }

        var parameters = new List<string>();
        for (var i = 0; i < entityTypes.Count; i++)
        {
            var parameterName = $"@entityType{i}";
            parameters.Add(parameterName);
            cmd.Parameters.AddWithValue(parameterName, entityTypes[i]);
        }

        return $"tags COLLATE NOCASE IN ({string.Join(", ", parameters)})";
    }

    // ── Index graph entities into FTS5 ──────────────────────────────

    /// <summary>
    /// Indexes all graph entities into FTS5 for unified search.
    /// Used when legacy import/fallback callers provide graph entity snapshots.
    /// </summary>
    public void IndexGraphEntities(IEnumerable<(string Name, string Type, List<string> Observations)> entities)
    {
        foreach (var (name, type, observations) in entities)
        {
            IndexInFts("entity", name, name, string.Join(" ", observations), type);
        }
    }

    /// <summary>
    /// Removes indexed graph entities that no longer exist in the graph.
    /// </summary>
    public int PruneGraphEntityIndex(IEnumerable<string> validEntityNames)
    {
        var valid = validEntityNames
            .GroupBy(name => name, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => group.First(), StringComparer.OrdinalIgnoreCase);
        var stale = new List<string>();

        using (var selectCmd = _db.CreateCommand())
        {
            selectCmd.CommandText = "SELECT source_id FROM memory_fts WHERE source_type = 'entity'";
            using var reader = selectCmd.ExecuteReader();
            while (reader.Read())
            {
                var sourceId = reader.GetString(0);
                if (!valid.TryGetValue(sourceId, out var canonical) ||
                    !sourceId.Equals(canonical, StringComparison.Ordinal))
                {
                    stale.Add(sourceId);
                }
            }
        }

        foreach (var sourceId in stale)
        {
            using var deleteCmd = _db.CreateCommand();
            deleteCmd.CommandText = "DELETE FROM memory_fts WHERE source_type = 'entity' AND source_id = @id";
            deleteCmd.Parameters.AddWithValue("@id", sourceId);
            deleteCmd.ExecuteNonQuery();
        }

        return stale.Count;
    }

    /// <summary>
    /// Reports graph entity FTS rows that do not match the live graph snapshot.
    /// This is read-only; callers that need repair must call pruning explicitly.
    /// </summary>
    public GraphEntityFtsDiagnostics GetGraphEntityFtsDiagnostics(IEnumerable<string> validEntityNames)
    {
        var valid = validEntityNames
            .GroupBy(name => name, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => group.First(), StringComparer.OrdinalIgnoreCase);
        var diagnostics = new GraphEntityFtsDiagnostics();

        using var selectCmd = _db.CreateCommand();
        selectCmd.CommandText = """
            SELECT source_id, title, tags
            FROM memory_fts
            WHERE source_type = 'entity'
            ORDER BY source_id COLLATE NOCASE
            """;

        using var reader = selectCmd.ExecuteReader();
        while (reader.Read())
        {
            diagnostics.EntityRows++;

            var sourceId = reader.GetString(0);
            var title = reader.GetString(1);
            var tags = reader.IsDBNull(2) ? null : reader.GetString(2);
            if (!valid.TryGetValue(sourceId, out var canonical))
            {
                diagnostics.OrphanEntityRows++;
                diagnostics.StaleRows.Add(new GraphEntityFtsIssue
                {
                    SourceId = sourceId,
                    Title = title,
                    Tags = tags,
                    Reason = "orphanEntity"
                });
                continue;
            }

            if (!sourceId.Equals(canonical, StringComparison.Ordinal))
            {
                diagnostics.NonCanonicalEntityRows++;
                diagnostics.StaleRows.Add(new GraphEntityFtsIssue
                {
                    SourceId = sourceId,
                    Title = title,
                    Tags = tags,
                    Reason = "nonCanonicalEntityId",
                    CanonicalName = canonical
                });
            }
        }

        return diagnostics;
    }

    public int CountStaleGraphEntityFtsRows(IEnumerable<string> validEntityNames) =>
        GetGraphEntityFtsDiagnostics(validEntityNames).StaleEntityRows;

    /// <summary>
    /// Sanitizes a query string for FTS5. Wraps terms in double quotes to handle
    /// path-like characters while preserving boolean operators and quoted phrases.
    /// </summary>
    private static string SanitizeFtsQuery(string query)
    {
        return string.Join(" ", TokenizeFtsQuery(query).Select(token =>
        {
            if (!token.IsQuoted && IsFtsOperator(token.Text))
            {
                return token.Text.ToUpperInvariant();
            }

            return $"\"{token.Text.Replace("\"", "\"\"")}\"";
        }));
    }

    private static IEnumerable<FtsQueryToken> TokenizeFtsQuery(string query)
    {
        var tokenizer = new FtsQueryTokenizer();

        foreach (var c in query)
        {
            var token = tokenizer.Read(c);
            if (token.HasValue)
            {
                yield return token.Value;
            }
        }

        var finalToken = tokenizer.Flush();
        if (finalToken.HasValue)
        {
            yield return finalToken.Value;
        }
    }

    private static FtsQueryToken NormalizeFtsToken(string text, bool isQuoted)
    {
        var normalizedText = !isQuoted && IsFtsOperator(text)
            ? text.ToUpperInvariant()
            : text;

        return new FtsQueryToken(normalizedText, isQuoted);
    }

    private static bool IsFtsOperator(string text)
    {
        return text is "AND" or "OR" or "NOT";
    }

    private readonly record struct FtsQueryToken(string Text, bool IsQuoted);

    private sealed class FtsQueryTokenizer
    {
        private readonly List<char> _current = new();
        private bool _inQuote;
        private bool _tokenWasQuoted;

        public FtsQueryToken? Read(char c)
        {
            if (c == '"')
            {
                return ReadQuote();
            }

            if (char.IsWhiteSpace(c) && !_inQuote)
            {
                return ReadWhitespace();
            }

            _current.Add(c);
            return null;
        }

        public FtsQueryToken? Flush()
        {
            return _current.Count > 0 ? CreateToken(_tokenWasQuoted) : null;
        }

        private FtsQueryToken? ReadQuote()
        {
            if (_inQuote)
            {
                var token = _current.Count > 0 ? CreateToken(isQuoted: true) : (FtsQueryToken?)null;
                _current.Clear();
                _inQuote = false;
                _tokenWasQuoted = false;
                return token;
            }

            var pending = Flush();
            _inQuote = true;
            _tokenWasQuoted = true;
            return pending;
        }

        private FtsQueryToken? ReadWhitespace()
        {
            var token = Flush();
            _tokenWasQuoted = false;
            return token;
        }

        private FtsQueryToken CreateToken(bool isQuoted)
        {
            var token = NormalizeFtsToken(new string(_current.ToArray()), isQuoted);
            _current.Clear();
            return token;
        }
    }
}
