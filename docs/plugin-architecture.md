# Plugin Architecture Plan

This document defines the planned plugin split for Assistant Framework V1. It is a contract-backed design artifact plus the source of truth for installer profile ownership. The current release still installs first-class skills from the root `skills/assistant-*` inventory by default, plugin-local skill copies are scaffolded for `assistant-core`, `assistant-research`, and `assistant-dev`, and no root skill directories move in this slice.

## Goals

- Reduce installed skill surface for users who only need a subset of the framework.
- Give core, development, research, and Unity workflows independent ownership boundaries.
- Prepare for Codex and Claude plugin-style distribution without changing today state prematurely.
- Keep current root-skill installs working until a plugin scaffold has its own tests.

## Current Compatibility Rule

The installer remains root-inventory based:

```text
current_install_inventory: skills/assistant-*/SKILL.md
current_plugin_profiles: assistant-core via --plugin assistant-core; assistant-research via --plugin assistant-research; assistant-dev via --plugin assistant-dev
current_unity_policy: skills/unity-* is outside the default assistant-* inventory
current_plugin_manifests: plugins/assistant-core/.codex-plugin/plugin.json plugins/assistant-research/.codex-plugin/plugin.json plugins/assistant-dev/.codex-plugin/plugin.json
```

The default install remains the root `skills/assistant-*` inventory. `--plugin assistant-core` installs the skills listed in the `assistant-core` boundary below from the root inventory, `--plugin assistant-research` installs the skills listed in the `assistant-research` boundary, and `--plugin assistant-dev` installs the skills listed in the `assistant-dev` boundary. The `plugins/assistant-core/.codex-plugin/plugin.json` scaffold includes plugin-local copies of the four core skills for Codex plugin packaging, and the installer performs manifest-aware dry-run validation for that scaffold. The `plugins/assistant-research/.codex-plugin/plugin.json` scaffold includes plugin-local copies of the three research skills, and the installer performs manifest-aware dry-run validation for that scaffold too. The `plugins/assistant-dev/.codex-plugin/plugin.json` scaffold includes plugin-local copies of the eight development skills, and the installer performs manifest-aware dry-run validation for that scaffold too. These scaffolds are not marketplace-registered yet. Do not move root skills or add more install behavior until the same slice has P0/P4 coverage for that behavior.

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

Unity skills remain local-only in the current release because `skills/unity-*` is outside the root `skills/assistant-*` inventory. The installer should not special-case Unity names; assistant-named custom skills should follow the same filesystem inventory rules as any other assistant skill.

## Future Manifest Expectations

As plugin scaffolding expands, each plugin should define equivalent metadata for every supported agent:

- Codex: `.codex-plugin/plugin.json`
- Claude: plugin manifest with skill discovery metadata
- Shared: plugin name, version, description, owned skills, optional hooks, and optional MCP servers

Manifests must be generated from the ownership map or guarded against it, so skill ownership cannot drift between docs, tests, and installer behavior.

## Migration Rules

1. Keep root `skills/assistant-*` installs as the default compatibility path until plugin manifests pass P0/P4.
2. Keep `--plugin assistant-core` as the first profile-backed install path before moving high-control development skills.
3. Preserve targeted single-skill install behavior during and after the split.
4. Keep default inventory behavior pattern-based; `skills/unity-*` stays outside the root `skills/assistant-*` inventory unless a future supported profile or manifest adds coverage.
5. Update eval, validator, installer, and docs contracts in the same slice as any behavior change.

## Implemented Slices

### Boundary Design

- Add this document.
- Add a P0/P4 boundary contract that parses the ownership block.
- Link the plan from the README.
- Keep install behavior unchanged.

### Assistant-Core Profile

- Add `./install.sh --agent <agent> --plugin assistant-core`.
- Parse profile ownership from this document.
- Keep `--skill` and `--plugin` mutually exclusive.
- Reject boundary-defined non-core plugin profiles through a generic not-installable profile gate.
- Keep plugin manifests absent during the profile-only slice.

### Assistant-Core Manifest Scaffold

- Add `plugins/assistant-core/.codex-plugin/plugin.json`.
- Add plugin-local copies of the four core skills under `plugins/assistant-core/skills/`.
- Guard plugin-local copies against root skill drift with P0/P4 contracts.
- Keep marketplace registration absent.

### Assistant-Core Manifest Dry-Run Validation

- Print `plugins/assistant-core/.codex-plugin/plugin.json` in `--plugin assistant-core --dry-run` output.
- Validate manifest `name`, `skills`, and plugin-local skill copies against the `assistant-core` boundary during dry-run.
- Keep real installs root-inventory based until marketplace registration is introduced.

### Assistant-Research Manifest Scaffold

- Add `plugins/assistant-research/.codex-plugin/plugin.json`.
- Add plugin-local copies of the three research skills under `plugins/assistant-research/skills/`.
- Guard plugin-local copies against root skill drift with P0/P4 contracts.
- Keep marketplace registration absent and keep `assistant-research` boundary-only until its install profile has coverage.

### Assistant-Research Profile

- Add `./install.sh --agent <agent> --plugin assistant-research`.
- Parse profile ownership from this document.
- Print `plugins/assistant-research/.codex-plugin/plugin.json` in `--plugin assistant-research --dry-run` output.
- Validate manifest `name`, `skills`, and plugin-local skill copies against the `assistant-research` boundary during dry-run.
- Keep real installs root-inventory based until marketplace registration is introduced.

### Assistant-Dev Manifest Scaffold

- Add `plugins/assistant-dev/.codex-plugin/plugin.json`.
- Add plugin-local copies of the eight development skills under `plugins/assistant-dev/skills/`.
- Guard plugin-local copies against root skill drift with P0/P4 contracts.
- Keep marketplace registration absent and keep `assistant-dev` boundary-only until its install profile has coverage.

### Assistant-Dev Profile

- Add `./install.sh --agent <agent> --plugin assistant-dev`.
- Parse profile ownership from this document.
- Print `plugins/assistant-dev/.codex-plugin/plugin.json` in `--plugin assistant-dev --dry-run` output.
- Validate manifest `name`, `skills`, and plugin-local skill copies against the `assistant-dev` boundary during dry-run.
- Keep real installs root-inventory based until marketplace registration is introduced.

The next slice can add marketplace registration or plugin-local install sourcing once all profile paths are stable.
