using Microsoft.Data.Sqlite;

namespace MemoryGraph.Storage;

/// <summary>
/// SQLite + FTS5 storage for reflexions, decisions, strategy lessons, and full-text search.
/// Lives alongside the existing JSONL graph store — does not replace it.
/// </summary>
public sealed class MemoryStore : IDisposable
{
    private readonly SqliteConnection _db;

    public MemoryStore(string dbPath)
    {
        var dir = Path.GetDirectoryName(dbPath);
        if (dir is not null && !Directory.Exists(dir))
        {
            Directory.CreateDirectory(dir);
        }

        _db = new SqliteConnection($"Data Source={dbPath}");
        _db.Open();
        InitializeSchema();
    }

    private void InitializeSchema()
    {
        using var cmd = _db.CreateCommand();
        cmd.CommandText = """
            -- Reflexions: post-task self-assessments
            CREATE TABLE IF NOT EXISTS reflexions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                task_description TEXT NOT NULL,
                project TEXT NOT NULL,
                project_type TEXT,
                task_type TEXT,
                size TEXT,
                went_well TEXT,
                went_wrong TEXT,
                lessons TEXT,
                plan_accuracy INTEGER,
                estimate_accuracy INTEGER,
                first_attempt_success INTEGER,
                created_at TEXT NOT NULL DEFAULT (datetime('now'))
            );

            -- Decisions: architectural and design decisions with rationale
            CREATE TABLE IF NOT EXISTS decisions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                decision TEXT NOT NULL,
                rationale TEXT NOT NULL,
                alternatives TEXT,
                constraints TEXT,
                project TEXT,
                tags TEXT,
                outcome TEXT,
                created_at TEXT NOT NULL DEFAULT (datetime('now'))
            );

            -- Strategy lessons: accumulated per project type
            CREATE TABLE IF NOT EXISTS strategy_lessons (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                project_type TEXT NOT NULL,
                phase TEXT NOT NULL,
                lesson TEXT NOT NULL,
                confidence REAL NOT NULL DEFAULT 0.5,
                reinforcement_count INTEGER NOT NULL DEFAULT 1,
                source_reflexion_id INTEGER REFERENCES reflexions(id),
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                last_reinforced TEXT NOT NULL DEFAULT (datetime('now'))
            );

            -- Confidence calibration tracking
            CREATE TABLE IF NOT EXISTS calibration (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                prediction_type TEXT NOT NULL,
                predicted TEXT NOT NULL,
                actual TEXT NOT NULL,
                was_accurate INTEGER NOT NULL,
                project_type TEXT,
                created_at TEXT NOT NULL DEFAULT (datetime('now'))
            );

            -- FTS5 full-text search index over all memory content
            CREATE VIRTUAL TABLE IF NOT EXISTS memory_fts USING fts5(
                source_type,
                source_id,
                title,
                content,
                tags,
                tokenize='porter unicode61'
            );

            -- Access tracking for relevance scoring
            CREATE TABLE IF NOT EXISTS access_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                source_type TEXT NOT NULL,
                source_id TEXT NOT NULL,
                accessed_at TEXT NOT NULL DEFAULT (datetime('now'))
            );
            """;
        cmd.ExecuteNonQuery();
    }

    // ── Reflexions ──────────────────────────────────────────────────

    public long AddReflexion(ReflexionEntry entry)
    {
        using var cmd = _db.CreateCommand();
        cmd.CommandText = """
            INSERT INTO reflexions (task_description, project, project_type, task_type, size,
                went_well, went_wrong, lessons, plan_accuracy, estimate_accuracy, first_attempt_success)
            VALUES (@task, @project, @projectType, @taskType, @size,
                @wentWell, @wentWrong, @lessons, @planAcc, @estAcc, @firstAttempt);
            SELECT last_insert_rowid();
            """;
        cmd.Parameters.AddWithValue("@task", entry.TaskDescription);
        cmd.Parameters.AddWithValue("@project", entry.Project);
        cmd.Parameters.AddWithValue("@projectType", (object?)entry.ProjectType ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@taskType", (object?)entry.TaskType ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@size", (object?)entry.Size ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@wentWell", entry.WentWell ?? "");
        cmd.Parameters.AddWithValue("@wentWrong", entry.WentWrong ?? "");
        cmd.Parameters.AddWithValue("@lessons", entry.Lessons ?? "");
        cmd.Parameters.AddWithValue("@planAcc", entry.PlanAccuracy);
        cmd.Parameters.AddWithValue("@estAcc", entry.EstimateAccuracy);
        cmd.Parameters.AddWithValue("@firstAttempt", entry.FirstAttemptSuccess ? 1 : 0);

        var id = (long)cmd.ExecuteScalar()!;

        // Index in FTS5
        IndexInFts("reflexion", id.ToString(), entry.TaskDescription,
            $"{entry.WentWell} {entry.WentWrong} {entry.Lessons}",
            $"{entry.ProjectType} {entry.TaskType} {entry.Project}");

        return id;
    }

    public List<ReflexionEntry> GetReflexions(string? projectType = null, string? taskType = null, int limit = 20)
    {
        using var cmd = _db.CreateCommand();
        var where = new List<string>();
        if (projectType is not null)
        {
            where.Add("project_type = @projectType");
            cmd.Parameters.AddWithValue("@projectType", projectType);
        }
        if (taskType is not null)
        {
            where.Add("task_type = @taskType");
            cmd.Parameters.AddWithValue("@taskType", taskType);
        }

        var whereClause = where.Count > 0 ? "WHERE " + string.Join(" AND ", where) : "";
        cmd.CommandText = $"SELECT * FROM reflexions {whereClause} ORDER BY created_at DESC LIMIT @limit";
        cmd.Parameters.AddWithValue("@limit", limit);

        return ReadReflexions(cmd);
    }

    // ── Decisions ───────────────────────────────────────────────────

    public long AddDecision(DecisionEntry entry)
    {
        using var cmd = _db.CreateCommand();
        cmd.CommandText = """
            INSERT INTO decisions (title, decision, rationale, alternatives, constraints, project, tags)
            VALUES (@title, @decision, @rationale, @alternatives, @constraints, @project, @tags);
            SELECT last_insert_rowid();
            """;
        cmd.Parameters.AddWithValue("@title", entry.Title);
        cmd.Parameters.AddWithValue("@decision", entry.Decision);
        cmd.Parameters.AddWithValue("@rationale", entry.Rationale);
        cmd.Parameters.AddWithValue("@alternatives", (object?)entry.Alternatives ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@constraints", (object?)entry.Constraints ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@project", (object?)entry.Project ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@tags", (object?)entry.Tags ?? DBNull.Value);

        var id = (long)cmd.ExecuteScalar()!;

        IndexInFts("decision", id.ToString(), entry.Title,
            $"{entry.Decision} {entry.Rationale} {entry.Alternatives}",
            entry.Tags ?? entry.Project ?? "");

        return id;
    }

    public List<DecisionEntry> GetDecisions(string? project = null, int limit = 20)
    {
        using var cmd = _db.CreateCommand();
        var whereClause = project is not null ? "WHERE project = @project" : "";
        if (project is not null)
        {
            cmd.Parameters.AddWithValue("@project", project);
        }
        cmd.CommandText = $"SELECT * FROM decisions {whereClause} ORDER BY created_at DESC LIMIT @limit";
        cmd.Parameters.AddWithValue("@limit", limit);

        return ReadDecisions(cmd);
    }

    // ── Strategy Lessons ────────────────────────────────────────────

    public long AddStrategyLesson(StrategyLesson lesson)
    {
        // Check for existing similar lesson first
        using var checkCmd = _db.CreateCommand();
        checkCmd.CommandText = """
            SELECT id, confidence, reinforcement_count FROM strategy_lessons
            WHERE project_type = @projectType AND phase = @phase AND lesson = @lesson
            """;
        checkCmd.Parameters.AddWithValue("@projectType", lesson.ProjectType);
        checkCmd.Parameters.AddWithValue("@phase", lesson.Phase);
        checkCmd.Parameters.AddWithValue("@lesson", lesson.Lesson);

        using var reader = checkCmd.ExecuteReader();
        if (reader.Read())
        {
            // Reinforce existing lesson
            var existingId = reader.GetInt64(0);
            var currentConfidence = reader.GetDouble(1);
            var count = reader.GetInt32(2);
            reader.Close();

            using var updateCmd = _db.CreateCommand();
            updateCmd.CommandText = """
                UPDATE strategy_lessons
                SET confidence = MIN(1.0, @confidence + 0.2),
                    reinforcement_count = @count + 1,
                    last_reinforced = datetime('now')
                WHERE id = @id
                """;
            updateCmd.Parameters.AddWithValue("@confidence", currentConfidence);
            updateCmd.Parameters.AddWithValue("@count", count);
            updateCmd.Parameters.AddWithValue("@id", existingId);
            updateCmd.ExecuteNonQuery();

            return existingId;
        }
        reader.Close();

        using var cmd = _db.CreateCommand();
        cmd.CommandText = """
            INSERT INTO strategy_lessons (project_type, phase, lesson, confidence, source_reflexion_id)
            VALUES (@projectType, @phase, @lesson, @confidence, @sourceId);
            SELECT last_insert_rowid();
            """;
        cmd.Parameters.AddWithValue("@projectType", lesson.ProjectType);
        cmd.Parameters.AddWithValue("@phase", lesson.Phase);
        cmd.Parameters.AddWithValue("@lesson", lesson.Lesson);
        cmd.Parameters.AddWithValue("@confidence", lesson.Confidence);
        cmd.Parameters.AddWithValue("@sourceId", (object?)lesson.SourceReflexionId ?? DBNull.Value);

        var id = (long)cmd.ExecuteScalar()!;

        IndexInFts("strategy", id.ToString(), $"{lesson.ProjectType} {lesson.Phase}",
            lesson.Lesson, lesson.ProjectType);

        return id;
    }

    public List<StrategyLesson> GetStrategyLessons(string projectType, string? phase = null, double minConfidence = 0.3)
    {
        using var cmd = _db.CreateCommand();
        var phaseFilter = phase is not null ? "AND phase = @phase" : "";
        if (phase is not null)
        {
            cmd.Parameters.AddWithValue("@phase", phase);
        }

        cmd.CommandText = $"""
            SELECT * FROM strategy_lessons
            WHERE project_type = @projectType {phaseFilter} AND confidence >= @minConf
            ORDER BY confidence DESC, last_reinforced DESC
            """;
        cmd.Parameters.AddWithValue("@projectType", projectType);
        cmd.Parameters.AddWithValue("@minConf", minConfidence);

        return ReadStrategyLessons(cmd);
    }

    // ── Calibration ─────────────────────────────────────────────────

    public void AddCalibration(string predictionType, string predicted, string actual, bool wasAccurate, string? projectType)
    {
        using var cmd = _db.CreateCommand();
        cmd.CommandText = """
            INSERT INTO calibration (prediction_type, predicted, actual, was_accurate, project_type)
            VALUES (@type, @predicted, @actual, @accurate, @projectType)
            """;
        cmd.Parameters.AddWithValue("@type", predictionType);
        cmd.Parameters.AddWithValue("@predicted", predicted);
        cmd.Parameters.AddWithValue("@actual", actual);
        cmd.Parameters.AddWithValue("@accurate", wasAccurate ? 1 : 0);
        cmd.Parameters.AddWithValue("@projectType", (object?)projectType ?? DBNull.Value);
        cmd.ExecuteNonQuery();
    }

    public CalibrationStats GetCalibrationStats(string? projectType = null)
    {
        using var cmd = _db.CreateCommand();
        var whereClause = projectType is not null ? "WHERE project_type = @projectType" : "";
        if (projectType is not null)
        {
            cmd.Parameters.AddWithValue("@projectType", projectType);
        }

        cmd.CommandText = $"""
            SELECT prediction_type,
                   COUNT(*) as total,
                   SUM(was_accurate) as accurate
            FROM calibration {whereClause}
            GROUP BY prediction_type
            """;

        var stats = new CalibrationStats();
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            stats.ByType[reader.GetString(0)] = new CalibrationTypeStats
            {
                Total = reader.GetInt32(1),
                Accurate = reader.GetInt32(2)
            };
        }

        return stats;
    }

    // ── FTS5 Search ─────────────────────────────────────────────────

    public void IndexInFts(string sourceType, string sourceId, string title, string content, string tags)
    {
        // Remove existing entry if present
        using var delCmd = _db.CreateCommand();
        delCmd.CommandText = "DELETE FROM memory_fts WHERE source_type = @type AND source_id = @id";
        delCmd.Parameters.AddWithValue("@type", sourceType);
        delCmd.Parameters.AddWithValue("@id", sourceId);
        delCmd.ExecuteNonQuery();

        using var cmd = _db.CreateCommand();
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
        using var cmd = _db.CreateCommand();
        var typeFilter = sourceType is not null ? "AND source_type = @type" : "";
        if (sourceType is not null)
        {
            cmd.Parameters.AddWithValue("@type", sourceType);
        }

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

    // ── Index graph entities into FTS5 ──────────────────────────────

    /// <summary>
    /// Indexes all graph entities into FTS5 for unified search.
    /// Called on startup after graph is loaded.
    /// </summary>
    public void IndexGraphEntities(IEnumerable<(string Name, string Type, List<string> Observations)> entities)
    {
        foreach (var (name, type, observations) in entities)
        {
            IndexInFts("entity", name, name, string.Join(" ", observations), type);
        }
    }

    // ── Stats ───────────────────────────────────────────────────────

    public MemoryStats GetStats()
    {
        var stats = new MemoryStats();

        using var cmd = _db.CreateCommand();
        cmd.CommandText = """
            SELECT 'reflexions' as tbl, COUNT(*) FROM reflexions
            UNION ALL SELECT 'decisions', COUNT(*) FROM decisions
            UNION ALL SELECT 'strategy_lessons', COUNT(*) FROM strategy_lessons
            UNION ALL SELECT 'calibration', COUNT(*) FROM calibration
            UNION ALL SELECT 'fts_entries', COUNT(*) FROM memory_fts
            """;

        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            var table = reader.GetString(0);
            var count = reader.GetInt32(1);
            switch (table)
            {
                case "reflexions": stats.Reflexions = count; break;
                case "decisions": stats.Decisions = count; break;
                case "strategy_lessons": stats.StrategyLessons = count; break;
                case "calibration": stats.CalibrationEntries = count; break;
                case "fts_entries": stats.FtsEntries = count; break;
            }
        }

        return stats;
    }

    // ── Consolidation ───────────────────────────────────────────────

    /// <summary>
    /// Decays strategy lessons that haven't been reinforced recently.
    /// Returns the number of lessons decayed and archived.
    /// </summary>
    public (int Decayed, int Archived) ConsolidateStrategyLessons()
    {
        // Decay lessons not reinforced in 90+ days
        using var decayCmd = _db.CreateCommand();
        decayCmd.CommandText = """
            UPDATE strategy_lessons
            SET confidence = MAX(0.0, confidence - 0.1)
            WHERE julianday('now') - julianday(last_reinforced) > 90
            AND confidence > 0.0
            """;
        var decayed = decayCmd.ExecuteNonQuery();

        // Archive (delete) lessons with confidence below threshold
        using var archiveCmd = _db.CreateCommand();
        archiveCmd.CommandText = """
            DELETE FROM strategy_lessons WHERE confidence < 0.1
            """;
        var archived = archiveCmd.ExecuteNonQuery();

        return (decayed, archived);
    }

    // ── Private helpers ─────────────────────────────────────────────

    private List<ReflexionEntry> ReadReflexions(SqliteCommand cmd)
    {
        var results = new List<ReflexionEntry>();
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            results.Add(new ReflexionEntry
            {
                Id = reader.GetInt64(0),
                TaskDescription = reader.GetString(1),
                Project = reader.GetString(2),
                ProjectType = reader.IsDBNull(3) ? null : reader.GetString(3),
                TaskType = reader.IsDBNull(4) ? null : reader.GetString(4),
                Size = reader.IsDBNull(5) ? null : reader.GetString(5),
                WentWell = reader.GetString(6),
                WentWrong = reader.GetString(7),
                Lessons = reader.GetString(8),
                PlanAccuracy = reader.GetInt32(9),
                EstimateAccuracy = reader.GetInt32(10),
                FirstAttemptSuccess = reader.GetInt32(11) == 1,
                CreatedAt = reader.GetString(12)
            });
        }
        return results;
    }

    private List<DecisionEntry> ReadDecisions(SqliteCommand cmd)
    {
        var results = new List<DecisionEntry>();
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            results.Add(new DecisionEntry
            {
                Id = reader.GetInt64(0),
                Title = reader.GetString(1),
                Decision = reader.GetString(2),
                Rationale = reader.GetString(3),
                Alternatives = reader.IsDBNull(4) ? null : reader.GetString(4),
                Constraints = reader.IsDBNull(5) ? null : reader.GetString(5),
                Project = reader.IsDBNull(6) ? null : reader.GetString(6),
                Tags = reader.IsDBNull(7) ? null : reader.GetString(7),
                Outcome = reader.IsDBNull(8) ? null : reader.GetString(8),
                CreatedAt = reader.GetString(9)
            });
        }
        return results;
    }

    private List<StrategyLesson> ReadStrategyLessons(SqliteCommand cmd)
    {
        var results = new List<StrategyLesson>();
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            results.Add(new StrategyLesson
            {
                Id = reader.GetInt64(0),
                ProjectType = reader.GetString(1),
                Phase = reader.GetString(2),
                Lesson = reader.GetString(3),
                Confidence = reader.GetDouble(4),
                ReinforcementCount = reader.GetInt32(5),
                SourceReflexionId = reader.IsDBNull(6) ? null : reader.GetInt64(6),
                CreatedAt = reader.GetString(7),
                LastReinforced = reader.GetString(8)
            });
        }
        return results;
    }

    /// <summary>
    /// Sanitizes a query string for FTS5. Wraps each term in double quotes
    /// to handle special characters (dots, hyphens, etc.) that FTS5 treats as syntax.
    /// Preserves explicit FTS5 operators (AND, OR, NOT) and quoted phrases.
    /// </summary>
    private static string SanitizeFtsQuery(string query)
    {
        // If already contains FTS5 syntax (quotes, AND/OR/NOT operators), use as-is
        if (query.Contains('"') || query.Contains(" AND ") || query.Contains(" OR ") || query.Contains(" NOT "))
        {
            return query;
        }

        // Split into words, strip internal quotes, and wrap each in quotes to handle special chars
        var words = query.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        return string.Join(" ", words.Select(w => $"\"{w.Replace("\"", "")}\""));
    }

    public void Dispose()
    {
        _db.Dispose();
    }
}
