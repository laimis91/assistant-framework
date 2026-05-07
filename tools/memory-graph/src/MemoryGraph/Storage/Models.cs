namespace MemoryGraph.Storage;

public sealed class ReflexionEntry
{
    public long Id { get; set; }
    public required string TaskDescription { get; set; }
    public required string Project { get; set; }
    public string? ProjectType { get; set; }
    public string? TaskType { get; set; }
    public string? Size { get; set; }
    public string? WentWell { get; set; }
    public string? WentWrong { get; set; }
    public string? Lessons { get; set; }
    public int PlanAccuracy { get; set; }
    public int EstimateAccuracy { get; set; }
    public bool FirstAttemptSuccess { get; set; }
    public string? CreatedAt { get; set; }
}

public sealed class DecisionEntry
{
    public long Id { get; set; }
    public required string Title { get; set; }
    public required string Decision { get; set; }
    public required string Rationale { get; set; }
    public string? Alternatives { get; set; }
    public string? Constraints { get; set; }
    public string? Project { get; set; }
    public string? Tags { get; set; }
    public string? Outcome { get; set; }
    public string? CreatedAt { get; set; }
}

public sealed class StrategyLesson
{
    public long Id { get; set; }
    public required string ProjectType { get; set; }
    public required string Phase { get; set; }
    public required string Lesson { get; set; }
    public double Confidence { get; set; } = 0.5;
    public int ReinforcementCount { get; set; } = 1;
    public long? SourceReflexionId { get; set; }
    public string? CreatedAt { get; set; }
    public string? LastReinforced { get; set; }
}

public sealed class FtsResult
{
    public required string SourceType { get; set; }
    public required string SourceId { get; set; }
    public required string Title { get; set; }
    public required string Snippet { get; set; }
    public double Rank { get; set; }
}

public sealed class GraphEntityFtsDiagnostics
{
    public int EntityRows { get; set; }
    public int StaleEntityRows => StaleRows.Count;
    public int OrphanEntityRows { get; set; }
    public int NonCanonicalEntityRows { get; set; }
    public List<GraphEntityFtsIssue> StaleRows { get; set; } = [];
}

public sealed class GraphEntityFtsIssue
{
    public required string SourceId { get; set; }
    public required string Title { get; set; }
    public string? Tags { get; set; }
    public required string Reason { get; set; }
    public string? CanonicalName { get; set; }
}

public sealed class MemoryStats
{
    public int Reflexions { get; set; }
    public int Decisions { get; set; }
    public int StrategyLessons { get; set; }
    public int CalibrationEntries { get; set; }
    public int FtsEntries { get; set; }
}

public sealed class CalibrationStats
{
    public Dictionary<string, CalibrationTypeStats> ByType { get; set; } = new();
}

public sealed class CalibrationTypeStats
{
    public int Total { get; set; }
    public int Accurate { get; set; }
    public double AccuracyRate => Total > 0 ? (double)Accurate / Total : 0;
}

public sealed class JsonlImportResult
{
    public bool NoOp { get; set; }
    public long? ImportId { get; set; }
    public required string SourcePath { get; set; }
    public required string FileHash { get; set; }
    public long FileLength { get; set; }
    public int LinesRead { get; set; }
    public int SkippedLines { get; set; }
    public int EntitiesRead { get; set; }
    public int EntitiesCreated { get; set; }
    public int EntitiesUpdated { get; set; }
    public int ObservationsAdded { get; set; }
    public int RelationsRead { get; set; }
    public int RelationsCreated { get; set; }
    public int RelationsDeduplicated { get; set; }
    public int RelationsSkipped { get; set; }
}

public sealed class GraphEntityMutationResult
{
    public bool Created { get; set; }
    public bool Updated { get; set; }
    public int NewObservations { get; set; }
}

public sealed class GraphEntityRemovalResult
{
    public bool Removed { get; set; }
    public int RelationsRemoved { get; set; }
}
