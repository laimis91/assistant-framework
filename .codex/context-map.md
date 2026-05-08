# Context Map: Assistant-Core Plugin Manifest Scaffold

## Current Installer Surface
- `install.sh` discovers default first-class skills from `skills/assistant-*/SKILL.md`.
- `--skill <name>` filters the install to one root skill.
- Codex AGENTS.md generation is based on the installed `SKILLS` array.
- `--plugin assistant-core` installs the four core skills from the root inventory.

## Target Slice
- Add `plugins/assistant-core/.codex-plugin/plugin.json`.
- Add plugin-local copies of the four assistant-core skills.
- Keep root install behavior and `--plugin assistant-core` behavior unchanged.
- Do not add marketplace registration yet.

## Key Files
- `plugins/assistant-core/.codex-plugin/plugin.json`
- `plugins/assistant-core/skills/`
- `docs/plugin-architecture.md`
- `README.md`
- `tests/p0-p4/plugin-boundary-contracts.sh`
- `tests/p0-p4/plugin-manifest-contracts.sh`
- `tests/test-p0-p4-contracts.sh`

## Verification Focus
- Manifest metadata is filled and points at `./skills/`.
- Plugin-local skills match the `assistant-core` boundary exactly.
- Plugin-local skill copies match root source skill files excluding `.DS_Store`.
- Marketplace registration remains absent.
