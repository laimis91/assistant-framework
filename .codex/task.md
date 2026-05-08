# Task Journal

Task: Assistant-core plugin install profile
Status: DONE
Current phase: DOCUMENT COMPLETE
Triaged as: medium

Clarification status: ready
Clarification defaults applied: false
Unresolved clarification topics:

## Requirements
- Add an installer profile for `assistant-core` using `./install.sh --agent <agent> --plugin assistant-core`.
- Keep default install behavior unchanged: root `skills/assistant-*` remains the default first-class release inventory.
- Keep `--skill` targeted single-skill installs working and mutually exclusive with `--plugin`.
- Do not hardcode Unity-specific exclusions in `install.sh`; custom assistant-named Unity skills must follow normal `skills/assistant-*` inventory behavior.
- Reject boundary-defined non-core plugin profiles through a generic not-installable profile gate until they have P0/P4 coverage.
- Use `docs/plugin-architecture.md` as the source for plugin skill ownership.

## Constraints
- Do not move skill directories.
- Do not add plugin manifests or marketplace files in this slice.
- Do not change hook installation behavior.
- Tests must cover profile dry-run, real profile install, generic boundary-only profile rejection, no Unity hardcoding, custom assistant-named skill inventory behavior, and `--skill`/`--plugin` conflict.

## Discovery Notes
- `install.sh` currently auto-discovers all root `skills/assistant-*/SKILL.md` skills.
- `install.sh` currently supports `--skill` but not `--plugin`.
- The plugin boundary doc contains a parseable ownership block:
  - `assistant-core`: `assistant-clarify`, `assistant-memory`, `assistant-reflexion`, `assistant-telos`.
  - `assistant-unity`: `skills/unity-*`, outside the default `skills/assistant-*` inventory.
- `tests/p0-p4/installer-contracts.sh` owns installer behavior contracts.
- `tests/p0-p4/plugin-boundary-contracts.sh` owns plugin boundary/doc drift contracts.

## Requirements Restatement
Implement an optional `assistant-core` install profile from the plugin boundary map without changing default root inventory installs or adding plugin manifests.

## Component Manifest
Approval status: approved by user on 2026-05-08

### Component 1: Installer Profile Contracts
- **What:** Add RED P0/P4 contracts for `--plugin assistant-core` behavior and invalid profile combinations.
- **Files:** modify `tests/p0-p4/installer-contracts.sh`.
- **Depends on:** none.
- **Verification criteria:**
  - [x] Initial `bash tests/p0-p4/installer-contracts.sh` fails before implementation on the new profile tests.
  - [ ] Dry-run `--plugin assistant-core` lists only core skills.
  - [ ] Real Codex profile install installs only core skills and AGENTS rows.
  - [ ] Boundary-only plugin profiles fail with generic not-installable guidance.
  - [ ] The installer contains no Unity-specific exclusion code.
  - [ ] Assistant-named custom skills follow default inventory behavior.
  - [ ] `--skill` plus `--plugin` fails clearly.

### Component 2: Installer Plugin Profile Support
- **What:** Add `--plugin` parsing, conflict validation, plugin boundary parsing, profile skill filtering, and installer output.
- **Files:** modify `install.sh`.
- **Depends on:** Component 1.
- **Verification criteria:**
  - [ ] `bash tests/p0-p4/installer-contracts.sh` passes.
  - [ ] Existing default install and single-skill install contracts still pass.

### Component 3: Docs And Boundary Drift Updates
- **What:** Update README and plugin architecture docs to describe the optional `assistant-core` profile while preserving default root install compatibility.
- **Files:** modify `README.md`; modify `docs/plugin-architecture.md`; modify `tests/p0-p4/plugin-boundary-contracts.sh` if needed.
- **Depends on:** Components 1 and 2.
- **Verification criteria:**
  - [ ] README documents `--plugin assistant-core`.
  - [ ] Plugin architecture doc states no manifests exist yet and root install remains the default compatibility path.
  - [ ] `bash tests/p0-p4/plugin-boundary-contracts.sh` passes.

## Plan
Plan approval: yes, approved by user on 2026-05-08.

## Build Progress
- Component 1: Installer Profile Contracts - DONE.
- Component 2: Installer Plugin Profile Support - DONE.
- Component 3: Docs And Boundary Drift Updates - DONE.

## Tests to run
- `bash tests/p0-p4/installer-contracts.sh`
- `bash tests/p0-p4/plugin-boundary-contracts.sh`
- `bash tests/test-p0-p4-contracts.sh`
- `git diff --check`

## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved assistant-core profile plan; `install.sh`; installer profile contracts; plugin boundary contracts; README and plugin architecture docs; workflow task artifacts.
- Missing acceptance criteria: none.
- Extra scope: none after review fix; only `assistant-core` is installable through `--plugin`.
- Changed files mismatch: none.
- Verification evidence mismatch: none.
- Required fixes: none.

### Quality Review #1
- Result: ISSUES_FOUND
- Rubric required: true
- Rubric scores:
  | Dimension | Score | Weight | Justification |
  |---|---:|---:|---|
  | Correctness | 4.0 | 0.30 | `assistant-core` behavior passed, but the first generic parser made boundary-only `assistant-dev` and `assistant-research` installable without P0/P4 coverage. |
  | Code Quality | 4.5 | 0.20 | Installer helpers were readable and localized, but needed an explicit supported-profile gate. |
  | Architecture | 4.0 | 0.20 | Boundary doc remained the source of truth, but profile behavior leaked beyond the approved first profile. |
  | Security | 5.0 | 0.15 | No new secret, network, auth, or permission surface was added. |
  | Test Coverage | 4.0 | 0.15 | Core profile and invalid Unity/conflict paths were covered; boundary-only profile rejection was missing. |
  | Weighted | 4.25 | 1.00 | REFINE due to one should-fix scope-control issue. |
- Findings:
  - SHOULD-FIX: `install.sh` accepted any non-Unity plugin boundary from `docs/plugin-architecture.md`, making `assistant-dev` and `assistant-research` installable despite this slice only approving and testing `assistant-core`. Risk category: correctness and unsafe change surface. Fix: reject boundary-defined non-core profiles until their install behavior has P0/P4 coverage, and add a contract for `assistant-dev`.
- Fixed in round:
  - Added installer rejection for boundary-only profiles other than `assistant-core`.
  - Added `installer rejects boundary-only plugin profiles without scaffold support` to `tests/p0-p4/installer-contracts.sh`.
- Validation after fix:
  - `bash tests/p0-p4/installer-contracts.sh` passed 16 checks.
  - `bash tests/p0-p4/plugin-boundary-contracts.sh` passed 6 checks.
  - `bash tests/test-p0-p4-contracts.sh` passed 128 checks after removing regenerated `tests/.DS_Store`.
  - `git diff --check` passed.
  - `find tests -type f -name .DS_Store -print` produced no output.

### Quality Review #2
- Result: CLEAN
- Rubric required: true
- Rubric scores:
  | Dimension | Score | Weight | Justification |
  |---|---:|---:|---|
  | Correctness | 5.0 | 0.30 | `assistant-core` installs only the four core skills, default/single-skill behavior remains covered, and non-core profiles are rejected until tested. |
  | Code Quality | 5.0 | 0.20 | Profile parsing and filtering are localized, shell-compatible, and covered by focused contracts. |
  | Architecture | 5.0 | 0.20 | The boundary doc remains the ownership source while manifests and skill moves remain absent. |
  | Security | 5.0 | 0.15 | No security-sensitive runtime surface was introduced. |
  | Test Coverage | 5.0 | 0.15 | RED/GREEN installer contracts, boundary contracts, aggregate P0/P4, and final hygiene checks are clean. |
  | Weighted | 5.00 | 1.00 | PASS. |
- Findings: none.
- Remaining items: none.

### Final Review Result
- Result: ISSUES_FIXED
- Rounds: 2
- Spec review result: PASS
- Quality review result: CLEAN

### Spec Review #2
- Result: PASS
- Scope reviewed: user correction to remove Unity-specific installer exclusions; `install.sh`; installer contracts; plugin architecture docs; context/task journal.
- Missing acceptance criteria: none.
- Extra scope: none; `assistant-core` remains the only installable plugin profile, and unsupported profiles use the same generic boundary-only rejection.
- Changed files mismatch: none.
- Verification evidence mismatch: none.
- Required fixes: none.

### Quality Review #3
- Result: CLEAN
- Rubric required: true
- Rubric scores:
  | Dimension | Score | Weight | Justification |
  |---|---:|---:|---|
  | Correctness | 5.0 | 0.30 | `install.sh` no longer contains Unity-specific exclusions, while `assistant-core` profile behavior and generic boundary-only rejection remain intact. |
  | Code Quality | 5.0 | 0.20 | The profile gate is simpler and profile payload filtering is generic for non-assistant ownership entries. |
  | Architecture | 5.0 | 0.20 | Default install behavior is pattern-based, so custom assistant-named skills can be added without installer name bans. |
  | Security | 5.0 | 0.15 | No secret, network, auth, or permission surface changed. |
  | Test Coverage | 5.0 | 0.15 | Contracts now assert no Unity hardcoding, custom assistant-named skill inclusion, focused installer behavior, and aggregate P0/P4 cleanliness. |
  | Weighted | 5.00 | 1.00 | PASS. |
- Findings: none.
- Remaining items: none.

### Final Review Result After User Correction
- Result: CLEAN
- Rounds: 1
- Spec review result: PASS
- Quality review result: CLEAN

## Documentation / Closeout
- `install.sh` now supports `--plugin assistant-core`.
- `install.sh` keeps `--skill` and `--plugin` mutually exclusive.
- `install.sh` rejects boundary-only profiles such as `assistant-dev` and `assistant-unity` through the same generic not-installable profile gate until they have install coverage.
- `install.sh` does not hardcode Unity-specific exclusions; assistant-named custom Unity skills follow the normal `skills/assistant-*` inventory rule.
- README documents the first profile install while preserving root `skills/assistant-*` as the default inventory.
- `docs/plugin-architecture.md` records `current_plugin_profile: assistant-core via --plugin assistant-core` and still states no plugin manifests exist yet.
- No skill directories moved, no plugin manifests were added, and hook behavior remains unchanged.

## Final Verification
- RED evidence: `bash tests/p0-p4/installer-contracts.sh` failed on new `--plugin` tests before implementation.
- `bash tests/p0-p4/installer-contracts.sh` - passed; 16 checks after removing Unity-specific installer rejection.
- `bash tests/p0-p4/plugin-boundary-contracts.sh` - passed; 6 checks.
- `bash tests/test-p0-p4-contracts.sh` - first rerun failed because the temporary assistant-named fixture leaked into later aggregate suites; fixed with immediate fixture cleanup.
- `bash tests/test-p0-p4-contracts.sh` - passed; 128 checks after fixture cleanup.
- `git diff --check` - passed.
- `find tests -type f -name .DS_Store -print` - passed with no output.
- `find skills -maxdepth 1 \( -name 'assistant-unity-contract-fixture-*' -o -name 'unity-contract-fixture-*' \) -print` - passed with no output.

## Component Verification Ledger
| Component | Status | Command / Evidence | Criteria |
|---|---|---|---|
| 1. Installer Profile Contracts | VERIFIED | RED: `bash tests/p0-p4/installer-contracts.sh` failed on new `--plugin` tests before implementation. GREEN: same command passed 16 checks after implementation and correction. | RED/GREEN evidence captured; contracts cover dry-run, real install, generic boundary-only rejection, no Unity hardcoding, assistant-named custom skill inclusion, and `--skill`/`--plugin` conflict. |
| 2. Installer Plugin Profile Support | VERIFIED | `bash tests/p0-p4/installer-contracts.sh` passed; `bash tests/test-p0-p4-contracts.sh` passed 128 checks after fixture cleanup. | Installer supports `--plugin assistant-core` from plugin boundary map without changing default or single-skill behavior. |
| 3. Docs And Boundary Drift Updates | VERIFIED | `bash tests/p0-p4/plugin-boundary-contracts.sh` passed 6 checks; `git diff --check` passed; `find tests -type f -name .DS_Store -print` produced no output. | README and plugin architecture docs describe optional profile support without claiming manifests, moved skills, or Unity-specific installer exclusions. |
