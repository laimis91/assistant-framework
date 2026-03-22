# GameObject Recipes

Reusable patterns for creating common game objects via Unity MCP tools. Each recipe lists the exact MCP tool calls in sequence.

## How to Use

1. Identify which recipe matches the need
2. Execute the MCP tool calls in order
3. Capture the instanceId from each creation step — later steps reference it
4. Adjust parameters to fit the specific game

## Recipe: Player Character (2D Top-Down)

```sequence
1. scene.createGameObject
   {name: "Player", position: [0, 0, 0], tag: "Player"}
   → save instanceId as PLAYER_ID

2. scene.addComponent
   {instanceId: PLAYER_ID, typeName: "SpriteRenderer"}
   → save component instanceId as SR_ID

3. scene.addComponent
   {instanceId: PLAYER_ID, typeName: "Rigidbody2D"}
   → save component instanceId as RB_ID

4. rigidbody2D.setSettings
   {instanceId: RB_ID, gravityScale: 0, freezeRotation: true, collisionDetection: "Continuous"}

5. scene.addComponent
   {instanceId: PLAYER_ID, typeName: "CircleCollider2D"}
   → save component instanceId as COL_ID

6. circleCollider2D.setSettings
   {instanceId: COL_ID, radius: 0.4}

7. scene.addComponent
   {instanceId: PLAYER_ID, typeName: "PlayerController"}
   (custom script — must exist in project)
```

## Recipe: Player Character (3D Top-Down)

```sequence
1. scene.createGameObject
   {name: "Player", position: [0, 0.5, 0], tag: "Player"}
   → save PLAYER_ID

2. scene.addComponent
   {instanceId: PLAYER_ID, typeName: "MeshFilter"}

3. scene.addComponent
   {instanceId: PLAYER_ID, typeName: "MeshRenderer"}
   → save MR_ID

4. scene.addComponent
   {instanceId: PLAYER_ID, typeName: "Rigidbody"}
   → save RB_ID

5. rigidbody.setSettings
   {instanceId: RB_ID, useGravity: true, freezeRotation: [true, false, true], collisionDetection: "Continuous"}

6. scene.addComponent
   {instanceId: PLAYER_ID, typeName: "CapsuleCollider"}
   → save COL_ID

7. capsuleCollider.setSettings
   {instanceId: COL_ID, radius: 0.4, height: 1.8, center: [0, 0.9, 0]}
```

## Recipe: Simple Enemy

```sequence
1. scene.createGameObject
   {name: "Enemy_[Type]", position: [x, y, z], tag: "Enemy"}
   → save ENEMY_ID

2. scene.addComponent
   {instanceId: ENEMY_ID, typeName: "SpriteRenderer"} (2D)
   OR
   scene.addComponent
   {instanceId: ENEMY_ID, typeName: "MeshRenderer"} (3D)

3. scene.addComponent
   {instanceId: ENEMY_ID, typeName: "Rigidbody2D"} (2D)
   → save RB_ID

4. rigidbody2D.setSettings
   {instanceId: RB_ID, gravityScale: 0, freezeRotation: true}

5. scene.addComponent
   {instanceId: ENEMY_ID, typeName: "CircleCollider2D"} (2D)

6. scene.addComponent
   {instanceId: ENEMY_ID, typeName: "EnemyAI"}
   (custom script)
```

## Recipe: Projectile

```sequence
1. scene.createGameObject
   {name: "Projectile", position: [0, 0, 0], tag: "Projectile"}
   → save PROJ_ID

2. scene.addComponent (SpriteRenderer or MeshRenderer)

3. scene.addComponent (Rigidbody2D or Rigidbody)
   → save RB_ID

4. rigidbody2D.setSettings
   {instanceId: RB_ID, gravityScale: 0, collisionDetection: "Continuous"}
   OR
   rigidbody.setSettings
   {instanceId: RB_ID, useGravity: false, collisionDetection: "ContinuousDynamic"}

5. scene.addComponent (CircleCollider2D or SphereCollider)
   → configure as trigger: {isTrigger: true}

6. assets.createPrefab
   {name: "Projectile", sourcePath: (scene path)}
   → Creates prefab for object pooling
```

## Recipe: XP Gem / Pickup

```sequence
1. scene.createGameObject
   {name: "XPGem", position: [0, 0, 0], tag: "Pickup"}
   → save GEM_ID

2. scene.addComponent
   {instanceId: GEM_ID, typeName: "SpriteRenderer"}

3. scene.addComponent
   {instanceId: GEM_ID, typeName: "CircleCollider2D"}
   → configure as trigger: {isTrigger: true, radius: 0.3}

4. scene.addComponent
   {instanceId: GEM_ID, typeName: "PickupBehavior"}
   (custom script — handles magnet pull and collection)

5. assets.createPrefab
   {name: "XPGem", ...}
```

## Recipe: Camera Setup (2D Top-Down)

```sequence
1. (Find existing Main Camera or create one)
   scene.findByTag {tag: "MainCamera"}
   → save CAM_ID

2. camera.setSettings
   {instanceId: CAM_ID, orthographic: true, orthographicSize: 8, backgroundColor: [0.05, 0.05, 0.1, 1]}

3. scene.addComponent
   {instanceId: CAM_ID, typeName: "CameraFollow"}
   (custom script — smooth follow player)
```

## Recipe: Boundary Walls (2D Arena)

```sequence
1. For each wall (Top, Bottom, Left, Right):
   scene.createGameObject
   {name: "Wall_Top", position: [0, Y, 0]}
   → save WALL_ID

2. scene.addComponent
   {instanceId: WALL_ID, typeName: "BoxCollider2D"}
   → save COL_ID

3. boxCollider2D.setSettings
   {instanceId: COL_ID, size: [arenaWidth, wallThickness]}

Repeat for all 4 walls with appropriate positions and sizes.
Parent all walls under an empty "Boundaries" GameObject.
```

## Tips

- **Always create prefabs** for anything spawned at runtime (enemies, projectiles, pickups)
- **Use tags** consistently: "Player", "Enemy", "Projectile", "Pickup", "Boundary"
- **Use layers** for physics filtering: Player, Enemy, Projectile, Pickup
- **Set collision detection to Continuous** for fast-moving objects (projectiles, dashing player)
- **Freeze rotation** on 2D rigidbodies unless rotation is a gameplay feature
