# Context Map: Assistant-Dev Plugin Manifest Scaffold

## Current Installer Surface
- `install.sh` discovers default first-class skills from `skills/assistant-*/SKILL.md`.
- `--plugin assistant-core` filters real installs to the four core root skills.
- `plugins/assistant-core/.codex-plugin/plugin.json` exists with plugin-local copies under `plugins/assistant-core/skills/`.
- `plugins/assistant-research/.codex-plugin/plugin.json` exists with plugin-local copies under `plugins/assistant-research/skills/`.
- `assistant-core --dry-run` validates the core manifest scaffold.
- The plugin scaffolds are not marketplace-registered.

## Target Slice
- Add `plugins/assistant-dev/.codex-plugin/plugin.json`.
- Add plugin-local copies of `assistant-diagrams`, `assistant-docs`, `assistant-onboard`, `assistant-review`, `assistant-security`, `assistant-skill-creator`, `assistant-tdd`, and `assistant-workflow`.
- Extend plugin manifest contracts across core, research, and dev plugin scaffolds.
- Keep `assistant-dev` boundary-only and not installable through `--plugin` yet.
- Keep marketplace registration absent.

## Key Files
- `install.sh`
- `plugins/assistant-core/.codex-plugin/plugin.json`
- `plugins/assistant-core/skills/`
- `plugins/assistant-research/.codex-plugin/plugin.json`
- `plugins/assistant-research/skills/`
- `plugins/assistant-dev/.codex-plugin/plugin.json`
- `plugins/assistant-dev/skills/`
- `docs/plugin-architecture.md`
- `README.md`
- `tests/p0-p4/plugin-manifest-contracts.sh`
- `tests/p0-p4/plugin-boundary-contracts.sh`
- `tests/test-p0-p4-contracts.sh`

## Verification Focus
- Dev manifest metadata is filled and points at `./skills/`.
- Dev plugin-local skills match the `assistant-dev` boundary exactly.
- Dev plugin-local skill copies match root source skill files excluding `.DS_Store`.
- Only core, research, and dev plugin manifests exist.
- Marketplace registration remains absent.
