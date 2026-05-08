# Unity Game

**Architecture:** Clean Architecture with Assembly Definitions (asmdef)

## Folder structure
```
Assets/
  _Project/
    Domain/               # Pure C# — no MonoBehaviour, no UnityEngine
      Domain.asmdef
    Application/          # Use cases, game state, interfaces
      Application.asmdef  # References: Domain
    Infrastructure/       # Save system, analytics, platform services
      Infrastructure.asmdef   # References: Application, Domain
    Presentation/         # MonoBehaviours, ScriptableObjects, UI
      Presentation.asmdef     # References: all above
    Resources/
    Scenes/
    Prefabs/
  Plugins/
tests/
  EditMode/
  PlayMode/
```

## Typical Discovery Q&A
```
1. Game loop?
   a) Turn-based  b) Real-time  c) Hybrid (real-time with pause)
2. Scene management?
   a) Single scene + runtime instantiation
   b) Multi-scene additive loading
   c) Scene per level
3. Input system?
   a) New Input System (action maps, recommended)
   b) Legacy Input Manager
4. State management?
   a) ScriptableObject events  b) Singleton GameManager  c) State machine
5. Save system?
   a) JSON to persistentDataPath  b) PlayerPrefs  c) Custom binary
```

## Architecture rules (Plan phase)
- Domain.asmdef: NO references (pure C#, no UnityEngine)
- Application.asmdef: references Domain only
- Infrastructure.asmdef: references Application, Domain
- Presentation.asmdef: references all above + Unity assemblies
- No MonoBehaviour in Domain or Application
- ScriptableObjects only in Presentation or Infrastructure
- Game logic testable without Play Mode (NUnit EditMode)
- No FindObjectOfType or static singletons in Domain/Application
- No `./generated/` file modifications unless explicitly asked

## Design rules (Design phase)
- UI Toolkit or Unity UI (Canvas) — pick one, don't mix
- Color palette in ScriptableObject or USS variables
- Consistent spacing and sizing across UI panels
- Test at target resolutions (mobile: 1080x1920, desktop: 1920x1080)
- CanvasScaler: Scale With Screen Size
- Minimum font size 14pt at target resolution

## Build/test
```
# EditMode tests (fast, no Play Mode):
Unity > Test Runner > EditMode > Run All

# PlayMode tests (integration):
Unity > Test Runner > PlayMode > Run All

# Verify: zero console errors, no missing prefab refs, clean scene load
```

## Roguelike / Bullet Heaven Patterns

### Common Systems Architecture
Map each system to its architecture layer:

**Domain Layer (pure C#, no Unity)**
- Stat system (base stats, modifiers, calculation)
- Upgrade/item definitions (data models, rarity, effects)
- Damage calculation (types, resistances, formulas)
- Wave configuration (enemy types, counts, timing)
- Run state (current stats, collected upgrades, score)
- Meta progression (unlocks, currencies, persistent data)

**Application Layer (use cases, interfaces)**
- ISpawnService (spawn enemies by wave config)
- IUpgradeService (roll upgrades, apply to player)
- IRunManager (initialize run, track progress, end run)
- ISaveService (save/load meta progression)
- IObjectPool<T> (pooling interface)

**Infrastructure Layer (implementations)**
- JsonSaveService (save to persistentDataPath)
- ScriptableObject-based game config
- Analytics integration (if any)

**Presentation Layer (MonoBehaviours, UI)**
- PlayerController (input, movement)
- EnemyBehavior (AI, pathfinding)
- WeaponBehavior (fire patterns, projectile spawning)
- SpawnManager (wave execution, spawn points)
- UpgradeUI (choice panel, reroll)
- HUD (health, XP, timer, kill count)
- CameraController (follow, bounds)
- ObjectPool<T> (Unity-specific pooling with GameObjects)
- VFXManager (particles, screen shake, hit flash)

### Game State Machine
```
                    ┌──────────┐
                    │  Boot    │
                    └────┬─────┘
                         ▼
                    ┌──────────┐
              ┌─────│  Menu    │─────┐
              │     └──────────┘     │
              ▼                      ▼
        ┌──────────┐          ┌──────────┐
        │ Character│          │ Settings │
        │  Select  │          └──────────┘
        └────┬─────┘
             ▼
        ┌──────────┐
        │  Loading │ (init run, seed, config)
        └────┬─────┘
             ▼
        ┌──────────┐     ┌──────────┐
        │ Playing  │────▶│  Paused  │
        └────┬─────┘◀────└──────────┘
             │
        ┌────┴─────┐
        ▼          ▼
   ┌────────┐ ┌────────┐
   │Level Up│ │  Boss  │
   │ Choice │ │  Intro │
   └───┬────┘ └───┬────┘
       │          │
       ▼          ▼
   (resume)   (resume)
             │
             ▼
        ┌──────────┐
        │ Game Over│ (death or victory)
        └────┬─────┘
             ▼
        ┌──────────┐
        │  Results │ (stats, meta currency)
        └────┬─────┘
             ▼
        (back to Menu)
```

### Object Pooling Pattern
Essential for bullet heaven (hundreds of projectiles/enemies):
```
Pool<T> where T : MonoBehaviour
  - Pre-instantiate N objects, set inactive
  - Get(): activate and return from pool
  - Return(T): deactivate and return to pool
  - Auto-expand if pool exhausted (log warning)

Pooled objects: projectiles, enemies, XP gems, damage numbers, particle effects
```

### ScriptableObject Configuration
Use ScriptableObjects for data-driven design:
- `EnemyConfig`: HP, speed, damage, sprite/prefab, behavior type
- `WeaponConfig`: damage, cooldown, projectile count, pattern, evolution target
- `UpgradeConfig`: stat changes, rarity, description, icon, stacking rules
- `WaveConfig`: enemy types, counts, spawn interval, duration
- `RunConfig`: starting weapons, XP curve, wave sequence, boss schedule
- `MetaConfig`: unlock costs, permanent upgrade costs, character stats

### Input System Setup
Prefer New Input System with action maps:
```
PlayerActions (Action Map)
  - Move: Vector2 (WASD / Left Stick)
  - Aim: Vector2 (Mouse / Right Stick) — if manual aim
  - Dash: Button
  - Pause: Button
  - Interact: Button (for co-op revive, shop)

UIActions (Action Map)
  - Navigate: Vector2
  - Submit: Button
  - Cancel: Button
```

### Discovery Q&A (Roguelike-specific, add to existing)
```
6. Dimension?
   a) 2D top-down  b) 2D side-scroll  c) 3D top-down  d) 3D third-person
7. Auto-attack or manual?
   a) Full auto (Vampire Survivors)  b) Aim + auto-fire  c) Manual aim + fire
8. Run duration target?
   a) 5 minutes  b) 15 minutes  c) 30 minutes  d) Variable
9. Meta progression?
   a) None (pure roguelike)  b) Permanent unlocks  c) Permanent stat boosts  d) Both
10. Multiplayer?
    a) Single-player only  b) Local co-op  c) Online co-op  d) Plan for later
```
