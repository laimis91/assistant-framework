# Implementation (Design to Code)

Bridge between game design documents and actual Unity implementation. Converts mechanics specs into C# scripts and UnityMCP tool calls.

## When to use
- Concept and mechanics docs are done, ready to start coding
- Need to convert a mechanic design into C# scripts + ScriptableObjects
- Want a step-by-step build order for implementing a game system

## Process

### Step 1: Read the Design

Before implementing anything, load:
1. The concept document (from concept.md output)
2. The relevant mechanics spec (from mechanics.md output)
3. The balance sheet (from balance.md output, if exists)

Extract from these:
- **Data model**: ScriptableObjects and their fields
- **Runtime components**: MonoBehaviours and their responsibilities
- **Domain logic**: Pure C# classes for calculations
- **Events**: What events connect systems

### Step 2: Determine Build Order

Follow this dependency-based order:

```
Phase 1: Foundation (no gameplay yet)
├── Project structure (folders, assembly definitions)
├── Core ScriptableObjects (data containers)
├── Event system (ScriptableObject events or C# events)
└── Object pool infrastructure

Phase 2: Player (can move around)
├── Player controller (movement)
├── Player stats (health, speed)
├── Camera follow
└── Basic input handling

Phase 3: Combat Core (things can die)
├── Health component (shared between player and enemies)
├── Damage system (DamageInfo, DamageCalculator)
├── Hit detection (triggers, overlap)
└── Death handling (events, cleanup)

Phase 4: Enemies (something to fight)
├── Enemy definitions (ScriptableObjects)
├── Enemy spawner
├── Basic AI (chase behavior)
└── Enemy pool

Phase 5: Weapons (player can fight back)
├── Weapon definitions (ScriptableObjects)
├── Auto-fire system
├── Projectile behavior + pool
└── One starter weapon implementation

Phase 6: Progression (reason to keep playing)
├── XP / pickup system
├── Level-up trigger
├── Upgrade definitions (ScriptableObjects)
├── Upgrade selection UI
└── Stat modifier system

Phase 7: Game Loop (complete session)
├── Wave/difficulty escalation
├── Win/lose conditions
├── Game state management
├── HUD (health, XP bar, timer, kills)
├── Pause menu
└── Game over screen
```

### Step 3: Generate Implementation Artifacts

For each system, produce:

**ScriptableObject definitions:**
```csharp
// Provide the full class with [CreateAssetMenu], fields, and default values
// Include [Header] attributes for Inspector organization
// Include [Tooltip] for non-obvious fields
```

**MonoBehaviour components:**
```csharp
// Provide the full class with:
// - Serialized fields for Inspector configuration
// - Awake/Start for initialization
// - Update/FixedUpdate as needed
// - Public methods for inter-system communication
// - Events for decoupled notifications
```

**Pure C# logic:**
```csharp
// Provide the full class with:
// - No Unity dependencies (testable in isolation)
// - Clear input/output contracts
// - Static methods where appropriate
```

**UnityMCP setup calls:**
```sequence
// For each prefab, scene object, or configuration that should be
// set up via MCP tools rather than code
```

### Step 4: Verify Each Phase

After implementing each phase:
1. Build: `dotnet build` or Unity compilation check
2. Scene setup: Use UnityMCP to create test objects
3. Play test: Enter play mode via `editor.enterPlayMode`
4. Capture: `editor.captureGameView` to verify visually
5. Exit: `editor.exitPlayMode`

Only proceed to next phase when current phase works.

## Implementation Patterns

### Event-Driven Communication
Systems should communicate through events, not direct references:

```csharp
// ScriptableObject-based event (recommended for Unity)
[CreateAssetMenu(menuName = "Events/Void Event")]
public class GameEvent : ScriptableObject
{
    private readonly List<System.Action> listeners = new();
    public void Raise() => listeners.ForEach(l => l.Invoke());
    public void Register(System.Action listener) => listeners.Add(listener);
    public void Unregister(System.Action listener) => listeners.Remove(listener);
}

// Usage: Weapon fires → DamageEvent raised → Health listens → Death check
// Usage: Enemy dies → KillEvent raised → XP system listens → XP awarded
```

### Object Pool Pattern
```csharp
public class SimplePool<T> where T : Component
{
    private readonly Queue<T> pool = new();
    private readonly T prefab;
    private readonly Transform parent;

    public T Get()
    {
        var obj = pool.Count > 0 ? pool.Dequeue() : Object.Instantiate(prefab, parent);
        obj.gameObject.SetActive(true);
        return obj;
    }

    public void Return(T obj)
    {
        obj.gameObject.SetActive(false);
        pool.Enqueue(obj);
    }
}
```

### Stat Modifier Stacking
```csharp
public class StatCalculator
{
    public static float Calculate(float baseValue, List<StatModifier> modifiers)
    {
        float flatBonus = modifiers.Where(m => m.Type == ModType.Flat).Sum(m => m.Value);
        float percentBonus = modifiers.Where(m => m.Type == ModType.Percent).Sum(m => m.Value);
        float multiplier = modifiers.Where(m => m.Type == ModType.Multiply)
            .Aggregate(1f, (acc, m) => acc * m.Value);

        return (baseValue + flatBonus) * (1 + percentBonus) * multiplier;
    }
}
```

## Tips
- Build Phase 1-3 in one session. Without damage and health, you can't test anything meaningful.
- Always implement the simplest version first. One enemy type, one weapon, one upgrade.
- Use ScriptableObjects for ALL static data. Never hardcode stats in MonoBehaviours.
- If two systems need to talk, use events. If you're injecting references everywhere, step back and add an event.
- The fastest path to "feels like a game" is: movement + one weapon + enemies that die + screen shake on hit.
