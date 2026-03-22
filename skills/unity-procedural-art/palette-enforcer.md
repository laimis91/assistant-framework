# Palette Enforcer

Define a color palette and systematically apply it across all materials, UI, lighting, and particles in the project.

## When to use
- After art direction establishes a palette (from art-direction.md or style-guide.md)
- Game looks inconsistent — colors don't match across different objects
- Changing the game's visual theme (e.g., from bright to dark)
- Adding new content that needs to match the existing style

## Process

### Step 1: Define the Palette

A game palette has 8-12 role-based colors:

| Role | Purpose | Example (Neon Arcade) |
|---|---|---|
| `player_primary` | Main player color | Cyan #00FFFF |
| `player_secondary` | Player accent/details | Dark cyan #008B8B |
| `enemy_common` | Basic enemy type | Red #FF3333 |
| `enemy_elite` | Stronger enemy variant | Magenta #FF00CC |
| `enemy_boss` | Boss enemies | Deep purple #6600CC |
| `projectile_player` | Player projectile | Yellow #FFFF00 |
| `projectile_enemy` | Enemy projectile | Orange #FF6600 |
| `pickup_xp` | XP gems/orbs | Green #00FF88 |
| `pickup_health` | Health drops | Bright green #00FF00 |
| `pickup_special` | Special items | Gold #FFD700 |
| `background` | Scene background | Near black #0A0A14 |
| `ui_accent` | UI highlights | White #FFFFFF |

### Step 2: Create a Palette ScriptableObject

Design a `ColorPalette` ScriptableObject that scripts can reference:

```csharp
[CreateAssetMenu(fileName = "GamePalette", menuName = "Game/Color Palette")]
public class ColorPalette : ScriptableObject
{
    [Header("Player")]
    public Color playerPrimary = new Color(0, 1, 1, 1);
    public Color playerSecondary = new Color(0, 0.55f, 0.55f, 1);

    [Header("Enemies")]
    public Color enemyCommon = new Color(1, 0.2f, 0.2f, 1);
    public Color enemyElite = new Color(1, 0, 0.8f, 1);
    public Color enemyBoss = new Color(0.4f, 0, 0.8f, 1);

    [Header("Projectiles")]
    public Color projectilePlayer = new Color(1, 1, 0, 1);
    public Color projectileEnemy = new Color(1, 0.4f, 0, 1);

    [Header("Pickups")]
    public Color pickupXP = new Color(0, 1, 0.53f, 1);
    public Color pickupHealth = new Color(0, 1, 0, 1);
    public Color pickupSpecial = new Color(1, 0.84f, 0, 1);

    [Header("Environment")]
    public Color background = new Color(0.04f, 0.04f, 0.08f, 1);
    public Color uiAccent = Color.white;
}
```

### Step 3: Apply Palette via UnityMCP

Systematic sweep through all game objects:

**Materials sweep:**
1. List all materials: `assets.findAssets {type: "Material"}`
2. For each material, set `_BaseColor` based on naming convention:
   - `Mat_Player*` → playerPrimary
   - `Mat_Enemy*` → enemyCommon (or elite/boss variant)
   - `Mat_Projectile_Player*` → projectilePlayer
   - `Mat_Projectile_Enemy*` → projectileEnemy
   - `Mat_Pickup*` → pickupXP/pickupHealth/pickupSpecial
3. For emissive materials, set `_EmissionColor` to matching color x intensity multiplier

**Lighting sweep:**
1. Set camera background color → `background`
2. Set global/directional light color based on palette temperature
3. Set ambient light based on palette background

**UI sweep:**
1. Set UI text colors → `uiAccent` or white
2. Set health bar fill → `pickupHealth`
3. Set XP bar fill → `pickupXP`
4. Set button highlights → `uiAccent`

**Particle sweep:**
1. For each particle system, match startColor to its role
2. Death particles → match the dying entity's color
3. Pickup particles → match the pickup's color

### Step 4: Validate Palette

After applying, capture screenshots via UnityMCP to verify:
1. `editor.captureSceneView` — Check overall look
2. `editor.captureGameView` — Check in-game readability

Validation checklist:
- [ ] Player is instantly identifiable
- [ ] Enemy types are distinguishable from each other
- [ ] Player projectiles don't look like enemy projectiles
- [ ] Pickups are visible but don't dominate the screen
- [ ] UI is readable over gameplay
- [ ] Background doesn't compete with gameplay elements

### Step 5: Theme Variants

Create palette variants for different areas/moods without redesigning:

| Base Palette | Variant | Changes |
|---|---|---|
| Neon Arcade | Ice World | Shift all hues +180 degrees, keep saturation |
| Neon Arcade | Hell Zone | Shift background to dark red, enemies to orange |
| Dark Fantasy | Cursed Forest | Add green tint to everything, reduce saturation |
| Dark Fantasy | Crystal Cave | Add blue tint, increase emission intensity |

Implementation: Create multiple ColorPalette ScriptableObjects. A `ThemeManager` swaps the active palette at runtime.

## Tips
- Name materials consistently (Mat_Player_Body, Mat_Enemy_Skeleton, etc.) so palette enforcement can be automated
- When adding new content, always pick from existing palette colors — don't introduce new colors
- Test palette changes with a busy scene (50+ enemies, particles, projectiles). Solo screenshots lie.
- If two things look the same in gameplay, they need different colors — even if it's "unrealistic"
