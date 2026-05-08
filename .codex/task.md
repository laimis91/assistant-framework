# Task Journal

Task: Assistant-research plugin manifest scaffold
Status: DONE
Current phase: DOCUMENT COMPLETE
Triaged as: medium

Clarification status: ready
Clarification defaults applied: false
Unresolved clarification topics:

## Requirements
- Add a repo-local `assistant-research` Codex plugin scaffold.
- Add `plugins/assistant-research/.codex-plugin/plugin.json`.
- Add plugin-local copies of `assistant-ideate`, `assistant-research`, and `assistant-thinking`.
- Keep `assistant-research` boundary-only and not installable through `--plugin` yet.
- Keep root install behavior and `--plugin assistant-core` behavior unchanged.
- Do not add marketplace registration.

## Constraints
- Do not move root `skills/assistant-*` directories.
- Do not add plugin manifests for `assistant-dev` or `assistant-unity`.
- Do not add `.agents/plugins/marketplace.json`.
- Do not change installer behavior in this slice.
- Tests must verify metadata, boundary ownership, copy parity, docs, allowed manifest set, and aggregate P0/P4.

## Discovery Notes
- `assistant-research` boundary owns `assistant-ideate`, `assistant-research`, and `assistant-thinking`.
- Root research skill directories include `.DS_Store` artifacts that must not be copied into plugin-local skill directories.
- Existing manifest contracts were core-specific and needed to become plugin-generic.
- Existing boundary contracts allowed only the assistant-core manifest before this slice.

## Requirements Restatement
Scaffold the second repo-local Codex plugin for `assistant-research` with plugin-local skill copies and generalized contracts, while leaving installer behavior and marketplace registration unchanged.

## Component Manifest
Approval status: approved by user via "commit and continue" on 2026-05-08.

### Component 1: Research Scaffold Contracts
- **What:** Generalize plugin manifest contracts for core and research scaffolds, and update boundary contracts to allow exactly core plus research manifests.
- **Files:** modify `tests/p0-p4/plugin-manifest-contracts.sh`; modify `tests/p0-p4/plugin-boundary-contracts.sh`.
- **Depends on:** committed assistant-core scaffold.
- **Verification criteria:**
  - [x] RED: `bash tests/p0-p4/plugin-manifest-contracts.sh` fails before research scaffold exists.
  - [x] RED: `bash tests/p0-p4/plugin-boundary-contracts.sh` fails before research manifest exists.
  - [x] GREEN: focused plugin suites pass after scaffold.

### Component 2: Assistant-Research Plugin Scaffold
- **What:** Add research plugin manifest and plugin-local skill copies.
- **Files:** add `plugins/assistant-research/.codex-plugin/plugin.json`; add `plugins/assistant-research/skills/**`.
- **Depends on:** Component 1.
- **Verification criteria:**
  - [x] Manifest has filled metadata and points to `./skills/`.
  - [x] Plugin-local skills match the `assistant-research` boundary exactly.
  - [x] Plugin-local skill files match root source files excluding `.DS_Store`.
  - [x] No marketplace registration file exists.

### Component 3: Documentation And Closeout
- **What:** Update docs, README, context map, and task journal to describe the research scaffold and current compatibility state.
- **Files:** modify `docs/plugin-architecture.md`; modify `README.md`; modify `.codex/context-map.md`; modify `.codex/task.md`.
- **Depends on:** Components 1 and 2.
- **Verification criteria:**
  - [x] Docs mention `plugins/assistant-research/.codex-plugin/plugin.json`.
  - [x] Docs state `assistant-research` remains boundary-only until install profile coverage exists.
  - [x] Aggregate P0/P4 passes.

## Plan
Plan approval: yes, approved by user via "commit and continue" on 2026-05-08.

## Build Progress
- Component 1: Research Scaffold Contracts - DONE.
- Component 2: Assistant-Research Plugin Scaffold - DONE.
- Component 3: Documentation And Closeout - DONE.

## Tests to run
- `bash tests/p0-p4/plugin-manifest-contracts.sh`
- `bash tests/p0-p4/plugin-boundary-contracts.sh`
- `bash tests/test-p0-p4-contracts.sh`
- `git diff --check`
- `find tests plugins -name .DS_Store -print`

## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved assistant-research manifest scaffold plan; `plugins/assistant-research/.codex-plugin/plugin.json`; plugin-local skill copies; plugin manifest contracts; plugin boundary contracts; README and plugin architecture docs; workflow task artifacts.
- Missing acceptance criteria: none.
- Extra scope: none; installer behavior is unchanged and marketplace registration remains absent.
- Changed files mismatch: none.
- Verification evidence mismatch: none.
- Required fixes: none.

### Quality Review #1
- Result: CLEAN
- Rubric required: true
- Rubric scores:
  | Dimension | Score | Weight | Justification |
  |---|---:|---:|---|
  | Correctness | 5.0 | 0.30 | The research manifest, plugin-local skill inventory, copy parity, docs, and allowed manifest set match the approved scope. |
  | Code Quality | 5.0 | 0.20 | Plugin manifest contract helpers now reuse boundary and copy-parity checks across multiple plugins. |
  | Architecture | 5.0 | 0.20 | The scaffold adds a second plugin package without changing root installs, install profiles, or marketplace registration. |
  | Security | 5.0 | 0.15 | No secret, network, auth, or permission surface was added. |
  | Test Coverage | 5.0 | 0.15 | RED/GREEN focused tests, aggregate P0/P4, manifest metadata checks, boundary checks, copy parity, and hygiene checks are clean. |
  | Weighted | 5.00 | 1.00 | PASS. |
- Findings: none.
- Remaining items: none.

### Final Review Result
- Result: CLEAN
- Rounds: 1
- Spec review result: PASS
- Quality review result: CLEAN

## Documentation / Closeout
- Added `plugins/assistant-research/.codex-plugin/plugin.json`.
- Added plugin-local copies of `assistant-ideate`, `assistant-research`, and `assistant-thinking`.
- Generalized plugin manifest contracts across core and research scaffolds.
- Updated plugin boundary contracts to allow exactly core plus research manifests.
- Updated README and `docs/plugin-architecture.md` to describe the research scaffold and boundary-only install state.
- No installer behavior, marketplace registration, or root skill directory moves were introduced.

## Final Verification
- RED evidence: `bash tests/p0-p4/plugin-manifest-contracts.sh` failed 4 checks before research scaffold existed.
- RED evidence: `bash tests/p0-p4/plugin-boundary-contracts.sh` failed 2 checks before research manifest/docs existed.
- `bash tests/p0-p4/plugin-manifest-contracts.sh` - passed; 7 checks.
- `bash tests/p0-p4/plugin-boundary-contracts.sh` - passed; 6 checks.
- `bash tests/test-p0-p4-contracts.sh` - first run failed only because regenerated `tests/.DS_Store` tripped hygiene/direct-run gates.
- `bash tests/test-p0-p4-contracts.sh` - passed; 136 checks after removing regenerated `tests/.DS_Store`.
- `git diff --check` - passed.
- `find tests plugins -name .DS_Store -print` - passed with no output.

## Component Verification Ledger
| Component | Status | Command / Evidence | Criteria |
|---|---|---|---|
| 1. Research Scaffold Contracts | VERIFIED | RED: focused plugin suites failed before research scaffold. GREEN: `bash tests/p0-p4/plugin-manifest-contracts.sh` passed 7 checks and `bash tests/p0-p4/plugin-boundary-contracts.sh` passed 6 checks. | Contracts cover metadata, boundary ownership, copy parity, docs, and allowed manifest set. |
| 2. Assistant-Research Plugin Scaffold | VERIFIED | `bash tests/p0-p4/plugin-manifest-contracts.sh` passed; `find plugins/assistant-research -name .DS_Store -print` produced no output. | Manifest exists, plugin-local copies match root sources, and no `.DS_Store` files were copied. |
| 3. Documentation And Closeout | VERIFIED | `bash tests/test-p0-p4-contracts.sh` passed 136 checks; `git diff --check` passed; hygiene checks passed. | Docs describe research scaffold, boundary-only install state, and marketplace absence. |
