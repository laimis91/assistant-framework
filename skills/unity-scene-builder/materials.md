# Material Presets

Recipes for creating materials via Unity MCP tools. These work with URP (Universal Render Pipeline) or Built-in pipeline.

## How to Create a Material

```sequence
1. assets.createMaterial
   {name: "Mat_[Name]", path: "Assets/_Project/Materials/"}
   → creates .mat file at specified path

2. material.setShader
   {assetPath: "Assets/_Project/Materials/Mat_[Name].mat", shader: "Universal Render Pipeline/Lit"}
   OR shader: "Universal Render Pipeline/Unlit"

3. material.setProperty
   {assetPath: "...", name: "_BaseColor", type: "color", value: [r, g, b, a]}
```

## Preset: Flat Color
Simple solid color, no lighting effects.
- Shader: `Universal Render Pipeline/Unlit`
- Properties: `_BaseColor` = desired color

## Preset: Metallic
Shiny, reflective surface.
- Shader: `Universal Render Pipeline/Lit`
- Properties: `_BaseColor`, `_Metallic` = 0.8, `_Smoothness` = 0.9

## Preset: Glowing / Emissive
Self-illuminating, great for projectiles and pickups.
- Shader: `Universal Render Pipeline/Lit`
- Properties: `_BaseColor`, `_EmissionColor` = bright color x intensity (e.g., [2, 0, 0, 1] for bright red glow)
- Keywords: enable `_EMISSION`

## Preset: Semi-Transparent
For shields, ghosts, overlays.
- Shader: `Universal Render Pipeline/Lit`
- Set surface type to Transparent
- Properties: `_BaseColor` with alpha < 1, `_Surface` = 1 (Transparent)

## Color Palettes for Programmer Art

### Neon Arcade
Player: Cyan [0, 1, 1, 1]
Enemies: Red [1, 0.2, 0.2, 1], Magenta [1, 0, 0.8, 1]
Projectiles: Yellow [1, 1, 0, 1], Green [0, 1, 0.5, 1]
Pickups: Gold [1, 0.85, 0, 1]
Background: Dark blue [0.02, 0.02, 0.08, 1]

### Dark Fantasy
Player: Silver [0.75, 0.75, 0.8, 1]
Enemies: Dark red [0.5, 0.1, 0.1, 1], Purple [0.3, 0.1, 0.4, 1]
Projectiles: White [1, 1, 1, 1], Fire [1, 0.5, 0, 1]
Pickups: Green [0.2, 0.8, 0.3, 1]
Background: Near black [0.05, 0.05, 0.05, 1]

### Pastel
Player: Light blue [0.6, 0.8, 1, 1]
Enemies: Coral [1, 0.5, 0.5, 1], Lavender [0.7, 0.5, 1, 1]
Projectiles: Mint [0.5, 1, 0.7, 1]
Pickups: Peach [1, 0.8, 0.6, 1]
Background: Cream [0.95, 0.93, 0.88, 1]
