using MemoryGraph.Graph;
using MemoryGraph.Storage;
using Microsoft.Data.Sqlite;
using Xunit;

namespace MemoryGraph.Tests;

public sealed class JsonlGraphImportTests : IDisposable
{
    private readonly string _dbPath;
    private readonly MemoryStore _store;

    public JsonlGraphImportTests()
    {
        _dbPath = Path.Combine(Path.GetTempPath(), $"jsonl-graph-import-{Guid.NewGuid()}.db");
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
    public void ImportGraphJsonl_ImportsAdditivelyAndNoOpsWhenUnchanged()
    {
        _store.AddOrUpdateGraphEntity("DbOnly", EntityType.Project, ["DB-only row"]);
        var path = TempJsonlFile("""
            {"kind":"entity","name":"TestProject","type":"project","observations":["First","first","Second"],"sourceFile":"graph.jsonl","createdAt":"2026-03-18T10:00:00Z","updatedAt":"2026-03-19T10:00:00Z"}
            {"kind":"entity","name":"Other","type":"technology","observations":["Other obs"],"createdAt":"2026-03-18T10:00:00Z","updatedAt":"2026-03-18T10:00:00Z"}
            {"kind":"relation","from":"TestProject","to":"Other","type":"uses","detail":"SDK","createdAt":"2026-03-20T10:00:00Z"}
            {"kind":"relation","from":"testproject","to":"other","type":"uses","detail":"duplicate"}
            {"kind":"relation","from":"Missing","to":"Other","type":"uses"}
            this is not json
            {"name":"NoKind"}
            """);

        try
        {
            var imported = _store.ImportGraphJsonl(path);
            var repeated = _store.ImportGraphJsonl(path);

            var entity = _store.GetGraphEntity("testproject");
            var dbOnly = _store.GetGraphEntity("DbOnly");
            var relation = Assert.Single(_store.GetAllGraphRelations());

            Assert.False(imported.NoOp);
            Assert.Equal(7, imported.LinesRead);
            Assert.Equal(2, imported.SkippedLines);
            Assert.Equal(2, imported.EntitiesRead);
            Assert.Equal(2, imported.EntitiesCreated);
            Assert.Equal(3, imported.ObservationsAdded);
            Assert.Equal(3, imported.RelationsRead);
            Assert.Equal(1, imported.RelationsCreated);
            Assert.Equal(1, imported.RelationsDeduplicated);
            Assert.Equal(1, imported.RelationsSkipped);

            Assert.True(repeated.NoOp);
            Assert.Equal(imported.ImportId, repeated.ImportId);
            Assert.NotNull(entity);
            Assert.Equal(["First", "Second"], entity.Observations);
            Assert.Equal("graph.jsonl", entity.SourceFile);
            Assert.Equal(new DateTime(2026, 3, 18, 10, 0, 0, DateTimeKind.Utc), entity.CreatedAt);
            Assert.Equal(new DateTime(2026, 3, 19, 10, 0, 0, DateTimeKind.Utc), entity.UpdatedAt);
            Assert.NotNull(dbOnly);
            Assert.Equal("TestProject", relation.From);
            Assert.Equal("Other", relation.To);
            Assert.Equal(RelationType.Uses, relation.Type);
            Assert.Equal("SDK", relation.Detail);
            Assert.Equal(new DateTime(2026, 3, 20, 10, 0, 0, DateTimeKind.Utc), relation.CreatedAt);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void ImportGraphJsonl_ImportsRelationBeforeEntityLines()
    {
        var path = TempJsonlFile("""
            {"kind":"relation","from":"ProjectA","to":"LibraryB","type":"uses","detail":"SDK","createdAt":"2026-03-20T10:00:00Z"}
            {"kind":"entity","name":"ProjectA","type":"project","observations":["Project observation"],"createdAt":"2026-03-18T10:00:00Z","updatedAt":"2026-03-18T10:00:00Z"}
            {"kind":"entity","name":"LibraryB","type":"technology","observations":["Library observation"],"createdAt":"2026-03-19T10:00:00Z","updatedAt":"2026-03-19T10:00:00Z"}
            """);

        try
        {
            var imported = _store.ImportGraphJsonl(path);

            var relation = Assert.Single(_store.GetAllGraphRelations());
            Assert.Equal(2, imported.EntitiesCreated);
            Assert.Equal(1, imported.RelationsRead);
            Assert.Equal(1, imported.RelationsCreated);
            Assert.Equal(0, imported.RelationsSkipped);
            Assert.Equal("ProjectA", relation.From);
            Assert.Equal("LibraryB", relation.To);
            Assert.Equal("SDK", relation.Detail);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void ImportGraphJsonl_SkipsRowsWithNonStringKind()
    {
        var path = TempJsonlFile("""
            {"kind":"entity","name":"ProjectA","type":"project","observations":["Valid"]}
            {"kind":0,"name":"NumericKind","type":"project","observations":["Must not abort import"]}
            """);

        try
        {
            var imported = _store.ImportGraphJsonl(path);

            Assert.Equal(2, imported.LinesRead);
            Assert.Equal(1, imported.SkippedLines);
            Assert.Equal(1, imported.EntitiesRead);
            Assert.Equal(1, imported.EntitiesCreated);
            Assert.NotNull(_store.GetGraphEntity("ProjectA"));
            Assert.Null(_store.GetGraphEntity("NumericKind"));
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void ImportGraphJsonl_SkipsEntityRowsMissingType()
    {
        var path = TempJsonlFile("""
            {"kind":"entity","name":"ProjectA","type":"project","observations":["Valid"]}
            {"kind":"entity","name":"MissingType","observations":["Must not default to Project"]}
            """);

        try
        {
            var imported = _store.ImportGraphJsonl(path);

            Assert.Equal(2, imported.LinesRead);
            Assert.Equal(1, imported.SkippedLines);
            Assert.Equal(1, imported.EntitiesRead);
            Assert.Equal(1, imported.EntitiesCreated);
            Assert.NotNull(_store.GetGraphEntity("ProjectA"));
            Assert.Null(_store.GetGraphEntity("MissingType"));
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void ImportGraphJsonl_SkipsEntityRowsWithNumericType()
    {
        var path = TempJsonlFile("""
            {"kind":"entity","name":"ProjectA","type":"project","observations":["Valid"]}
            {"kind":"entity","name":"NumericType","type":0,"observations":["Must not default to Project"]}
            """);

        try
        {
            var imported = _store.ImportGraphJsonl(path);

            Assert.Equal(2, imported.LinesRead);
            Assert.Equal(1, imported.SkippedLines);
            Assert.Equal(1, imported.EntitiesRead);
            Assert.Equal(1, imported.EntitiesCreated);
            Assert.NotNull(_store.GetGraphEntity("ProjectA"));
            Assert.Null(_store.GetGraphEntity("NumericType"));
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void ImportGraphJsonl_SkipsEntityRowsWithMalformedObservations()
    {
        var path = TempJsonlFile("""
            {"kind":"entity","name":"ProjectA","type":"project","observations":["Valid"]}
            {"kind":"entity","name":"ProjectB","type":"project"}
            {"kind":"entity","name":"NullObservation","type":"project","observations":[null]}
            {"kind":"entity","name":"NumberObservation","type":"project","observations":[1]}
            {"kind":"entity","name":"ObjectObservation","type":"project","observations":[{}]}
            {"kind":"entity","name":"MixedObservation","type":"project","observations":["Valid",1]}
            {"kind":"entity","name":"NonArrayObservation","type":"project","observations":"not-array"}
            """);

        try
        {
            var imported = _store.ImportGraphJsonl(path);

            Assert.Equal(7, imported.LinesRead);
            Assert.Equal(5, imported.SkippedLines);
            Assert.Equal(2, imported.EntitiesRead);
            Assert.Equal(2, imported.EntitiesCreated);
            Assert.Equal(1, imported.ObservationsAdded);
            Assert.NotNull(_store.GetGraphEntity("ProjectA"));
            Assert.NotNull(_store.GetGraphEntity("ProjectB"));
            Assert.Null(_store.GetGraphEntity("NullObservation"));
            Assert.Null(_store.GetGraphEntity("NumberObservation"));
            Assert.Null(_store.GetGraphEntity("ObjectObservation"));
            Assert.Null(_store.GetGraphEntity("MixedObservation"));
            Assert.Null(_store.GetGraphEntity("NonArrayObservation"));
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void ImportGraphJsonl_SkipsRelationRowsMissingType()
    {
        var path = TempJsonlFile("""
            {"kind":"entity","name":"ProjectA","type":"project","observations":["A"]}
            {"kind":"entity","name":"ProjectB","type":"project","observations":["B"]}
            {"kind":"relation","from":"ProjectA","to":"ProjectB","type":"uses","detail":"Valid"}
            {"kind":"relation","from":"ProjectA","to":"ProjectB","detail":"Must not default to DependsOn"}
            """);

        try
        {
            var imported = _store.ImportGraphJsonl(path);
            var relation = Assert.Single(_store.GetAllGraphRelations());

            Assert.Equal(4, imported.LinesRead);
            Assert.Equal(1, imported.SkippedLines);
            Assert.Equal(1, imported.RelationsRead);
            Assert.Equal(1, imported.RelationsCreated);
            Assert.Equal(RelationType.Uses, relation.Type);
            Assert.Equal("Valid", relation.Detail);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void ImportGraphJsonl_SkipsRelationRowsWithNumericType()
    {
        var path = TempJsonlFile("""
            {"kind":"entity","name":"ProjectA","type":"project","observations":["A"]}
            {"kind":"entity","name":"ProjectB","type":"project","observations":["B"]}
            {"kind":"relation","from":"ProjectA","to":"ProjectB","type":"uses","detail":"Valid"}
            {"kind":"relation","from":"ProjectA","to":"ProjectB","type":0,"detail":"Must not default to DependsOn"}
            """);

        try
        {
            var imported = _store.ImportGraphJsonl(path);
            var relation = Assert.Single(_store.GetAllGraphRelations());

            Assert.Equal(4, imported.LinesRead);
            Assert.Equal(1, imported.SkippedLines);
            Assert.Equal(1, imported.RelationsRead);
            Assert.Equal(1, imported.RelationsCreated);
            Assert.Equal(RelationType.Uses, relation.Type);
            Assert.Equal("Valid", relation.Detail);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void ImportGraphJsonl_ReimportsChangedFileWithoutDeletingAbsentRows()
    {
        var path = TempJsonlFile("""
            {"kind":"entity","name":"ProjectA","type":"project","observations":["One"],"createdAt":"2026-03-18T10:00:00Z","updatedAt":"2026-03-18T10:00:00Z"}
            """);

        try
        {
            _store.ImportGraphJsonl(path);
            File.WriteAllText(path, """
                {"kind":"entity","name":"ProjectA","type":"project","observations":["one","Two"],"createdAt":"2026-03-18T10:00:00Z","updatedAt":"2026-03-20T10:00:00Z"}
                {"kind":"entity","name":"ProjectB","type":"project","observations":["Three"],"createdAt":"2026-03-21T10:00:00Z","updatedAt":"2026-03-21T10:00:00Z"}
                """);

            var imported = _store.ImportGraphJsonl(path);

            var projectA = _store.GetGraphEntity("projecta");
            var projectB = _store.GetGraphEntity("projectb");

            Assert.False(imported.NoOp);
            Assert.Equal(2, imported.EntitiesRead);
            Assert.Equal(1, imported.EntitiesCreated);
            Assert.Equal(1, imported.EntitiesUpdated);
            Assert.NotNull(projectA);
            Assert.Equal(["One", "Two"], projectA.Observations);
            Assert.Equal(new DateTime(2026, 3, 20, 10, 0, 0, DateTimeKind.Utc), projectA.UpdatedAt);
            Assert.NotNull(projectB);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void ImportGraphJsonl_ReimportsTimestampOnlyEntityUpdates()
    {
        var path = TempJsonlFile("""
            {"kind":"entity","name":"ProjectA","type":"project","observations":["One"],"createdAt":"2026-03-18T10:00:00Z","updatedAt":"2026-03-18T10:00:00Z"}
            """);

        try
        {
            _store.ImportGraphJsonl(path);
            File.WriteAllText(path, """
                {"kind":"entity","name":"ProjectA","type":"project","observations":["one"],"createdAt":"2026-03-18T10:00:00Z","updatedAt":"2026-03-22T10:00:00Z"}
                """);

            var imported = _store.ImportGraphJsonl(path);

            var projectA = _store.GetGraphEntity("projecta");

            Assert.Equal(1, imported.EntitiesRead);
            Assert.Equal(0, imported.ObservationsAdded);
            Assert.Equal(1, imported.EntitiesUpdated);
            Assert.NotNull(projectA);
            Assert.Equal(["One"], projectA.Observations);
            Assert.Equal(new DateTime(2026, 3, 22, 10, 0, 0, DateTimeKind.Utc), projectA.UpdatedAt);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void ImportGraphJsonl_AddingObservationWithOlderTimestampDoesNotRegressUpdatedAt()
    {
        var path = TempJsonlFile("""
            {"kind":"entity","name":"ProjectA","type":"project","observations":["One"],"createdAt":"2026-03-18T10:00:00Z","updatedAt":"2026-03-22T10:00:00Z"}
            """);

        try
        {
            _store.ImportGraphJsonl(path);
            File.WriteAllText(path, """
                {"kind":"entity","name":"ProjectA","type":"project","observations":["one","Two"],"createdAt":"2026-03-18T10:00:00Z","updatedAt":"2026-03-19T10:00:00Z"}
                """);

            var imported = _store.ImportGraphJsonl(path);

            var projectA = _store.GetGraphEntity("projecta");

            Assert.Equal(1, imported.EntitiesRead);
            Assert.Equal(1, imported.ObservationsAdded);
            Assert.Equal(1, imported.EntitiesUpdated);
            Assert.NotNull(projectA);
            Assert.Equal(["One", "Two"], projectA.Observations);
            Assert.Equal(new DateTime(2026, 3, 22, 10, 0, 0, DateTimeKind.Utc), projectA.UpdatedAt);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void ImportGraphJsonl_RollsBackDataAndImportRecordOnStorageFailure()
    {
        var path = TempJsonlFile("""
            {"kind":"entity","name":"ProjectA","type":"project","observations":["Should rollback"],"createdAt":"2026-03-18T10:00:00Z","updatedAt":"2026-03-18T10:00:00Z"}
            {"kind":"entity","name":"ProjectB","type":"project","observations":["Other"],"createdAt":"2026-03-18T10:00:00Z","updatedAt":"2026-03-18T10:00:00Z"}
            {"kind":"relation","from":"ProjectA","to":"ProjectB","type":"dependsOn"}
            """);

        try
        {
            ExecuteNonQuery(_dbPath, "DROP TABLE graph_relations");

            Assert.Throws<SqliteException>(() => _store.ImportGraphJsonl(path));

            Assert.Equal(0, CountRows(_dbPath, "graph_entities"));
            Assert.Equal(0, CountRows(_dbPath, "jsonl_imports"));
            Assert.Empty(_store.Search("Should rollback", sourceType: "entity"));
        }
        finally
        {
            File.Delete(path);
        }
    }

    private static void ExecuteNonQuery(string dbPath, string sql)
    {
        using var connection = new SqliteConnection($"Data Source={dbPath}");
        connection.Open();
        using var command = connection.CreateCommand();
        command.CommandText = sql;
        command.ExecuteNonQuery();
    }

    private static int CountRows(string dbPath, string table)
    {
        using var connection = new SqliteConnection($"Data Source={dbPath}");
        connection.Open();
        using var command = connection.CreateCommand();
        command.CommandText = $"SELECT COUNT(*) FROM {table}";
        return Convert.ToInt32(command.ExecuteScalar());
    }

    private static string TempJsonlFile(string content)
    {
        var path = Path.Combine(Path.GetTempPath(), $"memory-graph-import-{Guid.NewGuid()}.jsonl");
        File.WriteAllText(path, content);
        return path;
    }
}
