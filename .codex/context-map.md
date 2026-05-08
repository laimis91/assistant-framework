# Context Map: Assistant-Core Plugin Install Profile

## Current Installer Surface
- `install.sh` discovers default first-class skills from `skills/assistant-*/SKILL.md`.
- `--skill <name>` filters the install to one root skill.
- Codex AGENTS.md generation is based on the installed `SKILLS` array.
- No plugin manifests or marketplace files exist in the repo.

## Target Slice
- Add `--plugin assistant-core` as an optional install profile.
- Parse profile skill ownership from `docs/plugin-architecture.md`.
- Keep default install and `--skill` behavior unchanged.
- Do not hardcode Unity-specific exclusions in `install.sh`; use the same inventory rules for custom assistant-named skills.

## Key Files
- `install.sh`
- `docs/plugin-architecture.md`
- `README.md`
- `tests/p0-p4/installer-contracts.sh`
- `tests/p0-p4/plugin-boundary-contracts.sh`
- `tests/test-p0-p4-contracts.sh`

## Verification Focus
- Dry-run output lists only core skills for `--plugin assistant-core`.
- Real Codex install creates only four core skill directories and four AGENTS rows.
- Default install still includes all assistant-named skills and excludes non-assistant local skills.
- Plugin manifests remain absent in this slice.
