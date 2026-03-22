# Style Guide

Guide for choosing and maintaining a visual style.

## Step 1: Pick a Visual Identity

Options ranked by ease of implementation:

1. **Geometric Neon** — Bright shapes on dark background. Best for: bullet heaven, arcade.
   - Pros: Easiest to implement, inherently readable, scales well
   - Cons: Can look generic
   - References: Geometry Wars, Just Shapes & Beats

2. **Flat Color / Minimalist** — Solid colors, clean shapes, no textures.
   - Pros: Clean, professional, easy to maintain consistency
   - Cons: Needs good color theory to not look bland
   - References: Thomas Was Alone, SUPERHOT

3. **Low-Poly 3D** — Simple 3D meshes with flat or minimal shading.
   - Pros: Looks modern, 3D gives depth, works without textures
   - Cons: Requires some 3D modeling (or asset store packs)
   - References: Totally Accurate Battle Simulator, Crossy Road

4. **Pixel Art** (requires external sprites or AI generation) — Retro pixel aesthetic.
   - Pros: Huge nostalgia appeal, large free asset libraries exist
   - Cons: Need sprites (can't generate from primitives alone)
   - References: Vampire Survivors, Enter the Gungeon

5. **Silhouette** — Black shapes with colored accents/outlines.
   - Pros: Very striking, easy to make everything readable
   - Cons: Limited color information per entity
   - References: Limbo, Badland

## Step 2: Define Color Rules

Create a Color Palette ScriptableObject with roles:
- **Player**: Must stand out. High contrast against background.
- **Enemies**: Warm/danger colors (red, orange, magenta). Different enemy types = different hues.
- **Projectiles (Player)**: Cool or neutral. Must not be confused with enemy attacks.
- **Projectiles (Enemy)**: Warm/danger. Clearly hostile.
- **Pickups**: Inviting colors (gold, green, bright blue).
- **Background**: Low saturation, recedes. Never competes with gameplay elements.
- **UI**: High contrast against all gameplay elements.

Rule: If you squint and can still tell player from enemy from pickup, your palette works.

## Step 3: Size Hierarchy

Establish relative sizes:
- Player: 1x (reference)
- Basic enemy: 0.5x-0.8x
- Elite enemy: 1.2x-1.5x
- Boss: 2x-4x
- Projectile: 0.1x-0.3x
- Pickup: 0.2x-0.4x

Size communicates threat level without any art.

## Step 4: Readability Checklist

Before finalizing any visual:
- [ ] Can I identify the player instantly?
- [ ] Can I distinguish enemy types at a glance?
- [ ] Can I see projectiles against the background?
- [ ] Can I read pickups among enemies?
- [ ] Does the screen stay readable with 50+ entities?
- [ ] Are UI elements always visible?
