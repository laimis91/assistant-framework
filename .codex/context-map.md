# Context Map: Plugin Split Design and Boundary Contracts

## Current Release Surface
- First-class skills live at `skills/assistant-*/SKILL.md`.
- `install.sh` auto-discovers root `skills/assistant-*` skills and installs them into each agent home.
- `tools/skills/validate-skills.sh` and `tools/evals/run-skill-evals.sh` default to first-class `assistant-*` inventory.
- Local Unity skill experiments are `skills/unity-*`; they are not tracked release skills and are excluded by default.

## Target Slice
- Add design documentation only: `docs/plugin-architecture.md`.
- Add contract tests only: `tests/p0-p4/plugin-boundary-contracts.sh`.
- Wire the new P0/P4 suite into `tests/test-p0-p4-contracts.sh`.
- Add a README note linking the plan.

## Planned Plugin Groups
- `assistant-core`: foundation skills for clarification, memory, reflexion, and Telos.
- `assistant-dev`: development workflow, review, TDD, security, onboarding, docs, diagrams, and skill creation.
- `assistant-research`: research, thinking, and ideation.
- `assistant-unity`: optional local Unity skills, represented by `skills/unity-*`.

## Constraints
- Do not move skill directories in this slice.
- Do not add `.codex-plugin/plugin.json` or Claude plugin manifests yet.
- Do not change current install behavior.
- The plugin boundary block in docs must remain simple enough for shell tests to parse.
