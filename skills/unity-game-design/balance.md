# Balance (Numbers and Curves)

Design game balance — difficulty curves, economy, stat progression, and tuning parameters.

## When to use
- Defining how difficulty scales during a run
- Setting up an economy (XP, gold, upgrade costs)
- Balancing weapons, enemies, or upgrades against each other
- Need actual numbers to put into ScriptableObjects, not just "it gets harder"

## Process

### Step 1: Choose a Difficulty Curve

| Curve | Formula | Feel | Best for |
|---|---|---|---|
| **Linear** | difficulty = base + (rate × time) | Predictable, steady | Tutorial, early game |
| **Exponential** | difficulty = base × (rate ^ time) | Accelerating pressure | Survivor/bullet heaven |
| **S-Curve (Sigmoid)** | difficulty = max / (1 + e^(-k×(time - midpoint))) | Slow start, steep middle, plateau | Story-driven roguelites |
| **Stepped** | Flat periods with sudden jumps | Rhythmic tension/release | Wave-based, boss encounters |
| **Exponential + soft cap** | Exponential below threshold, logarithmic above | Urgency with ceiling | Recommended default for roguelikes |

For roguelike/bullet heaven, the recommended default is **exponential with soft caps**. Enemy stats grow exponentially, but player power can temporarily exceed the curve through lucky upgrades, creating "power spike" moments that are the core fun.

### Step 2: Design the Economy

Map every resource in the game:

**Income sources** — What gives the player resources?
- Kill rewards (XP, gold, drops)
- Time-based income (passive XP trickle)
- Event rewards (chests, challenges, bosses)
- Streak/combo bonuses

**Sinks** — What consumes resources?
- Upgrades and level-ups
- Reroll costs (re-pick upgrade choices)
- Healing or revival
- Meta-currency conversion

**Flow rate** — Critical question: How fast does income grow relative to costs?
- If income outpaces costs → player feels rich, choices feel low-stakes
- If costs outpace income → player feels pressured, every choice matters
- Sweet spot: player can afford ~70% of what they want, forcing meaningful tradeoffs

### Step 3: Define Stat Progression

For each stat category, specify:

| Parameter | Description |
|---|---|
| **Base value** | Starting value at level 1 |
| **Growth** | How it increases per level (flat add, percentage, or formula) |
| **Soft cap** | Point where returns diminish (e.g., attack speed above 200% gives half benefit) |
| **Hard cap** | Absolute maximum (e.g., movement speed cannot exceed 2× base) |

Common stat categories for action roguelikes:
- Max HP, HP regen
- Movement speed
- Attack damage (per weapon)
- Attack speed / cooldown reduction
- Area of effect
- Projectile count, pierce count
- Pickup / magnet radius
- XP gain multiplier
- Critical hit chance, critical hit damage

### Step 4: Build a Weapon Balance Matrix

Compare all weapons on the same axes:

```
| Weapon | DPS | Range | AoE | Ease of Use | Niche |
|---|---|---|---|---|---|
| Magic Wand | Low | Long | None | Easy | Single target, starter |
| Holy Water | Med | Short | Large | Easy | Area denial |
| Knife | High | Long | None | Medium | Piercing, boss killer |
| Garlic | Low | Melee | Ring | Easy | Defensive, passive |
| Lightning | High | Full | Chain | Auto | Screen clear |
```

Design rule: No weapon should be strictly better than another across all axes. Each should have a niche where it excels.

### Step 5: Build an Enemy Balance Matrix

```
| Enemy | HP | Damage | Speed | Behavior | First Appears | Threat |
|---|---|---|---|---|---|---|
| Bat | 5 | 3 | Fast | Chase | 0:00 | Low |
| Skeleton | 15 | 5 | Medium | Chase | 1:00 | Medium |
| Mage | 10 | 8 | Slow | Ranged | 3:00 | Medium |
| Charger | 25 | 15 | Burst | Charge | 5:00 | High |
| Boss | 500 | 20 | Slow | Phases | 10:00 | Boss |
```

Scaling rule: Enemy HP and count should scale together. Don't just add HP — add more enemies and new types to keep the visual chaos growing.

### Step 6: Design Upgrade Tiers

```
| Tier | Rarity | Drop Weight | Power Budget | Examples |
|---|---|---|---|---|
| Common | 60% | 600 | 1× | +10% move speed, +5 max HP, +1 projectile |
| Uncommon | 25% | 250 | 2× | +25% attack speed, +15% area, HP regen |
| Rare | 10% | 100 | 4× | Projectiles pierce, +50% damage, double XP |
| Legendary | 4% | 40 | 8× | Double projectiles + chain, full screen AoE |
| Mythic | 1% | 10 | 16× | Game-breaking combo (build-defining) |
```

Design rules for upgrade tiers:
- First 2-3 upgrades should ALWAYS feel impactful. Never offer +2% HP as a first choice.
- Synergy discovery is the core fun. Design upgrade pools with intentional combos.
- "Broken builds" should be possible but rare. The player feeling overpowered is a feature.
- Higher tiers should change HOW you play, not just give bigger numbers.

## Output format

```
# Balance Sheet — [Game Name]

## Difficulty Curve
- Type: [linear/exponential/stepped/exponential+softcap]
- Formula: [mathematical expression]
- Key breakpoints:
  - [0:00-2:00] — Learning phase, enemies are sparse
  - [2:00-5:00] — Core loop established, manageable challenge
  - [5:00-10:00] — Pressure builds, upgrades needed to keep up
  - [10:00-15:00] — Peak chaos, screen full of enemies and projectiles
  - [15:00+] — Survival mode / endgame / boss

## Economy
| Resource | Source | Sink | Rate (per minute) |
|---|---|---|---|
| XP | Enemy kills, gems | Level-ups | ~100 early, ~500 late |
| Gold | Enemy drops, chests | Shop purchases | ~50 per wave |
| Meta-crystal | Run completion | Permanent upgrades | ~10 per run |

## Player Stat Progression
| Stat | Base | Per Level | Soft Cap | Hard Cap |
|---|---|---|---|---|
| Max HP | 100 | +10 flat | 300 (half benefit) | 500 |
| Move Speed | 5 | +3% | 150% base | 200% base |
| Attack Damage | 10 | +8% | None | None |
| Attack Speed | 1.0/sec | +5% | 3.0/sec (half) | 5.0/sec |
| Pickup Radius | 1.5 units | +10% | None | Full screen |

## Enemy Scaling (by time or wave)
| Time / Wave | HP Multiplier | Damage Mult | Speed Mult | New Enemy Types |
|---|---|---|---|---|
| 0:00 | 1.0× | 1.0× | 1.0× | Bat |
| 2:00 | 1.5× | 1.2× | 1.0× | Skeleton |
| 5:00 | 3.0× | 1.5× | 1.1× | Mage, Charger |
| 10:00 | 8.0× | 2.0× | 1.2× | Elite variants |
| 15:00 | 20.0× | 3.0× | 1.3× | Boss |

## Upgrade Pool
| Tier | Rarity % | Power Budget | Count in Pool |
|---|---|---|---|
| Common | 60% | 1× | 15 |
| Uncommon | 25% | 2× | 10 |
| Rare | 10% | 4× | 6 |
| Legendary | 4% | 8× | 3 |
| Mythic | 1% | 16× | 1 |

## Weapon Comparison
| Weapon | Base DPS | Range | AoE | Niche |
|---|---|---|---|---|
| [weapon data] |

## Tuning Levers (what to adjust first when playtesting)
1. [Most impactful parameter to tune]
2. [Second most impactful]
3. [Third]
```

## Tips
- Playtest with half your numbers first. It's easier to scale up than to realize everything is overtuned.
- The single most impactful tuning lever is usually enemy spawn rate, not enemy stats.
- If players feel weak: add more enemies (so weapons hit more), don't buff damage.
- If players feel overpowered: spawn enemies faster, don't nerf upgrades. Being overpowered is fun — make it harder to REACH that state.
- Balance in spreadsheets first. Build a simple formula in a spreadsheet to model DPS vs enemy HP over time before putting numbers in Unity.
- XP curves: use `xp_required = base × (level ^ exponent)`. Start with base=10, exponent=1.5. Adjust from there.
