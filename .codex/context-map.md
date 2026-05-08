# Context Map: Assistant-Research Plugin Manifest Scaffold

## Current Installer Surface
- `install.sh` discovers default first-class skills from `skills/assistant-*/SKILL.md`.
- `--plugin assistant-core` filters real installs to the four core root skills.
- `plugins/assistant-core/.codex-plugin/plugin.json` exists with plugin-local copies under `plugins/assistant-core/skills/`.
- `assistant-core --dry-run` validates the core manifest scaffold.
- The plugin scaffold is not marketplace-registered.

## Target Slice
- Add `plugins/assistant-research/.codex-plugin/plugin.json`.
- Add plugin-local copies of `assistant-ideate`, `assistant-research`, and `assistant-thinking`.
- Generalize plugin manifest contracts across core and research plugin scaffolds.
- Keep `assistant-research` boundary-only and not installable through `--plugin` yet.
- Keep marketplace registration absent.

## Key Files
- `install.sh`
- `plugins/assistant-core/.codex-plugin/plugin.json`
- `plugins/assistant-core/skills/`
- `plugins/assistant-research/.codex-plugin/plugin.json`
- `plugins/assistant-research/skills/`
- `docs/plugin-architecture.md`
- `README.md`
- `tests/p0-p4/plugin-manifest-contracts.sh`
- `tests/p0-p4/plugin-boundary-contracts.sh`
- `tests/test-p0-p4-contracts.sh`

## Verification Focus
- Research manifest metadata is filled and points at `./skills/`.
- Research plugin-local skills match the `assistant-research` boundary exactly.
- Research plugin-local skill copies match root source skill files excluding `.DS_Store`.
- Only core and research plugin manifests exist.
- Marketplace registration remains absent.
