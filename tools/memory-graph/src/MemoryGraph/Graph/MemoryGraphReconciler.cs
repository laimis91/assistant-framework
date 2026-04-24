using System.Text.Json;
using MemoryGraph.Storage;

namespace MemoryGraph.Graph;

/// <summary>
/// Reconciles durable SQLite memory rows into the graph so context lookups stay complete.
/// </summary>
public static class MemoryGraphReconciler
{
    public static ReconciliationResult ReconcileFromStore(KnowledgeGraph graph, MemoryStore store)
    {
        var reflexions = store.GetAllReflexions();
        var decisions = store.GetAllDecisions();
        var candidates = BuildProjectCandidates(reflexions, decisions);
        var projectsCreated = 0;
        var insightsCreated = 0;
        var relationsCreated = 0;

        foreach (var candidate in candidates.Values)
        {
            var projectName = EnsureRecoveredProject(graph, candidate, out var projectCreated);
            if (projectCreated)
            {
                projectsCreated++;
            }

            foreach (var reflexion in candidate.Reflexions)
            {
                var result = EnsureReflexionLessons(graph, projectName, reflexion);
                insightsCreated += result.InsightsCreated;
                relationsCreated += result.RelationsCreated;
            }
        }

        return new ReconciliationResult(projectsCreated, insightsCreated, relationsCreated);
    }

    public static ReconciliationResult EnsureReflexionGraphEntities(KnowledgeGraph graph, ReflexionEntry reflexion)
    {
        var projectName = EnsureReflectProject(graph, reflexion);
        var result = EnsureReflexionLessons(graph, projectName, reflexion);
        return new ReconciliationResult(0, result.InsightsCreated, result.RelationsCreated);
    }

    private static Dictionary<string, ProjectRecoveryCandidate> BuildProjectCandidates(
        List<ReflexionEntry> reflexions,
        List<DecisionEntry> decisions)
    {
        var candidates = new Dictionary<string, ProjectRecoveryCandidate>(StringComparer.OrdinalIgnoreCase);

        foreach (var reflexion in reflexions)
        {
            var project = NormalizeProject(reflexion.Project);
            if (project is null)
            {
                continue;
            }

            if (!candidates.TryGetValue(project, out var candidate))
            {
                candidate = new ProjectRecoveryCandidate(project);
                candidates[project] = candidate;
            }

            candidate.Reflexions.Add(reflexion);
            if (!string.IsNullOrWhiteSpace(reflexion.ProjectType))
            {
                candidate.ProjectTypes.Add(reflexion.ProjectType.Trim());
            }
        }

        foreach (var decision in decisions)
        {
            var project = NormalizeProject(decision.Project);
            if (project is null)
            {
                continue;
            }

            if (!candidates.TryGetValue(project, out var candidate))
            {
                candidate = new ProjectRecoveryCandidate(project);
                candidates[project] = candidate;
            }

            candidate.Decisions.Add(decision);
        }

        return candidates;
    }

    private static string EnsureRecoveredProject(
        KnowledgeGraph graph,
        ProjectRecoveryCandidate candidate,
        out bool created)
    {
        var existing = graph.GetEntity(candidate.Name);
        if (existing is not null)
        {
            created = false;
            return existing.Name;
        }

        var observations = new List<string>
        {
            "Recovered from SQLite memory.db relational data.",
            $"SQLite reflexion evidence count: {candidate.Reflexions.Count}",
            $"SQLite decision evidence count: {candidate.Decisions.Count}"
        };

        if (candidate.ProjectTypes.Count > 0)
        {
            observations.Add($"Project types observed in reflexions: {string.Join(", ", candidate.ProjectTypes.OrderBy(t => t, StringComparer.OrdinalIgnoreCase))}");
        }

        graph.AddOrUpdateEntity(candidate.Name, EntityType.Project, observations);
        created = true;
        return candidate.Name;
    }

    private static string EnsureReflectProject(KnowledgeGraph graph, ReflexionEntry reflexion)
    {
        var observations = new List<string> { "Recorded from memory_reflect SQLite reflexion data." };
        if (!string.IsNullOrWhiteSpace(reflexion.ProjectType))
        {
            observations.Add($"Project type observed in reflexion: {reflexion.ProjectType.Trim()}");
        }

        graph.AddOrUpdateEntity(reflexion.Project.Trim(), EntityType.Project, observations);
        return graph.GetEntity(reflexion.Project)?.Name ?? reflexion.Project.Trim();
    }

    private static ReconciliationResult EnsureReflexionLessons(
        KnowledgeGraph graph,
        string projectName,
        ReflexionEntry reflexion)
    {
        var insightsCreated = 0;
        var relationsCreated = 0;

        foreach (var lesson in ParseLessons(reflexion.Lessons))
        {
            var insightName = BuildInsightName(projectName, lesson);
            var source = reflexion.Id > 0
                ? $"Source: SQLite reflexion {reflexion.Id}"
                : "Source: SQLite reflexion lessons";

            var (created, _) = graph.AddOrUpdateEntity(insightName, EntityType.Insight, [lesson, source]);
            if (created)
            {
                insightsCreated++;
            }

            if (graph.AddRelation(insightName, projectName, RelationType.AppliesTo))
            {
                relationsCreated++;
            }
        }

        return new ReconciliationResult(0, insightsCreated, relationsCreated);
    }

    private static List<string> ParseLessons(string? lessons)
    {
        if (string.IsNullOrWhiteSpace(lessons))
        {
            return [];
        }

        var trimmed = lessons.Trim();
        if (trimmed.StartsWith('[') && trimmed.EndsWith(']'))
        {
            try
            {
                var parsed = JsonSerializer.Deserialize<List<string>>(trimmed);
                if (parsed is not null)
                {
                    return NormalizeLessons(parsed);
                }
            }
            catch (JsonException)
            {
                // Fall through to line splitting for malformed JSON-looking input.
            }
        }

        return NormalizeLessons(trimmed.Split('\n'));
    }

    private static List<string> NormalizeLessons(IEnumerable<string?> lessons)
    {
        return lessons
            .Select(l => l?.Trim())
            .Where(l => !string.IsNullOrWhiteSpace(l))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Cast<string>()
            .ToList();
    }

    private static string BuildInsightName(string projectName, string lesson)
    {
        var slug = GenerateSlug(lesson);
        var hash = DeterministicHash($"{NormalizeTextForKey(projectName)}\n{NormalizeTextForKey(lesson)}");
        return $"insight-reflexion-{slug}-{hash}";
    }

    private static string NormalizeTextForKey(string text)
    {
        var words = text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        return string.Join(" ", words).ToUpperInvariant();
    }

    private static string GenerateSlug(string text)
    {
        var words = text.Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .Take(5)
            .Select(w => new string(w.Where(char.IsLetterOrDigit).ToArray()))
            .Where(w => w.Length > 0)
            .Select(w => w.ToLowerInvariant());

        var slug = string.Join("-", words);
        return slug.Length > 0 ? slug : "unnamed";
    }

    private static string DeterministicHash(string text)
    {
        unchecked
        {
            uint hash = 2166136261;
            foreach (var c in text)
            {
                hash ^= c;
                hash *= 16777619;
            }

            return hash.ToString("x8")[..8];
        }
    }

    private static string? NormalizeProject(string? project)
    {
        return string.IsNullOrWhiteSpace(project) ? null : project.Trim();
    }

    private sealed class ProjectRecoveryCandidate
    {
        public ProjectRecoveryCandidate(string name)
        {
            Name = name;
        }

        public string Name { get; }
        public List<ReflexionEntry> Reflexions { get; } = [];
        public List<DecisionEntry> Decisions { get; } = [];
        public HashSet<string> ProjectTypes { get; } = new(StringComparer.OrdinalIgnoreCase);
    }
}

public sealed record ReconciliationResult(int ProjectsCreated, int InsightsCreated, int RelationsCreated);
