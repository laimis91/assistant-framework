---
name: unity-procedural-art
description: "Art direction, procedural visuals, and style enforcement for Unity games. Translates vague mood descriptions into concrete visual decisions, generates image AI prompts for assets, and applies consistent styles via UnityMCP. Built for developers who can't draw."
triggers:
  - pattern: "procedural art|programmer art|no art skills|unity visual style|unity art style|game juice|screen shake|art direction|visual style|color palette|make it look|looks like|visual feel|mood|vibe|style guide|image ai|sprite generation|generate sprites"
    priority: 65
    min_words: 4
    reminder: "This request matches unity-procedural-art. Consider whether the Skill tool should be invoked with skill='unity-procedural-art' for visual design and art direction."
---

# Procedural Art Skill

Visual techniques and art direction for developers who can't draw. Translates vibes into visuals, generates image AI prompts for assets, and enforces style consistency.

## Available Tools

| Tool | File | When to use |
|---|---|---|
| **Art Direction** | `art-direction.md` | Translate mood/vibe descriptions into concrete visual decisions and image AI prompts |
| **Palette Enforcer** | `palette-enforcer.md` | Define and apply a color palette across all materials, lighting, UI, and particles |
| **Style Guide** | `style-guide.md` | Choose and define a consistent visual style for the game |
| **Primitives** | `primitive-composition.md` | Build characters/objects from basic shapes |
| **Visual Feedback** | `visual-feedback.md` | Juice: screen shake, flash, scale punch, trails |
| **Lighting** | `lighting-mood.md` | Set mood through lighting, post-processing, and color |

## Workflow

1. **Art Direction** -- User describes a vibe -> concrete visual strategy + image AI prompts + Style Card
2. **Palette Enforcer** -- Define palette from Style Card -> apply across all project assets via MCP
3. **Style Guide** -- Detail the visual rules for ongoing consistency
4. **Primitives / Lighting / Visual Feedback** -- Build and polish the actual visuals

## Output

Every visual pass should return:
- **Style Card** -- Mood, references, palette, shapes, lighting, materials, and readability rules
- **Asset Prompts** -- Image AI prompts for sprites, textures, icons, or references when needed
- **Application Plan** -- UnityMCP material, lighting, particle, post-processing, or primitive steps
- **Consistency Rules** -- Constraints for future assets so the style remains cohesive
- **Verification Notes** -- Screenshot checks, readability concerns, and remaining art risks

## Philosophy

Good programmer art is not "bad art" -- it's a deliberate minimalist style. Games like Thomas Was Alone, Geometry Wars, and Vampire Survivors prove that simple visuals work when:
1. Colors are consistent and readable
2. Visual feedback is clear and satisfying
3. Enemy types are distinguishable at a glance
4. The screen is readable during chaos

## Art Barrier Strategy

For users who struggle with visual design:
- **Start with art-direction.md** -- even a single mood word is enough input
- **Use image AI** for sprites/textures you can't make from primitives -- the art-direction tool generates ready-to-use prompts
- **Let the assistant handle materials, lighting, particles, post-processing** via UnityMCP -- these are code, not art
- **The palette enforcer ensures consistency** -- the hardest part of art is keeping things cohesive, and that's fully automatable
