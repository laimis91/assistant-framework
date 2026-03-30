# SOLID Principles — Coding Checklist

Mandatory design quality gate for all task sizes. Referenced during Plan (to fill SOLID design notes) and enforced during Build (graduated checklist). Scale enforcement by task size.

## Graduated Enforcement

| Size | Principles | How |
|---|---|---|
| **Small** | SRP | 1 question before completing the step |
| **Medium** | SRP + OCP + DIP | 3 questions before completing each step |
| **Large/Mega** | All 5 (SRP, OCP, LSP, ISP, DIP) | Full checklist before completing each step |

## The Principles

### S — Single Responsibility Principle (ALL sizes)

**Rule:** A class should have only one reason to change.

**Concrete question:** "List the reasons this class/method would need to change. If more than one, separate them into distinct classes."

**Anti-pattern** — Journal with persistence baked in:
```csharp
public class Journal
{
    private readonly List<string> entries = new();

    public int AddEntry(string text) { /* journal logic */ }
    public void RemoveEntry(int index) { /* journal logic */ }

    // VIOLATION: persistence is a separate reason to change
    public void Save(string filename) { File.WriteAllText(filename, ToString()); }
    public void Load(string filename) { /* ... */ }
    public void Load(Uri uri) { /* ... */ }
}
```

**Correct** — separate persistence into its own class:
```csharp
public class Journal
{
    private readonly List<string> entries = new();
    public int AddEntry(string text) { /* ... */ }
    public void RemoveEntry(int index) { /* ... */ }
}

public class Persistence
{
    public void SaveToFile(Journal journal, string filename, bool overwrite = false)
    {
        if (overwrite || !File.Exists(filename))
            File.WriteAllText(filename, journal.ToString());
    }
}
```

**Signal:** If a class name needs "And" or "Manager" to describe what it does, it likely violates SRP.

---

### O — Open/Closed Principle (MEDIUM+)

**Rule:** Open for extension, closed for modification. New behavior should be addable without changing existing code.

**Concrete question:** "If a new variant of this behavior is needed next week, would you modify this class or extend it? If modify — redesign."

**Anti-pattern** — adding filter methods for every new criterion (state space explosion):
```csharp
public class ProductFilter
{
    public IEnumerable<Product> FilterByColor(IEnumerable<Product> products, Color color) { /* ... */ }
    public IEnumerable<Product> FilterBySize(IEnumerable<Product> products, Size size) { /* ... */ }
    public IEnumerable<Product> FilterBySizeAndColor(/* ... */) { /* ... */ }
    // 3 criteria = 7 methods. Every new criterion = modify this class.
}
```

**Correct** — specification pattern allows extension without modification:
```csharp
public interface ISpecification<T>
{
    bool IsSatisfied(T item);
}

public interface IFilter<T>
{
    IEnumerable<T> Filter(IEnumerable<T> items, ISpecification<T> spec);
}

public class ColorSpecification : ISpecification<Product>
{
    private readonly Color _color;
    public ColorSpecification(Color color) => _color = color;
    public bool IsSatisfied(Product p) => p.Color == _color;
}

// New criteria = new class, no existing code touched
public class AndSpecification<T> : ISpecification<T>
{
    private readonly ISpecification<T> _first, _second;
    public AndSpecification(ISpecification<T> first, ISpecification<T> second)
    {
        _first = first;
        _second = second;
    }
    public bool IsSatisfied(T item) => _first.IsSatisfied(item) && _second.IsSatisfied(item);
}
```

**Signal:** If adding a feature requires modifying a switch/case, if-else chain, or existing method body — consider whether the design is closed for modification.

---

### L — Liskov Substitution Principle (LARGE/MEGA)

**Rule:** Subtypes must be substitutable for their base types without breaking correctness.

**Concrete question:** "If a caller gets a subtype where it expects the base type, does anything break? Do any overrides change the expected behavior?"

**Anti-pattern** — Square overrides Rectangle with side effects:
```csharp
public class Rectangle
{
    public virtual int Width { get; set; }
    public virtual int Height { get; set; }
}

public class Square : Rectangle
{
    // VIOLATION: setting Width also changes Height — breaks Rectangle contract
    public override int Width
    {
        set { base.Width = base.Height = value; }
    }
    public override int Height
    {
        set { base.Width = base.Height = value; }
    }
}

// This function breaks when passed a Square:
static int Area(Rectangle r) => r.Width * r.Height;
// r = new Square(); r.Width = 4; → Area = 16 (not 4 * original height)
```

**Correct approach:** Don't make Square inherit from Rectangle. Use a common interface or separate types.

**Signal:** If an override changes the invariants or postconditions of the base, LSP is violated. Watch for `new` keyword hiding base members or overrides with unexpected side effects.

---

### I — Interface Segregation Principle (LARGE/MEGA)

**Rule:** No client should be forced to depend on methods it doesn't use. Prefer many small interfaces over one fat one.

**Concrete question:** "Does any implementer of this interface throw NotImplementedException for any method? If yes, the interface is too fat."

**Anti-pattern** — one fat interface forces unused implementations:
```csharp
public interface IMachine
{
    void Print(Document d);
    void Fax(Document d);
    void Scan(Document d);
}

public class OldFashionedPrinter : IMachine
{
    public void Print(Document d) { /* works */ }
    public void Fax(Document d) { throw new NotImplementedException(); }  // VIOLATION
    public void Scan(Document d) { throw new NotImplementedException(); }  // VIOLATION
}
```

**Correct** — segregated interfaces with composition:
```csharp
public interface IPrinter { void Print(Document d); }
public interface IScanner { void Scan(Document d); }

public class Printer : IPrinter
{
    public void Print(Document d) { /* ... */ }
}

// Multi-function device composes capabilities
public struct MultiFunctionMachine : IPrinter, IScanner
{
    private readonly IPrinter _printer;
    private readonly IScanner _scanner;

    public MultiFunctionMachine(IPrinter printer, IScanner scanner)
    {
        _printer = printer;
        _scanner = scanner;
    }

    public void Print(Document d) => _printer.Print(d);
    public void Scan(Document d) => _scanner.Scan(d);
}
```

**Signal:** If you see `NotImplementedException` in an interface implementation, the interface needs splitting.

---

### D — Dependency Inversion Principle (MEDIUM+)

**Rule:** High-level modules should not depend on low-level modules. Both should depend on abstractions.

**Concrete question:** "Does this high-level module import/reference a concrete low-level class directly? If yes, introduce an abstraction."

**Anti-pattern** — high-level Research depends directly on low-level Relationships storage:
```csharp
public class Research
{
    public Research(Relationships relationships)
    {
        // VIOLATION: directly accessing internal storage of a low-level module
        var relations = relationships.Relations;
        foreach (var r in relations
            .Where(x => x.Item1.Name == "John" && x.Item2 == Relationship.Parent))
        {
            WriteLine($"John has a child called {r.Item3.Name}");
        }
    }
}
```

**Correct** — depend on abstraction, let the low-level module implement it:
```csharp
public interface IRelationshipBrowser
{
    IEnumerable<Person> FindAllChildrenOf(string name);
}

public class Relationships : IRelationshipBrowser
{
    private List<(Person, Relationship, Person)> relations = new();

    public IEnumerable<Person> FindAllChildrenOf(string name) =>
        relations.Where(x => x.Item1.Name == name && x.Item2 == Relationship.Parent)
                 .Select(r => r.Item3);
}

public class Research
{
    public Research(IRelationshipBrowser browser)
    {
        foreach (var p in browser.FindAllChildrenOf("John"))
            WriteLine($"John has a child called {p.Name}");
    }
}
```

**Signal:** Constructor takes a concrete class instead of an interface? That's a DIP smell. Check if the dependency could be swapped for testing or future extension.

---

## Quick Reference Card

Use during Build phase — ask these questions for each implementation step:

### Small tasks (SRP only)
- [ ] **SRP:** List the reasons this class/method changes. More than one? → Separate.

### Medium tasks (SRP + OCP + DIP)
- [ ] **SRP:** List the reasons this class/method changes. More than one? → Separate.
- [ ] **OCP:** New variant next week — modify or extend? Modify → Redesign.
- [ ] **DIP:** High-level referencing concrete low-level? → Introduce abstraction.

### Large/Mega tasks (full SOLID)
- [ ] **SRP:** List the reasons this class/method changes. More than one? → Separate.
- [ ] **OCP:** New variant next week — modify or extend? Modify → Redesign.
- [ ] **LSP:** Subtype substitutable for base without breaking? Override changes invariants? → Fix hierarchy.
- [ ] **ISP:** Any NotImplementedException in interface impls? → Split interface.
- [ ] **DIP:** High-level referencing concrete low-level? → Introduce abstraction.
