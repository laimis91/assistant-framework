# Context Map: Assistant-Core Manifest Dry-Run Validation

## Current Installer Surface
- `install.sh` discovers default first-class skills from `skills/assistant-*/SKILL.md`.
- `--plugin assistant-core` filters real installs to the four core root skills.
- `plugins/assistant-core/.codex-plugin/plugin.json` exists with plugin-local copies under `plugins/assistant-core/skills/`.
- The plugin scaffold is not marketplace-registered.

## Target Slice
- Add manifest-aware validation during `--plugin assistant-core --dry-run`.
- Print the assistant-core plugin manifest path only in dry-run output.
- Validate manifest `name`, `skills`, and plugin-local skill copies against the active profile boundary.
- Keep real install behavior root-inventory based and avoid marketplace registration.

## Key Files
- `install.sh`
- `plugins/assistant-core/.codex-plugin/plugin.json`
- `plugins/assistant-core/skills/`
- `docs/plugin-architecture.md`
- `README.md`
- `tests/p0-p4/installer-contracts.sh`
- `tests/p0-p4/plugin-manifest-contracts.sh`
- `tests/test-p0-p4-contracts.sh`

## Verification Focus
- Dry-run output names the plugin manifest path.
- Dry-run rejects manifest drift such as missing `skills: ./skills/`.
- Real `--plugin assistant-core` install output does not print plugin manifest metadata.
- Focused installer and plugin manifest suites pass.
- Aggregate P0/P4 remains green.
