# Task Journal

Task: Plugin split design and boundary contracts
Status: DONE
Current phase: DOCUMENT COMPLETE
Triaged as: medium

Clarification status: ready
Clarification defaults applied: false
Unresolved clarification topics:

## Requirements
- Define planned plugin boundaries before moving any skill directories.
- Add contract guards so every tracked first-class `assistant-*` skill belongs to exactly one planned plugin.
- Keep current installer behavior unchanged for this slice: root `skills/assistant-*` remains the release inventory.
- Keep local-only `skills/unity-*` out of the first-class release inventory and model it as an optional future plugin.

## Constraints
- Do not move skills or introduce plugin manifests in this slice.
- Do not change install behavior or generated hook behavior.
- Keep plugin boundary data simple enough for shell P0/P4 contracts.
- Use current repo state as source of truth: 15 tracked `assistant-*` skills and no tracked `skills/unity-*` release skills.

## Discovery Notes
- `install.sh` still auto-discovers first-class release skills from `skills/assistant-*/SKILL.md`.
- `tests/test-p0-p4-contracts.sh` explicitly sources individual P0/P4 suites, so a new suite must be wired there.
- Current tracked first-class skills are:
  - `assistant-clarify`
  - `assistant-diagrams`
  - `assistant-docs`
  - `assistant-ideate`
  - `assistant-memory`
  - `assistant-onboard`
  - `assistant-reflexion`
  - `assistant-research`
  - `assistant-review`
  - `assistant-security`
  - `assistant-skill-creator`
  - `assistant-tdd`
  - `assistant-telos`
  - `assistant-thinking`
  - `assistant-workflow`
- `git ls-files 'skills/unity-*'` returns no tracked Unity skill release files.

## Requirements Restatement
Create a contract-backed plugin split design that defines future plugin groups and skill ownership without changing runtime install behavior yet.

## Component Manifest
Approval status: approved by user on 2026-05-08

### Component 1: Plugin Architecture Design Doc
- **What:** Add a design document for plugin boundaries, install profiles, manifest expectations, and migration rules.
- **Files:** create `docs/plugin-architecture.md`.
- **Depends on:** none.
- **Verification criteria:**
  - [ ] Defines `assistant-core`, `assistant-dev`, `assistant-research`, and `assistant-unity`.
  - [ ] Contains an authoritative boundary block parseable by contract tests.
  - [ ] States that no skill directories move and current install behavior remains root `skills/assistant-*`.

### Component 2: Plugin Boundary P0/P4 Contract
- **What:** Add a contract suite that checks plugin ownership and current-install compatibility.
- **Files:** create `tests/p0-p4/plugin-boundary-contracts.sh`; modify `tests/test-p0-p4-contracts.sh`.
- **Depends on:** Component 1.
- **Verification criteria:**
  - [ ] Every tracked `assistant-*` skill appears exactly once in the plugin boundary block.
  - [ ] No unknown `assistant-*` assignment appears in the boundary block.
  - [ ] Optional Unity plugin remains represented as `skills/unity-*` and current root install behavior remains documented.

### Component 3: README Current-State Note
- **What:** Add a short README note linking to the plugin architecture while preserving current install instructions.
- **Files:** modify `README.md`.
- **Depends on:** Component 1.
- **Verification criteria:**
  - [ ] README links `docs/plugin-architecture.md`.
  - [ ] README says plugin split is planned and contract-backed.
  - [ ] README says the current installer still uses root `skills/assistant-*`.

## Plan
Plan approval: yes, approved by user on 2026-05-08.

## Build Progress
- Component 1: Plugin Architecture Design Doc - DONE.
- Component 2: Plugin Boundary P0/P4 Contract - DONE.
- Component 3: README Current-State Note - DONE.

## Tests to run
- `bash tests/p0-p4/plugin-boundary-contracts.sh`
- `bash tests/test-p0-p4-contracts.sh`
- `git diff --check`

## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plugin split design slice; `docs/plugin-architecture.md`; `tests/p0-p4/plugin-boundary-contracts.sh`; aggregate P0/P4 wiring; README current-state note; workflow task artifacts.
- Missing acceptance criteria: none.
- Extra scope: none outside expected `.codex/` workflow state artifacts.
- Changed files mismatch: none.
- Verification evidence mismatch: none.
- Required fixes: none.

### Quality Review #1
- Result: CLEAN
- Rubric required: true
- Rubric scores:
  | Dimension | Score | Weight | Justification |
  |---|---:|---:|---|
  | Correctness | 5.0 | 0.30 | Plugin ownership block assigns all 15 tracked assistant skills exactly once, preserves current root install behavior, and keeps Unity local-only. |
  | Code Quality | 5.0 | 0.20 | Contract script follows existing P0/P4 harness style with focused checks and temporary cleanup. |
  | Architecture | 5.0 | 0.20 | Slice is design/contracts only and does not introduce manifests, move skills, or change installer behavior. |
  | Security | 5.0 | 0.15 | No new execution, network, secrets, or permission surface was added. |
  | Test Coverage | 5.0 | 0.15 | New direct P0/P4 suite, aggregate P0/P4 wiring, repository guard recovery, and whitespace checks cover the change. |
  | Weighted | 5.00 | 1.00 | PASS. |
- Findings: none.
- Remaining items: none.

### Final Review Result
- Result: CLEAN
- Rounds: 1
- Spec review result: PASS
- Quality review result: CLEAN

## Documentation / Closeout
- Added `docs/plugin-architecture.md` with planned `assistant-core`, `assistant-dev`, `assistant-research`, and `assistant-unity` boundaries.
- Added a parseable `PLUGIN_BOUNDARY_START` / `PLUGIN_BOUNDARY_END` ownership block.
- Added `tests/p0-p4/plugin-boundary-contracts.sh` and wired it into `tests/test-p0-p4-contracts.sh`.
- Updated README to link the plugin plan while preserving current root `skills/assistant-*` install semantics.
- No skill directories moved, no plugin manifests were added, and install behavior remains unchanged.

## Final Verification
- `bash tests/p0-p4/plugin-boundary-contracts.sh` - passed; 6 checks.
- `bash tests/test-p0-p4-contracts.sh` - passed; 123 checks after removing regenerated `tests/.DS_Store`.
- `git diff --check` - passed.
- `find tests -type f -name .DS_Store -print` - passed with no output.

## Component Verification Ledger
| Component | Status | Command / Evidence | Criteria |
|---|---|---|---|
| 1. Plugin Architecture Design Doc | VERIFIED | `bash tests/p0-p4/plugin-boundary-contracts.sh` passed; doc assertions found current install compatibility, required plugin groups, and no manifest/no-move constraints. | Defines planned plugin groups, parseable boundary block, and no-move/current-install constraints. |
| 2. Plugin Boundary P0/P4 Contract | VERIFIED | `bash tests/p0-p4/plugin-boundary-contracts.sh` passed 6 checks; `bash tests/test-p0-p4-contracts.sh` passed 123 checks after removing regenerated `tests/.DS_Store`. | Guards exact one-plugin assignment for every tracked assistant skill and current install compatibility. |
| 3. README Current-State Note | VERIFIED | `bash tests/p0-p4/plugin-boundary-contracts.sh` passed README assertion; `git diff --check` passed. | README links plugin architecture and preserves current root inventory semantics. |
