# Context Map: Assistant-Research Install Profile

## Current Installer Surface
- `install.sh` discovers default first-class skills from `skills/assistant-*/SKILL.md`.
- `--plugin assistant-core` filters real installs to the four core root skills.
- `plugins/assistant-core/.codex-plugin/plugin.json` exists with plugin-local copies under `plugins/assistant-core/skills/`.
- `plugins/assistant-research/.codex-plugin/plugin.json` exists with plugin-local copies under `plugins/assistant-research/skills/`.
- `assistant-core --dry-run` validates the core manifest scaffold.
- `assistant-research` is boundary-defined and scaffolded, but was rejected before this slice.
- The plugin scaffolds are not marketplace-registered.

## Target Slice
- Add `--plugin assistant-research` as an installable profile.
- Keep installs root-inventory based, filtered to `assistant-ideate`, `assistant-research`, and `assistant-thinking`.
- Reuse manifest-aware dry-run validation for `plugins/assistant-research/.codex-plugin/plugin.json`.
- Keep `assistant-dev` and `assistant-unity` boundary-only and not installable through `--plugin` yet.
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
- `tests/p0-p4/installer-contracts.sh`
- `tests/p0-p4/plugin-boundary-contracts.sh`
- `tests/test-p0-p4-contracts.sh`

## Verification Focus
- `assistant-research --dry-run` lists only research skills and validates its manifest.
- Real `assistant-research` profile installs only the three research root skills.
- AGENTS skill table for the profile lists exactly three research skills.
- `assistant-dev` and `assistant-unity` still use generic boundary-only rejection.
- Marketplace registration remains absent.
