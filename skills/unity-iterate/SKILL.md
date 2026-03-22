---
name: unity-iterate
description: "Orchestrator skill for Unity game development. Takes high-level requests like 'make the forest level feel dangerous' and routes to the right combination of game design, art direction, scene building, and playtesting skills."
triggers:
  - pattern: "make it feel|make the game|improve the|change the feel|the game needs|level feels|it should feel|make enemies|make player|make weapons|make this look|game doesn't feel|game should"
    priority: 75
    min_words: 4
    reminder: "This request matches unity-iterate. Consider whether the Skill tool should be invoked with skill='unity-iterate' for orchestrated game iteration."
---

# Iterate Skill

Orchestrator that translates high-level game direction into coordinated actions across multiple Unity skills.

## Purpose

The user says something vague like:
- "Make the forest level feel more dangerous"
- "The game needs more juice"
- "Enemies feel boring"
- "Make this look like Vampire Survivors"

This skill figures out WHICH other skills to invoke and in WHAT order.

## Available Skills to Orchestrate

| Skill | Responsibility |
|---|---|
| `unity-game-design` | Game mechanics, systems design, balance numbers |
| `unity-procedural-art` | Visual style, art direction, palette, image AI prompts |
| `unity-scene-builder` | Build scenes, objects, VFX, materials via MCP |
| `unity-playtest` | Capture state, gather feedback, apply tuning changes |
| `unity-multiplayer` | Networking and co-op patterns |

## Process

### Step 1: Parse the Request

Classify the request into one or more domains:

| Request contains... | Primary skill | Supporting skills |
|---|---|---|
| "feel", "mood", "atmosphere", "vibe" | `unity-procedural-art` (art-direction) | `unity-scene-builder` (lighting/materials) |
| "mechanic", "system", "ability", "weapon" | `unity-game-design` (mechanics) | `unity-scene-builder` (prefabs) |
| "balance", "too hard", "too easy", "numbers" | `unity-playtest` (iteration) | `unity-game-design` (balance) |
| "look like", "style", "color", "visual" | `unity-procedural-art` (palette/style) | `unity-scene-builder` (materials) |
| "juice", "satisfying", "punchy", "impact" | `unity-procedural-art` (visual-feedback) | `unity-scene-builder` (vfx-presets) |
| "boring", "repetitive", "variety" | `unity-game-design` (mechanics) | `unity-procedural-art` (visual variety) |
| "multiplayer", "co-op", "networking", "online" | `unity-multiplayer` (architecture) | `unity-scene-builder` (if building) |
| "build", "create", "add", "set up" | `unity-scene-builder` (recipes) | `unity-game-design` (if design needed first) |
| "test", "try", "check", "how does it" | `unity-playtest` (capture + iterate) | None |

### Step 2: Determine Action Sequence

Requests that span multiple domains follow this order:

```
1. DESIGN (if the mechanic/system doesn't exist yet)
   → unity-game-design: concept, mechanics, or balance

2. ART DIRECTION (if visuals need to change)
   → unity-procedural-art: art-direction → palette → style specifics

3. BUILD (create/modify Unity objects)
   → unity-scene-builder: recipes, scene-templates, vfx-presets, materials

4. APPLY VISUALS (materials, lighting, post-processing)
   → unity-procedural-art: palette-enforcer + lighting-mood
   → unity-scene-builder: materials, particles

5. TEST & TUNE (verify the changes work)
   → unity-playtest: capture → feedback → iterate
```

Not every request needs all 5 steps. Skip steps that aren't relevant.

### Step 3: Execute

For each step:
1. Invoke the relevant skill tool
2. Capture the output
3. Feed output as context to the next step
4. Apply changes via UnityMCP where applicable

### Step 4: Verify

Always end with verification:
1. Capture game view screenshot: `editor.captureGameView`
2. If possible, enter play mode briefly: `editor.enterPlayMode`
3. Present the result to the user
4. Ask if further iteration is needed

## Example Resolutions

### "Make the forest level feel more dangerous"
1. **Art Direction** -> Dark palette, cooler temperature, low lighting, fog
2. **Scene Builder** -> Apply dark materials, add point lights (flickering), enable fog
3. **VFX** -> Add red particle ambience, enemy glow effects
4. **Playtest** -> Capture before/after, check readability

### "The game needs more juice"
1. **Visual Feedback** -> Add screen shake, hit flash, scale punch, death particles
2. **VFX Presets** -> Apply hit-impact, enemy-death, level-up presets
3. **Scene Builder** -> Create VFX prefabs, add to existing objects via MCP
4. **Playtest** -> Test in play mode, check if effects are too subtle or too heavy

### "Enemies feel boring"
1. **Game Design** -> Design 2-3 new enemy behaviors (charger, ranged, swarm)
2. **Implementation** -> Generate C# scripts for new AI patterns
3. **Procedural Art** -> Differentiate enemy visuals (shape, color, emission)
4. **Scene Builder** -> Create prefabs for new enemy types
5. **Playtest** -> Test variety, tune spawn rates

### "Make this look like Vampire Survivors"
1. **Art Direction** -> Pixel art style, retro palette, dark background
2. **Image AI Prompts** -> Generate prompts for character/enemy sprites in VS style
3. **Palette** -> Define and apply VS-inspired palette (muted but readable)
4. **Lighting** -> Dark global, entity-based point lights
5. **Playtest** -> Capture comparison screenshots

## Tips
- When in doubt about where to start, start with `unity-playtest capture` to understand current state
- Always verify visually after changes — capture before and after
- If the user's request is purely about feel/mood, prioritize art direction over mechanics
- If the user's request is about boredom/engagement, prioritize mechanics over art
- "More juice" almost always means: screen shake + hit flash + particles + sound (even without sound tools)
