# Primitive Composition

Building game characters from Unity primitives (cubes, spheres, capsules, cylinders).

## Principles

- A character is a parent GameObject with primitive children
- Each primitive child has its own material (color/emission)
- Scale and position children relative to parent
- No mesh modeling needed — just composition

## Example: Robot Enemy (3D)

```
Robot (Empty, parent)
├── Body (Cube, scale: [0.6, 0.8, 0.4], material: enemy_red)
├── Head (Sphere, scale: [0.35, 0.35, 0.35], position: [0, 0.6, 0], material: enemy_dark)
├── Eye_L (Sphere, scale: [0.08, 0.08, 0.08], position: [-0.1, 0.65, 0.15], material: emissive_red)
├── Eye_R (Sphere, scale: [0.08, 0.08, 0.08], position: [0.1, 0.65, 0.15], material: emissive_red)
├── Arm_L (Cylinder, scale: [0.1, 0.3, 0.1], position: [-0.4, 0.2, 0], material: enemy_red)
└── Arm_R (Cylinder, scale: [0.1, 0.3, 0.1], position: [0.4, 0.2, 0], material: enemy_red)
```

## Example: Tank Enemy (3D)

```
Tank (Empty)
├── Hull (Cube, scale: [0.8, 0.3, 1.0], material: enemy_green)
├── Turret (Cube, scale: [0.4, 0.2, 0.4], position: [0, 0.25, 0], material: enemy_dark_green)
└── Barrel (Cylinder, scale: [0.08, 0.4, 0.08], position: [0, 0.3, 0.4], rotation: [90, 0, 0], material: enemy_dark)
```

## Example: Player Ship (2D via 3D primitives viewed top-down)

```
Ship (Empty)
├── Body (Cube, scale: [0.3, 0.1, 0.5], material: player_cyan)
├── Wing_L (Cube, scale: [0.5, 0.05, 0.25], position: [-0.25, 0, -0.1], rotation: [0, 0, -15], material: player_dark_cyan)
├── Wing_R (Cube, scale: [0.5, 0.05, 0.25], position: [0.25, 0, -0.1], rotation: [0, 0, 15], material: player_dark_cyan)
└── Engine (Sphere, scale: [0.15, 0.1, 0.15], position: [0, 0, -0.3], material: emissive_blue)
```

## Differentiation Strategies

When all enemies are primitives, differentiate by:
1. **Size** — Bigger = more dangerous
2. **Color** — Different hue per enemy type
3. **Shape** — Sphere=fast, cube=tanky, cylinder=ranged
4. **Emission** — Glowing parts indicate special abilities
5. **Child count** — More complex composition = elite/boss

## For 2D Games

Use SpriteRenderer with Unity's built-in shapes:
- Square sprite (scaled/colored) for most enemies
- Circle sprite for player and round enemies
- Triangle via rotated square or custom 3-point sprite
- Layer multiple sprites for composition (body + eyes + weapon)
