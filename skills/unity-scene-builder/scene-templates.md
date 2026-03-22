# Scene Templates

Complete scene setup recipes via Unity MCP tools. Each template lists every tool call needed to build the scene from scratch.

## Arena Scene (Bullet Heaven / Roguelike)

Full gameplay arena with all manager objects and infrastructure.

```sequence
--- Step 1: Camera ---
1. scene.findByTag {tag: "MainCamera"}
   → save CAM_ID
   (If not found: scene.createGameObject {name: "Main Camera", tag: "MainCamera"})

2. scene.addComponent {instanceId: CAM_ID, typeName: "Camera"}
   (skip if camera already exists on MainCamera)

3. camera.setSettings
   {instanceId: CAM_ID, orthographic: true, orthographicSize: 8, backgroundColor: [0.05, 0.05, 0.1, 1]}

4. scene.addComponent {instanceId: CAM_ID, typeName: "AudioListener"}
   (skip if already present)

5. scene.addComponent {instanceId: CAM_ID, typeName: "CameraFollow"}
   (custom script — smooth follow player)

--- Step 2: Player Spawn Point ---
6. scene.createGameObject
   {name: "PlayerSpawnPoint", position: [0, 0, 0]}
   → save SPAWN_ID

--- Step 3: Boundary Walls ---
7. scene.createGameObject {name: "Boundaries", position: [0, 0, 0]}
   → save BOUNDS_ID

8. scene.createGameObject {name: "Wall_Top", position: [0, 25, 0], parentId: BOUNDS_ID}
   → save WALL_T_ID
9. scene.addComponent {instanceId: WALL_T_ID, typeName: "BoxCollider2D"}
   → save COL_T_ID
10. boxCollider2D.setSettings {instanceId: COL_T_ID, size: [50, 1]}

11. scene.createGameObject {name: "Wall_Bottom", position: [0, -25, 0], parentId: BOUNDS_ID}
    → save WALL_B_ID
12. scene.addComponent {instanceId: WALL_B_ID, typeName: "BoxCollider2D"}
    → save COL_B_ID
13. boxCollider2D.setSettings {instanceId: COL_B_ID, size: [50, 1]}

14. scene.createGameObject {name: "Wall_Left", position: [-25, 0, 0], parentId: BOUNDS_ID}
    → save WALL_L_ID
15. scene.addComponent {instanceId: WALL_L_ID, typeName: "BoxCollider2D"}
    → save COL_L_ID
16. boxCollider2D.setSettings {instanceId: COL_L_ID, size: [1, 50]}

17. scene.createGameObject {name: "Wall_Right", position: [25, 0, 0], parentId: BOUNDS_ID}
    → save WALL_R_ID
18. scene.addComponent {instanceId: WALL_R_ID, typeName: "BoxCollider2D"}
    → save COL_R_ID
19. boxCollider2D.setSettings {instanceId: COL_R_ID, size: [1, 50]}

--- Step 4: Enemy Spawn Points ---
20. scene.createGameObject {name: "EnemySpawnPoints", position: [0, 0, 0]}
    → save ESP_ID

21. scene.createGameObject {name: "SpawnPoint_Top", position: [0, 12, 0], parentId: ESP_ID}
22. scene.createGameObject {name: "SpawnPoint_Bottom", position: [0, -12, 0], parentId: ESP_ID}
23. scene.createGameObject {name: "SpawnPoint_Left", position: [-12, 0, 0], parentId: ESP_ID}
24. scene.createGameObject {name: "SpawnPoint_Right", position: [12, 0, 0], parentId: ESP_ID}

--- Step 5: UI Canvas (HUD) ---
25. scene.createGameObject {name: "HUD_Canvas"}
    → save HUD_ID

26. scene.addComponent {instanceId: HUD_ID, typeName: "Canvas"}
27. canvas.setSettings {instanceId: HUD_ID, renderMode: "ScreenSpaceOverlay", sortingOrder: 10}
28. scene.addComponent {instanceId: HUD_ID, typeName: "CanvasScaler"}
29. scene.addComponent {instanceId: HUD_ID, typeName: "GraphicRaycaster"}

--- Step 6: Manager Objects ---
30. scene.createGameObject {name: "GameManager", position: [0, 0, 0]}
    → save GM_ID
31. scene.addComponent {instanceId: GM_ID, typeName: "GameManager"}
    (custom script)

32. scene.createGameObject {name: "SpawnManager", position: [0, 0, 0]}
    → save SM_ID
33. scene.addComponent {instanceId: SM_ID, typeName: "SpawnManager"}
    (custom script)

34. scene.createGameObject {name: "AudioManager", position: [0, 0, 0]}
    → save AM_ID
35. scene.addComponent {instanceId: AM_ID, typeName: "AudioSource"}
36. scene.addComponent {instanceId: AM_ID, typeName: "AudioManager"}
    (custom script)
```

### Verification
After setup, run:
```
scene.getHierarchy {}
```
Expected top-level objects: Main Camera, PlayerSpawnPoint, Boundaries, EnemySpawnPoints, HUD_Canvas, GameManager, SpawnManager, AudioManager.

---

## Main Menu Scene

Static menu with title and navigation buttons.

```sequence
--- Step 1: Camera ---
1. scene.findByTag {tag: "MainCamera"}
   → save CAM_ID

2. camera.setSettings
   {instanceId: CAM_ID, orthographic: true, orthographicSize: 5, backgroundColor: [0.05, 0.05, 0.1, 1]}

--- Step 2: Background ---
3. scene.createGameObject {name: "Background", position: [0, 0, 1]}
   → save BG_ID

4. scene.addComponent {instanceId: BG_ID, typeName: "SpriteRenderer"}
   → save BG_SR_ID
   (assign a solid color sprite or background texture)

--- Step 3: UI Canvas ---
5. scene.createGameObject {name: "MenuCanvas"}
   → save CANVAS_ID

6. scene.addComponent {instanceId: CANVAS_ID, typeName: "Canvas"}
7. canvas.setSettings {instanceId: CANVAS_ID, renderMode: "ScreenSpaceOverlay", sortingOrder: 10}
8. scene.addComponent {instanceId: CANVAS_ID, typeName: "CanvasScaler"}
9. scene.addComponent {instanceId: CANVAS_ID, typeName: "GraphicRaycaster"}

--- Step 4: Title Text ---
10. scene.createGameObject {name: "TitleText", parentId: CANVAS_ID}
    → save TITLE_ID
11. scene.addComponent {instanceId: TITLE_ID, typeName: "TextMeshProUGUI"}
    → configure: text = "GAME TITLE", fontSize = 72, alignment = center, anchor = upper center

--- Step 5: Buttons ---
12. scene.createGameObject {name: "ButtonContainer", parentId: CANVAS_ID}
    → save BTN_CONTAINER_ID
13. scene.addComponent {instanceId: BTN_CONTAINER_ID, typeName: "VerticalLayoutGroup"}

14. scene.createGameObject {name: "PlayButton", parentId: BTN_CONTAINER_ID}
    → save PLAY_ID
15. scene.addComponent {instanceId: PLAY_ID, typeName: "Button"}
16. scene.addComponent {instanceId: PLAY_ID, typeName: "Image"}
17. scene.createGameObject {name: "Text", parentId: PLAY_ID}
18. scene.addComponent {instanceId: (Text child), typeName: "TextMeshProUGUI"}
    → configure: text = "PLAY", fontSize = 36

19. scene.createGameObject {name: "OptionsButton", parentId: BTN_CONTAINER_ID}
    → save OPTIONS_ID
20. scene.addComponent {instanceId: OPTIONS_ID, typeName: "Button"}
21. scene.addComponent {instanceId: OPTIONS_ID, typeName: "Image"}
22. scene.createGameObject {name: "Text", parentId: OPTIONS_ID}
23. scene.addComponent {instanceId: (Text child), typeName: "TextMeshProUGUI"}
    → configure: text = "OPTIONS", fontSize = 36

24. scene.createGameObject {name: "QuitButton", parentId: BTN_CONTAINER_ID}
    → save QUIT_ID
25. scene.addComponent {instanceId: QUIT_ID, typeName: "Button"}
26. scene.addComponent {instanceId: QUIT_ID, typeName: "Image"}
27. scene.createGameObject {name: "Text", parentId: QUIT_ID}
28. scene.addComponent {instanceId: (Text child), typeName: "TextMeshProUGUI"}
    → configure: text = "QUIT", fontSize = 36

--- Step 6: Menu Manager ---
29. scene.createGameObject {name: "MenuManager"}
    → save MM_ID
30. scene.addComponent {instanceId: MM_ID, typeName: "MenuManager"}
    (custom script — handles button clicks and scene loading)
```

### Verification
After setup, run:
```
scene.getHierarchy {}
```
Expected top-level objects: Main Camera, Background, MenuCanvas, MenuManager.

---

## Game Over Scene

Results screen with stats and navigation.

```sequence
--- Step 1: Camera ---
1. scene.findByTag {tag: "MainCamera"}
   → save CAM_ID

2. camera.setSettings
   {instanceId: CAM_ID, orthographic: true, orthographicSize: 5, backgroundColor: [0.02, 0.02, 0.05, 1]}

--- Step 2: UI Canvas ---
3. scene.createGameObject {name: "GameOverCanvas"}
   → save CANVAS_ID

4. scene.addComponent {instanceId: CANVAS_ID, typeName: "Canvas"}
5. canvas.setSettings {instanceId: CANVAS_ID, renderMode: "ScreenSpaceOverlay"}
6. scene.addComponent {instanceId: CANVAS_ID, typeName: "CanvasScaler"}
7. scene.addComponent {instanceId: CANVAS_ID, typeName: "GraphicRaycaster"}

--- Step 3: Background ---
8. scene.createGameObject {name: "Background", parentId: CANVAS_ID}
   → save BG_ID
9. scene.addComponent {instanceId: BG_ID, typeName: "Image"}
   → configure: color = [0, 0, 0, 0.85], stretch to fill

--- Step 4: Game Over Panel ---
10. scene.createGameObject {name: "GameOverPanel", parentId: CANVAS_ID}
    → save PANEL_ID

11. scene.createGameObject {name: "Title", parentId: PANEL_ID}
12. scene.addComponent {typeName: "TextMeshProUGUI"}
    → configure: text = "GAME OVER", fontSize = 64, alignment = center

--- Step 5: Stats Display ---
13. scene.createGameObject {name: "StatsContainer", parentId: PANEL_ID}
    → save STATS_ID
14. scene.addComponent {instanceId: STATS_ID, typeName: "VerticalLayoutGroup"}

15. scene.createGameObject {name: "TimeSurvived", parentId: STATS_ID}
16. scene.addComponent {typeName: "TextMeshProUGUI"}
    → configure: text = "Time Survived: 00:00", fontSize = 28

17. scene.createGameObject {name: "EnemiesKilled", parentId: STATS_ID}
18. scene.addComponent {typeName: "TextMeshProUGUI"}
    → configure: text = "Enemies Killed: 0", fontSize = 28

19. scene.createGameObject {name: "LevelReached", parentId: STATS_ID}
20. scene.addComponent {typeName: "TextMeshProUGUI"}
    → configure: text = "Level Reached: 1", fontSize = 28

21. scene.createGameObject {name: "DamageDealt", parentId: STATS_ID}
22. scene.addComponent {typeName: "TextMeshProUGUI"}
    → configure: text = "Damage Dealt: 0", fontSize = 28

--- Step 6: Buttons ---
23. scene.createGameObject {name: "RetryButton", parentId: PANEL_ID}
    → save RETRY_ID
24. scene.addComponent {instanceId: RETRY_ID, typeName: "Button"}
25. scene.addComponent {instanceId: RETRY_ID, typeName: "Image"}
26. scene.createGameObject {name: "Text", parentId: RETRY_ID}
27. scene.addComponent {typeName: "TextMeshProUGUI"}
    → configure: text = "RETRY", fontSize = 36

28. scene.createGameObject {name: "MenuButton", parentId: PANEL_ID}
    → save MENU_ID
29. scene.addComponent {instanceId: MENU_ID, typeName: "Button"}
30. scene.addComponent {instanceId: MENU_ID, typeName: "Image"}
31. scene.createGameObject {name: "Text", parentId: MENU_ID}
32. scene.addComponent {typeName: "TextMeshProUGUI"}
    → configure: text = "MAIN MENU", fontSize = 36

--- Step 7: Manager ---
33. scene.createGameObject {name: "GameOverManager"}
    → save GOM_ID
34. scene.addComponent {instanceId: GOM_ID, typeName: "GameOverManager"}
    (custom script — populates stats, handles button clicks)
```

### Verification
After setup, run:
```
scene.getHierarchy {}
```
Expected top-level objects: Main Camera, GameOverCanvas, GameOverManager.

---

## Pause Overlay

Not a separate scene — added as an overlay within the Arena scene. Built on top of the Arena Scene template.

```sequence
--- Step 1: Pause Canvas (higher sort order than HUD) ---
1. scene.createGameObject {name: "PauseCanvas"}
   → save PAUSE_CANVAS_ID

2. scene.addComponent {instanceId: PAUSE_CANVAS_ID, typeName: "Canvas"}
3. canvas.setSettings {instanceId: PAUSE_CANVAS_ID, renderMode: "ScreenSpaceOverlay", sortingOrder: 100}
4. scene.addComponent {instanceId: PAUSE_CANVAS_ID, typeName: "CanvasScaler"}
5. scene.addComponent {instanceId: PAUSE_CANVAS_ID, typeName: "GraphicRaycaster"}
6. scene.addComponent {instanceId: PAUSE_CANVAS_ID, typeName: "CanvasGroup"}
   → save CG_ID
   → configure: alpha = 0, interactable = false, blocksRaycasts = false

--- Step 2: Dim Background ---
7. scene.createGameObject {name: "DimBackground", parentId: PAUSE_CANVAS_ID}
   → save DIM_ID
8. scene.addComponent {instanceId: DIM_ID, typeName: "Image"}
   → configure: color = [0, 0, 0, 0.7], stretch to fill entire screen

--- Step 3: Pause Panel ---
9. scene.createGameObject {name: "PausePanel", parentId: PAUSE_CANVAS_ID}
   → save PANEL_ID
10. scene.addComponent {instanceId: PANEL_ID, typeName: "Image"}
    → configure: centered, size ~400x500, color = [0.1, 0.1, 0.15, 0.95]

11. scene.addComponent {instanceId: PANEL_ID, typeName: "VerticalLayoutGroup"}

--- Step 4: Title ---
12. scene.createGameObject {name: "Title", parentId: PANEL_ID}
13. scene.addComponent {typeName: "TextMeshProUGUI"}
    → configure: text = "PAUSED", fontSize = 48, alignment = center

--- Step 5: Buttons ---
14. scene.createGameObject {name: "ResumeButton", parentId: PANEL_ID}
    → save RESUME_ID
15. scene.addComponent {instanceId: RESUME_ID, typeName: "Button"}
16. scene.addComponent {instanceId: RESUME_ID, typeName: "Image"}
17. scene.createGameObject {name: "Text", parentId: RESUME_ID}
18. scene.addComponent {typeName: "TextMeshProUGUI"}
    → configure: text = "RESUME", fontSize = 32

19. scene.createGameObject {name: "OptionsButton", parentId: PANEL_ID}
    → save OPT_ID
20. scene.addComponent {instanceId: OPT_ID, typeName: "Button"}
21. scene.addComponent {instanceId: OPT_ID, typeName: "Image"}
22. scene.createGameObject {name: "Text", parentId: OPT_ID}
23. scene.addComponent {typeName: "TextMeshProUGUI"}
    → configure: text = "OPTIONS", fontSize = 32

24. scene.createGameObject {name: "QuitButton", parentId: PANEL_ID}
    → save QUIT_ID
25. scene.addComponent {instanceId: QUIT_ID, typeName: "Button"}
26. scene.addComponent {instanceId: QUIT_ID, typeName: "Image"}
27. scene.createGameObject {name: "Text", parentId: QUIT_ID}
28. scene.addComponent {typeName: "TextMeshProUGUI"}
    → configure: text = "QUIT TO MENU", fontSize = 32
```

### Activation Logic
The PauseCanvas starts hidden (CanvasGroup alpha=0, interactable=false). To toggle pause:
1. Set CanvasGroup alpha = 1, interactable = true, blocksRaycasts = true
2. Set Time.timeScale = 0
To unpause:
1. Set CanvasGroup alpha = 0, interactable = false, blocksRaycasts = false
2. Set Time.timeScale = 1

### Verification
After setup, confirm PauseCanvas appears in hierarchy under the Arena scene with sort order 100.
