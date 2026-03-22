using MemoryGraph.Graph;

namespace MemoryGraph.Sync;

/// <summary>
/// Extracts entities and relations from markdown text using simple heuristics.
/// Not NLP — uses pattern matching and structural markers.
/// </summary>
public static class EntityExtractor
{
    /// <summary>
    /// Extracts entities from an insight markdown file.
    /// Title line becomes the entity name, body text becomes observations.
    /// </summary>
    public static ExtractionResult ExtractFromInsight(string content, string sourceFile, IReadOnlyCollection<Entity> existingEntities)
    {
        var result = new ExtractionResult();
        var lines = content.Split('\n');

        // Find the title (first # heading)
        string? title = null;
        var observations = new List<string>();

        foreach (var line in lines)
        {
            var trimmed = line.Trim();

            if (title is null && trimmed.StartsWith("# "))
            {
                title = trimmed[2..].Trim();
                continue;
            }

            if (title is not null && !string.IsNullOrWhiteSpace(trimmed) && !trimmed.StartsWith("#"))
            {
                // Strip markdown list markers (prefix only, not character-set trim)
                var obs = trimmed;
                if (obs.StartsWith("- ") || obs.StartsWith("* "))
                {
                    obs = obs[2..];
                }

                if (obs.Length > 0)
                {
                    observations.Add(obs);
                }
            }
        }

        if (title is null)
        {
            return result;
        }

        var entity = new Entity
        {
            Name = title,
            Type = EntityType.Insight,
            Observations = observations,
            SourceFile = sourceFile
        };
        result.Entities.Add(entity);

        // Check if the content mentions any known entities → create AppliesTo relations
        var fullText = content.ToLowerInvariant();
        foreach (var existing in existingEntities)
        {
            if (existing.Type is EntityType.Project or EntityType.Technology)
            {
                if (fullText.Contains(existing.Name.ToLowerInvariant()))
                {
                    result.Relations.Add(new Relation
                    {
                        From = title,
                        To = existing.Name,
                        Type = RelationType.AppliesTo
                    });
                }
            }
        }

        return result;
    }

    /// <summary>
    /// Extracts preferences from a user profile markdown file.
    /// Looks for "prefers X", "uses Y", key-value patterns.
    /// </summary>
    public static ExtractionResult ExtractFromProfile(string content, string sourceFile)
    {
        var result = new ExtractionResult();
        var lines = content.Split('\n');

        foreach (var line in lines)
        {
            var trimmed = line.Trim();
            if (trimmed.StartsWith("- ") || trimmed.StartsWith("* "))
            {
                trimmed = trimmed[2..];
            }

            // Look for "prefers X" or "prefer X" patterns
            if (trimmed.StartsWith("prefer", StringComparison.OrdinalIgnoreCase))
            {
                var observation = trimmed;
                var name = ExtractPreferenceName(trimmed);
                if (name is not null)
                {
                    AddOrMergePreference(result, name, observation, sourceFile);
                }
            }
            // Look for "uses X" patterns
            else if (trimmed.StartsWith("uses ", StringComparison.OrdinalIgnoreCase))
            {
                var observation = trimmed;
                var name = $"pref-{Slugify(trimmed)}";
                AddOrMergePreference(result, name, observation, sourceFile);
            }
            // Look for key: value patterns (e.g., "Naming: PascalCase for public")
            else if (trimmed.Contains(':') && !trimmed.StartsWith("http", StringComparison.OrdinalIgnoreCase))
            {
                var colonIndex = trimmed.IndexOf(':');
                var key = trimmed[..colonIndex].Trim();
                var value = trimmed[(colonIndex + 1)..].Trim();

                if (key.Length > 2 && key.Length < 40 && value.Length > 2 &&
                    !value.StartsWith("http", StringComparison.OrdinalIgnoreCase))
                {
                    var name = $"pref-{Slugify(key)}";
                    AddOrMergePreference(result, name, $"{key}: {value}", sourceFile);
                }
            }
        }

        return result;
    }

    /// <summary>
    /// Extracts conventions from a feedback markdown file.
    /// Looks for "always/never" statements and rule patterns.
    /// </summary>
    public static ExtractionResult ExtractFromFeedback(string content, string sourceFile)
    {
        var result = new ExtractionResult();
        var lines = content.Split('\n');

        foreach (var line in lines)
        {
            var trimmed = line.Trim();
            if (trimmed.StartsWith("- ") || trimmed.StartsWith("* "))
            {
                trimmed = trimmed[2..];
            }

            // "always" or "never" statements → Convention
            if (trimmed.StartsWith("always ", StringComparison.OrdinalIgnoreCase) ||
                trimmed.StartsWith("never ", StringComparison.OrdinalIgnoreCase))
            {
                var name = $"conv-{Slugify(trimmed)}";
                AddOrMergeEntity(result, name, EntityType.Convention, trimmed, sourceFile);
            }
            // Rule statements (lines that feel like conventions)
            else if (trimmed.StartsWith("rule:", StringComparison.OrdinalIgnoreCase) ||
                     trimmed.StartsWith("convention:", StringComparison.OrdinalIgnoreCase))
            {
                var colonIndex = trimmed.IndexOf(':');
                var value = trimmed[(colonIndex + 1)..].Trim();
                if (value.Length > 0)
                {
                    var name = $"conv-{Slugify(value)}";
                    AddOrMergeEntity(result, name, EntityType.Convention, value, sourceFile);
                }
            }
        }

        return result;
    }

    // ── Helpers ─────────────────────────────────────────────────────

    private static string? ExtractPreferenceName(string text)
    {
        // "prefers var when type is obvious" → "pref-var-when-type-is-obvious"
        var words = text.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (words.Length < 2)
        {
            return null;
        }

        // Skip the "prefers"/"prefer" word
        var meaningful = words.Skip(1).Take(6);
        return $"pref-{string.Join("-", meaningful.Select(w => w.ToLowerInvariant()))}";
    }

    private static void AddOrMergePreference(ExtractionResult result, string name, string observation, string sourceFile)
    {
        AddOrMergeEntity(result, name, EntityType.Preference, observation, sourceFile);
    }

    private static void AddOrMergeEntity(ExtractionResult result, string name, EntityType type, string observation, string sourceFile)
    {
        var existing = result.Entities.FirstOrDefault(e =>
            e.Name.Equals(name, StringComparison.OrdinalIgnoreCase));
        if (existing is not null)
        {
            existing.MergeObservations([observation]);
        }
        else
        {
            result.Entities.Add(new Entity
            {
                Name = name,
                Type = type,
                Observations = [observation],
                SourceFile = sourceFile
            });
        }
    }

    private static string Slugify(string text)
    {
        var words = text.Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .Take(6)
            .Select(w => new string(w.Where(c => char.IsLetterOrDigit(c) || c == '-').ToArray()))
            .Where(w => w.Length > 0)
            .Select(w => w.ToLowerInvariant());

        var slug = string.Join("-", words);
        if (slug.Length == 0) return "unnamed";
        return slug.Length > 50 ? slug[..50] : slug;
    }
}

/// <summary>
/// Result of extracting entities and relations from a markdown file.
/// </summary>
public sealed class ExtractionResult
{
    public List<Entity> Entities { get; } = [];
    public List<Relation> Relations { get; } = [];
}
