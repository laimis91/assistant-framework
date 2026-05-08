# Context Map: Assistant-Dev Install Profile

## Current Installer Surface
- `install.sh` discovers default first-class skills from `skills/assistant-*/SKILL.md`.
- `--plugin assistant-core` filters real installs to the four core root skills.
- `--plugin assistant-research` filters real installs to the three research root skills.
- `plugins/assistant-core`, `plugins/assistant-research`, and `plugins/assistant-dev` all have Codex manifests with plugin-local skill copies.
- `assistant-core --dry-run` and `assistant-research --dry-run` validate their manifest scaffolds.
- `assistant-dev` is boundary-defined and scaffolded, but was rejected before this slice.
- The plugin scaffolds are not marketplace-registered.

## Target Slice
- Add `--plugin assistant-dev` as an installable profile.
- Keep installs root-inventory based, filtered to the eight `assistant-dev` boundary skills.
- Reuse manifest-aware dry-run validation for `plugins/assistant-dev/.codex-plugin/plugin.json`.
- Keep `assistant-unity` boundary-only and not installable through `--plugin` yet.
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
- `assistant-dev --dry-run` lists only development skills and validates its manifest.
- Real `assistant-dev` profile installs only the eight development root skills.
- AGENTS skill table for the profile lists exactly eight development skills.
- `assistant-unity` still uses generic boundary-only rejection.
- Marketplace registration remains absent.
