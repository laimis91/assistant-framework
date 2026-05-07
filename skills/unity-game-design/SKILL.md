---
name: unity-game-design
description: "Game concept design, mechanics specification, and implementation planning for Unity games. From vague idea to buildable specs with core loops, progression, enemies, weapons, and upgrades. Includes implementation bridge for converting designs to code. Specialized for roguelike, roguelite, and bullet heaven genres."
triggers:
  - pattern: "game idea|game concept|design a game|game mechanics|game design|roguelike design|bullet heaven|roguelite design|implement game|build the game|start coding the game"
    priority: 70
    min_words: 4
    reminder: "This request matches unity-game-design. Consider whether the Skill tool should be invoked with skill='unity-game-design' for structured game concept development."
---

# Game Design Skill

Structured game concept development -- from vague idea to buildable specification to implementation plan.

## Available Tools

| Tool | File | When to use |
|---|---|---|
| **Concept** | `concept.md` | Flesh out a raw game idea into a structured concept document |
| **Mechanics** | `mechanics.md` | Deep-dive into specific game mechanics (combat, progression, spawning) |
| **Balance** | `balance.md` | Design difficulty curves, economy, upgrade scaling, stat progression |
| **Implementation** | `implementation.md` | Convert design docs into C# code, build order, and UnityMCP setup |
| **Genre: Roguelike** | `genres/roguelike.md` | Roguelike/roguelite specific patterns and systems |
| **Genre: Bullet Heaven** | `genres/bullet-heaven.md` | Bullet heaven / survivor specific patterns |

## Workflow

1. **Concept phase** -- User provides a rough idea -> produce a Game Concept Document
2. **Mechanics phase** -- Break each system into implementable specs
3. **Balance phase** -- Define numbers, curves, and tuning parameters
4. **Implementation phase** -- Convert specs to C# code, determine build order, set up via UnityMCP
5. Output feeds into `unity-scene-builder` for scene setup and `assistant-workflow` for structured development

## Output

Every design pass should return:
- **Concept Summary** -- Player fantasy, genre assumptions, and target feel
- **Core Loop** -- What the player does every 30 seconds
- **Session Loop** -- What a single run/session looks like
- **Meta Loop** -- What persists between runs (roguelite) or doesn't (roguelike)
- **Systems List** -- Each system with inputs, outputs, and dependencies
- **Implementation Priority** -- What to build first for a playable prototype
- **Build Order** -- Phase-by-phase implementation plan (from implementation.md)
- **Open Questions** -- Any decisions that block implementation or tuning
