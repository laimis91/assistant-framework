# Architecture

Multiplayer architecture decision guide.

## Step 1: Multiplayer Mode
| Mode | Description | Complexity | Best For |
|---|---|---|---|
| **Local Co-op** | Same device, split screen or shared | Low | Couch co-op roguelikes |
| **Online Co-op (P2P)** | 2-4 players, one hosts | Medium | Small group co-op |
| **Online Co-op (Dedicated)** | Server-authoritative | High | Competitive fairness |
| **Competitive PvP** | Players vs players | High | PvP roguelikes, arena |
| **Async** | Not real-time (leaderboards, ghosts, shared world) | Low-Medium | Meta-progression sharing |

## Step 2: Network Topology

**Client-Server (Recommended for most games)**
```
Player A (Host/Server) ←→ Player B (Client)
                       ←→ Player C (Client)
```
- One player is authoritative (host)
- All game state lives on host
- Clients send inputs, receive state
- Pros: Simpler, one source of truth
- Cons: Host advantage (lower latency), host migration needed if host leaves

**Dedicated Server**
```
            Server (headless)
           ↙    ↓    ↘
Player A   Player B   Player C
```
- No player has authority
- Fair for all players
- Pros: No host advantage, no migration
- Cons: Requires server infrastructure, higher cost

**Peer-to-Peer (Avoid for action games)**
```
Player A ←→ Player B
   ↕            ↕
Player C ←→ Player D
```
- Each peer has full state
- Pros: No server needed
- Cons: Synchronization hell, easy to cheat, doesn't scale

## Step 3: What to Sync
Categorize every game element:

| Category | Sync Method | Examples |
|---|---|---|
| **Authoritative** | Server owns, clients interpolate | Player HP, enemy spawns, item drops |
| **Predicted** | Client predicts, server corrects | Player movement, shooting |
| **Cosmetic** | Client-only, no sync needed | Particles, screen shake, damage numbers |
| **Event** | RPC on occurrence | Level up, pickup collected, boss spawned |

Rule: Sync as little as possible. If it's cosmetic, don't sync it.

## Step 4: Bandwidth Budget
For a roguelike/bullet heaven with 2-4 players:
- Player positions: ~20 bytes × 4 players × 30Hz = ~2.4 KB/s
- Enemy positions: ~20 bytes × 100 enemies × 10Hz = ~20 KB/s (optimize: only sync nearby)
- Events (damage, pickups, spawns): ~50 bytes × ~10/s = ~0.5 KB/s
- Total: ~25 KB/s upstream from server — very manageable

## Step 5: Architecture Decision Template
```markdown
## Multiplayer Architecture — [Game Name]

### Mode: [Local Co-op / Online Co-op / PvP / Async]
### Topology: [Client-Server / Dedicated / P2P]
### Framework: [Netcode for GameObjects / Photon Fusion / Mirror / Custom]
### Max Players: [N]
### Sync Strategy:
- Authoritative: [list]
- Predicted: [list]
- Cosmetic (no sync): [list]
- Event-based: [list]
### Estimated Bandwidth: [X KB/s per player]
```
