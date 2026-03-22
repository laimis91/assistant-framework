# Art Direction (Vibe to Visuals)

Translates plain-language descriptions into concrete visual decisions and generates prompts for image AI tools.

## When to use
- User describes a mood/feeling but can't articulate specific visual choices
- Need to bridge the gap between "dark and dangerous forest" and actual Unity settings
- Need prompts for image AI (Midjourney, DALL-E, Stable Diffusion) to generate sprites/textures
- Starting a new game and need a cohesive visual identity without art skills

## Process

### Step 1: Extract the Vibe
Ask the user for one or more of:
- **Mood words**: dark, cozy, chaotic, eerie, vibrant, retro, clean, gritty
- **Reference games**: "like Vampire Survivors but darker" or "Hades meets pixel art"
- **Emotions**: tension, power, wonder, dread, excitement, calm
- **Setting**: forest, dungeon, space, city, abstract, hell

If the user can only give one word, that's enough. Map it:

| Vibe Word | Color Temperature | Saturation | Contrast | Lighting | Post-Processing |
|---|---|---|---|---|---|
| Dark | Cool (blues, purples) | Low-Medium | High | Dim global, point lights | Vignette, low bloom |
| Bright | Warm (yellows, whites) | High | Medium | Strong directional | Bloom, no vignette |
| Neon | Cool-Neutral | Maximum | Maximum | Minimal global, all emissive | Heavy bloom, chromatic aberration |
| Retro | Warm (amber, green) | Medium | Medium | Flat/even | CRT effect, scanlines, slight blur |
| Gritty | Desaturated warm | Low | High | Harsh directional, hard shadows | Film grain, vignette, low saturation |
| Cozy | Warm (oranges, soft yellows) | Medium | Low | Soft omnidirectional, warm tint | Soft bloom, warm color grading |
| Eerie | Cool (greens, pale blues) | Low | Medium-High | Dim, flickering point lights | Fog, chromatic aberration, desaturation |
| Chaotic | Mixed, high energy | High | Very High | Multiple colored lights | Screen shake, bloom, particle-heavy |
| Clean | Neutral-Cool | Medium | Medium | Even, minimal shadows | Minimal effects, anti-aliasing |
| Abstract | Any (based on palette) | Variable | High | Flat/unlit or full emissive | Bloom on emissives |

### Step 2: Choose a Visual Strategy

Based on the vibe, recommend ONE of these approaches (ranked by ease):

1. **Geometric + Emissive** (easiest)
   - Use Unity primitives or simple sprites
   - Differentiate by color, emission, and scale
   - Works with: neon, abstract, chaotic, clean
   - Zero external assets needed

2. **Procedural Materials + Lighting**
   - URP shaders with color, emission, and post-processing
   - Mood comes from lighting and atmosphere
   - Works with: dark, eerie, gritty, cozy
   - Zero external assets needed

3. **AI-Generated Sprites + Unity Composition**
   - Generate sprites via image AI for characters/enemies/items
   - Unity handles: materials, lighting, particles, effects
   - Works with: retro, any style requiring specific character designs
   - Requires image AI tool access

4. **Asset Store + Customization**
   - Start with free asset packs
   - Customize via materials, color swaps, particle effects
   - Works with: any style
   - Requires browsing/downloading assets

### Step 3: Generate Image AI Prompts (if Strategy 3)

When the game needs sprites that can't be made from primitives, generate prompts for image AI tools.

**Prompt Template for Sprite Sheets:**
```
[art style] [subject], [view angle], [background], [mood adjectives], game asset, sprite sheet,
[additional style modifiers]

Style modifiers by genre:
- Pixel art: "pixel art, 16-bit, limited palette, crisp pixels, no anti-aliasing"
- Hand-drawn: "hand-drawn, ink lines, watercolor fill, slight texture"
- Flat vector: "flat design, vector art, clean edges, solid colors, no gradients"
- Painterly: "digital painting, visible brush strokes, rich colors, semi-realistic"
```

**Examples:**

For a roguelike bat enemy (pixel art):
```
pixel art bat enemy, top-down view, transparent background, dark purple wings with red eyes,
game asset sprite sheet, 4-frame animation, 32x32 pixels, limited palette, crisp pixels
```

For a forest tileset (painterly):
```
dark forest floor tiles, top-down view, seamless tileable, mossy stones and dead leaves,
eerie green lighting, game asset, digital painting style, muted earth tones
```

For UI icons (flat):
```
fantasy weapon icons set, flat design, transparent background, sword axe bow staff wand,
game UI asset, vector art, clean edges, gold and silver tones, consistent style
```

**Prompt Generation Rules:**
- Always specify: style, subject, view angle, background type
- Always include: "game asset" (improves consistency)
- For sprite sheets: specify frame count and pixel size
- For tilesets: include "seamless tileable"
- For consistency across assets: reuse the same style prefix for all prompts in a set
- Generate a "style prefix" once and reuse it: e.g., "16-bit pixel art, 4-color palette, dark fantasy theme,"

### Step 4: Map to Unity Settings

Translate the chosen vibe into specific Unity MCP tool calls:

**Lighting (via UnityMCP):**
- Global light intensity and color
- Point light placement and parameters
- Ambient light settings

**Post-Processing (via UnityMCP):**
- Volume override settings (bloom, vignette, color adjustments)
- Specific parameter values based on vibe mapping

**Materials (via UnityMCP):**
- Color palette applied to materials
- Emission settings for glowing objects
- Shader selection (Unlit vs Lit vs custom)

**Camera (via UnityMCP):**
- Background color
- Orthographic size (affects visual density)
- Clear flags

### Step 5: Create a Style Card

Output a concise reference card that can be saved to the project:

```
# [Game Name] — Style Card

## Vibe
[1-3 mood words]

## Visual Strategy
[Which approach from Step 2]

## Color Palette
- Player: [hex] — [description]
- Enemies: [hex values] — [description]
- Projectiles: [hex values] — [description]
- Pickups: [hex] — [description]
- Background: [hex] — [description]
- UI Accent: [hex] — [description]

## Lighting
- Global: [color, intensity]
- Player light: [color, intensity, radius] (if applicable)
- Ambient: [color]

## Post-Processing
- Bloom: [threshold, intensity]
- Vignette: [intensity, color]
- Other: [any additional effects]

## Image AI Style Prefix
[Reusable prompt prefix for consistent asset generation]
"[style], [theme], [modifiers], game asset,"

## Unity Settings Summary
[Key URP/rendering settings to apply]
```

## Tips
- When in doubt, go darker and more saturated. It's easier to brighten later.
- Consistency matters more than quality. A cohesive ugly game looks better than a mixed-quality one.
- Test your palette with 50+ entities on screen. Pretty colors that become unreadable in chaos are useless.
- The image AI style prefix is the most valuable output — it ensures all generated assets look like they belong together.
- Save the Style Card to the project's docs folder so every collaborator (human or AI) stays aligned.
