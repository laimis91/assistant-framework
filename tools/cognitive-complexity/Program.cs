using CognitiveComplexity;

var verbose = false;
var threshold = 15;
var files = new List<string>();

// ── Argument parsing ────────────────────────────────────────────────────
for (var i = 0; i < args.Length; i++)
{
    switch (args[i])
    {
        case "-v" or "--verbose":
            verbose = true;
            break;
        case "-t" or "--threshold" when i + 1 < args.Length:
            threshold = int.Parse(args[++i]);
            break;
        case "-h" or "--help":
            PrintUsage();
            return 0;
        default:
            files.Add(args[i]);
            break;
    }
}

if (files.Count == 0)
{
    PrintUsage();
    return 1;
}

// ── Analysis ────────────────────────────────────────────────────────────
var exitCode = 0;

foreach (var filepath in files)
{
    if (!File.Exists(filepath))
    {
        Console.Error.WriteLine($"Error: {filepath} not found");
        exitCode = 1;
        continue;
    }

    var source = File.ReadAllText(filepath);
    Console.WriteLine();
    Console.WriteLine(new string('=', 60));
    Console.WriteLine($"  File: {filepath}");
    Console.WriteLine(new string('=', 60));

    var results = CognitiveComplexityWalker.Analyze(source);
    PrintResults(results, verbose, threshold, ref exitCode);
}

return exitCode;

// ── Formatting ──────────────────────────────────────────────────────────

static void PrintResults(IReadOnlyList<FunctionComplexity> results, bool verbose, int threshold, ref int exitCode)
{
    var total = 0;

    foreach (var fn in results)
    {
        total += fn.Score;
        Console.WriteLine($"  {fn.Name} (line {fn.Line}): {fn.Score}");

        if (verbose)
        {
            foreach (var detail in fn.Details)
            {
                Console.WriteLine(detail);
            }
            Console.WriteLine();
        }
    }

    Console.WriteLine();
    Console.WriteLine($"  Total file complexity: {total}");
    Console.WriteLine($"  Functions analyzed:    {results.Count}");

    var flagged = results.Where(fn => fn.Score > threshold).ToList();
    if (flagged.Count > 0)
    {
        Console.WriteLine();
        Console.WriteLine($"  ⚠ Functions exceeding threshold (>{threshold}):");
        foreach (var fn in flagged)
        {
            Console.WriteLine($"    {fn.Name} (line {fn.Line}): {fn.Score}");
        }
        exitCode = 2;
    }
}

static void PrintUsage()
{
    Console.WriteLine("""
    Cognitive Complexity Calculator for C# (Roslyn-based)
    
    Usage: CognitiveComplexity [options] <files...>
    
    Options:
      -v, --verbose      Show per-line breakdown of complexity increments
      -t, --threshold N  Set complexity threshold for warnings (default: 15)
      -h, --help         Show this help
    
    Exit codes:
      0  All functions within threshold
      1  File not found or other error
      2  One or more functions exceed threshold
    
    Rules (SonarSource Cognitive Complexity):
      +1          for each break in linear flow (if, for, while, switch, catch, etc.)
      +nesting    added on top when flow-break is nested inside another
      no penalty  for shorthand structures (switch cases, else-if chains stay flat)
    """);
}
