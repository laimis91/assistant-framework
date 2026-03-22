# Visual Feedback

"Game juice" — making actions feel satisfying without art assets.

## Screen Shake

On hit, explosion, or boss slam:
```csharp
// Shake the camera by random offset, decaying over time
// Intensity: 0.1 (light hit), 0.3 (heavy hit), 0.5 (boss slam)
// Duration: 0.1s - 0.3s
```
Implementation: Offset camera position by random vector each frame, multiply by decay curve.

## Hit Flash

When enemy takes damage, briefly flash white:
- Set SpriteRenderer or MeshRenderer material to white emissive for 1-2 frames
- Then revert to original material
- Alternative: enable a white overlay sprite for the flash duration

## Scale Punch

Object briefly scales up then returns:
- On pickup collect: scale to 1.3x over 0.05s, back to 1x over 0.15s
- On damage dealt: enemy scales to 0.8x then back
- On level up: player pulses to 1.2x

## Knockback

Push enemy away from damage source:
- Apply impulse force on Rigidbody in direction away from hit
- Small enemies: strong knockback. Large enemies: minimal.
- Player knockback should be subtle (preserves control feel)

## Time Slow (Hit Stop)

Brief time freeze on significant hits:
- Set Time.timeScale to 0.1 for 0.05s, then restore to 1
- Only for critical hits, boss damage, or death blows
- Overuse makes the game feel sluggish

## Damage Numbers

Floating text showing damage dealt:
- Spawn at hit position
- Float upward (velocity + gravity)
- Fade out over 0.5-0.8s
- Color by damage type: white=normal, yellow=crit, red=player damage
- Scale by magnitude: bigger number = bigger text

## Trail Effects

Via TrailRenderer or particle trail:
- Player dash: bright trail, 0.2s lifetime
- Projectile: thin trail matching projectile color, 0.1s lifetime
- Enemy charge attack: red/orange trail warning

## Flash on Collect

When picking up an item:
- Brief white flash overlay (0.05s)
- Particle burst at collect position
- UI element pulse (if it affects a stat)

## Death Effects

Enemy death sequence:
1. Hit flash (white, 1 frame)
2. Scale punch (shrink to 0.5x over 0.1s)
3. Spawn explosion particle
4. Drop pickups
5. Destroy GameObject

## Priority Order for Implementation

1. Hit flash (highest impact for effort)
2. Screen shake
3. Scale punch
4. Damage numbers
5. Death particles
6. Knockback
7. Trail effects
8. Time slow (last — easy to overdo)
