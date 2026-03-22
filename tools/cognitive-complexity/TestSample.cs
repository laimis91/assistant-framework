namespace TestSamples;

public class ComplexityTestCases
{
    // Expected: 0 (simple getter)
    public string GetName() => "hello";

    // Expected: 1 (single if)
    public int SimpleIf(bool x)
    {
        if (x)          // +1
            return 1;
        return 0;
    }

    // Expected: 3 (nested if)
    public int NestedIf(bool a, bool b)
    {
        if (a)          // +1
        {
            if (b)      // +2 (1 + nesting=1)
                return 42;
        }
        return 0;
    }

    // Expected: 7 (SonarSource canonical example)
    public int SumOfPrimes(int max)
    {
        int total = 0;
        for (int i = 1; i <= max; ++i)       // +1
        {
            for (int j = 2; j < i; ++j)      // +2 (1 + nesting=1)
            {
                if (i % j == 0)              // +3 (1 + nesting=2)
                {
                    goto NEXT;               // +1
                }
            }
            total += i;
            NEXT:;
        }
        return total;
    }

    // Expected: 1 (switch = one increment for the whole structure)
    public string GetWords(int number)
    {
        switch (number)   // +1
        {
            case 1:  return "one";
            case 2:  return "a couple";
            default: return "lots";
        }
    }

    // Expected: 4 (if / else-if / else-if / else — all flat +1)
    public string Classify(int x)
    {
        if (x > 100)         // +1
            return "big";
        else if (x > 10)     // +1
            return "medium";
        else if (x > 0)      // +1
            return "small";
        else                  // +1
            return "negative";
    }

    // Expected: 2 (if + one boolean sequence)
    public void MixedBooleans(bool a, bool b)
    {
        if (a && b)     // +1 (if) +1 (&&)
        { }
    }

    // Expected: 4 (if + three boolean sequences: &&, ||, &&)
    public void ComplexBooleans(bool a, bool b, bool c, bool d)
    {
        if (a && b || c && d)   // +1 (if) +1 (&&) +1 (||) +1 (&&)
        { }
    }

    // Expected: 3 (catch + nested if)
    public void TryCatchExample()
    {
        try
        {
            // try itself = no increment
        }
        catch (Exception)          // +1
        {
            if (true)              // +2 (1 + nesting=1)
            { }
        }
    }

    // Expected: 1 (ternary)
    public string TernaryExample(bool x) => x ? "yes" : "no";   // +1

    // Expected: 6 (deeply nested)
    public void DeeplyNested(bool a, int b, bool c)
    {
        if (a)                         // +1
        {
            for (int x = 0; x < b; x++) // +2 (1 + nesting=1)
            {
                if (c)                  // +3 (1 + nesting=2)
                { }
            }
        }
    }

    // Expected: 3 (lambda + nested ternary)
    public void LambdaExample()
    {
        var items = new[] { 1, 2, 3 };
        var filtered = items.Where(x =>    // +1 (lambda)
            x > 0 ? x : 0                 // +2 (ternary, nesting=1)
        );
    }

    // Expected: 1 (switch expression, C# 8+)
    public string SwitchExpression(int x) => x switch   // +1
    {
        1 => "one",
        2 => "two",
        _ => "other",
    };

    // Higher score — complex real-world-ish method
    public List<string> ProcessData(List<Dictionary<string, object>> items, Dictionary<string, object> config)
    {
        var results = new List<string>();

        foreach (var item in items)                              // +1
        {
            if (item.ContainsKey("active"))                     // +2 (1 + nesting=1)
            {
                if (item["type"]?.ToString() == "A")            // +3 (1 + nesting=2)
                {
                    results.Add("a");
                }
                else if (item["type"]?.ToString() == "B")       // +1 (else if, flat)
                {
                    try
                    {
                        var val = Convert.ToInt32(item["val"]);
                        if (val > 0 && config.ContainsKey("positive"))  // +4 (1+nesting=3) +1 (&&)
                        {
                            results.Add(val.ToString());
                        }
                    }
                    catch (Exception)                           // +4 (1 + nesting=3)
                    {
                        continue;                               // no increment in C# (no label)
                    }
                }
                else                                            // +1 (else, flat)
                {
                    // skip
                }
            }
            else                                                // +1 (else, flat)
            {
                if (config.ContainsKey("include_inactive"))     // +3 (1 + nesting=2)
                {
                    results.Add("inactive");
                }
            }
        }

        return results;
    }
}
