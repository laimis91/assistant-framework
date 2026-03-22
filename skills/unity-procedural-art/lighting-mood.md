# Lighting and Mood

Setting mood and atmosphere through lighting and color without art assets.

## 2D Games

2D games in URP can use:
- **Global Light 2D** — Overall scene brightness and tint
- **Point Light 2D** — Localized light sources (player glow, enemy eyes, pickups)
- **Shadow Caster 2D** — Simple shadows from sprites

Mood presets:
- **Arcade Bright**: Global light white at 1.0 intensity. No shadows. Clean and readable.
- **Dungeon Dark**: Global light at 0.2-0.3 intensity, cool blue tint. Player has point light radius 5. Enemies glow faintly. Creates tension.
- **Neon Night**: Global light very dim (0.1). All entities have emissive materials or point lights. High contrast, visually striking.

## 3D Games

- **Directional Light** — Sun/moon. Angle and color set the time of day.
- **Point/Spot Lights** — Local atmosphere (torches, glowing objects).
- **Ambient Light** — Fill light for shadow areas.

Mood presets:
- **Bright Arena**: Directional light straight down, white, intensity 1. Ambient: sky color. Clean shadows.
- **Dark Dungeon**: Directional light at steep angle, dim blue. Ambient: dark blue. Player carries point light.
- **Hellscape**: Directional light red/orange, intensity 0.6. Ambient: dark red. Fog: red/brown, short distance.

## Post-Processing (URP Volume)

If URP is set up, use Volume overrides for polish:
- **Bloom** — Makes emissive materials glow. Essential for neon style. Threshold: 0.9, Intensity: 1-3.
- **Vignette** — Darkens screen edges. Adds focus. Intensity: 0.2-0.4.
- **Color Adjustments** — Saturation, contrast tweaks. Subtle goes a long way.
- **Chromatic Aberration** — Slight color fringing at edges. Use sparingly (0.1-0.2). Good for "hit" effect.

## Background Techniques (No Art Needed)

- **Solid color** — Simple and effective. Match mood preset.
- **Gradient** — Two-color gradient via unlit quad or UI Image. Sky-to-ground feel.
- **Scrolling grid** — Faint grid lines scrolling slowly. Gives sense of movement.
- **Particle stars** — Low-count, slow particle system for space/night feel.
- **Fog** — URP fog with matching ambient color. Hides draw distance, adds depth.
