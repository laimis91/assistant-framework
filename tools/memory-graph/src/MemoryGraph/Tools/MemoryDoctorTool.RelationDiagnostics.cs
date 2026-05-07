using MemoryGraph.Graph;

namespace MemoryGraph.Tools;

public sealed partial class MemoryDoctorTool
{
    private static List<RelationIssue> FindDanglingRelations(List<Relation> relations, List<Entity> entities)
    {
        var entityNames = entities.Select(e => e.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
        return relations
            .SelectMany(relation =>
            {
                var issues = new List<RelationIssue>();
                if (!entityNames.Contains(relation.From))
                {
                    issues.Add(new RelationIssue(relation.From, relation.To, relation.Type.ToString(), "missingFrom"));
                }

                if (!entityNames.Contains(relation.To))
                {
                    issues.Add(new RelationIssue(relation.From, relation.To, relation.Type.ToString(), "missingTo"));
                }

                return issues;
            })
            .OrderBy(issue => issue.From, StringComparer.OrdinalIgnoreCase)
            .ThenBy(issue => issue.To, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    private sealed record RelationIssue(string From, string To, string Type, string Reason);
}
