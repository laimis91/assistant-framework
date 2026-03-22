# VFX Presets

Ready-to-use visual effect recipes combining particles, materials, lights, and post-processing. Each preset is a complete effect, not just a particle system.

## When to use
- Need a complete visual effect (not just particles)
- Want consistent, genre-appropriate effects
- Building bullet heaven / roguelike effects that look good with programmer art

## Presets

### Hit Impact (Enemy Takes Damage)
Complete effect for when a projectile hits an enemy.

**Components:**
1. **Particle burst** — 8-12 particles, enemy's color, outward, 0.2s lifetime
2. **Hit flash** — Enemy material swaps to white emissive for 2 frames
3. **Scale punch** — Enemy shrinks to 0.85x over 0.05s, returns to 1x over 0.1s
4. **Damage number** — TextMeshPro floating up, fading out over 0.6s

**MCP sequence:**
```sequence
1. particleSystem.setSettings on pooled FX object:
   {duration: 0.2, looping: false, startLifetime: 0.2, startSpeed: 4,
    startSize: 0.15, maxParticles: 12, shape: "Sphere",
    emission: {type: "Burst", count: 10}, simulationSpace: "World"}

2. material.setProperty on hit entity (flash):
   {name: "_EmissionColor", value: [3, 3, 3, 1]}
   → Revert after 2 frames

3. Transform scale animation (via code, not MCP)
```

### Enemy Death
Complete death sequence — most important effect in bullet heaven.

**Components:**
1. **Hit flash** — White, 1 frame
2. **Scale shrink** — To 0.5x over 0.1s
3. **Explosion particles** — 15-25 particles, warm colors, outward burst
4. **Screen shake** — Intensity 0.05 (subtle), 0.1s duration
5. **XP gem spawn** — 1-5 gems at death position with slight spread

**MCP sequence:**
```sequence
1. particleSystem.setSettings on pooled FX_Death:
   {duration: 0.3, looping: false, startLifetime: 0.4, startSpeed: 5,
    startSize: 0.25, startColor: [1, 0.5, 0, 1], maxParticles: 25,
    shape: "Sphere", emission: {type: "Burst", count: 20},
    simulationSpace: "World", gravityModifier: 0.5}

2. Optional: spawn secondary particle (smoke/residue)
   {duration: 0.5, startLifetime: 0.6, startSpeed: 0.5,
    startSize: 0.4, startColor: [0.3, 0.3, 0.3, 0.5], maxParticles: 5,
    sizeOverLifetime: "grow", colorOverLifetime: "fadeAlpha"}
```

### Projectile Trail
Continuous trail behind a moving projectile.

**Components:**
1. **Trail Renderer** — Matches projectile color, fades over 0.15s
2. **Subtle particle emission** — Low-count particles along path
3. **Point light** (optional) — Small colored light on projectile for neon style

**MCP sequence:**
```sequence
1. On projectile prefab, add TrailRenderer:
   {time: 0.15, startWidth: 0.2, endWidth: 0,
    startColor: projectileColor, endColor: transparent,
    material: "Sprites-Default" or unlit colored}

2. Optional particle child:
   {looping: true, startLifetime: 0.1, startSpeed: 0, startSize: 0.1,
    emission: {rateOverTime: 20}, simulationSpace: "World",
    colorOverLifetime: "fadeAlpha", sizeOverLifetime: "shrink"}
```

### Level Up
Dramatic celebratory effect when player gains a level.

**Components:**
1. **Upward particle burst** — 25-30 particles, white/gold, cone shape
2. **Ring expansion** — Circle sprite scaling outward from player
3. **Screen flash** — Brief white overlay (0.05s)
4. **Time slow** — timeScale 0.3 for 0.2s, then pause for upgrade selection
5. **Sound cue** — Play level-up audio clip

**MCP sequence:**
```sequence
1. particleSystem.setSettings on FX_LevelUp:
   {duration: 0.5, looping: false, startLifetime: 0.8, startSpeed: 4,
    startSize: [0.15, 0.3], startColor: [1, 0.95, 0.5, 1],
    maxParticles: 30, shape: "Cone", shapeAngle: 15,
    emission: {type: "Burst", count: 28},
    colorOverLifetime: "gold→white→fade",
    sizeOverLifetime: "growThenShrink"}

2. Ring effect (SpriteRenderer child, circle sprite):
   Scale from 0 to 3x over 0.3s, fade alpha to 0
```

### Weapon Fire Flash
Brief muzzle flash / cast effect when weapon fires.

**Components:**
1. **Point light pulse** — Weapon color, intensity spike then decay
2. **Sprite flash** — Small bright sprite at fire point, 1-2 frames
3. **Small particle puff** — 3-5 particles at fire origin

### Area of Effect (AoE) Zone
Persistent damage zone on the ground.

**Components:**
1. **Ground circle** — Semi-transparent sprite or projector
2. **Edge particles** — Low-count particles orbiting the edge
3. **Pulse animation** — Circle scales 0.95x→1.05x rhythmically
4. **Damage tick flash** — Brief intensity spike on each damage tick

### Screen-Wide Clear
When player triggers a powerful screen-clearing ability.

**Components:**
1. **Expanding ring** — White/gold ring expanding from player to screen edge
2. **Heavy screen shake** — Intensity 0.3, duration 0.3s
3. **Time slow** — 0.1 timeScale for 0.15s
4. **All enemies hit flash** — Simultaneous white flash
5. **Mass death particles** — Multiple explosion bursts
6. **Chromatic aberration pulse** — Brief intensity spike on post-processing

### Pickup Magnet
Visual feedback when pickups are being pulled toward player.

**Components:**
1. **Speed lines** — Thin trail on each pickup moving toward player
2. **Glow intensify** — Pickup emission increases as it gets closer
3. **Collect burst** — Small particle pop on actual collection
4. **UI pulse** — Corresponding HUD element pulses (XP bar, health, etc.)

## Implementation Notes

- All one-shot effects should be pooled, not instantiated/destroyed
- Parent pooled effects to a `VFXPool` manager object
- Use `particleSystem.play` to trigger, auto-return to pool on completion
- For consistent style: all effects in a game should use the same particle material
- Layer particle systems: combine 2-3 simple systems for complex effects rather than one complex system
