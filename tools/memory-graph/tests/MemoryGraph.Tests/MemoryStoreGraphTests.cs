using MemoryGraph.Graph;
using MemoryGraph.Storage;
using Microsoft.Data.Sqlite;
using Xunit;

namespace MemoryGraph.Tests;

public sealed class MemoryStoreGraphTests : IDisposable
{
    private readonly string _dbPath;
    private readonly MemoryStore _store;

    public MemoryStoreGraphTests()
    {
        _dbPath = Path.Combine(Path.GetTempPath(), $"memory-graph-test-{Guid.NewGuid()}.db");
        _store = new MemoryStore(_dbPath);
    }

    public void Dispose()
    {
        _store.Dispose();
        if (File.Exists(_dbPath))
        {
            File.Delete(_dbPath);
        }
    }

    [Fact]
    public void IndexGraphEntities_MakesEntitiesSearchable()
    {
        var entities = new List<(string Name, string Type, List<string> Observations)>
        {
            ("MyAPI", "Project", new List<string> { "ASP.NET Core Minimal APIs", "Clean Architecture" }),
            ("EF Core", "Technology", new List<string> { "ORM for .NET", "Code-first migrations" })
        };

        _store.IndexGraphEntities(entities);

        var results = _store.Search("Minimal APIs");
        Assert.Single(results);
        Assert.Equal("MyAPI", results[0].SourceId);
    }

    [Fact]
    public void PruneGraphEntityIndex_RemovesEntityRowsMissingFromGraph()
    {
        _store.IndexInFts("entity", "LiveProject", "LiveProject", "live searchable content", "Project");
        _store.IndexInFts("entity", "OrphanProject", "OrphanProject", "orphan searchable content", "Project");
        _store.IndexInFts("reflexion", "1", "Orphan task", "orphan reflexion content", "feature");

        var pruned = _store.PruneGraphEntityIndex(["LiveProject"]);

        Assert.Equal(1, pruned);
        Assert.Empty(_store.Search("orphan searchable", sourceType: "entity"));
        Assert.Single(_store.Search("live searchable", sourceType: "entity"));
        Assert.Single(_store.Search("orphan reflexion", sourceType: "reflexion"));
    }

    [Fact]
    public void IndexGraphEntities_RemovesCaseVariantEntityRows()
    {
        _store.IndexInFts("entity", "api", "api", "stale lowercase api content", "Project");

        _store.IndexGraphEntities([
            ("API", "Project", new List<string> { "canonical uppercase api content" })
        ]);

        var results = _store.Search("api content", sourceType: "entity");
        Assert.Single(results);
        Assert.Equal("API", results[0].SourceId);
        Assert.Equal("API", results[0].Title);
    }

    [Fact]
    public void PruneGraphEntityIndex_RemovesCaseVariantEntityRows()
    {
        _store.IndexInFts("entity", "API", "API", "canonical uppercase api content", "Project");
        InsertFtsRow("entity", "api", "api", "stale lowercase api content", "Project");

        var pruned = _store.PruneGraphEntityIndex(["API"]);

        Assert.Equal(1, pruned);
        var results = _store.Search("api content", sourceType: "entity");
        Assert.Single(results);
        Assert.Equal("API", results[0].SourceId);
    }

    [Fact]
    public void GraphEntities_AddUpdateAndLookupCaseInsensitively()
    {
        var created = _store.AddOrUpdateGraphEntity(
            "TestProject",
            EntityType.Project,
            ["Uses SQLite", "Uses SQLite"]);

        var updated = _store.AddOrUpdateGraphEntity(
            "testproject",
            EntityType.Technology,
            ["uses sqlite", "Has graph tables"]);

        var entity = _store.GetGraphEntity("TESTPROJECT");
        var projects = _store.GetGraphEntitiesByType(EntityType.Project);

        Assert.True(created.Created);
        Assert.Equal(1, created.NewObservations);
        Assert.False(updated.Created);
        Assert.Equal(1, updated.NewObservations);
        Assert.NotNull(entity);
        Assert.Equal("TestProject", entity.Name);
        Assert.Equal(EntityType.Project, entity.Type);
        Assert.Equal(["Uses SQLite", "Has graph tables"], entity.Observations);
        Assert.Single(_store.GetAllGraphEntities());
        Assert.Single(projects);
    }

    [Fact]
    public void GraphEntities_MaintainFtsForDbRows()
    {
        _store.AddOrUpdateGraphEntity("SearchableProject", EntityType.Project, ["unique db graph content"]);

        var results = _store.Search("unique db graph", sourceType: "entity");

        Assert.Single(results);
        Assert.Equal("SearchableProject", results[0].SourceId);
    }

    [Fact]
    public void GraphRelations_DedupeQueryAndRemoveCaseInsensitively()
    {
        _store.AddOrUpdateGraphEntity("ProjectA", EntityType.Project, ["A"]);
        _store.AddOrUpdateGraphEntity("ProjectB", EntityType.Project, ["B"]);
        _store.AddOrUpdateGraphEntity("Library", EntityType.Technology, ["Lib"]);

        Assert.True(_store.AddGraphRelation("projecta", "PROJECTB", RelationType.DependsOn, "HTTP"));
        Assert.False(_store.AddGraphRelation("ProjectA", "ProjectB", RelationType.DependsOn, "Duplicate"));
        Assert.True(_store.AddGraphRelation("ProjectB", "Library", RelationType.Uses));

        var fromA = _store.GetGraphRelationsFrom("PROJECTA");
        var toB = _store.GetGraphRelationsTo("projectb");
        var forB = _store.GetGraphRelationsFor("PROJECTB");
        var all = _store.GetAllGraphRelations();

        Assert.Single(fromA);
        Assert.Equal("ProjectA", fromA[0].From);
        Assert.Equal("ProjectB", fromA[0].To);
        Assert.Equal("HTTP", fromA[0].Detail);
        Assert.Single(toB);
        Assert.Equal(2, forB.Count);
        Assert.Equal(2, all.Count);

        Assert.True(_store.RemoveGraphRelation("PROJECTA", "projectb", RelationType.DependsOn));
        Assert.False(_store.RemoveGraphRelation("PROJECTA", "projectb", RelationType.DependsOn));
        Assert.Empty(_store.GetGraphRelationsFrom("ProjectA"));
    }

    [Fact]
    public void GraphRelations_ValidateEndpoints()
    {
        _store.AddOrUpdateGraphEntity("ProjectA", EntityType.Project, ["A"]);

        var ex = Assert.Throws<KeyNotFoundException>(() =>
            _store.AddGraphRelation("ProjectA", "MissingProject", RelationType.DependsOn));

        Assert.Contains("Entity not found", ex.Message);
    }

    [Fact]
    public void GraphEntityRemove_CascadesRelationsObservationsAndPrunesFts()
    {
        _store.AddOrUpdateGraphEntity("ProjectA", EntityType.Project, ["cascade searchable content"]);
        _store.AddOrUpdateGraphEntity("ProjectB", EntityType.Project, ["B"]);
        _store.AddGraphRelation("ProjectA", "ProjectB", RelationType.DependsOn);
        _store.AddGraphRelation("ProjectB", "ProjectA", RelationType.SharedWith);

        var removed = _store.RemoveGraphEntity("projecta");

        Assert.True(removed.Removed);
        Assert.Equal(2, removed.RelationsRemoved);
        Assert.Null(_store.GetGraphEntity("ProjectA"));
        Assert.Empty(_store.GetAllGraphRelations());
        Assert.Empty(_store.Search("cascade searchable", sourceType: "entity"));
    }

    [Fact]
    public void ExistingLegacyDatabase_InitializesGraphTablesWithoutRemovingRows()
    {
        var path = Path.Combine(Path.GetTempPath(), $"memory-legacy-{Guid.NewGuid()}.db");
        try
        {
            CreateLegacyDatabase(path);

            using var store = new MemoryStore(path);
            var reflexion = Assert.Single(store.GetAllReflexions());
            var decision = Assert.Single(store.GetAllDecisions());

            store.AddOrUpdateGraphEntity("LegacyProject", EntityType.Project, ["existing db can grow graph tables"]);
            store.AddOrUpdateGraphEntity("SQLite", EntityType.Technology, ["embedded database"]);
            Assert.True(store.AddGraphRelation("LegacyProject", "SQLite", RelationType.Uses));

            Assert.Equal("Legacy task", reflexion.TaskDescription);
            Assert.Equal("Legacy decision", decision.Title);
            Assert.Single(store.GetAllGraphRelations());
            Assert.Single(store.Search("grow graph tables", sourceType: "entity"));
        }
        finally
        {
            File.Delete(path);
        }
    }

    private void InsertFtsRow(string sourceType, string sourceId, string title, string content, string tags)
    {
        using var connection = new SqliteConnection($"Data Source={_dbPath}");
        connection.Open();
        using var command = connection.CreateCommand();
        command.CommandText = """
            INSERT INTO memory_fts (source_type, source_id, title, content, tags)
            VALUES (@type, @id, @title, @content, @tags)
            """;
        command.Parameters.AddWithValue("@type", sourceType);
        command.Parameters.AddWithValue("@id", sourceId);
        command.Parameters.AddWithValue("@title", title);
        command.Parameters.AddWithValue("@content", content);
        command.Parameters.AddWithValue("@tags", tags);
        command.ExecuteNonQuery();
    }

    private static void CreateLegacyDatabase(string path)
    {
        using var connection = new SqliteConnection($"Data Source={path}");
        connection.Open();
        using var command = connection.CreateCommand();
        command.CommandText = """
            CREATE TABLE reflexions (
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

            CREATE TABLE decisions (
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

            INSERT INTO reflexions (
                task_description, project, project_type, task_type, size,
                went_well, went_wrong, lessons, plan_accuracy, estimate_accuracy, first_attempt_success)
            VALUES (
                'Legacy task', 'LegacyProject', 'dotnet-api', 'feature', 'small',
                'Worked', 'None', 'Keep rows', 4, 4, 1);

            INSERT INTO decisions (title, decision, rationale, project)
            VALUES ('Legacy decision', 'Keep SQLite', 'Already embedded', 'LegacyProject');
            """;
        command.ExecuteNonQuery();
    }
}
