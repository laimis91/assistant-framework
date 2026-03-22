# Mechanics (System Design)

Design specific game mechanics in detail. Use after the concept document to drill into individual systems.

## When to use
- Concept document is done and you need to implement a specific system
- A system's behavior needs precise definition before coding
- You need to decide between implementation approaches in Unity

## Process

For each mechanic, define these six sections:

### 1. Purpose
Why does this system exist? What player need does it serve? If you can't answer this clearly, the system may not be needed yet.

### 2. Inputs and Outputs
- **Inputs**: What triggers or feeds this system? (player action, timer, event, other system output)
- **Outputs**: What does it produce? (damage dealt, items spawned, state change, UI update)

### 3. Core Logic
The rules and processing. Use pseudocode when the logic is non-trivial. Keep it implementation-agnostic where possible — the Unity implementation section handles specifics.

### 4. Data Model
Key data structures. In Unity terms:
- **ScriptableObject** — Static data (weapon stats, enemy definitions, upgrade templates)
- **MonoBehaviour** — Runtime state attached to GameObjects (health component, weapon holder)
- **Plain C# class/struct** — Domain logic, calculations, no Unity dependency

### 5. Unity Implementation Notes
- **MonoBehaviour vs pure C#**: Does this need to be on a GameObject, or can it be a service?
- **Update vs FixedUpdate vs Event-driven**: Physics → FixedUpdate. Visuals/input → Update. State changes → Events.
- **Architecture layer**: Domain (pure logic), Application (orchestration), Presentation (MonoBehaviours, UI)
- **Object pooling**: Required for anything spawned frequently (projectiles, enemies, VFX, damage numbers)

### 6. Tuning Parameters
What values should be exposed for tweaking? These become fields on ScriptableObjects or config files. Every magic number should be a tuning parameter.

## Common Mechanics Templates

Use these as starting points. Adapt to the specific game.

### Spawner System
```
Purpose: Create enemies over time with escalating difficulty.

Inputs: Game timer, difficulty curve, player position
Outputs: Enemy instances at screen-edge positions

Logic:
- Maintain a spawn budget that increases over time
- Each enemy type has a spawn cost
- Each tick: accumulate budget, spend on enemies until budget < cheapest enemy
- Spawn position: random point on circle around player, outside camera bounds
- Anti-clump: minimum distance between spawn points

Data:
- SpawnWaveDefinition (ScriptableObject): enemy types, weights, budget per minute
- SpawnerService (plain C#): budget tracking, enemy selection
- SpawnerBehaviour (MonoBehaviour): position calculation, pool requests

Tuning: base budget, budget growth rate, spawn radius, min spawn distance,
        per-enemy-type weight curves
```

### Combat / Damage System
```
Purpose: Calculate and apply damage between entities.

Inputs: Damage source (weapon/projectile), target (enemy/player)
Outputs: HP reduction, death event, damage number display

Logic:
- damage = base_damage × modifiers
- Modifiers: flat bonus → percentage bonus → multiplicative bonus (applied in order)
- Optional: damage types (physical/fire/ice) with resistances
- Optional: critical hits (crit_chance, crit_multiplier)
- On kill: emit KillEvent for XP, drops, score

Hit Detection options:
- Physics triggers (OnTriggerEnter2D) — simple, good for most cases
- Overlap circle/box (Physics2D.OverlapCircle) — AoE, no rigidbody needed
- Raycast — beams, line attacks

Data:
- DamageInfo (struct): amount, type, source, crit flag
- Health (MonoBehaviour): current HP, max HP, TakeDamage(), OnDeath event
- DamageCalculator (plain C#): modifier stacking, crit rolls

Tuning: base damage per weapon, crit chance, crit multiplier,
        resistance values, invulnerability frames duration
```

### Upgrade / Stat System
```
Purpose: Let the player grow stronger through choices.

Inputs: Level-up event, upgrade pool, player's current upgrades
Outputs: Modified player stats, new/upgraded weapons

Logic:
- Maintain a list of all possible upgrades with rarity weights
- On level-up: pick N random upgrades (weighted by rarity), present to player
- Upgrades can be: new weapon, weapon level-up, passive stat boost
- Stat modifiers stack: base + sum(flat) × product(1 + percent)
- Max level per upgrade (e.g., 5 levels per weapon, 3 per passive)
- Exclude maxed-out upgrades from the pool

Data:
- UpgradeDefinition (ScriptableObject): name, description, icon, rarity,
  stat modifications, max level, per-level scaling
- PlayerStats (plain C#): base stats + modifier list, calculated final stats
- UpgradePool (plain C#): available upgrades, rarity weights, exclusion rules

Tuning: rarity weights, reroll cost, choices offered (3-4),
        stat values per upgrade level, max level per upgrade
```

### Weapon System
```
Purpose: Automatically attack enemies on behalf of the player.

Inputs: Fire timer, player position, enemy positions
Outputs: Projectiles or damage zones

Fire Patterns:
- Forward shot: fires toward nearest enemy or cursor direction
- Spread: N projectiles in an arc
- Burst: rapid sequence of shots
- Orbital: projectiles rotate around player
- Area: damage zone centered on player or random nearby position
- Beam: continuous line damage in a direction

Logic:
- Each weapon has independent cooldown timer
- On fire: create projectile(s) from pool, set velocity/behavior
- Projectile behaviors: straight, homing, piercing, bouncing, orbiting
- Piercing: projectile continues through enemies (with optional pierce limit)
- Bouncing: reflects off screen edges or chains between enemies

Data:
- WeaponDefinition (ScriptableObject): fire pattern, cooldown, damage,
  projectile speed, projectile count, pierce count, area, per-level scaling
- WeaponInstance (MonoBehaviour): cooldown timer, fire logic, level
- Projectile (MonoBehaviour): movement, hit detection, lifetime, pooled

Tuning: cooldown, damage, projectile speed, projectile count,
        area of effect, pierce count, duration, per-level scaling
```

### Enemy AI
```
Purpose: Give enemies distinct behaviors that create interesting positioning challenges.

Behavior Patterns:
- Chase: move directly toward player (simplest, most common)
- Circle: orbit the player at a fixed radius
- Charge: pause, telegraph, dash at high speed toward player's position
- Ranged: maintain distance, fire projectiles at player
- Swarm: chase but with flocking/separation from other enemies
- Boss: phase-based — combine patterns, add unique attacks

Logic:
- Each enemy type has a behavior enum and associated parameters
- Chase: direction = (player.position - self.position).normalized × speed
- Separation: add repulsion force from nearby enemies to prevent stacking
- Charge: enter telegraph state (flash/shake), record target position, dash

Data:
- EnemyDefinition (ScriptableObject): HP, damage, speed, behavior type,
  behavior params, XP value, sprite/color
- EnemyBehaviour (MonoBehaviour): state machine, movement, collision
- EnemyPool: object pool per enemy type

Tuning: speed, HP, damage, charge telegraph duration, charge speed,
        orbit radius, separation distance, aggro range
```

## Output format

For each mechanic designed:

```
## [Mechanic Name]

### Purpose
[1-2 sentences — why this exists]

### Data Model
- [ScriptableObject]: [what static data it holds]
- [MonoBehaviour]: [what runtime state it manages]
- [Plain C#]: [what logic it encapsulates]

### Logic
[Core rules. Pseudocode for anything non-obvious.]

### Unity Implementation
- Layer: [Domain / Application / Presentation]
- Pattern: [MonoBehaviour / pure C# / ScriptableObject / service]
- Timing: [Update / FixedUpdate / Event-driven]
- Pooling: [Yes/No — why]

### Dependencies
[What systems must exist before this one]

### Tuning Parameters
| Parameter | Type | Default | Notes |
|---|---|---|---|
| ... | float/int/enum | ... | ... |
```

## Tips
- Design the data model first. If the ScriptableObjects are right, the code follows naturally.
- Every system should be testable in isolation. If it can't work without three other systems, the coupling is too tight.
- Prefer events over direct references between systems. Weapon doesn't need to know about XP — it emits a KillEvent, and the XP system listens.
- Start with the simplest version of each mechanic. A chase enemy and a forward-shot weapon are enough for a prototype.
