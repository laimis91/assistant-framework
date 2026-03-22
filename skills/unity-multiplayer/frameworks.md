# Frameworks

Comparison of Unity multiplayer frameworks.

## Unity Netcode for GameObjects (NGO)
- **Publisher**: Unity (official)
- **Model**: Client-server, RPCs + NetworkVariables
- **Transport**: Unity Transport (UDP), supports Unity Relay
- **Pros**: Official, well-documented, integrated with Unity services (Relay, Lobby, Matchmaking), free
- **Cons**: Younger ecosystem, some rough edges, performance for large entity counts
- **Best for**: New projects using Unity ecosystem, moderate entity counts (<200 synced objects)
- **Key concepts**: NetworkObject, NetworkBehaviour, NetworkVariable<T>, ServerRpc, ClientRpc, NetworkManager

## Photon Fusion 2
- **Publisher**: Exit Games
- **Model**: Shared mode (P2P-like) or Host mode (client-server), tick-based simulation
- **Transport**: Photon Cloud (managed infrastructure)
- **Pros**: Mature, battle-tested, built-in lag compensation and prediction, managed servers, great docs
- **Cons**: Pricing (free tier has CCU limits), vendor lock-in to Photon Cloud
- **Best for**: Action games needing tight prediction/lag compensation, studios wanting managed infrastructure
- **Key concepts**: NetworkRunner, NetworkObject, [Networked] properties, FixedUpdateNetwork, RPCs

## Photon PUN 2
- **Publisher**: Exit Games
- **Model**: Room-based, client-server via Photon Cloud
- **Transport**: Photon Cloud
- **Pros**: Very easy to learn, huge community, tons of tutorials
- **Cons**: Older architecture, less suitable for fast-paced action (higher latency tolerance), being succeeded by Fusion
- **Best for**: Turn-based or slower-paced games, prototyping
- **Key concepts**: PhotonView, MonoBehaviourPun, RPC, OnPhotonSerializeView

## Mirror
- **Publisher**: Community (open source, MIT license)
- **Model**: Client-server, command/RPC pattern
- **Transport**: Pluggable (KCP default, WebSocket, Steam)
- **Pros**: Free and open source, mature (fork of UNet), large community, many transports
- **Cons**: Community-maintained (quality varies), less built-in infrastructure
- **Best for**: Self-hosted games, teams wanting full control, budget-conscious projects
- **Key concepts**: NetworkBehaviour, [SyncVar], [Command], [ClientRpc], NetworkManager

## FishNet
- **Publisher**: Community (open source)
- **Model**: Client-server, similar to Mirror but improved architecture
- **Transport**: Pluggable
- **Pros**: Modern API, better prediction support than Mirror, growing community
- **Cons**: Smaller community than Mirror, fewer tutorials
- **Best for**: Projects that want Mirror-like simplicity with better prediction
- **Key concepts**: NetworkBehaviour, [SyncVar], [ServerRpc], [ObserversRpc]

## Recommendation Matrix

| Scenario | Recommended | Why |
|---|---|---|
| First multiplayer game, co-op roguelike | **NGO + Unity Relay** | Official, simplest setup, free relay service |
| Fast-paced action, need tight prediction | **Photon Fusion 2** | Best built-in prediction/lag compensation |
| Self-hosted, full control, open source | **Mirror** | Free, mature, flexible |
| Prototype / game jam | **PUN 2** | Fastest to prototype |
| Modern open-source with prediction | **FishNet** | Mirror's successor in spirit |
