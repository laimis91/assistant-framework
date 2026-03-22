# Particle System Presets

Recipes for configuring particle systems via Unity MCP tools for common game effects.

## How to Create a Particle System

```sequence
1. scene.createGameObject
   {name: "FX_[Name]", position: [0, 0, 0]}
   → save FX_ID

2. scene.addComponent
   {instanceId: FX_ID, typeName: "ParticleSystem"}
   → save PS_ID

3. particleSystem.setSettings
   {instanceId: PS_ID, ...settings}
```

## Preset: Explosion (Enemy Death)
Quick burst of particles outward.
- duration: 0.3
- looping: false
- startLifetime: 0.4
- startSpeed: 5
- startSize: 0.3
- startColor: [1, 0.5, 0, 1] (orange)
- maxParticles: 20
- emission: burst of 15-20 particles
- shape: sphere
- simulationSpace: World
- gravityModifier: 0.5

Save as prefab for instantiation on enemy death.

## Preset: Bullet Trail
Continuous trail behind projectile.
- duration: 0 (infinite)
- looping: true
- startLifetime: 0.2
- startSpeed: 0
- startSize: 0.15
- startColor: projectile color with alpha 0.5
- maxParticles: 50
- emission: rate over time = 30
- shape: point (no spread)
- simulationSpace: World
- colorOverLifetime: fade alpha to 0
- sizeOverLifetime: shrink to 0

Attach as child of projectile prefab.

## Preset: XP Gem Collect
Small satisfying burst when collecting a pickup.
- duration: 0.2
- looping: false
- startLifetime: 0.3
- startSpeed: 2
- startSize: 0.1
- startColor: [1, 1, 0, 1] (gold)
- maxParticles: 8
- emission: burst of 5-8
- shape: sphere, radius 0.1

## Preset: Level Up
Dramatic upward burst for level-up moment.
- duration: 0.5
- looping: false
- startLifetime: 0.8
- startSpeed: 3 upward
- startSize: 0.2 to 0.4
- startColor: [1, 1, 1, 1] (white/gold)
- maxParticles: 30
- emission: burst of 25-30
- shape: cone pointing up, angle 15
- colorOverLifetime: gold → white → fade
- sizeOverLifetime: grow then shrink

## Preset: Damage Number Float
Not a particle system — use TextMeshPro with animation.
But for simple damage feedback without TMP:
- duration: 0.5
- looping: false
- startLifetime: 0.6
- startSpeed: 1.5 upward
- startSize: 0.4
- maxParticles: 1
- emission: burst of 1
- gravityModifier: -0.3 (float upward)
- colorOverLifetime: fade alpha to 0

## Tips
- Always set simulationSpace to World for effects that should stay in place
- Use looping: false + Play On Awake for one-shot effects
- Use looping: true for continuous effects (trails, auras)
- Parent one-shot effects to a pool manager, not to the dying object
- Keep maxParticles low for mobile performance (under 50 per system)
