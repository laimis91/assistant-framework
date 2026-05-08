# Task Journal

Task: Runtime phase-gate enforcement
Status: DONE
Current phase: DOCUMENT COMPLETE
Triaged as: medium

Clarification status: ready
Clarification defaults applied: false
Unresolved clarification topics:

## Requirements
- Add runtime phase-gate enforcement so active task journals produce actionable hook feedback before agents skip required workflow gates.
- Keep the slice bounded to the existing hook/runtime path and avoid a broad generic YAML contract interpreter in this iteration.
- Include tests with implementation and update docs that describe the runtime hook behavior.

## Constraints
- Preserve completed journal suppression for `Status: DONE`, `Status: DOCUMENTED`, and `--- WORKFLOW COMPLETE ---`.
- Preserve provider-specific hook behavior for Codex, Claude, and Gemini.
- Keep user custom hook behavior untouched.
- Do not use destructive cleanup commands.
- Subagent dispatch is unavailable unless explicitly requested in this environment, so context mapping and planning are recorded locally.

## Discovery Notes
- `workflow-enforcer.sh` already injects prompt-time workflow state and has clarification/plan/review reminders.
- `stop-review.sh` blocks completion when active build/review statuses lack structured Spec Review, Quality Review, final result, or metrics.
- `harness-gate.sh` blocks medium+ active build/review statuses without approved plan or rubric scoring.
- Current runtime checks are concentrated around BUILD/REVIEW; earlier phase gates such as component approval and later DOCUMENTING completion are only lightly represented.
- Agent readiness: 4/5. Documented install/test paths, a shell test suite, agent orientation docs, and runtime hook artifacts exist; no obvious lint/editorconfig baseline was found.

## Component Manifest
Approval status: approved by user on 2026-05-08

### Component 1: Shared Phase-Gate Runtime Helpers
- **What:** Add a small shared shell helper for parsing task journal phase-gate evidence and returning normalized yes/no state. Keep this targeted to fields the hooks already depend on rather than building a generic YAML contract interpreter.
- **Files:** `hooks/scripts/workflow-phase-gates.sh`; tests in `tests/test-hooks.sh`.
- **Depends on:** none.
- **Verification criteria:**
  - [ ] Helper reports medium+ task size, phase status, plan approval, decomposition approval, review completion, and metrics markers from representative task journals.
  - [ ] Helper treats completed journals as out of scope through existing resolver behavior, not by reintroducing stale completed-state injection.

### Component 2: Prompt-Time Gate Warnings
- **What:** Extend `workflow-enforcer.sh` to inject a concise `RUNTIME PHASE GATES` section for the active phase, including explicit warnings for missing component approval before planning/building, missing plan approval before building, incomplete review before documenting, and missing metrics before completion.
- **Files:** `hooks/scripts/workflow-enforcer.sh`; tests in `tests/test-hooks.sh`.
- **Depends on:** Component 1.
- **Verification criteria:**
  - [ ] `DECOMPOSING`, `PLANNING`, `BUILDING`, `REVIEWING`, and `DOCUMENTING` journals produce phase-specific runtime gate output.
  - [ ] Small tasks do not receive medium+ component-approval warnings.
  - [ ] Existing clarification gate warnings still render unchanged for pending or contradictory clarification state.

### Component 3: Stop-Time Documenting Gate Coverage
- **What:** Harden stop-time enforcement so an active `DOCUMENTING` task cannot stop if review or metrics evidence is incomplete, while completed task journals continue to be ignored.
- **Files:** `hooks/scripts/stop-review.sh`, `hooks/scripts/harness-gate.sh`; tests in `tests/test-hooks.sh`.
- **Depends on:** Component 1.
- **Verification criteria:**
  - [ ] `DOCUMENTING` with missing structured review blocks/retries through the existing review reason path.
  - [ ] `DOCUMENTING` with complete review but missing metrics blocks/retries through the existing metrics reason path.
  - [ ] `Status: DONE` and `--- WORKFLOW COMPLETE ---` journals remain non-blocking.

### Component 4: Runtime Contract Docs And P0-P4 Coverage
- **What:** Update docs and P0-P4 contracts so runtime phase-gate enforcement is visible and guarded from drift.
- **Files:** `README.md`, `docs/skill-contract-design-guide.md`, likely new `tests/p0-p4/runtime-phase-gate-contracts.sh`, `tests/test-p0-p4-contracts.sh`.
- **Depends on:** Components 1-3.
- **Verification criteria:**
  - [ ] README hook table names workflow enforcer, workflow guard, stop review, and harness gate accurately.
  - [ ] Contract design guide reflects that Level 3 now includes runtime phase-gate enforcement beyond review completion.
  - [ ] P0-P4 suite checks for the new runtime helper/hook/doc contract strings.

## Plan
Plan approval: yes, approved by user on 2026-05-08

## Goal
- Add runtime phase-gate enforcement to the existing hook path so active task journals produce actionable feedback before workflow gates are skipped.
- Keep this slice focused on shell hooks and contract tests; do not implement a generic YAML phase-gate interpreter.

## Constraints & decisions from Discovery
- Completed journal suppression must remain intact for `Status: DONE`, `Status: DOCUMENTED`, and `--- WORKFLOW COMPLETE ---`.
- Existing Codex, Claude, and Gemini hook semantics must remain compatible.
- Runtime enforcement should build on the active task journal and existing resolver/cache behavior.
- Current environment does not allow subagent dispatch unless explicitly requested, so implementation and verification will be performed locally under the approved task packets.
- Non-goal: enforce every natural-language assertion in `phase-gates.yaml` at runtime in this slice.

## Research
- Prompt-time runtime context lives in `hooks/scripts/workflow-enforcer.sh`.
- Stop-time lifecycle enforcement lives in `hooks/scripts/stop-review.sh` and `hooks/scripts/harness-gate.sh`.
- Active task journal resolution and completed-state suppression live in `hooks/scripts/task-journal-resolver.sh`.
- Source hook tests live in `tests/test-hooks.sh`.
- Aggregate P0/P4 contracts are sourced from `tests/test-p0-p4-contracts.sh`.
- Public docs that need alignment are `README.md`, `docs/skill-contract-design-guide.md`, and likely `docs/harness-design-guide.md`.

## Architecture
- Current architecture: shell hook scripts parse `.codex/.claude/.gemini/task.md` directly and emit JSON hook responses.
- Architecture for this change: add a focused shared shell helper for phase-gate state, then source it from prompt-time and stop-time hooks.
- Layer rules:
  - `task-journal-resolver.sh` remains responsible for finding and suppressing completed journals.
  - `workflow-phase-gates.sh` owns journal evidence parsing for runtime phase gates.
  - `workflow-enforcer.sh` owns prompt-time context text.
  - `stop-review.sh` and `harness-gate.sh` own stop/after-agent blocking decisions.
  - P0/P4 contracts guard docs and hook drift; `tests/test-hooks.sh` guards behavior.
- Dependency direction: resolver -> phase-gate helper -> runtime hooks -> tests/docs.
- SOLID design notes:
  - SRP: parsing helpers, prompt context, and stop decisions stay separate.
  - OCP: new runtime gate checks should be added as helper functions and hook tests without duplicating parser logic.
  - DIP: tests assert hook behavior and helper outputs, not internal implementation details beyond the public helper file existing.

## Analysis
### Options
1. Add warnings directly in `workflow-enforcer.sh` only. Fast, but increases parser duplication and does not harden stop-time `DOCUMENTING`.
2. Add a shared phase-gate helper and wire it into existing hooks. Slightly more work, lower drift risk.
3. Build a full runtime interpreter for `contracts/phase-gates.yaml`. More complete long term, too broad and brittle for this slice.

### Decision
- Chosen: option 2. It gives actual runtime enforcement while keeping scope reviewable.

### Risks / edge cases
- Duplicating review parsing can diverge from `stop-review.sh`; mitigate by moving reusable review-state checks into the helper.
- `DOCUMENTING` stop-time enforcement can accidentally block completed journals; mitigate by relying on the existing resolver/completed-journal behavior and adding regression tests.
- Prompt-time warnings can become noisy; mitigate with concise phase-specific output instead of dumping all gates every prompt.
- Metrics checks are date-sensitive; tests must use the current date and isolated `TEST_AGENT_HOME`.

## Task packets

### Task 1: Shared phase-gate helper
- Behavior / acceptance criteria:
  - Helper exposes task size, medium+ detection, current status, component approval, plan approval, review completion, and metrics-today checks.
  - Existing stop-review structured review parsing is reusable without changing accepted review formats.
  - Completed journal handling stays owned by `task-journal-resolver.sh`.
- Files:
  - Create: `hooks/scripts/workflow-phase-gates.sh`.
  - Modify: `hooks/scripts/stop-review.sh` as needed to consume shared review helpers.
  - Test: `tests/test-hooks.sh`.
- TDD / RED step:
  - Applies: no.
  - RED command: N/A.
  - Expected failure: N/A.
- Implementation notes / constraints:
  - Keep helper functions shell-only and dependency-light.
  - Do not source `task-journal-resolver.sh` from the helper; callers already resolve the active task journal.
  - Preserve current structured Spec Review PASS semantics.
- Verification:
  - Command: `bash tests/test-hooks.sh --filter "stop-review"`
  - Expected success signal: stop-review tests pass with existing review formats.
- Deviation / rollback rule:
  - If shared extraction risks changing review semantics, keep stop-review parsing local and limit the helper to new phase-gate fields.
- Worker status / evidence:
  - Status: pending
  - Evidence: pending

### Task 2: Prompt-time runtime phase gates
- Behavior / acceptance criteria:
  - `workflow-enforcer.sh` emits a concise `RUNTIME PHASE GATES` section for active task journals.
  - Medium+ `PLANNING`/`BUILDING` warns when component decomposition is not approved.
  - Medium+ `BUILDING` warns when plan approval is missing.
  - `REVIEWING` and `DOCUMENTING` warn when structured review completion is missing.
  - `DOCUMENTING` warns when metrics for today are missing.
  - Existing clarification warnings still render for pending, missing, or contradictory clarification state.
- Files:
  - Create: none beyond Task 1 helper.
  - Modify: `hooks/scripts/workflow-enforcer.sh`.
  - Test: `tests/test-hooks.sh`.
- TDD / RED step:
  - Applies: no.
  - RED command: N/A.
  - Expected failure: N/A.
- Implementation notes / constraints:
  - Keep output actionable and short.
  - Do not warn small tasks about component approval.
  - Keep no-task/completed-task behavior as lightweight rules only.
- Verification:
  - Command: `bash tests/test-hooks.sh --filter "workflow-enforcer"`
  - Expected success signal: workflow-enforcer tests pass, including new phase-gate warning cases.
- Deviation / rollback rule:
  - If gate text causes brittle tests, assert stable gate labels and key warnings rather than whole paragraphs.
- Worker status / evidence:
  - Status: pending
  - Evidence: pending

### Task 3: Stop-time DOCUMENTING enforcement
- Behavior / acceptance criteria:
  - `stop-review.sh` blocks/retries active `DOCUMENTING` tasks with missing Spec Review, Quality Review, final result, or metrics.
  - `harness-gate.sh` treats active `DOCUMENTING` medium+ tasks as lifecycle-active for plan/rubric/score checks.
  - Completed journals remain non-blocking.
- Files:
  - Create: none.
  - Modify: `hooks/scripts/stop-review.sh`, `hooks/scripts/harness-gate.sh`.
  - Test: `tests/test-hooks.sh`.
- TDD / RED step:
  - Applies: no.
  - RED command: N/A.
  - Expected failure: N/A.
- Implementation notes / constraints:
  - Reuse existing reason messages where possible.
  - Preserve Claude block and Gemini retry behavior, including loop guards.
- Verification:
  - Command: `bash tests/test-hooks.sh --filter "DOCUMENTING"`
  - Expected success signal: new documenting tests pass for missing review, missing metrics, and completed journal bypass.
- Deviation / rollback rule:
  - If `DOCUMENTING` proves too broad for harness scoring, keep plan/rubric checks on build/review only and document why; stop-review metrics/review coverage remains required.
- Worker status / evidence:
  - Status: pending
  - Evidence: pending

### Task 4: Runtime docs and P0/P4 contracts
- Behavior / acceptance criteria:
  - README hook table accurately names workflow enforcer, workflow guard, stop review, and harness gate.
  - Contract design guide states Level 3 now includes runtime phase-gate enforcement beyond review completion.
  - Harness docs mention `DOCUMENTING` lifecycle coverage if stop-time behavior changes.
  - P0/P4 contracts assert the helper exists, hooks source it, docs describe runtime phase gates, and aggregate P0/P4 includes the new suite.
- Files:
  - Create: `tests/p0-p4/runtime-phase-gate-contracts.sh`.
  - Modify: `tests/test-p0-p4-contracts.sh`, `README.md`, `docs/skill-contract-design-guide.md`, `docs/harness-design-guide.md`.
  - Test: `tests/p0-p4/runtime-phase-gate-contracts.sh`.
- TDD / RED step:
  - Applies: no.
  - RED command: N/A.
  - Expected failure: N/A.
- Implementation notes / constraints:
  - Docs should describe enforced behavior, not aspirational future behavior.
  - Keep P0/P4 checks focused on stable contract strings and source wiring.
- Verification:
  - Command: `bash tests/p0-p4/runtime-phase-gate-contracts.sh && bash tests/test-p0-p4-contracts.sh`
  - Expected success signal: direct and aggregate contract suites pass.
- Deviation / rollback rule:
  - If aggregate P0/P4 runtime is noisy, keep direct suite strict and add only one aggregate inclusion assertion.
- Worker status / evidence:
  - Status: pending
  - Evidence: pending

## Tests to run
- `bash tests/test-hooks.sh --filter "workflow-enforcer"`
- `bash tests/test-hooks.sh --filter "stop-review"`
- `bash tests/test-hooks.sh --filter "harness-gate"`
- `bash tests/test-hooks.sh --filter "DOCUMENTING"`
- `bash tests/p0-p4/runtime-phase-gate-contracts.sh`
- `bash tests/test-p0-p4-contracts.sh`
- `git diff --check`

## Build Progress
- Task 1: Shared phase-gate helper — DONE.
- Task 2: Prompt-time runtime phase gates — DONE.
- Task 3: Stop-time DOCUMENTING enforcement — DONE.
- Task 4: Runtime docs and P0/P4 contracts — DONE.

## Component Verification Ledger
| Component | Status | Command / Evidence | Criteria |
|---|---|---|---|
| 1. Shared Phase-Gate Runtime Helpers | VERIFIED | `bash tests/test-hooks.sh --filter "workflow-phase-gates"` passed 3/3; `bash -n hooks/scripts/workflow-phase-gates.sh hooks/scripts/stop-review.sh hooks/scripts/harness-gate.sh tests/test-hooks.sh` passed. | Helper reports medium+ task size, component approval, plan approval, review completion, missing-review reason, and metrics-today state; regression rejects `Approval status: not approved`. |
| 2. Prompt-Time Gate Warnings | VERIFIED | `bash tests/test-hooks.sh --filter "workflow-enforcer"` passed 34/34. | `RUNTIME PHASE GATES` renders; medium PLANNING without component approval warns; small PLANNING does not warn; REVIEWING incomplete review warns; DOCUMENTING missing metrics warns; clarification warnings remain covered. |
| 3. Stop-Time Documenting Gate Coverage | VERIFIED | `bash tests/test-hooks.sh --filter "stop-review"` passed 33/33; `bash tests/test-hooks.sh --filter "harness-gate"` passed 3/3; `bash tests/test-hooks.sh --filter "DOCUMENTING"` passed 6/6. | DOCUMENTING without review blocks; DOCUMENTING complete review without metrics blocks; DOCUMENTING review+metrics allows; harness gate blocks medium DOCUMENTING without plan approval and allows scored review. |
| 4. Runtime Contract Docs And P0-P4 Coverage | VERIFIED | `bash tests/p0-p4/runtime-phase-gate-contracts.sh` passed 5/5; `bash tests/test-p0-p4-contracts.sh` passed 114/114. | README, contract guide, harness guide, helper wiring, installer dependency, and aggregate P0/P4 inclusion are covered. |

## Review Log
- Build verification:
  - `bash tests/test-hooks.sh`: passed 130/130.
  - `bash tests/test-p0-p4-contracts.sh`: passed 114/114.
  - `git diff --check`: passed.
- Changed files:
  - `hooks/scripts/workflow-phase-gates.sh` created.
  - `hooks/scripts/workflow-enforcer.sh` modified.
  - `hooks/scripts/stop-review.sh` modified.
  - `hooks/scripts/harness-gate.sh` modified.
  - `install.sh` modified.
  - `tests/test-hooks.sh` modified.
  - `tests/p0-p4/runtime-phase-gate-contracts.sh` created.
  - `tests/p0-p4/codex-hook-reinstall-contracts.sh` modified.
  - `tests/test-p0-p4-contracts.sh` modified.
  - `README.md` modified.
  - `docs/skill-contract-design-guide.md` modified.
  - `docs/harness-design-guide.md` modified.
  - `.codex/task.md` and `.codex/context-map.md` updated as workflow artifacts.
- Plan deviation:
  - `install.sh` and `tests/p0-p4/codex-hook-reinstall-contracts.sh` were added to the change set because the new sourced helper must be copied and cleaned up with installed Codex hooks. This was disclosed during Review and verified by install/reinstall tests.
### Spec Review #1: runtime phase-gate enforcement
  - Result: PASS
  - Scope reviewed: Components 1-4 from the approved decomposition and task packets.
  - Missing acceptance criteria: none.
  - Extra scope: none. Installer dependency handling is in-scope support for the new sourced hook helper and is covered by install/reinstall tests.
  - Changed files mismatch: none remaining. `install.sh` and `tests/p0-p4/codex-hook-reinstall-contracts.sh` were required support files for installed-hook behavior and are recorded as a plan deviation above.
  - Verification evidence mismatch: none. Full hook suite, aggregate P0/P4 suite, runtime phase-gate contract suite, focused hook filters, and diff hygiene evidence are recorded above.
  - Required fixes: none.
### Quality Review #1
  - Result: CLEAN
  - Rubric: correctness 4.5, code_quality 4.0, architecture 4.5, security 5.0, test_coverage 4.5
  - Weighted: 4.48
  - Findings: none.
  - Notes: The broad `Approved by user on` component-approval fallback was removed during manual review before this round and covered with a `not approved` regression test.

## Metrics
- Appended `/Users/laimis/.codex/memory/metrics/workflow-metrics.jsonl` entry:
  - date: 2026-05-08
  - task: runtime phase-gate enforcement
  - size: medium
  - review_rounds: 1
  - plan_deviations: 1
  - build_failures: 0
  - components_verified: 4

## Verification Summary
- Changed files:
  - `hooks/scripts/workflow-phase-gates.sh` created as shared runtime phase-gate helper.
  - `hooks/scripts/workflow-enforcer.sh` updated with prompt-time runtime phase gate state and warnings.
  - `hooks/scripts/stop-review.sh` updated to use shared review/metrics helpers and enforce `DOCUMENTING`.
  - `hooks/scripts/harness-gate.sh` updated to use shared status/plan helpers and enforce `DOCUMENTING`.
  - `install.sh` updated to install and clean the new helper for Codex hooks.
  - `tests/test-hooks.sh` expanded with helper, runtime warning, DOCUMENTING, harness, and installer dependency coverage.
  - `tests/p0-p4/runtime-phase-gate-contracts.sh` added and aggregate P0/P4 wiring updated.
  - README and contract/harness docs updated to describe runtime phase-gate enforcement.
- Tests:
  - `bash tests/test-hooks.sh`: passed 130/130.
  - `bash tests/test-p0-p4-contracts.sh`: passed 114/114.
  - `git diff --check`: passed.
  - Real task-journal smoke: `stop-review.sh` and `harness-gate.sh` produced no block output for this completed review/metrics state.
- Manual test steps:
  - Run `bash tests/test-hooks.sh --filter "workflow-phase-gates"`.
  - Run `bash tests/test-hooks.sh --filter "DOCUMENTING"`.
  - Run `bash tests/p0-p4/runtime-phase-gate-contracts.sh`.

--- WORKFLOW COMPLETE ---
