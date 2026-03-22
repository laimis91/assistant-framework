# UI Templates

Recipes for building game UI via Unity MCP tools.

## HUD (In-Game Overlay)

Standard heads-up display for roguelike/bullet heaven:

```sequence
1. scene.createGameObject {name: "HUD_Canvas"}
   → save CANVAS_ID

2. scene.addComponent {instanceId: CANVAS_ID, typeName: "Canvas"}
   canvas.setSettings {renderMode: "ScreenSpaceOverlay", sortingOrder: 10}

3. scene.addComponent {instanceId: CANVAS_ID, typeName: "CanvasScaler"}
   (set to Scale With Screen Size, reference 1920x1080)

4. scene.addComponent {instanceId: CANVAS_ID, typeName: "GraphicRaycaster"}

Children of HUD_Canvas:

5. "HealthBar" — Image (filled) anchored top-left
6. "XPBar" — Image (filled) anchored bottom, full width
7. "Timer" — Text anchored top-center
8. "KillCount" — Text anchored top-right
9. "Level" — Text anchored top-left below health
10. "WeaponSlots" — Horizontal Layout Group anchored bottom-left
```

## Level-Up Choice Panel

Overlay that appears on level-up:

```sequence
1. "LevelUpPanel" — Panel with semi-transparent background, centered
2. "Title" — Text "CHOOSE AN UPGRADE" at top of panel
3. "ChoicesContainer" — Horizontal Layout Group, centered
4. For each choice (typically 3-4):
   "Choice_N" — Button with:
     - "Icon" — Image placeholder
     - "Name" — Text (upgrade name)
     - "Description" — Text (what it does)
     - "Rarity" — Text or color indicator
5. "RerollButton" — Button at bottom (optional, costs currency)

Set Time.timeScale = 0 when panel is active.
```

## Pause Menu

```sequence
1. "PauseCanvas" — Canvas, Screen Space Overlay, sort order 100
2. "DimBackground" — Image, full screen, black with alpha 0.7
3. "PausePanel" — Panel centered, ~400x500
4. "Title" — Text "PAUSED"
5. "ResumeButton" — Button
6. "OptionsButton" — Button
7. "QuitButton" — Button

CanvasGroup on PauseCanvas: alpha 0, interactable false (toggle on pause)
```

## Game Over Screen

```sequence
1. "GameOverCanvas" — Canvas, Screen Space Overlay
2. "Background" — Image, full screen, dark
3. "GameOverPanel" — Panel centered
4. "Title" — Text "GAME OVER" or "VICTORY"
5. "StatsContainer" — Vertical Layout:
   - "TimeSurvived" — Text
   - "EnemiesKilled" — Text
   - "Level Reached" — Text
   - "DamageDealt" — Text
6. "RetryButton" — Button
7. "MenuButton" — Button
```

## Tips
- Use CanvasGroup for fading entire UI panels in/out
- Set Time.timeScale = 0 for pause; restore to 1 on resume
- Anchor UI elements to screen edges, not center (survives resolution changes)
- Use TextMeshPro instead of legacy Text for crisp rendering
- Keep font sizes readable: minimum 18pt for HUD, 24pt for menus
- Color-code rarity: white=common, green=uncommon, blue=rare, purple=legendary, gold=mythic
