# Design Principles — Writing Guide

Apply this guide while planning and writing code at every task size. It is the
framework's default design standard: object-oriented, SOLID and extendable code.
Explicit project or user instructions take precedence where they differ.

The guide separates two decisions:

| Decision | Rule |
|---|---|
| **Structure** | Always SOLID and extendable. Not optional and not graded by task size. |
| **Pattern machinery** | Factories, registries, selection config and pattern combinations are added when a second variant exists or is requested. |

## Structure: always

1. **One responsibility per class.** List the reasons the class or method would
   change. More than one reason means separate classes. A name that needs "And",
   "Manager" or "Helper" to describe it usually hides several responsibilities.
2. **Roles behind interfaces.** A collaborator that holds behaviour, and every
   boundary to I/O, time, randomness, network, storage or engine APIs, is used
   through an interface. Callers depend on the abstraction and receive it
   through the constructor.
3. **No behaviour chosen by type code.** A value that identifies a kind or mode,
   such as an enum, string code, bool flag or type check, never selects which
   behaviour runs. Each kind is its own class implementing a shared interface,
   or data when kinds differ only in values (see
   [Data or behaviour](#data-or-behaviour)). Ordinary conditions on state, such
   as `if (order.IsPaid)`, are not type codes. A registry or factory at the
   composition boundary is the one place a key picks an implementation.
4. **Substitutable implementations.** Every implementation keeps the caller's
   expectations: no narrower inputs, weaker results, surprise exceptions or
   caller type checks.
5. **Small interfaces.** No implementation throws `NotImplementedException` or
   leaves a member as a no-op because the interface is too broad. Split the
   interface by client need.

Structure does not require:

- interfaces for data: records, value objects and DTOs hold no behaviour to swap;
- a class or interface without a role you can name; pass-through wrappers are
  not structure;
- converting an enum that is a plain list of values with no behaviour attached,
  or an external API's enum such as an engine key code.

## Pattern machinery: when a second variant exists or is requested

A single variant gets its interface and one implementation, and nothing more.
Do not add a factory, registry, selection setting, format or kind enum, or empty
classes for variants nobody has requested. When the second variant arrives, add
its class and the selection machinery in the same change.

## Choose the pattern

| About to write | Write instead |
|---|---|
| Phase or mode checks repeated across commands | State: one class per phase, each deciding which commands it accepts |
| `if (item.IsX)` branches in several places | One class per kind behind a shared interface |
| A switch turning result codes into messages | Result objects that carry their own message and data |
| A switch choosing an algorithm or output format | Strategy behind an interface; a registry or factory picks one once a second exists |
| One method per combination of criteria | Specification, with combinators for And/Or/Not |
| Extra behaviour wrapped around existing behaviour | Decorator |
| Construction that varies by kind or needs many optional parts | Factory or Builder |
| Checks for "nothing here" before every call | Null Object |
| Objects polling another object for changes | Observer or events |
| Incompatible interface from another component | Adapter |
| Tree of parts treated like a single part | Composite |

## Data or behaviour

Ask what differs between the kinds:

- **Only values** such as health, speed, cost or width: one class, with the
  values in data. Use a record, a configuration file or a data asset.
- **Behaviour** such as what happens on arrival, which rules apply, or how
  output is produced: one class per kind behind an interface.

When a value starts driving a branch (`IsBoss`, `CanFly`), the kinds now differ
in behaviour. Move that behaviour into the kind's class.

## Extension points table

Every plan that changes code records each concept that has, or will have,
several variants. The table records machinery decisions; structure is not a
decision.

| What varies | Variants now or requested | Machinery | Revisit when |
|---|---|---|---|
| Export format | CSV only | Interface and one class; no factory | A second format is requested: add its class and a format registry |
| Enemy kind | Regular, mini boss, boss | Class per kind; values in data assets | — |

## Refactor before extending

Before the first edit to existing code, check whether the change does any of:

1. adds a second variant to something that has one;
2. adds a case to a behaviour switch, a value to a behaviour-selecting enum, or
   another branch on the same type code;
3. repeats an existing type-code check in a new place;
4. needs edits in three or more places to add one new kind;
5. turns a data value into a branch condition;
6. adds a bool or mode parameter that changes what a method does;
7. adds another method for a new combination of criteria;
8. needs a test double for a concrete dependency;
9. meets a "Revisit when" condition in a recorded extension points table.

If any applies, refactor first:

- Change the structure without changing behaviour, with the existing checks
  passing. Then add the new variant as a new class or data asset, in a separate
  step.
- Refactor only the concept being extended. Leave unrelated code to its own
  change.
- A refactor that changes saved data, a public interface or many files is part
  of the plan the user approves.

## Writing check

Before finishing each implementation step, confirm:

- [ ] Each new or changed class has one reason to change.
- [ ] Behaviour collaborators and external boundaries are reached through interfaces.
- [ ] No value identifying a kind or mode (enum, string code, flag, type check) selects behaviour, outside a registry or factory.
- [ ] Kinds that differ only in values are data, not classes.
- [ ] No factory, registry or selection setting exists for a single variant.
- [ ] Every class and interface has a role you can name.
- [ ] A new kind can be added without editing existing kinds.

## Examples

Kinds as classes, with values in data:

```csharp
public sealed record EnemyStats(int Health, float Speed);

public interface IEnemyKind
{
    EnemyStats Stats { get; }
    void OnReachedBase(IRunOutcome outcome);
}

public sealed class RegularEnemy(EnemyStats stats) : IEnemyKind
{
    public EnemyStats Stats { get; } = stats;
    public void OnReachedBase(IRunOutcome outcome) => outcome.LoseLives(1);
}

public sealed class BossEnemy(EnemyStats stats) : IEnemyKind
{
    public EnemyStats Stats { get; } = stats;
    public void OnReachedBase(IRunOutcome outcome) => outcome.LoseRun();
}
```

Phases as states:

```csharp
public abstract class RunPhase
{
    public virtual CommandResult PlaceTower(Run run, BuildSpot spot) => CommandResult.WrongPhase;
    public virtual CommandResult StartWave(Run run) => CommandResult.WrongPhase;
}

public sealed class PreparePhase : RunPhase
{
    public override CommandResult PlaceTower(Run run, BuildSpot spot) => run.Build(spot);
    public override CommandResult StartWave(Run run)
    {
        run.EnterPhase(new WavePhase());
        return CommandResult.Ok;
    }
}
```

A result that carries its own message:

```csharp
public sealed record CommandResult(bool Succeeded, string Message)
{
    public static readonly CommandResult Ok = new(true, string.Empty);
    public static readonly CommandResult WrongPhase = Refused("That can't be done right now.");
    public static CommandResult Refused(string message) => new(false, message);
}
```

One variant: interface and one class.

```csharp
public interface IExportFormat
{
    string FileExtension { get; }
    void Write(IReadOnlyList<ExportRow> rows, Stream output);
}

public sealed class CsvExportFormat : IExportFormat { /* ... */ }
```

A second variant: add its class, a selection key and a registry in the same change.

```csharp
using System.Diagnostics.CodeAnalysis;

public interface IExportFormat
{
    string Name { get; }
    string FileExtension { get; }
    void Write(IReadOnlyList<ExportRow> rows, Stream output);
}

public sealed class ExportFormatRegistry(IEnumerable<IExportFormat> formats)
{
    private readonly Dictionary<string, IExportFormat> byName =
        formats.ToDictionary(format => format.Name);

    public bool TryGet(string name, [NotNullWhen(true)] out IExportFormat? format) =>
        byName.TryGetValue(name, out format);
}
```

A Null Object instead of repeated null checks:

```csharp
public interface IRunLog { void Record(string message); }

public sealed class NoRunLog : IRunLog
{
    public static readonly NoRunLog Instance = new();
    public void Record(string message) { }
}
```

## Unity

- Keep game rules in plain C# classes; MonoBehaviours connect them to the scene.
- Use ScriptableObject assets for kinds that differ only in values, and for
  kinds whose behaviour is chosen in the editor.
- `[SerializeReference]` stores polymorphic objects in a field, but renaming or
  moving the class breaks saved data unless `[MovedFrom]` records the old name.
- In per-frame code, avoid allocating new objects for each call; reuse state and
  strategy instances.

## Optional library examples

When a configured pattern library is available, load
[design-pattern-retrieval.md](../design-pattern-retrieval.md) and use at most a
few examples for a specific force. Library examples show one pattern in
isolation; their supporting code, such as an enum that picks a strategy, is not
the style to copy.
