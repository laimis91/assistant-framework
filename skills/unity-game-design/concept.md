# Concept (Game Concept Document)

Take a raw game idea and produce a structured, buildable Game Concept Document.

## When to use
- User has a vague game idea that needs structure
- Starting a new game project and need a north-star document
- Need to align on scope before building anything

## Process

### Step 1: Extract the Core Fantasy
Identify three things:
- **Power fantasy** — What makes the player feel awesome?
- **Core tension** — What creates moment-to-moment engagement?
- **Unique hook** — What distinguishes this from similar games?

If the user's idea is vague, ask targeted questions:
- "What existing game is closest to what you're imagining?"
- "What's the single most important feeling you want the player to have?"
- "How long should a single session/run last?"

### Step 2: Define the Core Loop (30-second loop)
Every game has a tight loop the player repeats constantly:

```
[Action] → [Feedback] → [Reward/Consequence] → [Decision] → repeat
```

Reference examples:
- **Vampire Survivors**: Move → Auto-attack hits → XP drops → Choose upgrade
- **Hades**: Attack/dash → Defeat enemies → Boon offered → Pick boon, choose next room
- **Brotato**: Position yourself → Weapons auto-fire → Gold drops → Buy items between waves
- **Enter the Gungeon**: Dodge-roll/shoot → Clear room → Get gun/item → Choose next room

### Step 3: Session Structure
Define what a single play session looks like:
- **Target duration**: 5 minutes (arcade), 15 minutes (survivor), 30 minutes (run-based)
- **Phases**: What does early/mid/late game feel like?
- **Escalation**: How does difficulty/intensity increase?
- **End condition**: Timer, boss, death, floor count, objective

### Step 4: Meta Progression (if roguelite)
What persists between runs:
- Unlockable characters or starting weapons
- Permanent stat upgrades (bought with meta-currency)
- New items/weapons added to the random pool
- Story or lore progression
- Achievement-gated content

If pure roguelike: state explicitly that nothing persists. Player skill is the only progression.

### Step 5: Systems Inventory
List every system the game needs. For each:
- **Name** and one-line description
- **Dependencies** — what other systems must exist first
- **Priority**: P0 (prototype), P1 (complete loop), P2 (polish)

P0 should be the absolute minimum for a playable prototype — typically: player movement, one weapon, one enemy type, basic spawning, basic damage/health.

### Step 6: Art Direction Notes
Recommend a visual approach that works for programmer art:
- **Style**: Geometric shapes, pixel art, low-poly, neon/glow
- **Color palette mood**: Dark+neon, pastel, earthy, monochrome+accent
- **Camera**: Top-down, side-scroll, isometric, third-person
- **Reference games**: Games with similar visual simplicity that still look good

## Output format

```
# [Game Name] — Concept Document

## Elevator Pitch
[1-2 sentences. What is this game?]

## Core Fantasy
[What makes the player feel awesome]

## Core Loop (30 seconds)
[Action] → [Feedback] → [Reward] → [Decision]

## Session Structure
- Duration: [X minutes target]
- Early game: [description — first 1-3 minutes]
- Mid game: [description — building power]
- Late game: [description — peak chaos/challenge]
- End condition: [how a run ends]

## Meta Progression
- [What persists between runs, or "None — pure roguelike"]

## Systems (Priority Order)
| System | Description | Dependencies | Priority |
|---|---|---|---|
| Player Movement | WASD/stick movement with speed stat | None | P0 |
| ... | ... | ... | P0/P1/P2 |

## Visual Direction
- Style: [geometric/pixel/low-poly/neon]
- Perspective: [top-down/side/iso]
- Palette: [description]
- References: [similar games with achievable art]

## Prototype Scope (P0 only)
[Bullet list of exactly what the minimum playable version includes]
[This is what gets built first — nothing else until this is playable]
```

## Tips
- A good concept document fits on 1-2 pages. If it's longer, you're over-designing.
- The prototype scope is the most important section — it prevents scope creep.
- Every system in P0 must directly serve the core loop. If it doesn't, it's P1 or P2.
- Name the game even if it's a placeholder — it makes discussion easier.
