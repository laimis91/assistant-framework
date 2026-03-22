# Capture (Game State Snapshot via MCP)

Gather comprehensive game state snapshots using UnityMCP tools for informed playtesting and iteration.

## When to use
- Before and after a playtest session to compare state
- When something "feels wrong" but the user can't articulate what
- When tuning numbers and need baseline measurements
- Debugging gameplay issues by inspecting runtime state

## Process

### Step 1: Pre-Flight Check
```sequence
1. editor.getPlayModeState
   → Confirm we're in Edit Mode (for scene inspection) or Play Mode (for runtime state)

2. scene.getHierarchy
   → Map the full scene structure, identify key objects
```

### Step 2: Visual Capture
```sequence
1. editor.captureSceneView
   → Scene editor view — shows full layout, lighting, spatial relationships
   → Save as "capture_scene_[timestamp].png"

2. editor.captureGameView
   → What the player sees — check readability, visual density, UI clarity
   → Save as "capture_game_[timestamp].png"
```

### Step 3: Configuration Capture
For each key system, read current settings:

**Player:**
```sequence
1. Find player: scene.findByTag {tag: "Player"}
   → save PLAYER_ID

2. scene.getComponentProperties {instanceId: PLAYER_ID, typeName: "PlayerController"}
   → movement speed, dash cooldown, etc.

3. scene.getComponentProperties {instanceId: PLAYER_ID, typeName: "Health"}
   → max HP, current HP, regen rate
```

**Camera:**
```sequence
1. scene.findByTag {tag: "MainCamera"}
   → save CAM_ID

2. camera.getSettings {instanceId: CAM_ID}
   → orthographic size, background color, viewport
```

**Enemies (sample one of each type):**
```sequence
1. scene.findByTag {tag: "Enemy"}
   → get instanceIds for active enemies

2. For each unique enemy type:
   scene.getComponentProperties {instanceId: ENEMY_ID, typeName: "EnemyBehaviour"}
   → speed, HP, damage, behavior type
```

**Spawner:**
```sequence
1. scene.findByName {name: "SpawnManager"}
   → save SM_ID

2. scene.getComponentProperties {instanceId: SM_ID, typeName: "SpawnManager"}
   → current wave, spawn rate, active enemy count, difficulty multiplier
```

### Step 4: Runtime Metrics (Play Mode only)
If in Play Mode, capture dynamic state:

```sequence
1. Count active enemies: scene.findByTag {tag: "Enemy"} → count results
2. Count active projectiles: scene.findByTag {tag: "Projectile"} → count
3. Count active pickups: scene.findByTag {tag: "Pickup"} → count
4. Player position and velocity
5. Current game time / wave number
```

### Step 5: Compile Snapshot

Output a structured snapshot:

```
# Playtest Snapshot — [timestamp]

## Visual
- Scene capture: [path]
- Game view capture: [path]
- Visual notes: [any observations about readability, density, etc.]

## Player State
- Position: [x, y]
- HP: [current]/[max]
- Speed: [value]
- Weapons: [list with levels]
- Upgrades: [list]

## World State
- Game time: [mm:ss]
- Wave/difficulty: [current]
- Active enemies: [count]
- Active projectiles: [count]
- Active pickups: [count]

## Settings Snapshot
- Spawn rate: [value]
- Difficulty multiplier: [value]
- Camera size: [value]

## Observations
- [Automated observations based on data, e.g.:]
- "Enemy count (150) is high — check for pooling issues"
- "No projectiles active — is the weapon system working?"
- "Player HP is full — difficulty may be too low at this stage"
```

## Tips
- Take snapshots at consistent time intervals (e.g., every 2 minutes) for meaningful comparison
- The game view capture is the most valuable artifact — it shows exactly what the player experiences
- Compare pre-change and post-change snapshots to validate tuning adjustments
- If enemy count is climbing but kill count isn't, weapons are undertuned or enemies are too tanky
