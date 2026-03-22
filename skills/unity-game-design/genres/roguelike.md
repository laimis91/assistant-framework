# Genre: Roguelike / Roguelite

Patterns and systems specific to roguelike and roguelite games. Use alongside concept.md and mechanics.md when the game fits this genre.

## When to use
- Designing a game with permadeath and run-based structure
- Need a checklist of systems roguelikes typically require
- Deciding between roguelike (no persistence) and roguelite (meta-progression)
- Designing meta-progression systems

## Core Elements

| Element | Roguelike (pure) | Roguelite |
|---|---|---|
| Permadeath | Yes — run ends, everything resets | Yes — run ends, but some things persist |
| Procedural generation | Required — levels, items, enemies | Required |
| Run-based structure | Each attempt is self-contained | Each attempt plus meta-layer |
| Meaningful choices | Upgrades, paths, risk/reward | Same, plus meta-investment choices |
| Skill as progression | Only form of progression | Primary, supplemented by meta-upgrades |

## Run Structure Template

```
[Character Select]
    ↓
[Starting Room / Wave 1]
    ↓
[Explore / Fight] ←──────────────────┐
    ↓                                 │
[Reward: Upgrade Choice]              │
    ↓                                 │
[Escalation: Harder Enemies / Next Area]
    ↓                                 │
[Mini-boss or Event] ────────────────→┘
    ↓
[Boss / Final Wave / Time Limit]
    ↓
[Death or Victory]
    ↓
[Run Summary Screen]
    ↓
[Meta Progression Screen (roguelite only)]
    ↓
[Back to Character Select]
```

## Systems Checklist

Core systems every roguelike needs:

### P0 — Prototype
- [ ] Run initialization (seed generation, starting loadout)
- [ ] Player movement and basic combat
- [ ] One enemy type with chase behavior
- [ ] Basic spawning (timed or wave-based)
- [ ] Health and death
- [ ] At least one upgrade/power-up

### P1 — Complete Loop
- [ ] Procedural level or wave generation
- [ ] Enemy variety (3-5 types with distinct behaviors)
- [ ] Item/upgrade drop and choice system (pick 1 of N)
- [ ] XP or resource collection
- [ ] Difficulty scaling over time
- [ ] Player death flow → run-end screen → restart
- [ ] Run statistics (kills, time survived, damage dealt)

### P2 — Meta and Polish
- [ ] Meta-progression currency (earned per run)
- [ ] Permanent unlock shop
- [ ] Character/class selection (different starting loadouts)
- [ ] Save system (meta-progress persistence)
- [ ] Achievements or milestone unlocks
- [ ] Leaderboard or personal bests
- [ ] Story/lore elements between runs
- [ ] Challenge modes or difficulty modifiers

## Meta Progression Patterns

Choose one or combine several:

### 1. Unlock Pool Expansion (Vampire Survivors style)
- New weapons/items are added to the random pool as you achieve milestones
- Pro: Every run feels different as the pool grows
- Con: Can dilute the pool — too many options make it hard to get what you want
- Implementation: `UnlockRegistry` ScriptableObject — list of all items with unlock conditions

### 2. Permanent Stat Boosts (Rogue Legacy style)
- Spend meta-currency on small permanent upgrades (+5% HP, +3% damage)
- Pro: Steady sense of progress even on bad runs
- Con: Can trivialize difficulty over time — needs careful scaling
- Implementation: `MetaUpgradeTree` ScriptableObject — upgrade nodes with costs and effects

### 3. Character Unlocks (Hades style)
- New playable characters with different starting weapons and passive abilities
- Pro: High replay value, each character is a different experience
- Con: Requires balancing multiple playstyles
- Implementation: `CharacterDefinition` ScriptableObject — starting loadout, stats, unique ability

### 4. Story Progression (Hades style)
- Narrative advances with each run, win or lose
- Pro: Gives purpose to failed runs, motivates "one more try"
- Con: Significant content creation investment
- Implementation: `StoryState` — tracks conversation flags, run count triggers, NPC relationship levels

### 5. Challenge Modes (Dead Cells style)
- Harder modifiers unlocked after victories (Boss Cell equivalent)
- Pro: Endgame for skilled players
- Con: Only relevant after players can win consistently
- Implementation: `DifficultyModifier` ScriptableObject — stat multipliers, new enemy behaviors, removed safety nets

## Procedural Generation Approaches

For a first implementation, choose the simplest approach that fits the game:

| Approach | Complexity | Best for |
|---|---|---|
| **Random enemy placement on fixed arena** | Low | Bullet heaven, arena survivors |
| **Room templates with random connections** | Medium | Dungeon crawlers (Binding of Isaac) |
| **Tile-based procedural layouts** | High | Traditional roguelikes (Spelunky, Dungeon Crawl) |
| **Wave definitions with random composition** | Low | Wave-based arena games |

Recommendation for prototypes: Start with random wave composition on a fixed arena. Add procedural layouts later if the game needs exploration.

## Balance Notes for Roguelikes

### Upgrade Feel
- First 2-3 upgrades must ALWAYS feel impactful. Never offer "+2% health" as a first choice.
- Early upgrades should change how you play (new weapon, new behavior), not just tweak numbers.
- Later upgrades can be numerical — by then the player has a build identity.

### Synergy Design
- Synergy discovery is the core fun of a roguelike. Design upgrade pools with intentional combos.
- Create "build archetypes" — groups of upgrades that work together (speed build, AoE build, crit build).
- Signal synergies to the player: color coding, tags, explicit "synergy bonus" when combining related items.
- Not every combo needs to be designed. Leave room for emergent synergies the player discovers.

### Death Feel
- Death should trigger "I want to try again" not "that was unfair."
- Show what killed the player and how close they were to the next milestone.
- The run summary screen is critical — make the player feel their run meant something.
- If using meta-progression: always award SOME meta-currency, even on short runs.

### Seed and Reproducibility
- Use seeded random for procedural generation. This enables: seed sharing, bug reproduction, daily challenge modes.
- Implementation: Initialize `System.Random` with a seed. Store seed in run state. Display seed on death screen.

## Unity-Specific Implementation Notes

### Run State Management
```
RunState (plain C#, not MonoBehaviour):
  - Seed
  - Current wave/floor
  - Elapsed time
  - Player stats snapshot
  - Collected upgrades
  - Kill count, damage dealt, etc.
  - Save/Load for mid-run saves
```

### Scene Flow
Typical scene structure for a roguelite:
1. **MainMenu** — Title, settings, quit
2. **MetaHub** — Character select, upgrade shop, run history (roguelite only)
3. **GameScene** — The actual run (single scene for arena games, or scene-per-floor for dungeon crawlers)
4. **RunEnd** — Summary, meta-currency award, return to hub

For arena/survivor games: a single GameScene with runtime-spawned content is simplest. Avoid multiple scenes per run unless the game has distinct floors/areas.

### Object Pooling
Mandatory for:
- Enemies (dozens to hundreds on screen)
- Projectiles (potentially thousands per minute)
- Damage numbers (one per hit)
- XP gems / pickups
- VFX (hit effects, death effects)

Use Unity's built-in ObjectPool<T> (Unity 2021+) or a simple custom pool.
