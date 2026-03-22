# Roguelike Co-op

Multiplayer patterns specifically for roguelike/bullet heaven co-op.

## Shared vs Split Progression
**Shared (Recommended for bullet heaven co-op):**
- All players share XP pool
- One player levels up = all see the choice, voter decides (or each picks their own upgrade from shared pool)
- Simpler to implement, encourages teamwork

**Split:**
- Each player has own XP/level
- Independent upgrade choices
- Can create power imbalances but more strategic

## Enemy Scaling for Co-op
- Scale enemy HP by player count: `baseHP × (1 + 0.5 × (playerCount - 1))`
- Scale spawn rate: `baseRate × (1 + 0.3 × (playerCount - 1))`
- Don't scale enemy damage linearly — gets unfun fast. Scale by ~10-15% per extra player.

## Pickup Distribution
Options:
1. **Shared pickups**: First to touch gets it (competitive feel)
2. **Instanced pickups**: Each player sees their own copy (no competition)
3. **AoE pickups**: Collecting benefits all nearby players (cooperative feel)

Recommended for co-op: Instanced or AoE. Shared creates friction.

## Revive Mechanics
Essential for co-op roguelikes:
- Downed state: player stops attacking, timer starts
- Nearby ally can revive (hold interact)
- If timer expires: permanent death for that run (or respawn at cost)
- Vampire Survivors style: no revive, but dead player can become a ghost that collects XP

## Camera in Co-op
Options:
1. **Shared camera**: Camera frames all players. Limits spread distance. Simple.
2. **Tethered**: Players can spread, but camera has max zoom. Rubber-band force pulls toward center.
3. **Split screen**: Each player has own camera. Maximum freedom. Expensive to render.
4. **Teleport**: If too far apart, teleport the lagging player to the leader.

Recommended for bullet heaven: Shared camera with tether. Forces proximity, simplifies networking.

## What to Sync in Bullet Heaven Co-op
| Element | Sync? | Method |
|---|---|---|
| Player position | Yes | Predicted (owner sends, others interpolate) |
| Player weapons/stats | Yes | NetworkVariable (owner writes) |
| Enemy positions | Yes | Snapshot from server, clients interpolate |
| Enemy HP | Server only | Clients see damage via RPC/event |
| Projectiles (player) | Spawn on server | Replicate via pool activation |
| Projectiles (enemy) | Spawn on server | Replicate via pool activation |
| XP gems | Server-authoritative | Position sync, collection event RPC |
| Upgrade choices | Event RPC | Server sends options, client responds with choice |
| Damage numbers | No | Client-side cosmetic |
| Particles | No | Client-side cosmetic |
| Screen shake | No | Client-side cosmetic |

## Session Flow
```
1. [Lobby] Host creates room → others join → character select
2. [Loading] Server initializes run (seed, wave config) → sync to clients
3. [Playing] Server spawns enemies, manages waves → clients control players
4. [Level Up] Server pauses spawning → each client picks upgrade → server resumes
5. [Boss] Server spawns boss → all clients engage
6. [End] Server declares victory/defeat → sync stats → meta-progression screen
7. [Lobby] Return to lobby for next run
```
