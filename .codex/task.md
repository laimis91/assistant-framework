# Task Journal

Task: Assistant-dev plugin manifest scaffold
Status: DONE
Current phase: DOCUMENT COMPLETE
Triaged as: medium

Clarification status: ready
Clarification defaults applied: false
Unresolved clarification topics:

## Requirements
- Add a repo-local `assistant-dev` Codex plugin scaffold.
- Add `plugins/assistant-dev/.codex-plugin/plugin.json`.
- Add plugin-local copies of `assistant-diagrams`, `assistant-docs`, `assistant-onboard`, `assistant-review`, `assistant-security`, `assistant-skill-creator`, `assistant-tdd`, and `assistant-workflow`.
- Keep `assistant-dev` boundary-only and not installable through `--plugin` yet.
- Keep root install behavior and `--plugin assistant-core` behavior unchanged.
- Do not add marketplace registration.

## Constraints
- Do not move root `skills/assistant-*` directories.
- Do not add installer behavior for `assistant-dev`.
- Do not add `.agents/plugins/marketplace.json`.
- Do not special-case or exclude local Unity skills in installer logic.
- Tests must verify metadata, boundary ownership, copy parity, docs, allowed manifest set, and aggregate P0/P4.

## Discovery Notes
- `assistant-dev` boundary owns eight development skills: `assistant-diagrams`, `assistant-docs`, `assistant-onboard`, `assistant-review`, `assistant-security`, `assistant-skill-creator`, `assistant-tdd`, and `assistant-workflow`.
- Several root dev skill directories contain `.DS_Store` artifacts that must not be copied into plugin-local skill directories.
- Existing manifest contracts already had generic inventory and copy-parity helpers and needed one more plugin-specific metadata block.
- Existing boundary contracts allowed only core plus research manifests before this slice.

## Requirements Restatement
Scaffold the third repo-local Codex plugin for `assistant-dev` with plugin-local skill copies and contract coverage, while leaving installer behavior and marketplace registration unchanged.

## Component Manifest
Approval status: approved by user via "great, commit and we can continue" on 2026-05-08.

### Component 1: Dev Scaffold Contracts
- **What:** Extend plugin manifest contracts for the dev scaffold and update boundary contracts to allow exactly core, research, and dev manifests.
- **Files:** modify `tests/p0-p4/plugin-manifest-contracts.sh`; modify `tests/p0-p4/plugin-boundary-contracts.sh`.
- **Depends on:** committed assistant-research scaffold.
- **Verification criteria:**
  - [x] RED: `bash tests/p0-p4/plugin-manifest-contracts.sh` fails before dev scaffold exists.
  - [x] RED: `bash tests/p0-p4/plugin-boundary-contracts.sh` fails before dev manifest/docs exist.
  - [x] GREEN: focused plugin suites pass after scaffold.

### Component 2: Assistant-Dev Plugin Scaffold
- **What:** Add dev plugin manifest and plugin-local skill copies.
- **Files:** add `plugins/assistant-dev/.codex-plugin/plugin.json`; add `plugins/assistant-dev/skills/**`.
- **Depends on:** Component 1.
- **Verification criteria:**
  - [x] Manifest has filled metadata and points to `./skills/`.
  - [x] Plugin-local skills match the `assistant-dev` boundary exactly.
  - [x] Plugin-local skill files match root source files excluding `.DS_Store`.
  - [x] No marketplace registration file exists.

### Component 3: Documentation And Closeout
- **What:** Update docs, README, context map, and task journal to describe the dev scaffold and current compatibility state.
- **Files:** modify `docs/plugin-architecture.md`; modify `README.md`; modify `.codex/context-map.md`; modify `.codex/task.md`.
- **Depends on:** Components 1 and 2.
- **Verification criteria:**
  - [x] Docs mention `plugins/assistant-dev/.codex-plugin/plugin.json`.
  - [x] Docs state `assistant-dev` remains boundary-only until install profile coverage exists.
  - [x] Aggregate P0/P4 passes.

## Plan
Plan approval: yes, approved by user via "great, commit and we can continue" on 2026-05-08.

### Task DEV-1: Contract Expectations
- Behavior / acceptance criteria:
  - Plugin manifest contracts require `assistant-dev` metadata, inventory, copy parity, and docs.
  - Plugin boundary contracts allow exactly core, research, and dev manifests.
- Files:
  - Create: none
  - Modify: `tests/p0-p4/plugin-manifest-contracts.sh`, `tests/p0-p4/plugin-boundary-contracts.sh`
  - Test: `tests/p0-p4/plugin-manifest-contracts.sh`, `tests/p0-p4/plugin-boundary-contracts.sh`
- TDD / RED step:
  - Applies: yes
  - RED command: `bash tests/p0-p4/plugin-manifest-contracts.sh` and `bash tests/p0-p4/plugin-boundary-contracts.sh`
  - Expected failure: missing dev manifest, skill inventory, copy parity, docs, and allowed manifest set.
- Implementation notes / constraints:
  - Reuse generic boundary and copy-parity helpers.
  - Do not add install profile assertions for `assistant-dev`.
- Verification:
  - Command: `bash tests/p0-p4/plugin-manifest-contracts.sh` and `bash tests/p0-p4/plugin-boundary-contracts.sh`
  - Expected success signal: exit code 0 with dev scaffold checks passing.
- Deviation / rollback rule:
  - If contract changes require installer behavior, stop and re-plan; do not add behavior in this slice.
- Worker status / evidence:
  - Status: done
  - Evidence: RED focused tests failed for the expected missing scaffold/docs; GREEN focused tests passed after scaffold.

### Task DEV-2: Plugin Files
- Behavior / acceptance criteria:
  - `plugins/assistant-dev/.codex-plugin/plugin.json` contains filled Codex plugin metadata.
  - `plugins/assistant-dev/skills/` contains exactly the eight boundary-owned skill copies.
  - Plugin-local copies exclude `.DS_Store`.
- Files:
  - Create: `plugins/assistant-dev/.codex-plugin/plugin.json`, `plugins/assistant-dev/skills/**`
  - Modify: none
  - Test: `tests/p0-p4/plugin-manifest-contracts.sh`
- TDD / RED step:
  - Applies: yes
  - RED command: covered by DEV-1.
  - Expected failure: covered by DEV-1.
- Implementation notes / constraints:
  - Copy from root `skills/` without changing root skill directories.
- Verification:
  - Command: `bash tests/p0-p4/plugin-manifest-contracts.sh`
  - Expected success signal: exit code 0 and dev metadata/inventory/parity checks pass.
- Deviation / rollback rule:
  - If source skill layout differs, adjust copy logic only; do not alter source skills.
- Worker status / evidence:
  - Status: done
  - Evidence: `bash tests/p0-p4/plugin-manifest-contracts.sh` passed 10 checks and `find plugins/assistant-dev -name .DS_Store -print` produced no output.

### Task DEV-3: Docs And Closeout
- Behavior / acceptance criteria:
  - README and plugin architecture docs describe core, research, and dev scaffolds.
  - Docs preserve default root install and `assistant-core` profile behavior.
  - Task journal records spec and quality review with rubric scores before commit.
- Files:
  - Create: none
  - Modify: `README.md`, `docs/plugin-architecture.md`, `.codex/context-map.md`, `.codex/task.md`
  - Test: `tests/test-p0-p4-contracts.sh`
- TDD / RED step:
  - Applies: yes
  - RED command: covered by DEV-1 boundary/docs failures.
  - Expected failure: docs and allowed manifest set fail before docs/scaffold updates.
- Implementation notes / constraints:
  - Do not add `.agents/plugins/marketplace.json`.
  - Do not change installer behavior.
- Verification:
  - Command: `bash tests/test-p0-p4-contracts.sh`, `git diff --check`, `find tests plugins -name .DS_Store -print`
  - Expected success signal: exit code 0 for aggregate and diff checks; no `.DS_Store` output.
- Deviation / rollback rule:
  - If aggregate failures are unrelated to plugin scaffold behavior, isolate and report before expanding scope.
- Worker status / evidence:
  - Status: done
  - Evidence: `bash tests/test-p0-p4-contracts.sh` passed 139 checks after removing regenerated `.DS_Store` artifacts; `git diff --check` and hygiene checks passed.

## Build Progress
- Component 1: Dev Scaffold Contracts - DONE.
- Component 2: Assistant-Dev Plugin Scaffold - DONE.
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
- Scope reviewed: approved assistant-dev manifest scaffold plan; `plugins/assistant-dev/.codex-plugin/plugin.json`; plugin-local skill copies; plugin manifest contracts; plugin boundary contracts; README and plugin architecture docs; workflow task artifacts.
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
  | Correctness | 5.0 | 0.30 | The dev manifest, plugin-local skill inventory, copy parity, docs, and allowed manifest set match the approved scope. |
  | Code Quality | 5.0 | 0.20 | The existing generic contract helpers were reused, and the dev-specific checks follow the core/research pattern. |
  | Architecture | 5.0 | 0.20 | The scaffold adds the third plugin package without changing root installs, install profiles, or marketplace registration. |
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
- Added `plugins/assistant-dev/.codex-plugin/plugin.json`.
- Added plugin-local copies of `assistant-diagrams`, `assistant-docs`, `assistant-onboard`, `assistant-review`, `assistant-security`, `assistant-skill-creator`, `assistant-tdd`, and `assistant-workflow`.
- Extended plugin manifest contracts across core, research, and dev scaffolds.
- Updated plugin boundary contracts to allow exactly core, research, and dev manifests.
- Updated README and `docs/plugin-architecture.md` to describe the dev scaffold and boundary-only install state.
- No installer behavior, marketplace registration, root skill directory moves, or Unity install exclusions were introduced.

## Final Verification
- RED evidence: `bash tests/p0-p4/plugin-manifest-contracts.sh` failed 4 checks before dev scaffold existed.
- RED evidence: `bash tests/p0-p4/plugin-boundary-contracts.sh` failed 2 checks before dev manifest/docs existed.
- `bash tests/p0-p4/plugin-manifest-contracts.sh` - passed; 10 checks.
- `bash tests/p0-p4/plugin-boundary-contracts.sh` - passed; 6 checks.
- `find plugins/assistant-dev -name .DS_Store -print` - passed with no output.
- `bash tests/test-p0-p4-contracts.sh` - first run failed only because regenerated `tests/.DS_Store` and `plugins/.DS_Store` tripped hygiene/direct-run gates.
- `bash tests/test-p0-p4-contracts.sh` - passed; 139 checks after removing regenerated `.DS_Store` artifacts.
- `git diff --check` - passed.
- `find tests plugins -name .DS_Store -print` - passed with no output.

## Component Verification Ledger
| Component | Status | Command / Evidence | Criteria |
|---|---|---|---|
| 1. Dev Scaffold Contracts | VERIFIED | RED: focused plugin suites failed before dev scaffold. GREEN: `bash tests/p0-p4/plugin-manifest-contracts.sh` passed 10 checks and `bash tests/p0-p4/plugin-boundary-contracts.sh` passed 6 checks. | Contracts cover metadata, boundary ownership, copy parity, docs, and allowed manifest set. |
| 2. Assistant-Dev Plugin Scaffold | VERIFIED | `bash tests/p0-p4/plugin-manifest-contracts.sh` passed; `find plugins/assistant-dev -name .DS_Store -print` produced no output. | Manifest exists, plugin-local copies match root sources, and no `.DS_Store` files are copied. |
| 3. Documentation And Closeout | VERIFIED | `bash tests/test-p0-p4-contracts.sh` passed 139 checks; `git diff --check` passed; hygiene checks passed. | Docs describe dev scaffold, boundary-only install state, and marketplace absence. |
