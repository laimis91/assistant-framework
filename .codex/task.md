# Task Journal

Task: Assistant-core manifest dry-run validation
Status: DONE
Current phase: DOCUMENT COMPLETE
Triaged as: medium

Clarification status: ready
Clarification defaults applied: false
Unresolved clarification topics:

## Requirements
- Add manifest-aware validation for `./install.sh --agent codex --plugin assistant-core --dry-run`.
- Print the assistant-core manifest path in dry-run output.
- Validate manifest `name`, `skills`, and plugin-local skill copies against the active `assistant-core` profile boundary.
- Reject manifest drift during dry-run with a clear error.
- Keep real `--plugin assistant-core` installs root-inventory based.
- Do not add marketplace registration.

## Constraints
- Do not change default install behavior.
- Do not move root `skills/assistant-*` directories.
- Do not make plugin-local skill copies the real install source yet.
- Do not add plugin manifests for other planned plugins.
- Keep Unity handling pattern-based and avoid installer-specific Unity exclusions.

## Discovery Notes
- `install.sh` previously resolved `--plugin assistant-core` only from `docs/plugin-architecture.md`.
- `plugins/assistant-core/.codex-plugin/plugin.json` exists and points at `./skills/`.
- Dry-run output previously listed selected root skills but did not mention or validate the plugin manifest.
- Real profile installs already install only the four core root skills and generate four Codex AGENTS rows.

## Requirements Restatement
Make the assistant-core installer dry-run aware of the scaffolded Codex plugin manifest without changing real install behavior or marketplace distribution.

## Component Manifest
Approval status: approved by user via "ok commit and continue" on 2026-05-08.

### Component 1: Dry-Run Manifest Contracts
- **What:** Extend installer and manifest P0/P4 contracts for dry-run manifest path output, manifest validation, drift rejection, and docs.
- **Files:** modify `tests/p0-p4/installer-contracts.sh`; modify `tests/p0-p4/plugin-manifest-contracts.sh`.
- **Depends on:** committed assistant-core manifest scaffold.
- **Verification criteria:**
  - [x] RED: `bash tests/p0-p4/installer-contracts.sh` fails before implementation on missing dry-run manifest output and drift rejection.
  - [x] RED: `bash tests/p0-p4/plugin-manifest-contracts.sh` fails before docs mention manifest-aware dry-run validation.
  - [x] GREEN: focused installer and plugin manifest suites pass after implementation.

### Component 2: Installer Dry-Run Validation
- **What:** Add `install.sh` helper functions to locate and validate the assistant-core plugin manifest during dry-run.
- **Files:** modify `install.sh`.
- **Depends on:** Component 1.
- **Verification criteria:**
  - [x] Dry-run prints `Plugin manifest: <repo>/plugins/assistant-core/.codex-plugin/plugin.json`.
  - [x] Dry-run validates `name: assistant-core`.
  - [x] Dry-run validates `skills: ./skills/`.
  - [x] Dry-run validates plugin-local skill copies match the active profile boundary.
  - [x] Real `--plugin assistant-core` install output does not print plugin manifest metadata.

### Component 3: Documentation And Closeout
- **What:** Update README, plugin architecture docs, context map, and task journal for manifest-aware dry-run validation.
- **Files:** modify `README.md`; modify `docs/plugin-architecture.md`; modify `.codex/context-map.md`; modify `.codex/task.md`.
- **Depends on:** Components 1 and 2.
- **Verification criteria:**
  - [x] Docs mention manifest-aware dry-run validation.
  - [x] Aggregate P0/P4 passes.
  - [x] Hygiene checks pass.

## Plan
Plan approval: yes, approved by user via "ok commit and continue" on 2026-05-08.

## Build Progress
- Component 1: Dry-Run Manifest Contracts - DONE.
- Component 2: Installer Dry-Run Validation - DONE.
- Component 3: Documentation And Closeout - DONE.

## Tests to run
- `bash tests/p0-p4/installer-contracts.sh`
- `bash tests/p0-p4/plugin-manifest-contracts.sh`
- `bash tests/test-p0-p4-contracts.sh`
- `bash install.sh --agent codex --plugin assistant-core --no-hooks --dry-run`
- Real install smoke with temp `HOME`
- `git diff --check`
- `find tests -type f -name .DS_Store -print`

## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved dry-run validation plan; `install.sh`; installer contracts; plugin manifest contracts; README and plugin architecture docs; context/task journal.
- Missing acceptance criteria: none.
- Extra scope: none; real install source remains root inventory and marketplace registration remains absent.
- Changed files mismatch: none.
- Verification evidence mismatch: none.
- Required fixes: none.

### Quality Review #1
- Result: ISSUES_FOUND
- Rubric required: true
- Rubric scores:
  | Dimension | Score | Weight | Justification |
  |---|---:|---:|---|
  | Correctness | 4.5 | 0.30 | Dry-run validation passed, but first implementation printed manifest metadata for real profile installs too. |
  | Code Quality | 5.0 | 0.20 | Manifest validation helpers are localized and focused on profile dry-run behavior. |
  | Architecture | 4.5 | 0.20 | Real installs stayed root-inventory based, but real install output needed to remain unchanged for scope precision. |
  | Security | 5.0 | 0.15 | No secret, network, auth, or permission surface was added. |
  | Test Coverage | 5.0 | 0.15 | Tests cover dry-run happy path, drift rejection, docs, focused suites, aggregate P0/P4, and real install output. |
  | Weighted | 4.75 | 1.00 | REFINE due to one dry-run-only scope issue. |
- Findings:
  - SHOULD-FIX: `install.sh` printed `Plugin manifest:` for real `--plugin assistant-core` installs. Risk category: unsafe change surface. Fix: print the manifest path only when `DRY_RUN=true`, preserving real install output.
- Fixed in round:
  - Limited the manifest output line to dry-run mode.
  - Added an ad hoc real install smoke check with a temp `HOME` to assert real install output does not print `Plugin manifest:`.
- Validation after fix:
  - `bash tests/p0-p4/installer-contracts.sh` passed 17 checks.
  - `bash tests/p0-p4/plugin-manifest-contracts.sh` passed 4 checks.
  - Real install smoke check passed.
  - `git diff --check` passed.
  - `bash tests/test-p0-p4-contracts.sh` passed 133 checks.

### Quality Review #2
- Result: CLEAN
- Rubric required: true
- Rubric scores:
  | Dimension | Score | Weight | Justification |
  |---|---:|---:|---|
  | Correctness | 5.0 | 0.30 | Dry-run now validates manifest metadata and plugin-local copies while real install output remains unchanged. |
  | Code Quality | 5.0 | 0.20 | Validation logic is small, named, and uses structured JSON parsing through `jq`. |
  | Architecture | 5.0 | 0.20 | The installer gains scaffold validation without changing install source, plugin registration, or default inventory. |
  | Security | 5.0 | 0.15 | No sensitive runtime surface was introduced. |
  | Test Coverage | 5.0 | 0.15 | Focused and aggregate suites are clean, with explicit drift and real-install smoke coverage. |
  | Weighted | 5.00 | 1.00 | PASS. |
- Findings: none.
- Remaining items: none.

### Final Review Result
- Result: ISSUES_FIXED
- Rounds: 2
- Spec review result: PASS
- Quality review result: CLEAN

## Documentation / Closeout
- `install.sh` now locates `plugins/assistant-core/.codex-plugin/plugin.json` for `--plugin assistant-core --dry-run`.
- Dry-run validates manifest `name`, `skills: ./skills/`, and plugin-local skill copies against the active profile boundary.
- Dry-run rejects manifest drift, including missing `skills` metadata.
- Real `--plugin assistant-core` installs remain root-inventory based and do not print plugin manifest metadata.
- README and `docs/plugin-architecture.md` describe manifest-aware dry-run validation.
- No marketplace registration or additional plugin manifests were added.

## Final Verification
- RED evidence: `bash tests/p0-p4/installer-contracts.sh` failed 2 new checks before implementation.
- RED evidence: `bash tests/p0-p4/plugin-manifest-contracts.sh` failed 1 new docs check before implementation.
- `bash tests/p0-p4/installer-contracts.sh` - passed; 17 checks.
- `bash tests/p0-p4/plugin-manifest-contracts.sh` - passed; 4 checks.
- `bash tests/test-p0-p4-contracts.sh` - first run failed only because regenerated `tests/.DS_Store` tripped hygiene/direct-run gates.
- `bash tests/test-p0-p4-contracts.sh` - passed; 133 checks after removing regenerated `tests/.DS_Store`.
- `bash install.sh --agent codex --plugin assistant-core --no-hooks --dry-run` - printed manifest path and validation lines.
- Real install smoke with temp `HOME` - passed; output does not include `Plugin manifest:`.
- `jq -e '.name == "assistant-core" and .skills == "./skills/"' plugins/assistant-core/.codex-plugin/plugin.json` - passed.
- `git diff --check` - passed.
- `find tests -type f -name .DS_Store -print` - passed with no output.

## Component Verification Ledger
| Component | Status | Command / Evidence | Criteria |
|---|---|---|---|
| 1. Dry-Run Manifest Contracts | VERIFIED | RED: focused installer and manifest suites failed before implementation. GREEN: `bash tests/p0-p4/installer-contracts.sh` passed 17 checks and `bash tests/p0-p4/plugin-manifest-contracts.sh` passed 4 checks. | Contracts cover manifest path output, validation lines, drift rejection, and docs. |
| 2. Installer Dry-Run Validation | VERIFIED | Dry-run command printed manifest validation lines; real install smoke omitted `Plugin manifest:`. | Dry-run validates manifest metadata and plugin-local copies without changing real install behavior. |
| 3. Documentation And Closeout | VERIFIED | `bash tests/test-p0-p4-contracts.sh` passed 133 checks; `git diff --check` passed; `.DS_Store` hygiene passed. | Docs and journal describe manifest-aware dry-run validation and preserve marketplace absence. |
