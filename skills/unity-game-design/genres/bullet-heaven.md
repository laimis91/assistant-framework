# Genre: Bullet Heaven / Survivor

Patterns and systems specific to bullet heaven and survivor games (Vampire Survivors, Brotato, Soulstone Survivors, etc.). Use alongside concept.md and mechanics.md.

## When to use
- Designing a game where weapons auto-fire and the player focuses on movement
- Need the standard systems and patterns for the survivor subgenre
- Designing weapon types, evolution systems, or wave-based spawning

## Core Elements

| Element | Description |
|---|---|
| **Auto-attacking** | Player weapons fire automatically — no attack button |
| **Movement as primary skill** | Positioning and dodging is the core gameplay input |
| **Swarm enemies** | Large numbers of simple enemies, not few complex ones |
| **Power escalation** | Player goes from weak to absurdly powerful within one run |
| **Time-based runs** | Survive X minutes to win (typically 15-30 minutes) |
| **Choice-driven builds** | Level-up presents N random upgrades, player picks one |

## Session Flow

```
[Start: 1 weapon, weak stats]
    ↓
[Move through arena, enemies approach from edges]
    ↓
[Weapons auto-fire, enemies die, drop XP gems]
    ↓
[Collect gems → level up → pick 1 of 3-4 upgrades]    ←─┐
    ↓                                                      │
[More enemies spawn, faster and tougher]                   │
    ↓                                                      │
[Acquire more weapons, upgrade existing ones]              │
    ↓                                                      │
[Screen fills with projectiles and enemies] ───────────────┘
    ↓
[Peak power: player clears entire screen regularly]
    ↓
[Final wave or boss at time limit]
    ↓
[Victory or death → run summary → meta-progression]
```

## Key Systems

### 1. Auto-Attack Manager
The central system that coordinates all weapon firing.

- Each weapon has its own independent cooldown timer
- Weapons fire automatically when cooldown expires
- Targeting: nearest enemy, random enemy, fixed direction, or mouse/stick aim
- Weapon slots: typically 6 maximum (Vampire Survivors standard)
- Order matters: first weapon acquired is the "main" — may get UI priority

Implementation:
- `WeaponManager` (MonoBehaviour on player): holds weapon slot list, ticks cooldowns
- Each weapon is a `WeaponInstance` with reference to a `WeaponDefinition` (ScriptableObject)
- Fire logic can be a strategy pattern: `IWeaponFirePattern` with implementations per weapon type

### 2. Weapon Types

Standard weapon archetypes for bullet heaven games:

| Type | Pattern | Example (VS) | Implementation |
|---|---|---|---|
| **Projectile** | Fires toward nearest enemy | Magic Wand | Spawn pooled projectile, set velocity |
| **Multi-projectile** | N projectiles in a spread | Knife (with upgrades) | Spawn N projectiles with angle offsets |
| **Area (player-centered)** | Damage zone around player | Garlic | Overlap circle every tick, damage all in radius |
| **Area (targeted)** | Damage zone at enemy position | Holy Water | Spawn zone at random/nearest enemy pos |
| **Orbital** | Rotates around player | King Bible | Spawn N objects, rotate on circle path |
| **Beam** | Continuous line damage | N/A | Raycast or box collider, damage on tick |
| **Homing** | Seeks nearest enemy | Runetracer (bouncing) | Projectile with steering toward target |
| **Summon** | Allied units fight independently | N/A | Spawn AI ally with its own attack pattern |
| **Chain** | Damage jumps between enemies | Lightning Ring | On hit, find nearest unhit enemy, repeat |

Design rule: The starting weapon pool should cover different niches — one single-target, one AoE, one defensive. Let the player's choices shape their build.

### 3. Weapon Evolution

A defining feature of the genre (Vampire Survivors popularized it):

```
Base Weapon (max level) + Matching Passive Item = Evolved Weapon
```

- Evolution happens via a chest drop after reaching the level cap on both components
- Evolved weapons are dramatically more powerful — a major power spike
- Each weapon has exactly one evolution path

Implementation:
- `EvolutionRecipe` (ScriptableObject): weapon_id + passive_id → evolved_weapon_id
- `EvolutionChecker` (plain C#): on chest pickup, check if any recipe is satisfied
- Display evolution requirements subtly in UI (so players learn the combos)

### 4. Enemy Wave Spawner

The spawner is the difficulty engine in a bullet heaven game.

Spawn logic:
- **Budget system**: Each tick accumulates a "spawn budget" based on elapsed time
- **Enemy cost**: Each enemy type has a spawn cost proportional to its threat
- **Composition**: Define which enemy types are available at each time bracket
- **Position**: Spawn at random points on a circle around the player, outside camera bounds
- **Anti-clump**: Minimum distance between spawn points, distribute around the circle
- **Elite/special spawns**: Timer-based events (every 60 seconds, spawn an elite)

Escalation levers:
1. Spawn rate increases (more budget per tick)
2. New enemy types introduced
3. Enemy stat multipliers increase
4. Elite and mini-boss frequency increases
5. Swarm events (sudden burst of many enemies from one direction)

### 5. XP and Level-Up System

The primary progression within a run:

- Enemies drop XP gems on death (amount scales with enemy type)
- Gems are physical pickups — player walks over them or they're pulled in by magnet radius
- XP required per level: `xp = base × (level ^ exponent)` — start with base=10, exponent=1.5
- Early levels fast (every 10-15 seconds), later levels slower (every 30-60 seconds)

Level-up flow:
1. XP bar fills → game pauses (or slows)
2. Present 3-4 random upgrades from the pool
3. Player picks one
4. Game resumes
5. If multiple level-ups pending, repeat immediately

Implementation:
- `ExperienceSystem` (plain C#): tracks XP, calculates level thresholds
- `LevelUpUI` (MonoBehaviour): pause, display choices, handle selection
- `UpgradePool` (plain C#): weighted random selection, excludes maxed upgrades

### 6. Pickup System

- XP gems: small, color-coded by value (green=1, blue=5, red=25)
- Magnet radius: player stat that auto-collects pickups within range
- Magnet pickup: temporarily pulls ALL gems on screen to player
- Chest: contains gold, weapon evolution, or bonus upgrade
- Healing pickup: restores HP (drop from elites or time-based)
- Coin/gold: separate currency for in-run shop (if applicable)

Implementation:
- All pickups share a base `Pickup` MonoBehaviour with type enum
- Magnet: each frame, pickups within radius lerp toward player
- Object pooled — hundreds of gems can be on screen simultaneously

### 7. Chest and Event System

Periodic rewards outside the XP system:
- **Timed chests**: Appear every N minutes at a fixed or random position
- **Kill milestone chests**: Appear after killing X enemies
- **Elite drops**: Elites/mini-bosses drop guaranteed chests
- **Events**: Swarm events, treasure goblins, bonus XP waves

Chest contents priority:
1. Weapon evolution (if recipe is satisfied)
2. Gold / meta-currency
3. Healing
4. Bonus upgrade choice

## Pacing Guide

| Time | Phase | Player State | Enemy State | Events |
|---|---|---|---|---|
| 0:00-2:00 | **Learning** | 1 weapon, figuring out controls | Sparse bats, slow approach | None |
| 2:00-5:00 | **Building** | 2-3 weapons, first meaningful upgrades | New enemy types, moderate density | First chest |
| 5:00-10:00 | **Scaling** | 4-5 weapons, build identity forming | Dense swarms, first elites | Elites spawn, chests |
| 10:00-15:00 | **Power spike** | Full weapon loadout, some maxed | Screen-filling hordes | Evolutions possible |
| 15:00-20:00 | **Peak** | Evolved weapons, screen-clearing power | Desperate enemy density | Mini-boss |
| 20:00-30:00 | **Endgame** | Player at peak, enemies catch up | Overwhelming numbers | Final boss at 30:00 |

The "screen-clearing moment" (when the player's combined weapons visibly annihilate everything) should happen naturally around minute 15-20. This is the peak of the power fantasy.

## Balance Notes for Bullet Heaven

### Weapon Balance
- 6 weapon slots is the sweet spot. Fewer feels limiting, more causes visual chaos and decision fatigue.
- Early weapons should cover different niches. Don't offer three single-target projectile weapons.
- Weapon DPS should be close at equal levels. Differentiate by pattern, range, and utility — not raw damage.

### XP and Leveling
- Fast early levels keep the player engaged during the weakest phase.
- By minute 5, the player should have had at least 8-10 upgrade choices.
- Rerolls (re-randomize upgrade choices) should cost increasing amounts. First reroll cheap, subsequent expensive.

### Enemy Design
- Individual enemies should be weak. The threat comes from numbers, not individual power.
- Enemy HP should scale slower than player DPS. The power fantasy IS feeling strong.
- Variety comes from behavior, not stats. A fast charger and a slow ranged enemy feel different even at the same HP.
- Enemy knockback on hit helps readability and gives the player breathing room.

### Screen Readability
- This is the single biggest design challenge. When 200 enemies and 50 projectiles are on screen, the player must still be able to read the battlefield.
- Enemy art should be simple and uniform so the player sees "mass" not "detail."
- Player projectiles should be visually distinct from enemies (bright vs dark, or contrasting colors).
- Damage numbers: small, fast-fading, color-coded by damage type. Don't let them obscure enemies.

## Visual Considerations for Programmer Art

### Minimum Viable Art
- **Player**: A colored triangle or circle with a directional indicator
- **Enemies**: Colored shapes — differentiate by size and color (red=aggressive, blue=ranged)
- **Projectiles**: Small bright circles with a simple trail (particle system or trail renderer)
- **XP gems**: Small colored diamonds with a glow shader (green/blue/red by value)
- **Damage numbers**: TextMeshPro floating text, white with black outline
- **Health bar**: Simple UI bar, red fill, positioned above player or in HUD

### Camera
- Top-down is standard and easiest to implement.
- Camera follows player with slight lag (SmoothDamp).
- World should be larger than the screen — enemies spawn offscreen and approach.
- Consider a "danger indicator" UI at screen edges showing enemy approach direction.

### Particle Effects (essential feedback)
- Hit effect: small burst of particles in enemy's color
- Death effect: slightly larger burst
- XP gem collect: tiny sparkle
- Level up: screen flash or radial burst
- Damage number: critical hits get larger text and a different color

### Performance
- Object pooling is mandatory for everything spawned at runtime
- Enemy count target: handle 200-500 simultaneously
- Projectile count target: handle 100+ simultaneously
- Consider spatial partitioning for hit detection if overlap checks become expensive
- Disable enemy-to-enemy collision — let them stack. Only player-to-enemy and projectile-to-enemy matter.

## Unity-Specific Architecture

### Recommended Component Structure
```
Player (GameObject)
├── PlayerMovement (MonoBehaviour) — input handling, physics movement
├── PlayerHealth (MonoBehaviour) — HP, damage, death, invulnerability frames
├── WeaponManager (MonoBehaviour) — weapon slot list, cooldown ticking
├── ExperienceCollector (MonoBehaviour) — trigger collider for gem pickup
└── MagnetField (MonoBehaviour) — expanding trigger collider for gem attraction

Enemy (GameObject, pooled)
├── EnemyBehaviour (MonoBehaviour) — movement AI, state
├── Health (MonoBehaviour) — HP, damage, death, drop on death
└── ContactDamage (MonoBehaviour) — damages player on collision

Projectile (GameObject, pooled)
├── ProjectileMovement (MonoBehaviour) — velocity, homing, bounce
├── ProjectileDamage (MonoBehaviour) — hit detection, pierce count
└── Lifetime (MonoBehaviour) — auto-return to pool after N seconds

Pickup (GameObject, pooled)
├── PickupBehaviour (MonoBehaviour) — type, value, magnet response
└── SpriteRenderer / simple mesh
```

### Event Bus
Use an event bus or ScriptableObject events to decouple systems:
- `OnEnemyKilled(EnemyDefinition, Vector3 position)` — triggers XP drop, score, kill count
- `OnXPCollected(int amount)` — feeds experience system
- `OnLevelUp(int newLevel)` — triggers upgrade UI
- `OnUpgradeChosen(UpgradeDefinition)` — applies stat changes, adds weapon
- `OnPlayerDeath()` — triggers run-end flow
- `OnWeaponEvolved(WeaponDefinition evolved)` — visual/audio celebration

This keeps systems independent. The weapon system doesn't know about XP. The spawner doesn't know about upgrades. They communicate through events.
