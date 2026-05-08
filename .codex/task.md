# Task Journal

Task: Assistant-dev plugin install profile
Status: DONE
Current phase: DOCUMENT COMPLETE
Triaged as: medium

Clarification status: ready
Clarification defaults applied: false
Unresolved clarification topics:

## Requirements
- Add `./install.sh --agent <agent> --plugin assistant-dev`.
- Install only `assistant-diagrams`, `assistant-docs`, `assistant-onboard`, `assistant-review`, `assistant-security`, `assistant-skill-creator`, `assistant-tdd`, and `assistant-workflow` from the root skill inventory.
- Preserve default root `skills/assistant-*` installs.
- Preserve `--plugin assistant-core` and `--plugin assistant-research` behavior.
- Keep `assistant-unity` boundary-only and not installable yet.
- Reuse manifest-aware dry-run validation for `plugins/assistant-dev/.codex-plugin/plugin.json`.
- Do not add marketplace registration or Unity-specific installer exclusions.

## Constraints
- Do not move root `skills/assistant-*` directories.
- Do not install from plugin-local skill copies yet.
- Do not add `.agents/plugins/marketplace.json`.
- Do not special-case or exclude local Unity skills in installer logic.
- Tests must verify dry-run output, real install inventory, AGENTS rows, Unity boundary-only rejection, docs, and aggregate P0/P4.

## Discovery Notes
- `install.sh` currently supports `assistant-core` and `assistant-research` through `supported_plugin_profiles`.
- `apply_plugin_profile` already parses profile skill ownership from `docs/plugin-architecture.md`.
- `validate_plugin_manifest_dry_run` is profile-generic once the profile is allowed.
- `assistant-dev` plugin-local copies already match the ownership boundary.
- Current tests already cover core/research dry-run, core/research install, Unity boundary-only rejection, unknown profile rejection, and plugin manifests.

## Requirements Restatement
Make `assistant-dev` an installable plugin profile using the same root-inventory and manifest-validation path as core and research, while leaving default installs, existing profiles, Unity policy, and marketplace registration unchanged.

## Component Manifest
Approval status: approved by user via "ok, lets continue" on 2026-05-08.

### Component 1: Dev Profile Contracts
- **What:** Add installer contract coverage for dev dry-run, dev real install, updated Unity boundary-only message, and docs.
- **Files:** modify `tests/p0-p4/installer-contracts.sh`; modify `tests/p0-p4/plugin-boundary-contracts.sh`.
- **Depends on:** committed assistant-dev manifest scaffold.
- **Verification criteria:**
  - [x] RED: `bash tests/p0-p4/installer-contracts.sh` fails before `assistant-dev` is allowed.
  - [x] RED: `bash tests/p0-p4/plugin-boundary-contracts.sh` fails before docs mention the dev profile.
  - [x] GREEN: focused installer and boundary suites pass after implementation.

### Component 2: Installer Profile Behavior
- **What:** Allow `assistant-dev` as a supported install profile and keep unsupported profile handling generic.
- **Files:** modify `install.sh`.
- **Depends on:** Component 1.
- **Verification criteria:**
  - [x] `assistant-dev --dry-run` validates the dev manifest and lists only development skills.
  - [x] `assistant-dev` real install writes only the eight development skills.
  - [x] Generated Codex `AGENTS.md` has exactly eight assistant skill rows for the dev profile.
  - [x] `assistant-unity` remains rejected as boundary-only without Unity-specific installer code.

### Component 3: Documentation And Closeout
- **What:** Update README, plugin architecture docs, context map, and task journal.
- **Files:** modify `README.md`; modify `docs/plugin-architecture.md`; modify `.codex/context-map.md`; modify `.codex/task.md`.
- **Depends on:** Components 1 and 2.
- **Verification criteria:**
  - [x] Docs mention all three installable profiles.
  - [x] Docs state marketplace registration and plugin-local install sourcing remain future work.
  - [x] Aggregate P0/P4 passes.

## Plan
Plan approval: yes, approved by user via "ok, lets continue" on 2026-05-08.

### Task DEV-PROFILE-1: Contract Expectations
- Behavior / acceptance criteria:
  - Dev dry-run checks manifest path, manifest validation, and development-only skills.
  - Dev install checks installed skill directories and AGENTS rows.
  - Unity remains boundary-only and unknown profiles still fail clearly.
- Files:
  - Create: none
  - Modify: `tests/p0-p4/installer-contracts.sh`, `tests/p0-p4/plugin-boundary-contracts.sh`
  - Test: `tests/p0-p4/installer-contracts.sh`, `tests/p0-p4/plugin-boundary-contracts.sh`
- TDD / RED step:
  - Applies: yes
  - RED command: `bash tests/p0-p4/installer-contracts.sh` and `bash tests/p0-p4/plugin-boundary-contracts.sh`
  - Expected failure: dev profile rejected and docs still describe core/research only.
- Implementation notes / constraints:
  - Keep profile assertions root-inventory based.
  - Do not add marketplace checks beyond existing absence.
- Verification:
  - Command: `bash tests/p0-p4/installer-contracts.sh` and `bash tests/p0-p4/plugin-boundary-contracts.sh`
  - Expected success signal: exit code 0 with dev profile checks passing.
- Deviation / rollback rule:
  - If tests require plugin-local installs, stop and re-plan; this slice stays root-inventory based.
- Worker status / evidence:
  - Status: done
  - Evidence: RED focused tests failed for the expected missing profile/docs behavior; GREEN focused tests passed after implementation.

### Task DEV-PROFILE-2: Installer Support
- Behavior / acceptance criteria:
  - `assistant-dev` is in the supported install profile allowlist.
  - Unsupported boundary profiles report all supported install profiles.
  - Existing `assistant-core` and `assistant-research` behavior remains unchanged.
- Files:
  - Create: none
  - Modify: `install.sh`
  - Test: `tests/p0-p4/installer-contracts.sh`
- TDD / RED step:
  - Applies: yes
  - RED command: covered by DEV-PROFILE-1.
  - Expected failure: covered by DEV-PROFILE-1.
- Implementation notes / constraints:
  - Reuse `plugin_profile_line` and `validate_plugin_manifest_dry_run`.
  - Do not hardcode Unity-specific handling.
- Verification:
  - Command: `bash tests/p0-p4/installer-contracts.sh`
  - Expected success signal: exit code 0.
- Deviation / rollback rule:
  - If allowing dev affects default/core/research installs, revert installer changes and isolate the profile filter.
- Worker status / evidence:
  - Status: done
  - Evidence: `bash tests/p0-p4/installer-contracts.sh` passed 21 checks, including dev dry-run, dev real install, and Unity boundary-only rejection.

### Task DEV-PROFILE-3: Docs And Closeout
- Behavior / acceptance criteria:
  - README documents `assistant-core`, `assistant-research`, and `assistant-dev` profile commands.
  - Plugin architecture docs list current installable profiles and the implemented dev profile slice.
  - Task journal records spec and quality review with rubric scores before commit.
- Files:
  - Create: none
  - Modify: `README.md`, `docs/plugin-architecture.md`, `.codex/context-map.md`, `.codex/task.md`
  - Test: `tests/test-p0-p4-contracts.sh`
- TDD / RED step:
  - Applies: yes
  - RED command: covered by DEV-PROFILE-1 boundary/docs failures.
  - Expected failure: docs fail before profile docs update.
- Implementation notes / constraints:
  - Keep marketplace registration absent.
  - Keep plugin-local install sourcing as future work.
- Verification:
  - Command: `bash tests/test-p0-p4-contracts.sh`, `git diff --check`, `find tests plugins -name .DS_Store -print`
  - Expected success signal: exit code 0 for aggregate and diff checks; no `.DS_Store` output.
- Deviation / rollback rule:
  - If aggregate failures are unrelated to the profile, isolate and report before expanding scope.
- Worker status / evidence:
  - Status: done
  - Evidence: `bash tests/test-p0-p4-contracts.sh` passed 143 checks after removing regenerated `.DS_Store` artifacts; `git diff --check` and hygiene checks passed.

## Build Progress
- Component 1: Dev Profile Contracts - DONE.
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
- Scope reviewed: approved assistant-dev install profile plan; `install.sh`; installer contracts; plugin boundary contracts; README and plugin architecture docs; workflow task artifacts.
- Missing acceptance criteria: none.
- Extra scope: none; default installs remain root-inventory based, `assistant-core` and `assistant-research` remain covered, `assistant-unity` remains boundary-only, and marketplace registration remains absent.
- Changed files mismatch: none.
- Verification evidence mismatch: none.
- Required fixes: none.

### Quality Review #1
- Result: CLEAN
- Rubric required: true
- Rubric scores:
  | Dimension | Score | Weight | Justification |
  |---|---:|---:|---|
  | Correctness | 5.0 | 0.30 | `assistant-dev` now uses the same boundary-derived profile filter and manifest validation path as core/research, with default/core/research/Unity behavior protected by tests. |
  | Code Quality | 5.0 | 0.20 | The installer change is a one-line allowlist extension and the tests follow the existing profile contract pattern. |
  | Architecture | 5.0 | 0.20 | The profile remains root-inventory based and does not introduce marketplace registration, plugin-local install sourcing, or Unity-specific branching. |
  | Security | 5.0 | 0.15 | No secret, network, auth, or permission surface was added. Temporary install homes remain isolated in tests. |
  | Test Coverage | 5.0 | 0.15 | RED/GREEN focused tests cover dev dry-run, real install, AGENTS rows, Unity rejection, unknown profile rejection, docs, plugin manifests, aggregate P0/P4, and hygiene. |
  | Weighted | 5.00 | 1.00 | PASS. |
- Findings: none.
- Remaining items: none.

### Final Review Result
- Result: CLEAN
- Rounds: 1
- Spec review result: PASS
- Quality review result: CLEAN

## Documentation / Closeout
- Added `assistant-dev` to the supported installer profile allowlist.
- Added focused installer contract coverage for `assistant-dev --dry-run` and real install behavior.
- Updated Unity boundary-only rejection tests to require all supported profiles in the message.
- Updated README and `docs/plugin-architecture.md` to describe all current installable profiles and the dev profile slice.
- No marketplace registration, plugin-local install sourcing, root skill moves, or Unity install exclusions were introduced.

## Final Verification
- RED evidence: `bash tests/p0-p4/installer-contracts.sh` failed 3 checks before `assistant-dev` was allowed.
- RED evidence: `bash tests/p0-p4/plugin-boundary-contracts.sh` failed 2 checks before docs mentioned the dev profile.
- `bash tests/p0-p4/installer-contracts.sh` - passed; 21 checks.
- `bash tests/p0-p4/plugin-boundary-contracts.sh` - passed; 6 checks.
- `bash tests/p0-p4/plugin-manifest-contracts.sh` - passed; 10 checks.
- `bash tests/test-p0-p4-contracts.sh` - first run failed only because regenerated `tests/.DS_Store` and `plugins/.DS_Store` tripped hygiene/direct-run gates.
- `bash tests/test-p0-p4-contracts.sh` - passed; 143 checks after removing regenerated `.DS_Store` artifacts.
- `git diff --check` - passed.
- `find tests plugins -name .DS_Store -print` - passed with no output.

## Component Verification Ledger
| Component | Status | Command / Evidence | Criteria |
|---|---|---|---|
| 1. Dev Profile Contracts | VERIFIED | RED: focused installer and boundary suites failed before profile/docs implementation. GREEN: `bash tests/p0-p4/installer-contracts.sh` passed 21 checks and `bash tests/p0-p4/plugin-boundary-contracts.sh` passed 6 checks. | Contracts cover dev dry-run, dev install, Unity boundary-only rejection, unknown profile rejection, and docs. |
| 2. Installer Profile Behavior | VERIFIED | `bash tests/p0-p4/installer-contracts.sh` passed, including dev dry-run, real install, AGENTS rows, Unity rejection, and unknown profile checks. | Dev profile installs only development skills; unsupported profiles remain rejected generically. |
| 3. Documentation And Closeout | VERIFIED | `bash tests/test-p0-p4-contracts.sh` passed 143 checks; `git diff --check` passed; hygiene checks passed. | Docs describe installable profiles, marketplace absence, and plugin-local install future work. |
