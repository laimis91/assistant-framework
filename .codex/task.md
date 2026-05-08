# Task Journal

Task: Assistant-core plugin manifest scaffold
Status: DONE
Current phase: DOCUMENT COMPLETE
Triaged as: medium

Clarification status: ready
Clarification defaults applied: false
Unresolved clarification topics:

## Requirements
- Add a repo-local `assistant-core` Codex plugin scaffold.
- Add `plugins/assistant-core/.codex-plugin/plugin.json`.
- Add plugin-local copies of the four assistant-core skills under `plugins/assistant-core/skills/`.
- Keep root install behavior and `--plugin assistant-core` behavior unchanged.
- Do not add marketplace registration in this slice.
- Keep Unity handling pattern-based and avoid installer-specific Unity exclusions.

## Constraints
- Do not move root `skills/assistant-*` directories.
- Do not add plugin manifests for `assistant-dev`, `assistant-research`, or `assistant-unity`.
- Do not add `.agents/plugins/marketplace.json`.
- Tests must verify manifest metadata, boundary skill ownership, plugin-local copy parity, documentation, and aggregate P0/P4 behavior.

## Discovery Notes
- No plugin manifests or marketplace files existed before this slice.
- Codex curated plugins use `.codex-plugin/plugin.json` plus plugin-local `skills/`.
- The `assistant-core` boundary owns `assistant-clarify`, `assistant-memory`, `assistant-reflexion`, and `assistant-telos`.
- Root core skill directories include `.DS_Store` artifacts that must not be copied into plugin-local skill directories.

## Requirements Restatement
Scaffold the first repo-local Codex plugin for `assistant-core` with plugin-local skill copies and contracts, while leaving root install compatibility and marketplace registration unchanged.

## Component Manifest
Approval status: approved by user on 2026-05-08.

### Component 1: Manifest Contracts
- **What:** Add P0/P4 contracts for `assistant-core` manifest metadata, plugin-local skill ownership, copy parity, docs, and no marketplace registration.
- **Files:** add `tests/p0-p4/plugin-manifest-contracts.sh`; modify `tests/test-p0-p4-contracts.sh`; modify `tests/p0-p4/plugin-boundary-contracts.sh`.
- **Depends on:** none.
- **Verification criteria:**
  - [x] RED: `bash tests/p0-p4/plugin-manifest-contracts.sh` fails before scaffold exists.
  - [x] RED: `bash tests/p0-p4/plugin-boundary-contracts.sh` fails before scaffold manifest exists.
  - [x] Contracts are wired into aggregate P0/P4.

### Component 2: Assistant-Core Plugin Scaffold
- **What:** Add `plugins/assistant-core/.codex-plugin/plugin.json` and plugin-local copies of the four core skills.
- **Files:** add `plugins/assistant-core/.codex-plugin/plugin.json`; add `plugins/assistant-core/skills/**`.
- **Depends on:** Component 1.
- **Verification criteria:**
  - [x] Manifest has filled metadata and points to `./skills/`.
  - [x] Plugin-local skills match the `assistant-core` boundary exactly.
  - [x] Plugin-local skill files match root source files excluding `.DS_Store`.
  - [x] No marketplace registration file exists.

### Component 3: Documentation And Drift Guards
- **What:** Update docs and README to describe the scaffold without implying marketplace distribution or root skill moves.
- **Files:** modify `docs/plugin-architecture.md`; modify `README.md`; modify `.codex/context-map.md`.
- **Depends on:** Components 1 and 2.
- **Verification criteria:**
  - [x] Docs mention `plugins/assistant-core/.codex-plugin/plugin.json`.
  - [x] Docs state plugin-local copies exist and root skills do not move.
  - [x] Aggregate P0/P4 passes.

## Plan
Plan approval: yes, approved by user on 2026-05-08.

## Build Progress
- Component 1: Manifest Contracts - DONE.
- Component 2: Assistant-Core Plugin Scaffold - DONE.
- Component 3: Documentation And Drift Guards - DONE.

## Tests to run
- `bash tests/p0-p4/plugin-manifest-contracts.sh`
- `bash tests/p0-p4/plugin-boundary-contracts.sh`
- `bash tests/test-p0-p4-contracts.sh`
- `git diff --check`
- `find tests -type f -name .DS_Store -print`
- `find plugins/assistant-core -name .DS_Store -print`

## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved assistant-core manifest scaffold plan; `plugins/assistant-core/.codex-plugin/plugin.json`; plugin-local skill copies; plugin manifest contracts; plugin boundary contracts; README and plugin architecture docs; workflow task artifacts.
- Missing acceptance criteria: none.
- Extra scope: none; only `assistant-core` scaffold was added and marketplace registration remains absent.
- Changed files mismatch: none.
- Verification evidence mismatch: none.
- Required fixes: none.

### Quality Review #1
- Result: ISSUES_FOUND
- Rubric required: true
- Rubric scores:
  | Dimension | Score | Weight | Justification |
  |---|---:|---:|---|
  | Correctness | 4.5 | 0.30 | Scaffold behavior and tests passed, but docs said "no skill directories move" while plugin-local skill copies were added. |
  | Code Quality | 5.0 | 0.20 | Contracts are focused and compare plugin-local copies directly against root sources. |
  | Architecture | 4.5 | 0.20 | Root install compatibility was preserved, but the wording needed to distinguish root skill directories from plugin-local copies. |
  | Security | 5.0 | 0.15 | No secret, network, auth, or permission surface was added. |
  | Test Coverage | 5.0 | 0.15 | RED/GREEN manifest tests, boundary tests, copy parity tests, aggregate P0/P4, and hygiene checks cover the slice. |
  | Weighted | 4.75 | 1.00 | REFINE due to one documentation precision issue. |
- Findings:
  - SHOULD-FIX: `docs/plugin-architecture.md` said no skill directories move in a slice that adds plugin-local skill copies. Risk category: correctness and documentation drift. Fix: clarify that no root skill directories move, and update the boundary contract to check that wording.
- Fixed in round:
  - Changed docs to say "no root skill directories move in this slice".
  - Updated `tests/p0-p4/plugin-boundary-contracts.sh` to require that clearer wording.
- Validation after fix:
  - `bash tests/p0-p4/plugin-boundary-contracts.sh` passed 6 checks.
  - `bash tests/p0-p4/plugin-manifest-contracts.sh` passed 4 checks.
  - `git diff --check` passed.
  - `bash tests/test-p0-p4-contracts.sh` passed 132 checks after removing regenerated `tests/.DS_Store`.

### Quality Review #2
- Result: CLEAN
- Rubric required: true
- Rubric scores:
  | Dimension | Score | Weight | Justification |
  |---|---:|---:|---|
  | Correctness | 5.0 | 0.30 | The manifest, plugin-local skill inventory, copy parity, docs, and marketplace absence match the approved scope. |
  | Code Quality | 5.0 | 0.20 | The new contract suite is localized and uses direct file inventory/content comparisons. |
  | Architecture | 5.0 | 0.20 | The scaffold introduces plugin packaging without changing root installs or registering marketplace distribution. |
  | Security | 5.0 | 0.15 | No security-sensitive runtime surface was introduced. |
  | Test Coverage | 5.0 | 0.15 | Focused suites and aggregate P0/P4 are clean, including final `.DS_Store` and plugin hygiene checks. |
  | Weighted | 5.00 | 1.00 | PASS. |
- Findings: none.
- Remaining items: none.

### Final Review Result
- Result: ISSUES_FIXED
- Rounds: 2
- Spec review result: PASS
- Quality review result: CLEAN

## Documentation / Closeout
- Added `plugins/assistant-core/.codex-plugin/plugin.json`.
- Added plugin-local copies of `assistant-clarify`, `assistant-memory`, `assistant-reflexion`, and `assistant-telos`.
- Added `tests/p0-p4/plugin-manifest-contracts.sh` and wired it into aggregate P0/P4.
- Updated plugin boundary contracts for the assistant-core scaffold.
- Updated README and `docs/plugin-architecture.md` to describe the scaffold and marketplace absence.
- Root install behavior and `--plugin assistant-core` behavior remain unchanged.

## Final Verification
- RED evidence: `bash tests/p0-p4/plugin-manifest-contracts.sh` failed with 4 failures before scaffold existed.
- RED evidence: `bash tests/p0-p4/plugin-boundary-contracts.sh` failed on missing assistant-core manifest before scaffold existed.
- `bash tests/p0-p4/plugin-manifest-contracts.sh` - passed; 4 checks.
- `bash tests/p0-p4/plugin-boundary-contracts.sh` - passed; 6 checks.
- `bash tests/test-p0-p4-contracts.sh` - first post-review rerun failed only because generated `tests/.DS_Store` tripped hygiene/direct-run gates.
- `bash tests/test-p0-p4-contracts.sh` - passed; 132 checks after removing regenerated `tests/.DS_Store`.
- `git diff --check` - passed.
- `find tests -type f -name .DS_Store -print` - passed with no output.
- `find plugins/assistant-core -name .DS_Store -print` - passed with no output.

## Component Verification Ledger
| Component | Status | Command / Evidence | Criteria |
|---|---|---|---|
| 1. Manifest Contracts | VERIFIED | RED: `bash tests/p0-p4/plugin-manifest-contracts.sh` failed before scaffold; `bash tests/p0-p4/plugin-boundary-contracts.sh` failed before manifest. GREEN: both focused suites passed after scaffold. | Contracts cover manifest metadata, boundary ownership, copy parity, docs, no marketplace registration, and aggregate wiring. |
| 2. Assistant-Core Plugin Scaffold | VERIFIED | `bash tests/p0-p4/plugin-manifest-contracts.sh` passed 4 checks; `find plugins/assistant-core -name .DS_Store -print` produced no output. | Manifest exists, plugin-local copies match root sources, and no `.DS_Store` files were copied. |
| 3. Documentation And Drift Guards | VERIFIED | `bash tests/p0-p4/plugin-boundary-contracts.sh` passed 6 checks; `bash tests/test-p0-p4-contracts.sh` passed 132 checks; `git diff --check` passed. | Docs describe scaffold state without claiming marketplace registration or root skill moves. |
