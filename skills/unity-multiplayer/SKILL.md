---
name: unity-multiplayer
description: "Multiplayer architecture and networking patterns for Unity games. Covers topology selection, framework comparison, and implementation patterns for co-op, competitive, and hybrid multiplayer."
triggers:
  - pattern: "multiplayer|netcode|photon|mirror networking|fishnet|matchmaking|lobby system|co-op networking|online co-op"
    priority: 70
    min_words: 4
    reminder: "This request matches unity-multiplayer. Consider whether the Skill tool should be invoked with skill='unity-multiplayer' for multiplayer architecture and networking patterns."
---

# Multiplayer Skill

Architecture decisions and implementation patterns for Unity multiplayer games.

## Available Tools

| Tool | File | When to use |
|---|---|---|
| **Architecture** | `architecture.md` | Choose topology, framework, and high-level networking design |
| **Frameworks** | `frameworks.md` | Compare Unity networking frameworks (Netcode, Photon, Mirror, etc.) |
| **Patterns** | `patterns.md` | Common multiplayer patterns (sync, prediction, lag compensation) |
| **Roguelike Co-op** | `roguelike-coop.md` | Multiplayer patterns specific to roguelike/bullet heaven co-op |

## Decision Flow

1. **What kind of multiplayer?** → Architecture tool
2. **Which framework?** → Frameworks comparison
3. **How to implement?** → Patterns for specific mechanics
4. **Genre-specific?** → Roguelike co-op patterns
