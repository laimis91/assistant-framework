using MemoryGraph.Graph;
using Xunit;

namespace MemoryGraph.Tests;

public class GraphStoreTests
{
    private static string TempFile() => Path.Combine(Path.GetTempPath(), $"test-store-{Guid.NewGuid()}.jsonl");

    [Fact]
    public void Load_NonExistentFile_ReturnsEmpty()
    {
        var store = new GraphStore(TempFile());

        var (entities, relations, _) = store.Load();

        Assert.Empty(entities);
        Assert.Empty(relations);
    }

    [Fact]
    public void SaveAndLoad_RoundTripsEntities()
    {
        var path = TempFile();
        var store = new GraphStore(path);

        var entities = new List<Entity>
        {
            new()
            {
                Name = "TestProject",
                Type = EntityType.Project,
                Observations = ["obs1", "obs2"],
                CreatedAt = new DateTime(2026, 3, 18, 10, 0, 0, DateTimeKind.Utc),
                UpdatedAt = new DateTime(2026, 3, 18, 10, 0, 0, DateTimeKind.Utc)
            }
        };

        store.Save(entities, []);
        var (loaded, _, _) = store.Load();

        Assert.Single(loaded);
        Assert.Equal("TestProject", loaded[0].Name);
        Assert.Equal(EntityType.Project, loaded[0].Type);
        Assert.Equal(2, loaded[0].Observations.Count);
    }

    [Fact]
    public void SaveAndLoad_RoundTripsRelations()
    {
        var path = TempFile();
        var store = new GraphStore(path);

        var relations = new List<Relation>
        {
            new()
            {
                From = "A",
                To = "B",
                Type = RelationType.DependsOn,
                Detail = "HTTP calls",
                CreatedAt = new DateTime(2026, 3, 18, 10, 0, 0, DateTimeKind.Utc)
            }
        };

        store.Save([], relations);
        var (_, loaded, _) = store.Load();

        Assert.Single(loaded);
        Assert.Equal("A", loaded[0].From);
        Assert.Equal("B", loaded[0].To);
        Assert.Equal(RelationType.DependsOn, loaded[0].Type);
        Assert.Equal("HTTP calls", loaded[0].Detail);
    }

    [Fact]
    public void Load_SkipsMalformedLines()
    {
        var path = TempFile();
        File.WriteAllText(path, """
            {"kind":"entity","name":"Good","type":"project","observations":["ok"],"createdAt":"2026-03-18T10:00:00Z","updatedAt":"2026-03-18T10:00:00Z"}
            this is not json
            {"kind":"entity","name":"AlsoGood","type":"technology","observations":["ok"],"createdAt":"2026-03-18T10:00:00Z","updatedAt":"2026-03-18T10:00:00Z"}
            """);

        var store = new GraphStore(path);
        var (entities, _, skipped) = store.Load();

        Assert.Equal(2, entities.Count);
        Assert.Equal(1, skipped);
    }

    [Fact]
    public void Load_SkipsEntityRowsMissingType()
    {
        var path = TempFile();
        File.WriteAllText(path, """
            {"kind":"entity","name":"Good","type":"project","observations":["ok"],"createdAt":"2026-03-18T10:00:00Z","updatedAt":"2026-03-18T10:00:00Z"}
            {"kind":"entity","name":"MissingType","observations":["must not default"]}
            """);

        var store = new GraphStore(path);
        var (entities, _, skipped) = store.Load();

        Assert.Single(entities);
        Assert.Equal("Good", entities[0].Name);
        Assert.Equal(EntityType.Project, entities[0].Type);
        Assert.Equal(1, skipped);
    }

    [Fact]
    public void Load_SkipsEntityRowsWithNumericType()
    {
        var path = TempFile();
        File.WriteAllText(path, """
            {"kind":"entity","name":"Good","type":"project","observations":["ok"],"createdAt":"2026-03-18T10:00:00Z","updatedAt":"2026-03-18T10:00:00Z"}
            {"kind":"entity","name":"NumericType","type":0,"observations":["must not default"]}
            """);

        var store = new GraphStore(path);
        var (entities, _, skipped) = store.Load();

        Assert.Single(entities);
        Assert.Equal("Good", entities[0].Name);
        Assert.Equal(EntityType.Project, entities[0].Type);
        Assert.Equal(1, skipped);
    }

    [Fact]
    public void Load_SkipsEntityRowsMissingName()
    {
        var path = TempFile();
        File.WriteAllText(path, """
            {"kind":"entity","name":"Good","type":"project","observations":["ok"],"createdAt":"2026-03-18T10:00:00Z","updatedAt":"2026-03-18T10:00:00Z"}
            {"kind":"entity","type":"technology","observations":["must not load"]}
            """);

        var store = new GraphStore(path);
        var (entities, _, skipped) = store.Load();

        Assert.Single(entities);
        Assert.Equal("Good", entities[0].Name);
        Assert.Equal(1, skipped);
    }

    [Fact]
    public void Load_SkipsEntityRowsWithMalformedObservations()
    {
        var path = TempFile();
        File.WriteAllText(path, """
            {"kind":"entity","name":"Good","type":"project","observations":["ok"],"createdAt":"2026-03-18T10:00:00Z","updatedAt":"2026-03-18T10:00:00Z"}
            {"kind":"entity","name":"MissingObservations","type":"technology","createdAt":"2026-03-18T10:00:00Z","updatedAt":"2026-03-18T10:00:00Z"}
            {"kind":"entity","name":"NullObservation","type":"project","observations":[null],"createdAt":"2026-03-18T10:00:00Z","updatedAt":"2026-03-18T10:00:00Z"}
            {"kind":"entity","name":"NumberObservation","type":"project","observations":[1],"createdAt":"2026-03-18T10:00:00Z","updatedAt":"2026-03-18T10:00:00Z"}
            {"kind":"entity","name":"ObjectObservation","type":"project","observations":[{}],"createdAt":"2026-03-18T10:00:00Z","updatedAt":"2026-03-18T10:00:00Z"}
            {"kind":"entity","name":"MixedObservation","type":"project","observations":["ok",1],"createdAt":"2026-03-18T10:00:00Z","updatedAt":"2026-03-18T10:00:00Z"}
            {"kind":"entity","name":"NonArrayObservation","type":"project","observations":"not-array","createdAt":"2026-03-18T10:00:00Z","updatedAt":"2026-03-18T10:00:00Z"}
            """);

        var store = new GraphStore(path);
        var (entities, _, skipped) = store.Load();

        Assert.Equal(2, entities.Count);
        Assert.Contains(entities, entity => entity.Name == "Good" && entity.Observations.SequenceEqual(["ok"]));
        Assert.Contains(entities, entity => entity.Name == "MissingObservations" && entity.Observations.Count == 0);
        Assert.Equal(5, skipped);
    }

    [Fact]
    public void Load_SkipsRelationRowsMissingType()
    {
        var path = TempFile();
        File.WriteAllText(path, """
            {"kind":"relation","from":"A","to":"B","type":"uses","detail":"valid","createdAt":"2026-03-18T10:00:00Z"}
            {"kind":"relation","from":"A","to":"B","detail":"must not default"}
            """);

        var store = new GraphStore(path);
        var (_, relations, skipped) = store.Load();

        Assert.Single(relations);
        Assert.Equal(RelationType.Uses, relations[0].Type);
        Assert.Equal("valid", relations[0].Detail);
        Assert.Equal(1, skipped);
    }

    [Fact]
    public void Load_SkipsRelationRowsWithNumericType()
    {
        var path = TempFile();
        File.WriteAllText(path, """
            {"kind":"relation","from":"A","to":"B","type":"uses","detail":"valid","createdAt":"2026-03-18T10:00:00Z"}
            {"kind":"relation","from":"A","to":"B","type":0,"detail":"must not default"}
            """);

        var store = new GraphStore(path);
        var (_, relations, skipped) = store.Load();

        Assert.Single(relations);
        Assert.Equal(RelationType.Uses, relations[0].Type);
        Assert.Equal("valid", relations[0].Detail);
        Assert.Equal(1, skipped);
    }

    [Fact]
    public void Load_SkipsRelationRowsMissingFrom()
    {
        var path = TempFile();
        File.WriteAllText(path, """
            {"kind":"relation","from":"A","to":"B","type":"uses","detail":"valid","createdAt":"2026-03-18T10:00:00Z"}
            {"kind":"relation","to":"B","type":"uses","detail":"must not load"}
            """);

        var store = new GraphStore(path);
        var (_, relations, skipped) = store.Load();

        Assert.Single(relations);
        Assert.Equal("A", relations[0].From);
        Assert.Equal(1, skipped);
    }

    [Fact]
    public void Load_SkipsRelationRowsMissingTo()
    {
        var path = TempFile();
        File.WriteAllText(path, """
            {"kind":"relation","from":"A","to":"B","type":"uses","detail":"valid","createdAt":"2026-03-18T10:00:00Z"}
            {"kind":"relation","from":"A","type":"uses","detail":"must not load"}
            """);

        var store = new GraphStore(path);
        var (_, relations, skipped) = store.Load();

        Assert.Single(relations);
        Assert.Equal("B", relations[0].To);
        Assert.Equal(1, skipped);
    }

    [Fact]
    public void Save_CreatesDirectoryIfMissing()
    {
        var dir = Path.Combine(Path.GetTempPath(), $"test-dir-{Guid.NewGuid()}");
        var path = Path.Combine(dir, "graph.jsonl");
        var store = new GraphStore(path);

        store.Save([new Entity { Name = "Test", Type = EntityType.Project }], []);

        Assert.True(File.Exists(path));

        // Cleanup
        Directory.Delete(dir, true);
    }

    [Fact]
    public void SaveAndLoad_PreservesNullSourceFile()
    {
        var path = TempFile();
        var store = new GraphStore(path);

        store.Save([new Entity { Name = "Test", Type = EntityType.Project, SourceFile = null }], []);
        var (loaded, _, _) = store.Load();

        Assert.Single(loaded);
        Assert.Null(loaded[0].SourceFile);
    }

    [Fact]
    public void SaveAndLoad_PreservesSourceFile()
    {
        var path = TempFile();
        var store = new GraphStore(path);

        store.Save([new Entity { Name = "Test", Type = EntityType.Insight, SourceFile = "insights/test.md" }], []);
        var (loaded, _, _) = store.Load();

        Assert.Single(loaded);
        Assert.Equal("insights/test.md", loaded[0].SourceFile);
    }

    [Fact]
    public void SaveAndLoad_PreservesNullDetail()
    {
        var path = TempFile();
        var store = new GraphStore(path);

        store.Save([], [new Relation { From = "A", To = "B", Type = RelationType.Uses, Detail = null }]);
        var (_, loaded, _) = store.Load();

        Assert.Single(loaded);
        Assert.Null(loaded[0].Detail);
    }
}
