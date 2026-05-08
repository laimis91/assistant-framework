# Task Journal

Task: Assistant-research plugin install profile
Status: DONE
Current phase: DOCUMENT COMPLETE
Triaged as: medium

Clarification status: ready
Clarification defaults applied: false
Unresolved clarification topics:

## Requirements
- Add `./install.sh --agent <agent> --plugin assistant-research`.
- Install only `assistant-ideate`, `assistant-research`, and `assistant-thinking` from the root skill inventory.
- Preserve default root `skills/assistant-*` installs.
- Preserve `--plugin assistant-core` behavior.
- Keep `assistant-dev` and `assistant-unity` boundary-only and not installable yet.
- Reuse manifest-aware dry-run validation for `plugins/assistant-research/.codex-plugin/plugin.json`.
- Do not add marketplace registration or Unity-specific installer exclusions.

## Constraints
- Do not move root `skills/assistant-*` directories.
- Do not install from plugin-local skill copies yet.
- Do not add `.agents/plugins/marketplace.json`.
- Do not special-case or exclude local Unity skills in installer logic.
- Tests must verify dry-run output, real install inventory, AGENTS rows, boundary-only rejections, docs, and aggregate P0/P4.

## Discovery Notes
- `install.sh` currently accepts exactly one installable profile: `assistant-core`.
- `apply_plugin_profile` already parses profile skill ownership from `docs/plugin-architecture.md`.
- `validate_plugin_manifest_dry_run` is profile-generic once the profile is allowed.
- `assistant-research` plugin-local copies already match the ownership boundary.
- Current tests already cover core dry-run, core install, boundary-only rejection, and plugin manifests.

## Requirements Restatement
Make `assistant-research` an installable plugin profile using the same root-inventory and manifest-validation path as `assistant-core`, while leaving default installs, `assistant-core`, `assistant-dev`, Unity policy, and marketplace registration unchanged.

## Component Manifest
Approval status: approved by user via "ok, lets continue" on 2026-05-08.

### Component 1: Research Profile Contracts
- **What:** Add installer contract coverage for research dry-run, research real install, and updated boundary-only messages.
- **Files:** modify `tests/p0-p4/installer-contracts.sh`; modify `tests/p0-p4/plugin-boundary-contracts.sh`.
- **Depends on:** committed assistant-research manifest scaffold.
- **Verification criteria:**
  - [x] RED: `bash tests/p0-p4/installer-contracts.sh` fails before `assistant-research` is allowed.
  - [x] RED: `bash tests/p0-p4/plugin-boundary-contracts.sh` fails before docs mention the research profile.
  - [x] GREEN: focused installer and boundary suites pass after implementation.

### Component 2: Installer Profile Behavior
- **What:** Allow `assistant-research` as a supported install profile and keep boundary-only rejection generic for unsupported profiles.
- **Files:** modify `install.sh`.
- **Depends on:** Component 1.
- **Verification criteria:**
  - [x] `assistant-research --dry-run` validates the research manifest and lists only research skills.
  - [x] `assistant-research` real install writes only the three research skills.
  - [x] Generated Codex `AGENTS.md` has exactly three assistant skill rows for the research profile.
  - [x] `assistant-dev` and `assistant-unity` remain rejected as boundary-only.

### Component 3: Documentation And Closeout
- **What:** Update README, plugin architecture docs, context map, and task journal.
- **Files:** modify `README.md`; modify `docs/plugin-architecture.md`; modify `.codex/context-map.md`; modify `.codex/task.md`.
- **Depends on:** Components 1 and 2.
- **Verification criteria:**
  - [x] Docs mention both installable profiles.
  - [x] Docs state `assistant-dev` remains boundary-only until install profile coverage exists.
  - [x] Aggregate P0/P4 passes.

## Plan
Plan approval: yes, approved by user via "ok, lets continue" on 2026-05-08.

### Task RESEARCH-PROFILE-1: Contract Expectations
- Behavior / acceptance criteria:
  - Research dry-run checks manifest path, manifest validation, and research-only skills.
  - Research install checks installed skill directories and AGENTS rows.
  - Boundary-only checks still reject `assistant-dev` and `assistant-unity`.
- Files:
  - Create: none
  - Modify: `tests/p0-p4/installer-contracts.sh`, `tests/p0-p4/plugin-boundary-contracts.sh`
  - Test: `tests/p0-p4/installer-contracts.sh`, `tests/p0-p4/plugin-boundary-contracts.sh`
- TDD / RED step:
  - Applies: yes
  - RED command: `bash tests/p0-p4/installer-contracts.sh` and `bash tests/p0-p4/plugin-boundary-contracts.sh`
  - Expected failure: research profile rejected and docs still describe one installable profile.
- Implementation notes / constraints:
  - Keep profile assertions root-inventory based.
  - Do not add marketplace checks beyond existing absence.
- Verification:
  - Command: `bash tests/p0-p4/installer-contracts.sh` and `bash tests/p0-p4/plugin-boundary-contracts.sh`
  - Expected success signal: exit code 0 with research profile checks passing.
- Deviation / rollback rule:
  - If tests require plugin-local installs, stop and re-plan; this slice stays root-inventory based.
- Worker status / evidence:
  - Status: done
  - Evidence: RED focused tests failed for the expected missing profile/docs behavior; GREEN focused tests passed after implementation.

### Task RESEARCH-PROFILE-2: Installer Support
- Behavior / acceptance criteria:
  - `assistant-research` is in the supported install profile allowlist.
  - Unsupported boundary profiles report all supported install profiles.
  - Existing `assistant-core` behavior remains unchanged.
- Files:
  - Create: none
  - Modify: `install.sh`
  - Test: `tests/p0-p4/installer-contracts.sh`
- TDD / RED step:
  - Applies: yes
  - RED command: covered by RESEARCH-PROFILE-1.
  - Expected failure: covered by RESEARCH-PROFILE-1.
- Implementation notes / constraints:
  - Reuse `plugin_profile_line` and `validate_plugin_manifest_dry_run`.
  - Do not hardcode Unity-specific handling.
- Verification:
  - Command: `bash tests/p0-p4/installer-contracts.sh`
  - Expected success signal: exit code 0.
- Deviation / rollback rule:
  - If allowing research affects default or core installs, revert installer changes and isolate the profile filter.
- Worker status / evidence:
  - Status: done
  - Evidence: `bash tests/p0-p4/installer-contracts.sh` passed 19 checks, including research dry-run, research real install, and boundary-only rejections.

### Task RESEARCH-PROFILE-3: Docs And Closeout
- Behavior / acceptance criteria:
  - README documents `assistant-core` and `assistant-research` profile commands.
  - Plugin architecture docs list current installable profiles and the implemented research profile slice.
  - Task journal records spec and quality review with rubric scores before commit.
- Files:
  - Create: none
  - Modify: `README.md`, `docs/plugin-architecture.md`, `.codex/context-map.md`, `.codex/task.md`
  - Test: `tests/test-p0-p4-contracts.sh`
- TDD / RED step:
  - Applies: yes
  - RED command: covered by RESEARCH-PROFILE-1 boundary/docs failures.
  - Expected failure: docs fail before profile docs update.
- Implementation notes / constraints:
  - Keep `assistant-dev` described as scaffolded but boundary-only.
  - Do not add marketplace registration.
- Verification:
  - Command: `bash tests/test-p0-p4-contracts.sh`, `git diff --check`, `find tests plugins -name .DS_Store -print`
  - Expected success signal: exit code 0 for aggregate and diff checks; no `.DS_Store` output.
- Deviation / rollback rule:
  - If aggregate failures are unrelated to the profile, isolate and report before expanding scope.
- Worker status / evidence:
  - Status: done
  - Evidence: `bash tests/test-p0-p4-contracts.sh` passed 141 checks after removing regenerated `tests/.DS_Store`; `git diff --check` and hygiene checks passed.

## Build Progress
- Component 1: Research Profile Contracts - DONE.
- Component 2: Installer Profile Behavior - DONE.
- Component 3: Documentation And Closeout - DONE.

## Tests to run
- `bash tests/p0-p4/installer-contracts.sh`
- `bash tests/p0-p4/plugin-boundary-contracts.sh`
- `bash tests/p0-p4/plugin-manifest-contracts.sh`
- `bash tests/test-p0-p4-contracts.sh`
- `git diff --check`
- `find tests plugins -name .DS_Store -print`

## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved assistant-research install profile plan; `install.sh`; installer contracts; plugin boundary contracts; README and plugin architecture docs; workflow task artifacts.
- Missing acceptance criteria: none.
- Extra scope: none; default installs remain root-inventory based, `assistant-core` remains covered, `assistant-dev` and `assistant-unity` remain boundary-only, and marketplace registration remains absent.
- Changed files mismatch: none.
- Verification evidence mismatch: none.
- Required fixes: none.

### Quality Review #1
- Result: CLEAN
- Rubric required: true
- Rubric scores:
  | Dimension | Score | Weight | Justification |
  |---|---:|---:|---|
  | Correctness | 5.0 | 0.30 | `assistant-research` now uses the same boundary-derived profile filter and manifest validation path as core, with default/core/dev/Unity behavior protected by tests. |
  | Code Quality | 5.0 | 0.20 | The installer change is a small supported-profile allowlist and reuses existing profile parsing and validation helpers. |
  | Architecture | 5.0 | 0.20 | The profile remains root-inventory based and does not introduce marketplace registration, plugin-local install sourcing, or Unity-specific branching. |
  | Security | 5.0 | 0.15 | No secret, network, auth, or permission surface was added. Temporary install homes remain isolated in tests. |
  | Test Coverage | 5.0 | 0.15 | RED/GREEN focused tests cover research dry-run, real install, AGENTS rows, boundary-only rejections, docs, plugin manifests, aggregate P0/P4, and hygiene. |
  | Weighted | 5.00 | 1.00 | PASS. |
- Findings: none.
- Remaining items: none.

### Final Review Result
- Result: CLEAN
- Rounds: 1
- Spec review result: PASS
- Quality review result: CLEAN

## Documentation / Closeout
- Added `assistant-research` to the supported installer profile allowlist.
- Added focused installer contract coverage for `assistant-research --dry-run` and real install behavior.
- Updated boundary-only rejection tests to require all supported profiles in the message.
- Updated README and `docs/plugin-architecture.md` to describe the current installable profiles and the research profile slice.
- No marketplace registration, plugin-local install sourcing, root skill moves, or Unity install exclusions were introduced.

## Final Verification
- RED evidence: `bash tests/p0-p4/installer-contracts.sh` failed 4 checks before `assistant-research` was allowed.
- RED evidence: `bash tests/p0-p4/plugin-boundary-contracts.sh` failed 2 checks before docs mentioned the research profile.
- `bash tests/p0-p4/installer-contracts.sh` - passed; 19 checks.
- `bash tests/p0-p4/plugin-boundary-contracts.sh` - passed; 6 checks.
- `bash tests/p0-p4/plugin-manifest-contracts.sh` - passed; 10 checks.
- `bash tests/test-p0-p4-contracts.sh` - first run failed only because regenerated `tests/.DS_Store` tripped hygiene/direct-run gates.
- `bash tests/test-p0-p4-contracts.sh` - passed; 141 checks after removing regenerated `tests/.DS_Store`.
- `git diff --check` - passed.
- `find tests plugins -name .DS_Store -print` - passed with no output.

## Component Verification Ledger
| Component | Status | Command / Evidence | Criteria |
|---|---|---|---|
| 1. Research Profile Contracts | VERIFIED | RED: focused installer and boundary suites failed before profile/docs implementation. GREEN: `bash tests/p0-p4/installer-contracts.sh` passed 19 checks and `bash tests/p0-p4/plugin-boundary-contracts.sh` passed 6 checks. | Contracts cover research dry-run, research install, boundary-only rejections, and docs. |
| 2. Installer Profile Behavior | VERIFIED | `bash tests/p0-p4/installer-contracts.sh` passed, including research dry-run, real install, AGENTS rows, and boundary-only rejection checks. | Research profile installs only research skills; unsupported profiles remain rejected generically. |
| 3. Documentation And Closeout | VERIFIED | `bash tests/test-p0-p4-contracts.sh` passed 141 checks; `git diff --check` passed; hygiene checks passed. | Docs describe installable profiles, dev boundary-only state, and marketplace absence. |
