# Iteration (Feedback to Action)

Convert playtest feedback and observations into concrete tuning changes, then apply them via UnityMCP.

## When to use
- After a playtest session with observations/feedback
- When the game "feels" wrong and you need data-driven adjustments
- When tuning difficulty, pacing, or game feel

## Process

### Step 1: Analyze Feedback

Map feedback to tunable systems:

| Feedback | System | Likely Lever |
|---|---|---|
| "Too easy" | Spawner | Increase spawn rate or enemy HP |
| "Too hard" | Spawner / Player | Decrease spawn rate or buff player stats |
| "Boring" | Weapons / Spawner | Increase enemy count, add variety, more weapon effects |
| "Can't see what's happening" | Visuals | Reduce particle count, adjust colors, increase contrast |
| "Feels sluggish" | Player | Increase move speed, reduce attack cooldowns |
| "Enemies are bullet sponges" | Balance | Reduce enemy HP or increase player damage |
| "No sense of progression" | Upgrades | Make upgrades more impactful, increase level-up frequency |
| "Weapons feel weak" | Weapons | Add screen shake, increase projectile size, add VFX |
| "I die without knowing why" | Visual Feedback | Add clearer damage indicators, enemy telegraph, HP bar |

### Step 2: Determine Changes

For each issue, define:
- **Parameter to change** — exact field on exact component
- **Current value** — from capture snapshot
- **New value** — calculated adjustment
- **Rationale** — why this change addresses the feedback

**Tuning rules of thumb:**
- First adjustment: change by 20-30%. Small changes (5-10%) are often imperceptible.
- Never change more than 2-3 parameters at once — otherwise you can't tell what helped.
- Prioritize "feel" changes (speed, responsiveness, VFX) over "math" changes (damage, HP).
- If unsure between buffing player and nerfing enemies, buff the player. Being powerful is fun.

### Step 3: Apply Changes via UnityMCP

```sequence
1. editor.getPlayModeState
   → Must be in Edit Mode to modify serialized values
   → If in Play Mode: editor.exitPlayMode, wait, then proceed

2. For each parameter change:
   scene.findByName or scene.findByTag → get target object
   scene.setComponentProperties {instanceId: ID, typeName: "Component",
     properties: {fieldName: newValue}}

3. After all changes applied:
   scene.saveScene → persist changes

4. Verification:
   editor.enterPlayMode → test changes
   editor.captureGameView → visual verification
   → Compare with pre-change capture
```

### Step 4: A/B Comparison

After applying changes:
1. Capture a new snapshot (use capture.md process)
2. Compare side-by-side with the pre-change snapshot
3. Document what changed and whether it improved the feel

```
## Iteration Log — [timestamp]

### Issue
[What felt wrong]

### Changes Applied
| Parameter | Old Value | New Value | Component | Object |
|---|---|---|---|---|
| moveSpeed | 5.0 | 6.5 | PlayerController | Player |
| spawnRate | 2.0 | 1.5 | SpawnManager | SpawnManager |

### Result
[Better / Worse / Different problem now]

### Next Steps
[What to try next if not resolved]
```

### Step 5: Iterate

If the change helped but isn't enough:
- Apply another 20-30% in the same direction
- Capture again, compare

If the change made it worse:
- Revert to previous value
- Try adjusting a different parameter

If the change revealed a different problem:
- Log the new issue
- Address it in the next iteration cycle

## Quick Tuning Recipes

### "Make it feel faster"
1. Player move speed +25%
2. Attack cooldowns -20%
3. Projectile speed +30%
4. Camera follow smoothing -15% (tighter follow = feels faster)

### "Make deaths more dramatic"
1. Death particle count +50%
2. Screen shake on kill: add or increase intensity
3. Time slow on kill: add 0.05s hitstop
4. Death sound: ensure one exists and is audible

### "Make upgrades feel impactful"
1. First upgrade power +50% (should feel transformative)
2. Add visual change on upgrade (glow, size, color shift)
3. Level-up VFX: ensure it's noticeable
4. Reduce XP required for first 3 levels by 20%

### "Reduce visual chaos"
1. Reduce particle count per system by 30%
2. Reduce particle lifetime by 25%
3. Increase contrast between player and enemies
4. Reduce background visual complexity
5. Ensure UI has background panels for readability

## Tips
- The most common mistake is changing too many things at once. Discipline is hard but necessary.
- "It feels right" is a valid test result. Trust the user's feel, but capture the numbers so you can reproduce it.
- Keep an iteration log in the project. Future tuning sessions benefit from knowing what was already tried.
- If you're going in circles (buff X, nerf Y, buff X again), the problem is structural, not numerical. Step back and reconsider the mechanic design.
