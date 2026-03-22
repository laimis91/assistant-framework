namespace CognitiveComplexity;

/// <summary>
/// A single increment contributing to a function's cognitive complexity.
/// </summary>
public sealed record ComplexityDetail(
    int Line,
    int Column,
    int Increment,
    int Nesting,
    string Reason)
{
    public int Total => Increment + Nesting;

    public override string ToString()
    {
        var nestingStr = Nesting > 0 ? $" (nesting={Nesting})" : "";
        return $"  Line {Line,5}: +{Total}{nestingStr} — {Reason}";
    }
}

/// <summary>
/// Cognitive complexity result for a single method/function.
/// </summary>
public sealed class FunctionComplexity
{
    public string Name { get; }
    public int Line { get; }
    public List<ComplexityDetail> Details { get; } = [];

    public int Score => Details.Sum(d => d.Total);

    public FunctionComplexity(string name, int line)
    {
        Name = name;
        Line = line;
    }
}
