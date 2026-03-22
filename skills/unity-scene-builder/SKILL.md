---
name: unity-scene-builder
description: "Orchestrates Unity MCP tools to build scenes, GameObjects, prefabs, VFX, and materials efficiently. Provides recipes and presets for common game patterns instead of manual tool-by-tool assembly."
triggers:
  - pattern: "create scene|set up scene|build prefab|add enemy|add player|unity scene setup|create gameobject|create prefab|create material|add effect|add vfx|particle effect|visual effect|explosion effect|death effect|trail effect"
    priority: 65
    min_words: 4
    reminder: "This request matches unity-scene-builder. Consider whether the Skill tool should be invoked with skill='unity-scene-builder' for Unity MCP orchestration recipes."
---

# Scene Builder Skill

Orchestrates Unity MCP tools into high-level recipes for building game scenes, objects, and effects.

## Prerequisites

Requires the **UnityMCP** server (WebSocket relay bridge to Unity Editor). The MCP server must be:
- Configured in Claude Code settings as an MCP server
- Running and connected to an open Unity Editor instance
- Minimum tools required: `scene.*`, `assets.*`, `material.*`, `rigidbody.*`, `camera.*`, `canvas.*`, `particleSystem.*`, `editor.*`

When the MCP server is not connected, recipes can still be used as step-by-step plans for manual execution.

## Available Tools

| Tool | File | When to use |
|---|---|---|
| **Recipes** | `recipes.md` | Common GameObject patterns (player, enemy, projectile, pickup, etc.) |
| **Scene Templates** | `scene-templates.md` | Full scene setups (arena, menu, game over) |
| **VFX Presets** | `vfx-presets.md` | Complete visual effects (hit, death, level-up, trails, AoE) |
| **Materials** | `materials.md` | Material creation with visual presets |
| **Particles** | `particles.md` | Particle system configuration for common effects |
| **UI** | `ui-templates.md` | HUD, menus, and in-game UI patterns |

## How It Works

Each recipe is a sequence of Unity MCP tool calls. When the Unity MCP server is connected, execute the tool calls directly. When it's not connected, output the recipe as a step-by-step plan that can be executed later.

## Important

- Always check `editor.getPlayModeState` first — scene modifications require Edit Mode
- Track instanceIds returned from creation calls — subsequent calls need them
- Use `scene.getHierarchy` to verify results after complex operations
- Prefer prefabs for anything that will be instantiated multiple times
- For VFX: always pool effects, never instantiate/destroy at runtime
