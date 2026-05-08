# Plugin Architecture Plan

This document defines the planned plugin split for Assistant Framework V1. It is a contract-backed design artifact only: the current release still installs first-class skills from the root `skills/assistant-*` inventory, and no skill directories move in this slice.

## Goals

- Reduce installed skill surface for users who only need a subset of the framework.
- Give core, development, research, and Unity workflows independent ownership boundaries.
- Prepare for Codex and Claude plugin-style distribution without changing today state prematurely.
- Keep current root-skill installs working until a plugin scaffold has its own tests.

## Current Compatibility Rule

The installer remains root-inventory based:

```text
current_install_inventory: skills/assistant-*/SKILL.md
current_unity_policy: skills/unity-* is local-only and opt-in
current_plugin_manifests: none
```

Do not move skills, add plugin manifests, or change install profiles until the next implementation slice has P0/P4 coverage for the new behavior.

## Planned Plugin Inventory

The block below is the authoritative planned ownership map. Contract tests parse this block and require every tracked first-class `assistant-*` skill to appear exactly once.

```text
PLUGIN_BOUNDARY_START
assistant-core: assistant-clarify assistant-memory assistant-reflexion assistant-telos
assistant-dev: assistant-diagrams assistant-docs assistant-onboard assistant-review assistant-security assistant-skill-creator assistant-tdd assistant-workflow
assistant-research: assistant-ideate assistant-research assistant-thinking
assistant-unity: skills/unity-*
PLUGIN_BOUNDARY_END
```

### `assistant-core`

Foundation skills that are useful across development, research, and personal context workflows:

- `assistant-clarify`
- `assistant-memory`
- `assistant-reflexion`
- `assistant-telos`

### `assistant-dev`

Development execution skills:

- `assistant-diagrams`
- `assistant-docs`
- `assistant-onboard`
- `assistant-review`
- `assistant-security`
- `assistant-skill-creator`
- `assistant-tdd`
- `assistant-workflow`

### `assistant-research`

Investigation, reasoning, and ideation skills:

- `assistant-ideate`
- `assistant-research`
- `assistant-thinking`

### `assistant-unity`

Optional local game-development skills:

- `skills/unity-*`

Unity skills remain local-only in the current release. They are not part of the tracked first-class release inventory and should not be installed by default.

## Future Manifest Expectations

When plugin scaffolding begins, each plugin should define equivalent metadata for every supported agent:

- Codex: `.codex-plugin/plugin.json`
- Claude: plugin manifest with skill discovery metadata
- Shared: plugin name, version, description, owned skills, optional hooks, and optional MCP servers

Manifests must be generated from the ownership map or guarded against it, so skill ownership cannot drift between docs, tests, and installer behavior.

## Migration Rules

1. Keep root `skills/assistant-*` installs as the compatibility path until plugin installs pass P0/P4.
2. Scaffold one plugin first, preferably `assistant-core`, before moving high-control development skills.
3. Preserve targeted single-skill install behavior during and after the split.
4. Keep local-only Unity opt-in; never make `skills/unity-*` part of the default release inventory by accident.
5. Update eval, validator, installer, and docs contracts in the same slice as any behavior change.

## First Implementation Slice

This slice is intentionally limited to design and contracts:

- Add this document.
- Add a P0/P4 boundary contract that parses the ownership block.
- Link the plan from the README.
- Keep install behavior unchanged.

The next slice can scaffold `assistant-core` manifests and installer dry-run support once this boundary is stable.
