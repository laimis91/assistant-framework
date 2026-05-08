# Task Journal

Status: DONE
Current phase: DOCUMENT COMPLETE

## Task

Implement the next Assistant Framework improvement slice from skill ecosystem research: add provider-neutral per-skill eval fixtures and runner support on top of the first-class skill validator.

## Input Contract

- Task type: feature
- Scope hint: auto
- Clarification status: ready
- Clarification defaults applied: false
- Unresolved clarification topics: none

## Constraints

- Keep evals offline and provider-neutral; do not add provider SDK, network, or model API calls.
- Default per-skill eval inventory must align with first-class `skills/assistant-*` skills; `skills/unity-*` remains local-only.
- Build on existing shell and `jq` tooling; avoid new runtime dependencies.
- Do not edit implementation files before decomposition and plan approval.

## Discovery Notes

- Prior validator slice is committed as `892eb62 Add first-class skill validator`.
- Existing framework evals live in `docs/evals/framework-instruction-cases.json`.
- Existing eval runner is `tools/evals/run-framework-instruction-evals.sh`.
- Existing P0/P4 eval coverage is `tests/p0-p4/eval-contracts.sh`.
- No existing `skills/*/evals/*` files were found during initial discovery.
- Code Mapper was dispatched as Lorentz, then interrupted and closed after timeout without a returned map.
- Recovery context map was written to `.codex/context-map.md` from direct Discover evidence.
- Agent readiness: 4/5. Build/test entrypoints, tests, agent instructions, and workflow metrics exist; shell lint/editorconfig layer was not found.
- Requirements summary: add an offline per-skill eval path that complements the source validator, defaults to first-class `assistant-*` skills, excludes local-only Unity skills, and starts with a bounded pilot fixture set.

## Component Manifest

Approved by user on 2026-05-08.

Sub-agent note: Architect was dispatched as Aquinas for component decomposition, then interrupted and closed after timeout without a returned manifest. The manifest below is a recovery decomposition from `.codex/context-map.md` and direct Discover evidence.

### Component 1: Per-skill eval runner
- What: Add a reusable offline runner for per-skill eval fixtures, matching the existing framework eval command modes while supporting skill selection and first-class inventory defaults.
- Files: create `tools/evals/run-skill-evals.sh`; optionally create helper modules only if runner size demands it.
- Depends on: none.
- Verification criteria:
  - `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-clarify` exits 0 for a valid pilot fixture.
  - `tools/evals/run-skill-evals.sh --list --skill assistant-clarify` lists pilot case rows.
  - `tools/evals/run-skill-evals.sh --emit-prompts <dir> --skill assistant-clarify` writes one Markdown prompt packet per pilot case.
  - `tools/evals/run-skill-evals.sh --responses <dir> --skill assistant-clarify` fails missing/empty/expectation-violating responses and passes generated expectation-complete responses.

### Component 2: Pilot per-skill fixtures
- What: Add a small pilot set of skill-local eval fixtures for behavior that is easy to judge with local machine expectations.
- Files: create `skills/assistant-clarify/evals/cases.json`; create `skills/assistant-thinking/evals/cases.json`.
- Depends on: Component 1 schema.
- Verification criteria:
  - Pilot fixtures validate with non-empty suite metadata and case arrays.
  - Clarify fixture checks ambiguous prompt handling and structured brief output.
  - Thinking fixture checks tool-selection/methodology behavior and dissenting-view/confidence output.
  - Fixtures remain provider-neutral and contain no provider SDK/API/network assumptions.

### Component 3: P0/P4 eval contracts
- What: Add contract tests for the new per-skill eval runner, fixture schema, first-class inventory behavior, local-only exclusion, prompt emission, and response grading.
- Files: modify `tests/p0-p4/eval-contracts.sh` or create `tests/p0-p4/skill-eval-contracts.sh`; modify `tests/test-p0-p4-contracts.sh` if a new suite file is created.
- Depends on: Components 1 and 2.
- Verification criteria:
  - Direct skill-eval suite passes.
  - Aggregate `bash tests/test-p0-p4-contracts.sh` includes the skill-eval suite.
  - Default inventory checks do not require `skills/unity-*`.
  - Malformed fixture tests fail with clear schema errors.

### Component 4: Documentation and direction
- What: Document per-skill eval usage, pilot-scope intent, and how evals complement structural validation and future Level 4 conformance.
- Files: modify `docs/evals/README.md`; modify `docs/skill-contract-design-guide.md`; optionally modify `README.md`.
- Depends on: Components 1-3.
- Verification criteria:
  - Docs show validate/list/emit/responses examples for per-skill evals.
  - Docs state default scope and local-only Unity exclusion.
  - Docs distinguish heuristic local grading from human/LLM judgment.
  - Docs describe pilot fixtures as the first step toward broader per-skill coverage.

## Approved Plan

Approved by user on 2026-05-08. Plan:

## Goal
- Add an offline, provider-neutral per-skill eval path that can validate, list, emit prompts for, and locally grade skill-specific eval fixtures.
- Keep the first slice bounded to shared runner support plus two pilot first-class skills: `assistant-clarify` and `assistant-thinking`.

## Constraints & decisions
- Provider-neutral only: no SDK, endpoint, network, or model API calls.
- Default inventory remains first-class `skills/assistant-*`; local-only `skills/unity-*` is excluded unless explicitly requested.
- Pilot scope: do not require eval fixtures for all 15 first-class skills in this slice.
- Use existing shell plus `jq` tooling.
- Code Mapper and Architect were dispatched but timed out; recovery context/decomposition is recorded in this journal.

## Research
- Existing framework evals: `docs/evals/framework-instruction-cases.json`.
- Existing framework runner: `tools/evals/run-framework-instruction-evals.sh`.
- Existing eval contracts: `tests/p0-p4/eval-contracts.sh`.
- Skill source validator inventory logic: `tools/skills/validate-skills.sh`, `tools/skills/lib/validate-inventory.sh`.
- No existing `skills/*/evals/*` fixtures were found.

## Architecture
- Current architecture: shell-based offline validation and contract tests.
- Architecture for this change: add per-skill eval fixtures under each skill, a per-skill runner under `tools/evals`, and P0/P4 contracts.
- Layer rules:
  - Skill-local fixtures live with their owning skill.
  - Runner logic stays in `tools/evals`; tests stay in `tests/p0-p4`.
  - Docs explain usage and limits; docs do not define behavior not enforced by tests.
- Dependency direction: fixtures -> runner -> P0/P4 contracts/docs.
- SOLID design notes:
  - SRP: runner owns eval operations; fixtures own skill behavior cases; tests own regression assertions.
  - OCP: new skill eval coverage should be added by adding `skills/<skill>/evals/cases.json`, not by editing grading logic.
  - DIP: shell tests depend on command behavior and fixture schema, not internal helper implementation.

## Analysis
### Options
1. Duplicate the existing framework runner into a skill runner — fastest, but likely drifts.
2. Add a skill-specific runner with shared local helper functions for common emit/grade behavior — better maintainability with moderate scope.
3. Replace framework and skill eval runners with a larger generic runner — cleaner long term, too much for this slice.

### Decision
- Chosen: option 2. Keep the slice bounded while avoiding needless drift in the new code.

### Risks / edge cases
- Runner schema can accidentally imply all first-class skills must have evals now; mitigate by validating discovered fixtures and documenting pilot scope.
- Local-only Unity skills can leak into default inventory; test default exclusion with a generated local fixture.
- Heuristic substring grading can be mistaken for semantic evaluation; docs and output must label it as local proxy grading.
- Shell runner growth can become hard to review; split helper functions only if the implementation starts mixing unrelated responsibilities.

## Task packets

### Task 1: Per-skill eval runner
- Behavior / acceptance criteria:
  - `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-clarify` validates a skill-local fixture.
  - `--list` prints skill, case id, category, and title.
  - `--emit-prompts DIR` writes Markdown prompt packets under a skill-specific path.
  - `--responses DIR` locally grades captured responses using required/forbidden substring expectations.
  - Default inventory excludes local-only Unity skills.
- Files:
  - Create: `tools/evals/run-skill-evals.sh`; optional `tools/evals/lib/*.sh` if needed for SRP.
  - Modify: none expected.
  - Test: `tests/p0-p4/skill-eval-contracts.sh`.
- TDD / RED step:
  - Applies: no.
  - RED command: N/A.
  - Expected failure: N/A.
- Implementation notes / constraints:
  - Follow existing `tools/evals/run-framework-instruction-evals.sh` command style.
  - Keep all operations offline and provider-neutral.
  - Targeted `--skill` should accept a skill name, skill directory, or `SKILL.md` path where practical.
- Verification:
  - Command: `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-clarify`
  - Expected success signal: exit code 0 and a clear fixture-valid message.
- Deviation / rollback rule:
  - If generic runner extraction becomes larger than the slice, keep the framework runner unchanged and isolate reusable logic in the new skill runner only.
- Worker status / evidence:
  - Status: pending
  - Evidence: pending

### Task 2: Pilot skill fixtures
- Behavior / acceptance criteria:
  - `assistant-clarify` fixture checks ambiguous prompt interpretation, structured brief, clarifying questions/defaults, execution target, and status.
  - `assistant-thinking` fixture checks structured tool selection, methodology, recommendation, confidence, and dissenting view.
  - Both fixtures include non-empty machine expectations and provider-neutral metadata.
- Files:
  - Create: `skills/assistant-clarify/evals/cases.json`; `skills/assistant-thinking/evals/cases.json`.
  - Modify: none expected.
  - Test: `tests/p0-p4/skill-eval-contracts.sh`.
- TDD / RED step:
  - Applies: no.
  - RED command: N/A.
  - Expected failure: N/A.
- Implementation notes / constraints:
  - Keep cases small and behavior-focused; do not encode provider-specific wording.
  - Use deterministic substrings as proxy checks, not semantic grading.
- Verification:
  - Command: `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-thinking`
  - Expected success signal: exit code 0 and fixture-valid output.
- Deviation / rollback rule:
  - If a pilot skill proves hard to express deterministically, replace only that pilot with another first-class utility skill and record the reason.
- Worker status / evidence:
  - Status: pending
  - Evidence: pending

### Task 3: P0/P4 skill-eval contracts
- Behavior / acceptance criteria:
  - Direct skill-eval contracts pass.
  - Aggregate P0/P4 suite sources and runs the skill-eval contracts.
  - Malformed fixture cases fail with clear schema errors.
  - Missing/empty/expectation-violating response directories fail, and generated expectation-complete responses pass.
  - Generated local-only Unity fixture is not included by default.
- Files:
  - Create: `tests/p0-p4/skill-eval-contracts.sh`.
  - Modify: `tests/test-p0-p4-contracts.sh`.
  - Test: `tests/p0-p4/skill-eval-contracts.sh`.
- TDD / RED step:
  - Applies: no.
  - RED command: N/A.
  - Expected failure: N/A.
- Implementation notes / constraints:
  - Use unique `mktemp` fixture paths for any local-only skill tests and clean up only generated paths.
  - Reuse P0/P4 harness helpers.
- Verification:
  - Command: `bash tests/p0-p4/skill-eval-contracts.sh`
  - Expected success signal: all skill-eval contract tests pass with 0 failures.
- Deviation / rollback rule:
  - If aggregate runtime becomes noisy, keep the direct suite strict and add aggregate inclusion as a separate minimal assertion.
- Worker status / evidence:
  - Status: pending
  - Evidence: pending

### Task 4: Documentation
- Behavior / acceptance criteria:
  - Docs show per-skill eval validate/list/emit/responses commands.
  - Docs state pilot scope and first-class default inventory.
  - Docs state local-only Unity exclusion.
  - Docs explain heuristic local grading limits and Level 4 direction.
- Files:
  - Create: none.
  - Modify: `docs/evals/README.md`; `docs/skill-contract-design-guide.md`; `README.md`.
  - Test: `tests/p0-p4/skill-eval-contracts.sh`; `rg -n "run-skill-evals|per-skill|local-only|pilot|Level 4" README.md docs/evals/README.md docs/skill-contract-design-guide.md`.
- TDD / RED step:
  - Applies: no.
  - RED command: N/A.
  - Expected failure: N/A.
- Implementation notes / constraints:
  - Do not imply complete per-skill coverage until all skills have fixtures.
  - Keep examples provider-neutral.
- Verification:
  - Command: `rg -n "run-skill-evals|per-skill|local-only|pilot|Level 4" README.md docs/evals/README.md docs/skill-contract-design-guide.md`
  - Expected success signal: command finds expected documentation terms in all target docs.
- Deviation / rollback rule:
  - If README becomes too noisy, keep detailed examples in `docs/evals/README.md` and only link from README.
- Worker status / evidence:
  - Status: pending
  - Evidence: pending

## Tests to run
- `tools/evals/run-skill-evals.sh --validate-fixture`
- `tools/evals/run-skill-evals.sh --list`
- `tools/evals/run-skill-evals.sh --emit-prompts <tmpdir>`
- `tools/evals/run-skill-evals.sh --responses <tmpdir>`
- `tools/evals/run-framework-instruction-evals.sh --validate-fixture`
- `bash tests/p0-p4/skill-eval-contracts.sh`
- `bash tests/p0-p4/eval-contracts.sh`
- `bash tests/test-p0-p4-contracts.sh`
- `tools/skills/validate-skills.sh`
- `git diff --check`

## Component Verification Ledger

| Component | Status | Command / Evidence | Criteria |
|---|---|---|---|
| 1. Per-skill eval runner | VERIFIED | Builder/Tester Dalton: targeted clarify/thinking validation passed; default validation passed for 2 fixtures; list emitted 4 cases; emit wrote 4 prompt packets; generated response grading passed total=4 failed=0; `bash -n tools/evals/run-skill-evals.sh` passed. | Runner validates, lists, emits, grades, and stays provider-neutral/offline. |
| 2. Pilot skill fixtures | VERIFIED | Builder/Tester Dalton: `jq empty` passed for both pilot fixtures; targeted runner validation passed for `assistant-clarify` and `assistant-thinking`. | Clarify and thinking fixtures validate and include machine expectations. |
| 3. P0/P4 skill-eval contracts | VERIFIED | Builder/Tester Banach: direct `bash tests/p0-p4/skill-eval-contracts.sh` passed 13/13 and `bash tests/p0-p4/eval-contracts.sh` passed 14/14; aggregate initially failed due unrelated untracked `tests/.DS_Store`. After approved removal, Builder/Tester Descartes: `bash tests/test-p0-p4-contracts.sh` passed 100/100. | Direct and aggregate contract coverage passes; aggregate includes skill-eval suite. |
| 4. Documentation | VERIFIED | Code Writer Heisenberg updated `docs/evals/README.md`, `docs/skill-contract-design-guide.md`, and `README.md`; Builder/Tester Hypatia verified docs coverage with `rg -n "run-skill-evals|per-skill|local-only|pilot|Level 4" README.md docs/evals/README.md docs/skill-contract-design-guide.md`. | Docs explain per-skill eval usage, pilot scope, local-only exclusion, heuristic grading limits, and Level 4 direction. |

## Review Log

- BUILD verification passed:
  - `tools/evals/run-skill-evals.sh --validate-fixture`: passed, 2 fixtures validated.
  - `tools/evals/run-skill-evals.sh --list`: passed, 4 pilot cases listed.
  - `tools/evals/run-skill-evals.sh --emit-prompts /tmp/skill-eval-final-prompts.jVQpxU`: passed, 4 prompt packets written.
  - `tools/evals/run-skill-evals.sh --responses /tmp/skill-eval-final-responses.ugErfz`: passed, total=4 passed=4 failed=0.
  - `tools/evals/run-framework-instruction-evals.sh --validate-fixture`: passed.
  - `tools/skills/validate-skills.sh`: passed, 15 skills validated.
  - `bash tests/p0-p4/skill-eval-contracts.sh`: passed 13/13.
  - `bash tests/p0-p4/eval-contracts.sh`: passed 14/14.
  - `bash tests/test-p0-p4-contracts.sh`: passed 100/100 after approved removal of generated untracked `tests/.DS_Store`.
  - `rg -n "run-skill-evals|per-skill|local-only|pilot|Level 4" README.md docs/evals/README.md docs/skill-contract-design-guide.md`: passed.
  - `git diff --check`: passed.
- Build changed files:
  - `tools/evals/run-skill-evals.sh` created.
  - `skills/assistant-clarify/evals/cases.json` created.
  - `skills/assistant-thinking/evals/cases.json` created.
  - `tests/p0-p4/skill-eval-contracts.sh` created.
  - `tests/test-p0-p4-contracts.sh` modified.
  - `docs/evals/README.md` modified.
  - `docs/skill-contract-design-guide.md` modified.
  - `README.md` modified.
  - `.codex/context-map.md` and `.codex/task.md` updated as workflow artifacts.
- Spec Review #1: per-skill eval slice
  - Result: PASS
  - Scope reviewed: Tasks 1-4 from the approved plan.
  - Missing acceptance criteria: none.
  - Extra scope: none remaining. Approved generated-file hygiene removed untracked `tests/.DS_Store` to unblock repo guard.
  - Changed files mismatch: none. `.codex/context-map.md` and `.codex/task.md` are workflow artifacts.
  - Verification evidence mismatch: none. Runner, fixtures, direct skill eval contracts, framework eval contracts, aggregate P0/P4, skill validator, docs coverage, and diff hygiene evidence are recorded above.
  - Required fixes: none.
- Quality Review Round 1:
  - Result: has_must_fix
  - Rubric: correctness 3.5, code_quality 3.0, architecture 3.5, security 3.0, test_coverage 3.5
  - Weighted: 3.35
  - Finding 1 (must-fix): fixture case IDs were only non-empty strings but were used as filesystem path components, allowing path separators/traversal or duplicate IDs to corrupt emitted prompt paths.
  - Finding 2 (should-fix): `tools/evals/run-skill-evals.sh` was a 614-line mixed-responsibility script.
  - Fixes:
    - Added safe unique case-ID validation that rejects `/`, `\`, `.`, `..`, and duplicates.
    - Added P0/P4 negative tests for slash, traversal, and duplicate case IDs.
    - Split runner responsibilities into `tools/evals/lib/skill-eval-common.sh`, `skill-eval-inventory.sh`, `skill-eval-fixtures.sh`, `skill-eval-render.sh`, and `skill-eval-grade.sh`; public runner is now a thin CLI wrapper.
  - Validation after fixes:
    - `bash -n tools/evals/run-skill-evals.sh tools/evals/lib/*.sh tests/p0-p4/skill-eval-contracts.sh`: passed.
    - `tools/evals/run-skill-evals.sh --validate-fixture`: passed, 2 fixtures.
    - `tools/evals/run-skill-evals.sh --list`: passed, 4 cases.
    - `tools/evals/run-skill-evals.sh --emit-prompts <tmpdir>` plus generated responses smoke: passed, 4/4.
    - `bash tests/p0-p4/skill-eval-contracts.sh`: passed 16/16.
    - `bash tests/test-p0-p4-contracts.sh`: passed 103/103.
    - `git diff --check`: passed.
- Quality Review Round 2:
  - Result: has_must_fix
  - Rubric: correctness 3.5, code_quality 4.0, architecture 4.0, security 3.5, test_coverage 4.0
  - Weighted: 3.78
  - Finding (must-fix): case ID validation still allowed control characters/newlines, which line-oriented shell loops could split into multiple prompt packet paths.
  - Fix:
    - Tightened `safe_case_id` to a positive allowlist: letters, digits, dot, underscore, and hyphen only, while still rejecting `.` and `..`.
    - Added P0/P4 negative coverage for newline and tab control-character case IDs while preserving slash, traversal, and duplicate tests.
  - Validation after fix:
    - `bash -n tools/evals/run-skill-evals.sh tools/evals/lib/*.sh tests/p0-p4/skill-eval-contracts.sh`: passed.
    - `tools/evals/run-skill-evals.sh --validate-fixture`: passed, 2 fixtures.
    - `tools/evals/run-skill-evals.sh --emit-prompts <tmpdir>` plus generated responses smoke: passed, 4/4.
    - `bash tests/p0-p4/skill-eval-contracts.sh`: passed 18/18.
    - `bash tests/test-p0-p4-contracts.sh`: passed 105/105.
    - `git diff --check`: passed.
- Quality Review Round 3:
  - Result: has_should_fix
  - Rubric: correctness 4.5, code_quality 4.0, architecture 4.5, security 5.0, test_coverage 4.0
  - Weighted: 4.40
  - Finding (should-fix): P0/P4 suite only exercised `--skill` selection for `--validate-fixture`, and lacked positive `--include-local` coverage.
  - Fix:
    - Added targeted tests for `--list --skill assistant-clarify`.
    - Added targeted tests for `--emit-prompts <dir> --skill assistant-clarify`.
    - Added flat single-skill `--responses <dir> --skill assistant-clarify` coverage.
    - Added positive `--list --include-local` coverage with a generated local-only `skills/unity-*` fixture while preserving default exclusion.
  - Validation after fix:
    - `bash -n tests/p0-p4/skill-eval-contracts.sh`: passed.
    - `bash tests/p0-p4/skill-eval-contracts.sh`: passed 22/22.
    - `bash tests/test-p0-p4-contracts.sh`: passed 109/109.
    - `tools/evals/run-skill-evals.sh --validate-fixture`: passed, 2 fixtures.
    - `tools/evals/run-skill-evals.sh --list`: passed, 4 cases.
    - `git diff --check`: passed.
- Quality Review Round 4:
  - Result: clean
  - Rubric: correctness 4.5, code_quality 4.0, architecture 4.5, security 5.0, test_coverage 4.5
  - Weighted: 4.48
  - Findings: none.
  - Final Result: CLEAN.

## Verification Summary

- Changed files:
  - `tools/evals/run-skill-evals.sh` created as the public per-skill eval CLI.
  - `tools/evals/lib/skill-eval-common.sh`, `skill-eval-inventory.sh`, `skill-eval-fixtures.sh`, `skill-eval-render.sh`, and `skill-eval-grade.sh` created as focused runner modules.
  - `skills/assistant-clarify/evals/cases.json` and `skills/assistant-thinking/evals/cases.json` created as pilot fixtures.
  - `tests/p0-p4/skill-eval-contracts.sh` created and `tests/test-p0-p4-contracts.sh` updated.
  - `README.md`, `docs/evals/README.md`, and `docs/skill-contract-design-guide.md` updated.
  - `.codex/context-map.md` and `.codex/task.md` updated as workflow artifacts.
- Test coverage:
  - `tools/evals/run-skill-evals.sh --validate-fixture`: passed, 2 fixtures.
  - `tools/evals/run-skill-evals.sh --list`: passed, 4 pilot cases.
  - `tools/evals/run-skill-evals.sh --emit-prompts <tmpdir>` plus generated responses smoke: passed.
  - `tools/evals/run-framework-instruction-evals.sh --validate-fixture`: passed.
  - `tools/skills/validate-skills.sh`: passed, 15 skills.
  - `bash tests/p0-p4/skill-eval-contracts.sh`: passed 22/22 after review fixes.
  - `bash tests/p0-p4/eval-contracts.sh`: passed 14/14.
  - `bash tests/test-p0-p4-contracts.sh`: passed 109/109.
  - `git diff --check`: passed.
  - C# complexity gate: no `.cs` files to analyze.
- Review result: CLEAN after 4 quality review rounds, final weighted score 4.48.
- User confirmation: `looks good`.
- Manual test steps:
  - Run `tools/evals/run-skill-evals.sh --list`.
  - Run `tools/evals/run-skill-evals.sh --emit-prompts /tmp/skill-prompts`.
  - Run `bash tests/p0-p4/skill-eval-contracts.sh`.
- Known limitations:
  - This is pilot per-skill eval coverage for `assistant-clarify` and `assistant-thinking`; it does not yet provide fixtures for all 15 first-class skills.
  - Local grading remains deterministic substring proxy checking and does not replace semantic human or LLM review.

## Metrics

- Appended `/Users/laimis/.codex/memory/metrics/workflow-metrics.jsonl` entry for 2026-05-08.

## Reflexion

- Recorded memory insight: per-skill eval case IDs need filename-safe positive allowlist validation plus duplicate and control-character regression coverage.
- Recorded memory insight: shell eval runners should be split into inventory, validation, rendering, and grading modules early.
- Recorded `memory_reflect` reflexion id 42 for this medium feature task.

--- WORKFLOW COMPLETE ---
