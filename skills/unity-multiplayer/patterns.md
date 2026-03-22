# Patterns

Common multiplayer implementation patterns.

## State Synchronization
**NetworkVariable / SyncVar pattern:**
- Server owns the variable
- Changes automatically replicate to clients
- Use for: HP, score, position, game state

**Snapshot Interpolation:**
- Server sends full state snapshots at fixed rate (10-20 Hz)
- Clients interpolate between two snapshots (renders ~100ms behind server)
- Smooth visuals, but adds latency
- Use for: Enemy positions in bullet heaven (many entities, low precision needed)

## Client-Side Prediction
For responsive player movement:
1. Client processes input immediately (local prediction)
2. Client sends input to server
3. Server processes input authoritatively, sends back result
4. Client reconciles: if server result differs, correct smoothly
- Critical for: Player movement, shooting, dashing

## Lag Compensation
For hit detection across latency:
1. Server stores position history for all entities (ring buffer, ~200ms)
2. When client fires, include timestamp
3. Server rewinds entity positions to client's perceived time
4. Perform hit check against historical positions
5. Apply damage in present time
- Critical for: Projectile/homing hit detection in co-op

## Object Pooling (Networked)
Bullet heaven = many projectiles. Network-spawning each one is expensive.
- Pool NetworkObjects on both server and client
- Server activates pooled object, sets position/velocity via NetworkVariable
- Client sees activation, no spawn RPC needed
- Use for: Projectiles, XP gems, damage numbers

## Authority Patterns
| Pattern | Who Controls | Use Case |
|---|---|---|
| Server-authoritative | Server only | Enemy AI, item drops, game state |
| Client-authoritative | Owning client | Player movement (trust client) |
| Server with client prediction | Both (server wins) | Player actions needing responsiveness |
| Owner-only write | Owning client writes, all read | Player stats, loadout |

## RPCs vs NetworkVariables
- **NetworkVariable**: Continuous state (position, HP). Auto-syncs, has callbacks.
- **ServerRpc**: Client → Server one-shot (fire weapon, use ability, pick up item).
- **ClientRpc**: Server → All clients one-shot (play sound, show effect, announce event).
- Rule: If it changes every frame, use NetworkVariable. If it happens once, use RPC.
