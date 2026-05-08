# Task Journal

Task: High-control per-skill eval coverage
Status: DONE
Current phase: DOCUMENT COMPLETE
Triaged as: medium

Clarification status: ready
Clarification defaults applied: false
Unresolved clarification topics:

## Requirements
- Expand Level 4 provider-neutral per-skill eval coverage beyond the current `assistant-clarify` and `assistant-thinking` pilot.
- Add focused fixtures for high-control skills where missed instructions create the largest workflow risk: `assistant-workflow`, `assistant-review`, `assistant-tdd`, and `assistant-security`.
- Keep the existing runner architecture unless fixture coverage exposes a minimal contract-test gap.
- Update P0/P4 contracts and docs so the new default inventory and coverage state are guarded from drift.

## Constraints
- Keep all evals offline, provider-neutral, and based on local fixture validation/listing/emission/grading.
- Do not add provider SDKs, model calls, or network requirements.
- Keep fixtures skill-local at `skills/<skill>/evals/cases.json`.
- Preserve local-only `unity-*` exclusion from the default inventory unless `--include-local` is passed.
- Subagent dispatch has not been explicitly requested in this environment, so implementation and verification will be performed locally while preserving the workflow handoff evidence shape.
- Do not use destructive cleanup commands.

## Discovery Notes
- `tools/evals/run-skill-evals.sh` already validates, lists, emits prompt packets, and locally grades response files through shell and `jq`.
- Existing pilot fixtures are `skills/assistant-clarify/evals/cases.json` and `skills/assistant-thinking/evals/cases.json`.
- `tests/p0-p4/skill-eval-contracts.sh` already guards default inventory, targeted selection, prompt emission, response grading, malformed fixtures, and local-only inclusion behavior.
- Docs currently describe the per-skill eval slice as a two-skill pilot and call broader coverage future work.
- Target skill contracts provide observable behaviors worth fixture testing:
  - `assistant-workflow`: visible checkpoints, Discover/Decompose/Plan gates, approval before Build, tests with implementation, Review loop, output artifacts.
  - `assistant-review`: review scope resolution, autonomous review-fix loop, all must-fix and should-fix handling, validation before next round, rubric for medium+ scopes.
  - `assistant-tdd`: RED before GREEN, exactly one behavior test per RED, right failure reason, no production code before RED evidence, all tests after GREEN/REFACTOR.
  - `assistant-security`: scoped analysis, methodology selection, evidence-based findings, severity scale, remediation, prioritized action items.
- Agent readiness: 4/5. The repo has agent instructions, documented eval commands, shell-based contract tests, and existing eval fixtures; no obvious standalone linter/editorconfig baseline was found.

## Requirements Restatement
Add four new skill-local eval fixture suites for the highest-risk process/security skills, then update the contract tests and docs so default eval coverage visibly moves from a two-skill pilot to a six-skill high-control coverage slice. The runner should remain provider-neutral and local-only unless a small test-only adjustment is required.

## Component Manifest
Approval status: approved by user on 2026-05-08

### Component 1: Workflow And Review Fixtures
- **What:** Add provider-neutral behavior fixtures for the two orchestration-heavy process skills, covering mandatory phase gates and review-loop discipline.
- **Files:** create `skills/assistant-workflow/evals/cases.json`; create `skills/assistant-review/evals/cases.json`.
- **Depends on:** none.
- **Verification criteria:**
  - [ ] `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-workflow --skill assistant-review` validates both fixture files.
  - [ ] `tools/evals/run-skill-evals.sh --list --skill assistant-workflow --skill assistant-review` lists cases that cover workflow gates and review loop behavior.
  - [ ] Fixture machine expectations include required and forbidden substrings for approval gates, phase checkpoints, review findings, and no premature implementation.

### Component 2: TDD And Security Fixtures
- **What:** Add provider-neutral behavior fixtures for the strict execution-discipline and security-analysis skills, covering RED evidence, no production-before-test behavior, evidence-based findings, severity, and remediation.
- **Files:** create `skills/assistant-tdd/evals/cases.json`; create `skills/assistant-security/evals/cases.json`.
- **Depends on:** none.
- **Verification criteria:**
  - [ ] `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-tdd --skill assistant-security` validates both fixture files.
  - [ ] `tools/evals/run-skill-evals.sh --list --skill assistant-tdd --skill assistant-security` lists cases that cover TDD gates and security report behavior.
  - [ ] Fixture machine expectations include required and forbidden substrings for RED/GREEN/REFACTOR gates, evidence, severity, impact, remediation, and no speculative findings.

### Component 3: P0/P4 Eval Contract Expansion
- **What:** Extend existing contract tests to lock in the expanded default fixture inventory, targeted selection, prompt emission, generated response grading, and representative new case rows.
- **Files:** modify `tests/p0-p4/skill-eval-contracts.sh`.
- **Depends on:** Components 1 and 2.
- **Verification criteria:**
  - [ ] `bash tests/p0-p4/skill-eval-contracts.sh` passes and asserts all six default first-class fixture suites.
  - [ ] Generated all-required responses pass with the expanded default case count.
  - [ ] Targeted selection tests include at least one newly covered high-control skill.

### Component 4: Eval Coverage Documentation
- **What:** Update public and design docs so they describe the six-skill high-control coverage slice instead of the older two-skill pilot.
- **Files:** modify `README.md`; modify `docs/evals/README.md`; modify `docs/skill-contract-design-guide.md`.
- **Depends on:** Components 1 through 3.
- **Verification criteria:**
  - [ ] Docs list or describe coverage for `assistant-clarify`, `assistant-thinking`, `assistant-workflow`, `assistant-review`, `assistant-tdd`, and `assistant-security`.
  - [ ] Docs still state that coverage is not complete for all first-class skills.
  - [ ] Docs continue to describe local heuristic grading as a provider-neutral proxy, not semantic judgment.

## Plan
Plan approval: yes, approved by user on 2026-05-08

## Goal
- Expand provider-neutral per-skill eval coverage from the current two-skill pilot to a six-skill high-control slice.
- Add skill-local fixtures for `assistant-workflow`, `assistant-review`, `assistant-tdd`, and `assistant-security`.
- Update P0/P4 contracts and docs so the new coverage state is visible and guarded.

## Constraints & decisions from Discovery
- The eval runner stays local and provider-neutral; no model calls, provider SDKs, or network behavior are added.
- Fixtures stay beside the skills at `skills/<skill>/evals/cases.json`.
- Default inventory continues to include first-class `assistant-*` fixtures and exclude local-only `unity-*` fixtures unless `--include-local` is passed.
- Coverage should be described as a six-skill high-control slice, not complete coverage for all first-class skills.
- Current environment does not allow subagent dispatch unless explicitly requested, so local implementation will preserve task-packet evidence instead of actual subagent handoffs.
- Non-goal: semantic LLM judging or provider-specific adapters.

## Research
- Modules/subprojects: shell eval runner under `tools/evals/`; skill instructions under `skills/assistant-*`; P0/P4 contracts under `tests/p0-p4/`; docs under `README.md` and `docs/`.
- Key files/paths:
  - `tools/evals/run-skill-evals.sh`
  - `tools/evals/lib/skill-eval-inventory.sh`
  - `tools/evals/lib/skill-eval-fixtures.sh`
  - `tools/evals/lib/skill-eval-render.sh`
  - `tools/evals/lib/skill-eval-grade.sh`
  - `tests/p0-p4/skill-eval-contracts.sh`
  - `docs/evals/README.md`
  - `docs/skill-contract-design-guide.md`
  - `README.md`
- Existing patterns:
  - Fixtures use `schema_version`, `suite_id`, `skill`, provider-neutral flags, `recommended_use`, and `cases`.
  - Each case includes `id`, `title`, `category`, `purpose`, `prompt`, `setup_context`, `expected_behavior`, `pass_criteria`, `fail_signals`, and `machine_expectations`.
  - Machine expectations use deterministic required and forbidden substrings as offline proxies.
  - Contract tests use dynamic case counts but currently assert only pilot fixture names and representative pilot rows.

## Architecture
- Current architecture: skill-local JSON fixtures are discovered and validated by a shell runner; docs and P0/P4 contracts describe the supported surface.
- Architecture for this change: add four more fixture suites using the existing schema, then update tests/docs. No new runner layer is planned.
- Layer rules:
  - Skill behavior examples live with each skill.
  - Generic runner/schema logic stays under `tools/evals/lib/`.
  - P0/P4 checks guard stable public behavior and inventory expectations.
  - Docs describe actual implemented coverage, not aspirational coverage.
- Dependency direction: skill fixtures -> runner validation/listing/emission/grading -> P0/P4 contracts -> docs.
- New files placement:
  - `skills/assistant-workflow/evals/cases.json`: workflow skill behavior fixtures.
  - `skills/assistant-review/evals/cases.json`: review loop behavior fixtures.
  - `skills/assistant-tdd/evals/cases.json`: TDD behavior fixtures.
  - `skills/assistant-security/evals/cases.json`: security analysis behavior fixtures.
- SOLID design notes:
  - SRP: fixtures describe observable behavior only; runner code continues to own execution mechanics.
  - OCP: adding future skill coverage should require adding new `evals/cases.json` files, not modifying runner discovery.
  - DIP: docs and contract tests depend on runner outputs and fixture files, not hidden implementation details beyond stable paths.

## Analysis
### Options
1. Add fixtures only and rely on dynamic runner counts. Fast, but default coverage drift would be easy to miss.
2. Add fixtures plus focused P0/P4 and docs updates. More complete and still bounded.
3. Rewrite the runner into a richer semantic evaluator. Too broad and violates the local/provider-neutral constraint for this slice.

### Decision
- Chosen: option 2. It improves behavior coverage while preserving the existing runner design.

### Risks / edge cases
- Required substrings can become too brittle. Mitigation: use stable contract terms, phase names, and output labels rather than prose-heavy sentences.
- Docs can overstate coverage. Mitigation: explicitly say this is six-skill high-control coverage, not all first-class skills.
- Contract tests can become overly tied to exact fixture count. Mitigation: keep total count dynamic and assert representative fixture names/case rows.
- New fixture directories may unintentionally include local-only skills. Mitigation: only add under first-class `assistant-*` directories and keep existing local-only tests.

## Task packets

### Task 1: Workflow And Review Fixtures
- Behavior / acceptance criteria:
  - `assistant-workflow` has cases covering phase checkpoints, Discover/Decompose/Plan approval gates, and no Build before approval.
  - `assistant-review` has cases covering scoped review material, autonomous loop behavior, findings, validation, rubric, and no one-shot incomplete review.
  - Both fixtures validate through the existing schema with non-empty required and forbidden machine expectations.
- Files:
  - Create: `skills/assistant-workflow/evals/cases.json`, `skills/assistant-review/evals/cases.json`.
  - Modify: none.
  - Test: runner validation/listing through `tools/evals/run-skill-evals.sh`.
- TDD / RED step:
  - Applies: no. This component adds eval fixture data and validates it with the existing runner.
  - RED command: N/A.
  - Expected failure: N/A.
- Implementation notes / constraints:
  - Follow the existing `assistant-clarify` and `assistant-thinking` fixture shape.
  - Keep case ids safe filename components.
  - Use stable contract words such as `--- PHASE:`, `WAITING`, `approved`, `review_material_snapshot`, `must-fix`, `should-fix`, and `rubric`.
- Verification:
  - Command: `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-workflow --skill assistant-review && tools/evals/run-skill-evals.sh --list --skill assistant-workflow --skill assistant-review`
  - Expected success signal: exit code 0 and list rows for both new skills.
- Deviation / rollback rule:
  - If a case cannot be represented with deterministic local substrings, narrow the case to observable contract labels and record the limitation before continuing.
- Worker status / evidence:
  - Status: done.
  - Evidence: `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-workflow --skill assistant-review` passed; `tools/evals/run-skill-evals.sh --list --skill assistant-workflow --skill assistant-review` listed four cases.

### Task 2: TDD And Security Fixtures
- Behavior / acceptance criteria:
  - `assistant-tdd` has cases covering RED before GREEN, right failure reason, no production code before RED evidence, and all tests after GREEN/REFACTOR.
  - `assistant-security` has cases covering scoped analysis, tool/methodology selection, evidence, severity, impact, remediation, risk summary, and action items.
  - Both fixtures validate through the existing schema with non-empty required and forbidden machine expectations.
- Files:
  - Create: `skills/assistant-tdd/evals/cases.json`, `skills/assistant-security/evals/cases.json`.
  - Modify: none.
  - Test: runner validation/listing through `tools/evals/run-skill-evals.sh`.
- TDD / RED step:
  - Applies: no. This component adds eval fixture data and validates it with the existing runner.
  - RED command: N/A.
  - Expected failure: N/A.
- Implementation notes / constraints:
  - Use stable TDD labels: `RED`, `GREEN`, `REFACTOR`, `right reason`, `production code`, and `all tests`.
  - Use stable security labels: `severity`, `impact`, `evidence`, `remediation`, `risk summary`, and `action items`.
  - Forbidden substrings should catch shortcuts such as skipping RED or speculative security claims.
- Verification:
  - Command: `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-tdd --skill assistant-security && tools/evals/run-skill-evals.sh --list --skill assistant-tdd --skill assistant-security`
  - Expected success signal: exit code 0 and list rows for both new skills.
- Deviation / rollback rule:
  - If fixture wording makes response grading unrealistic, keep the schema-valid fixture and move the brittle exact phrase into human pass criteria rather than machine expectations.
- Worker status / evidence:
  - Status: done.
  - Evidence: `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-tdd --skill assistant-security` passed; `tools/evals/run-skill-evals.sh --list --skill assistant-tdd --skill assistant-security` listed four cases.

### Task 3: P0/P4 Eval Contract Expansion
- Behavior / acceptance criteria:
  - Default validation output explicitly includes all six tracked first-class fixture suites.
  - List output includes representative rows for at least one new workflow/review case and one new TDD/security case.
  - Generated all-required response grading passes with the expanded dynamic default case count.
  - Targeted selection coverage includes a newly covered high-control skill.
- Files:
  - Create: none.
  - Modify: `tests/p0-p4/skill-eval-contracts.sh`.
  - Test: `tests/p0-p4/skill-eval-contracts.sh`.
- TDD / RED step:
  - Applies: no. Existing P0/P4 suite is being extended after fixture files exist; runner validation remains the behavior gate.
  - RED command: N/A.
  - Expected failure: N/A.
- Implementation notes / constraints:
  - Keep total fixture and case counts dynamic.
  - Avoid duplicating fixture schema validation logic in the P0/P4 script.
  - Use representative exact rows that are stable and useful for drift detection.
- Verification:
  - Command: `bash tests/p0-p4/skill-eval-contracts.sh`
  - Expected success signal: suite exits 0 and reports all skill eval contract tests passed.
- Deviation / rollback rule:
  - If exact new row assertions become too noisy, assert fixture path presence plus targeted output for one stable case per new skill group.
- Worker status / evidence:
  - Status: done.
  - Evidence: `bash tests/p0-p4/skill-eval-contracts.sh` passed 23/23.

### Task 4: Eval Coverage Documentation
- Behavior / acceptance criteria:
  - README and eval docs state current default coverage is six first-class skills: `assistant-clarify`, `assistant-thinking`, `assistant-workflow`, `assistant-review`, `assistant-tdd`, and `assistant-security`.
  - Docs continue to say this is not complete coverage for all first-class skills.
  - Contract design guide describes the new wider Level 4 per-skill coverage state and remaining future work.
- Files:
  - Create: none.
  - Modify: `README.md`, `docs/evals/README.md`, `docs/skill-contract-design-guide.md`.
  - Test: docs are covered by inspection plus aggregate P0/P4 where relevant.
- TDD / RED step:
  - Applies: no. This component updates documentation; contract tests from Task 3 cover executable behavior.
  - RED command: N/A.
  - Expected failure: N/A.
- Implementation notes / constraints:
  - Do not claim semantic LLM judging.
  - Do not claim all 15 first-class skills are covered.
  - Keep command examples unchanged unless required by the expanded coverage.
- Verification:
  - Command: `bash tests/test-p0-p4-contracts.sh && git diff --check`
  - Expected success signal: aggregate P0/P4 exits 0 and whitespace check exits 0.
- Deviation / rollback rule:
  - If docs need a new terminology phrase, keep it consistent across README, eval docs, and contract guide before continuing.
- Worker status / evidence:
  - Status: done.
  - Evidence: `tools/evals/run-skill-evals.sh --validate-fixture` validated six fixtures; `tools/evals/run-skill-evals.sh --list` listed 12 cases; `bash tests/p0-p4/skill-eval-contracts.sh` passed 24/24; `bash tests/test-p0-p4-contracts.sh` passed 116/116; `git diff --check` passed.

## Tests to run
- `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-workflow --skill assistant-review`
- `tools/evals/run-skill-evals.sh --list --skill assistant-workflow --skill assistant-review`
- `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-tdd --skill assistant-security`
- `tools/evals/run-skill-evals.sh --list --skill assistant-tdd --skill assistant-security`
- `tools/evals/run-skill-evals.sh --validate-fixture`
- `tools/evals/run-skill-evals.sh --list`
- `bash tests/p0-p4/skill-eval-contracts.sh`
- `bash tests/test-p0-p4-contracts.sh`
- `git diff --check`

## Build Progress
- Component 1: Workflow And Review Fixtures - DONE.
- Component 2: TDD And Security Fixtures - DONE.
- Component 3: P0/P4 Eval Contract Expansion - DONE.
- Component 4: Eval Coverage Documentation - DONE.

## Component Verification Ledger
| Component | Status | Command / Evidence | Criteria |
|---|---|---|---|
| 1. Workflow And Review Fixtures | VERIFIED | `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-workflow --skill assistant-review` passed; `tools/evals/run-skill-evals.sh --list --skill assistant-workflow --skill assistant-review` listed four cases. | Both fixture files validate; list output includes workflow gate and review loop cases; machine expectations include approval gates, phase checkpoints, review findings, and premature-implementation forbidden phrases. |
| 2. TDD And Security Fixtures | VERIFIED | `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-tdd --skill assistant-security` passed; `tools/evals/run-skill-evals.sh --list --skill assistant-tdd --skill assistant-security` listed four cases. | Both fixture files validate; list output includes TDD gate and security report cases; machine expectations include RED/GREEN/REFACTOR, evidence, severity, impact, remediation, and speculative-finding forbidden phrases. |
| 3. P0/P4 Eval Contract Expansion | VERIFIED | `bash tests/p0-p4/skill-eval-contracts.sh` passed 23/23. | Default validation output asserts all six tracked fixture suites; list output includes representative high-control rows; targeted selection includes `assistant-security`; generated all-required responses pass with dynamic default count. |
| 4. Eval Coverage Documentation | VERIFIED | `tools/evals/run-skill-evals.sh --validate-fixture` validated six fixtures; `tools/evals/run-skill-evals.sh --list` listed 12 cases; `bash tests/p0-p4/skill-eval-contracts.sh` passed 24/24; `bash tests/test-p0-p4-contracts.sh` passed 116/116; `git diff --check` passed. | README, eval docs, and contract design guide describe the six-skill high-control slice; docs still say coverage is not complete for all first-class skills; local grading remains described as heuristic/provider-neutral, not semantic judgment. |

## Review Log
- Build verification:
  - `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-workflow --skill assistant-review`: passed.
  - `tools/evals/run-skill-evals.sh --list --skill assistant-workflow --skill assistant-review`: listed four cases.
  - `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-tdd --skill assistant-security`: passed.
  - `tools/evals/run-skill-evals.sh --list --skill assistant-tdd --skill assistant-security`: listed four cases.
  - `tools/evals/run-skill-evals.sh --validate-fixture`: validated six fixtures.
  - `tools/evals/run-skill-evals.sh --list`: listed 12 cases.
  - `bash tests/p0-p4/skill-eval-contracts.sh`: passed 24/24.
  - `bash tests/test-p0-p4-contracts.sh`: passed 116/116.
  - `git diff --check`: passed.
- Plan deviation:
  - Added a doc-drift assertion to `tests/p0-p4/skill-eval-contracts.sh` while updating docs so the six-skill coverage wording is contract-tested. This stays within the approved P0/P4 and docs scope.
### Spec Review #1
- Result: PASS
- Scope reviewed: Components 1-4 from the approved decomposition and task packets.
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Result: ISSUES_FIXED
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 5.0, test_coverage 4.5
- Weighted: 4.25
- Findings:
  - should-fix: `skills/assistant-workflow/evals/cases.json` required `PLAN DEVIATION` and `--- PHASE: REVIEW ---` in a Build-phase case even when a correct response may have no deviation and may not yet be in Review.
- Fixed:
  - Replaced those brittle required substrings with stable Build-phase expectations: `deviation` and `tests`.
- Validation after fix:
  - `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-workflow`: passed.
  - `bash tests/p0-p4/skill-eval-contracts.sh`: passed 24/24.
  - `bash tests/test-p0-p4-contracts.sh`: passed 116/116.
  - `git diff --check`: passed.
### Quality Review #2
- Result: CLEAN
- Rubric: correctness 4.5, code_quality 4.0, architecture 4.5, security 5.0, test_coverage 4.5
- Weighted: 4.48
- Findings: none.
### Final Result
- Result: ISSUES_FIXED

## Verification Summary
- Changed files:
  - `skills/assistant-workflow/evals/cases.json` created with workflow phase-gate and component-verification cases.
  - `skills/assistant-review/evals/cases.json` created with review-loop and rubric cases.
  - `skills/assistant-tdd/evals/cases.json` created with RED evidence and GREEN/REFACTOR verification cases.
  - `skills/assistant-security/evals/cases.json` created with scoping/methodology and findings/report-contract cases.
  - `tests/p0-p4/skill-eval-contracts.sh` expanded for six-skill default inventory, representative rows, targeted high-control selection, prompt emission, generated response grading, and docs drift.
  - `README.md`, `docs/evals/README.md`, and `docs/skill-contract-design-guide.md` updated to describe six-skill high-control coverage while preserving the not-full-coverage limitation.
  - `.codex/task.md` and `.codex/context-map.md` updated as workflow artifacts.
- Tests:
  - `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-workflow --skill assistant-review`: passed.
  - `tools/evals/run-skill-evals.sh --list --skill assistant-workflow --skill assistant-review`: listed four cases.
  - `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-tdd --skill assistant-security`: passed.
  - `tools/evals/run-skill-evals.sh --list --skill assistant-tdd --skill assistant-security`: listed four cases.
  - `tools/evals/run-skill-evals.sh --validate-fixture`: validated six fixtures.
  - `tools/evals/run-skill-evals.sh --list`: listed 12 cases.
  - `bash tests/p0-p4/skill-eval-contracts.sh`: passed 24/24.
  - `bash tests/test-p0-p4-contracts.sh`: passed 116/116.
  - `git diff --check`: passed.
- Manual test steps:
  - Run `tools/evals/run-skill-evals.sh --list`.
  - Run `tools/evals/run-skill-evals.sh --emit-prompts /tmp/skill-eval-prompts --skill assistant-workflow`.
  - Run `bash tests/p0-p4/skill-eval-contracts.sh`.

## Metrics
- Appended `/Users/laimis/.codex/memory/metrics/workflow-metrics.jsonl` entry:
  - date: 2026-05-08
  - task: high-control per-skill eval coverage
  - size: medium
  - review_rounds: 2
  - plan_deviations: 1
  - build_failures: 0
  - criteria_defined: 12
  - components_verified: 4

--- WORKFLOW COMPLETE ---
