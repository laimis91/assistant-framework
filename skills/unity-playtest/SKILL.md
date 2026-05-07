---
name: unity-playtest
description: "Structured playtesting with automated game state capture via UnityMCP. Captures screenshots, runtime metrics, and component settings. Converts feedback into tuning changes applied directly through MCP tools."
triggers:
  - pattern: "playtest|playtest feedback|game feels|gameplay testing|how does it play|try the game|tune the game|feels too|too easy|too hard|too slow|too fast|adjust difficulty|balance the game"
    priority: 70
    min_words: 4
    reminder: "This request matches unity-playtest. Consider whether the Skill tool should be invoked with skill='unity-playtest' for structured playtesting and tuning."
---

# Playtest Skill

Structured feedback loop with automated capture and tuning via UnityMCP.

## Available Tools

| Tool | File | When to use |
|---|---|---|
| **Capture** | `capture.md` | Snapshot game state: screenshots, settings, runtime metrics via MCP |
| **Feedback** | `feedback.md` | Structured feedback template for playtest sessions |
| **Iteration** | `iteration.md` | Convert feedback to tuning changes, apply via MCP, verify with A/B comparison |

## Workflow

1. **Capture** -- Snapshot current state before changes (screenshots + settings + metrics)
2. **Play** -- User playtests (or the assistant enters Play Mode via MCP and observes)
3. **Feedback** -- User provides feedback or the assistant analyzes captured state
4. **Iterate** -- Map feedback to parameter changes -> apply via MCP -> recapture -> compare
5. Repeat until the game feels right

## MCP Integration

This skill leverages UnityMCP for:
- `editor.captureSceneView` / `editor.captureGameView` -- Visual snapshots
- `scene.getComponentProperties` -- Read current settings
- `scene.setComponentProperties` -- Apply tuning changes
- `editor.enterPlayMode` / `editor.exitPlayMode` -- Runtime testing
- `scene.getHierarchy` -- Map scene structure

When MCP is unavailable, tools output step-by-step manual instructions instead.

## Output

Every playtest pass should return:
- **Capture Summary** -- Screenshots, runtime metrics, scene hierarchy, and component settings inspected
- **Feedback Findings** -- What feels too hard, easy, slow, fast, unclear, or satisfying
- **Tuning Changes** -- Parameters changed through UnityMCP, with before/after values when available
- **Comparison Result** -- Evidence from recapture or play-mode observation after tuning
- **Next Checks** -- Remaining risks, manual playtest steps, or suggested follow-up tuning
