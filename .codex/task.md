# Task Journal

Task: Implement workflow triage, trigger, and clarification gate recommendations
Status: DONE
Current phase: DOCUMENT COMPLETE
Current phase: BUILD
Triaged as: medium
Task type: refactor
Risk tier: moderate

Clarification status: ready
Clarification defaults applied: false
Unresolved clarification topics:

Required gates:
- trigger regression
- triage rubric
- clarification cap
- clarification admissibility
- task category gate packs
- runtime context
- eval coverage

Required agents:
- Code Mapper
- Architect
- Code Writer
- Builder/Tester
- Reviewer

Plan approval: yes, approved by user via "approve" on 2026-05-12

## Requirements
- Narrow workflow routing triggers to concrete development verbs: rewrite, implement, fix, migrate, refactor, plus safe command-style code phrasing.
- Avoid raw `code` trigger wording that routes explain/review/docs prompts into workflow.
- Add structured triage with task type, risk tier, size, required agents, and required gates.
- Add task-category gate packs for bugfix, feature, refactor/migration/rewrite, config/infra, security/input, and docs-only work.
- Add clarification cap plus admissibility gate: caps are maximums, not quotas; questions must be correctness-shaping and non-discoverable from code/context.
- Wire the new triage and clarification fields into contracts, task journal, runtime context, and eval fixtures.
- Add regression coverage proving clear tasks proceed with zero ritual questions and ambiguous risky tasks stop before Plan/Build.

## Constraints
- Keep the single Plan approval gate; do not reintroduce Decompose approval.
- Keep changes scoped to Assistant Framework workflow routing, contracts, hooks, refs, and tests/evals.
- Preserve existing hook behavior for no-journal and completed-journal cases.
- Do not treat raw `code` as a workflow trigger.
- Do not touch the untracked root `AGENTS.md`.

## Discovery Notes
- `skill-router.sh` collects all matching skills, so trigger false positives can collide with docs/review/clarify skills.
- Existing hooks already enforce pending clarification state once a task journal exists.
- Current enforcer runtime context reads only size, phase, clarification, plan/review/metrics fields.
- The current workflow input contract has `task_type`, but it lacks migration/rewrite/docs/security/infra categories and risk/gate metadata.
- Current workflow evals cover plan-before-build and component verification, but not trigger false positives or clarification cap/admissibility.
- Current hook tests cover pending clarification state but not the "question cap is not a quota" behavior.

## Requirements Restatement
Improve assistant-workflow so development prompts route reliably, triage produces explicit type/risk/gate metadata, clarification asks only admissible blocking questions, and tests/evals guard against both unsafe guessing and ritual questioning.

## Component Manifest
Approval status: approved by user via "approve" on 2026-05-12.

### Component 1: Trigger Routing And Regression Coverage
- **What:** Narrow workflow triggers to concrete development verbs and command-style code phrasing, with positive and negative router tests.
- **Files:** `skills/assistant-workflow/SKILL.md`, `tests/test-hooks.sh`, possibly `install.sh`/installer expectations if generated skill metadata changes.
- **Depends on:** none.
- **Verification criteria:**
  - [ ] Rewrite/migrate/refactor/implement/fix prompts route to assistant-workflow.
  - [ ] Explain/review/docs prompts containing `code` do not route to assistant-workflow solely because of `code`.
  - [ ] Existing skill-router tests still pass.

### Component 2: Triage Rubric And Gate Packs
- **What:** Add explicit triage rubric and category gate packs, then wire task type/risk/gate metadata into contracts and journal templates.
- **Files:** `skills/assistant-workflow/SKILL.md`, `skills/assistant-workflow/contracts/input.yaml`, `skills/assistant-workflow/contracts/phase-gates.yaml`, `skills/assistant-workflow/contracts/output.yaml`, `skills/assistant-workflow/contracts/handoffs.yaml`, `skills/assistant-workflow/references/phases.md`, `skills/assistant-workflow/references/task-journal-template.md`, `skills/assistant-workflow/references/plan-template.md`, new triage/gate-pack reference if useful.
- **Depends on:** Component 1.
- **Verification criteria:**
  - [ ] Triage requires task type, risk tier, required gates, and required agents.
  - [ ] Refactor/migration/rewrite tasks get baseline/parity gates.
  - [ ] Bugfix, feature, config/infra, security/input, and docs-only categories have distinct gates.
  - [ ] Skill validator accepts all contract changes.

### Component 3: Clarification Cap And Runtime Context
- **What:** Make question caps maximums, add question admissibility rules, persist clarification confidence/evidence, and surface the fields in runtime context.
- **Files:** workflow contracts/references, `hooks/scripts/workflow-enforcer.sh`, `tests/test-hooks.sh`, `tests/p0-p4/runtime-phase-gate-contracts.sh`.
- **Depends on:** Component 2.
- **Verification criteria:**
  - [ ] Clear medium+ tasks can record zero questions with high confidence.
  - [ ] Ambiguous risky tasks remain blocked while unresolved topics exist.
  - [ ] Runtime context exposes clarification question cap/admissibility state without forcing random questions.

### Component 4: Eval And Aggregate Contract Coverage
- **What:** Add eval fixtures for trigger routing and clarification cap/admissibility; update P0/P4 guards.
- **Files:** `skills/assistant-workflow/evals/cases.json`, `docs/evals/framework-instruction-cases.json`, `plugins/assistant-dev/skills/assistant-workflow/**` scaffold mirror, P0/P4 contract suites as needed.
- **Depends on:** Components 1-3.
- **Verification criteria:**
  - [ ] Workflow eval fixture validation passes.
  - [ ] P0/P4 focused workflow/runtime/skill eval contracts pass.
  - [ ] Aggregate P0/P4 passes without `.DS_Store` noise.

## Plan
Plan approval: yes, approved by user via "approve" on 2026-05-12.

### Task WF-TRIAGE-1: Trigger Routing And Regression Coverage
- Behavior / acceptance criteria:
  - Workflow routes rewrite, migrate, refactor, implement, fix, and safe code-command prompts.
  - Workflow does not route explain/review/docs prompts solely because they contain `code`.
- Files:
  - Create: none
  - Modify: `skills/assistant-workflow/SKILL.md`, `tests/test-hooks.sh`
  - Test: `tests/test-hooks.sh`
- TDD / RED step:
  - Applies: yes
  - RED command: `./tests/test-hooks.sh --filter "assistant-workflow trigger"`
  - Expected failure: new trigger regression tests fail before trigger pattern is updated.
- Implementation notes / constraints:
  - Do not add raw `code` as a standalone trigger.
  - Keep router semantics unchanged unless frontmatter regex is insufficient.
- Verification:
  - Command: `./tests/test-hooks.sh --filter skill-router`
  - Expected success signal: exit code 0 with workflow positive/negative trigger tests passing.
- Deviation / rollback rule:
  - If safe `code` phrasing causes false positives, remove it and keep verb triggers only.
- Worker status / evidence:
  - Status: done
  - Evidence: `./tests/test-hooks.sh --filter skill-router` passed 8 checks, including workflow verb/code-command positives and raw-code negative cases.

### Task WF-TRIAGE-2: Triage Rubric And Gate Packs
- Behavior / acceptance criteria:
  - Triage records task type, risk tier, required gates, and required agents.
  - Gate packs exist for bugfix, feature, refactor/migration/rewrite, config/infra, security/input, and docs-only work.
  - Contracts and journal templates define the same fields consistently.
- Files:
  - Create: optional `skills/assistant-workflow/references/triage-rubric.md`
  - Modify: `skills/assistant-workflow/SKILL.md`, `skills/assistant-workflow/contracts/input.yaml`, `skills/assistant-workflow/contracts/phase-gates.yaml`, `skills/assistant-workflow/contracts/output.yaml`, `skills/assistant-workflow/contracts/handoffs.yaml`, `skills/assistant-workflow/references/phases.md`, `skills/assistant-workflow/references/task-journal-template.md`, `skills/assistant-workflow/references/plan-template.md`
  - Test: `tests/p0-p4/workflow-basics-contracts.sh`, `tools/skills/validate-skills.sh`
- TDD / RED step:
  - Applies: yes
  - RED command: `bash tests/p0-p4/workflow-basics-contracts.sh`
  - Expected failure: contract guard fails before rubric/gate-pack terms exist.
- Implementation notes / constraints:
  - Preserve single Plan approval gate.
  - Keep required input fields compliant with `on_missing`.
- Verification:
  - Command: `bash tests/p0-p4/workflow-contracts.sh` and `tools/skills/validate-skills.sh --skill assistant-workflow`
  - Expected success signal: exit code 0.
- Deviation / rollback rule:
  - If adding required fields makes routing reminders too noisy, keep fields optional but enforce through phase gates/output.
- Worker status / evidence:
  - Status: done
  - Evidence: `bash tests/p0-p4/workflow-contracts.sh` passed 27 checks; `tools/skills/validate-skills.sh --skill assistant-workflow` passed.

### Task WF-TRIAGE-3: Clarification Cap And Runtime Context
- Behavior / acceptance criteria:
  - Question caps are maximums, not quotas.
  - Clear medium+ tasks can proceed with zero questions when confidence is high.
  - Ambiguous risky tasks remain blocked while unresolved topics exist.
  - Runtime context surfaces clarification confidence and admissibility state.
- Files:
  - Create: none
  - Modify: workflow contracts/references, `hooks/scripts/workflow-enforcer.sh`, `tests/test-hooks.sh`, `tests/p0-p4/runtime-phase-gate-contracts.sh`
  - Test: `tests/test-hooks.sh`, `tests/p0-p4/runtime-phase-gate-contracts.sh`
- TDD / RED step:
  - Applies: yes
  - RED command: `./tests/test-hooks.sh --filter "clarification cap"` and `bash tests/p0-p4/runtime-phase-gate-contracts.sh`
  - Expected failure: tests fail before runtime/admissibility text is wired.
- Implementation notes / constraints:
  - Do not enforce a minimum question count for medium+ tasks.
  - Questions must include why needed, risk if guessed, and safe default if any.
- Verification:
  - Command: `./tests/test-hooks.sh --filter workflow-enforcer` and `bash tests/p0-p4/runtime-phase-gate-contracts.sh`
  - Expected success signal: exit code 0.
- Deviation / rollback rule:
  - If runtime parsing becomes brittle, leave semantic admissibility in contracts/evals and only surface persisted fields in hooks.
- Worker status / evidence:
  - Status: done
  - Evidence: `./tests/test-hooks.sh --filter workflow-enforcer` passed 35 checks; `bash tests/p0-p4/runtime-phase-gate-contracts.sh` passed 6 checks; `tools/skills/validate-skills.sh --skill assistant-workflow` passed.

### Task WF-TRIAGE-4: Eval And Aggregate Contract Coverage
- Behavior / acceptance criteria:
  - Workflow evals cover trigger positives/negatives and clarification cap/admissibility.
  - Framework instruction evals cover clear task zero-question behavior and ambiguous risky blocking behavior.
  - Focused and aggregate contract suites pass.
- Files:
  - Create: none
  - Modify: `skills/assistant-workflow/evals/cases.json`, `docs/evals/framework-instruction-cases.json`, `plugins/assistant-dev/skills/assistant-workflow/**` scaffold mirror, P0/P4 contract suites as needed
  - Test: `tools/evals/run-skill-evals.sh`, `tests/test-p0-p4-contracts.sh`
- TDD / RED step:
  - Applies: yes
  - RED command: `bash tests/p0-p4/skill-eval-contracts.sh`
  - Expected failure: case list guards fail before expected eval cases are added.
- Implementation notes / constraints:
  - Keep fixtures provider-neutral and offline.
  - Deterministic substring checks should be proxies, not semantic graders.
- Verification:
  - Command: `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-workflow`, `bash tests/p0-p4/skill-eval-contracts.sh`, and `bash tests/test-p0-p4-contracts.sh`
  - Expected success signal: exit code 0.
- Deviation / rollback rule:
  - If aggregate failures are unrelated, isolate and report before expanding scope.
- Worker status / evidence:
  - Status: done
  - Evidence: `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-workflow` passed; `tools/evals/run-framework-instruction-evals.sh --validate-fixture` passed; `bash tests/p0-p4/skill-eval-contracts.sh` passed 24 checks; `bash tests/p0-p4/eval-contracts.sh` passed 15 checks.

## Tests to run
- `./tests/test-hooks.sh --filter skill-router`
- `./tests/test-hooks.sh --filter workflow-enforcer`
- `bash tests/p0-p4/workflow-contracts.sh`
- `bash tests/p0-p4/runtime-phase-gate-contracts.sh`
- `bash tests/p0-p4/skill-eval-contracts.sh`
- `tools/skills/validate-skills.sh --skill assistant-workflow`
- `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-workflow`
- `bash tests/test-p0-p4-contracts.sh`
- `git diff --check`
- `find tests plugins -name .DS_Store -print`

## Review Log

### Spec Review #1: Task WF-TRIAGE-1 Trigger Routing And Regression Coverage
- Result: PASS
- Scope reviewed: Component 1 / Task WF-TRIAGE-1 against changed files `skills/assistant-workflow/SKILL.md` and `tests/test-hooks.sh`
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none

### Quality Review #1: Task WF-TRIAGE-1 Trigger Routing And Regression Coverage
- Result: ISSUES_FIXED
- Rounds: 2
- Scope reviewed: `git diff -- skills/assistant-workflow/SKILL.md tests/test-hooks.sh`
- Findings: 0 must-fix, 1 should-fix
- Fixed: Added `implement` and `fix` prompts to the concrete development verb regression test.
- Re-test: PASS — `./tests/test-hooks.sh --filter skill-router` returned 8 passed, 0 failed, 124 skipped.
- Remaining: none

### Final result
- Result: ISSUES_FIXED
- Total must-fix resolved: 0
- Total should-fix resolved: 1

### Spec Review #2: Full Workflow Triage Recommendations
- Result: PASS
- Scope reviewed: approved task packets WF-TRIAGE-1 through WF-TRIAGE-4, component verification ledger, workflow skill/contracts/references, runtime hook context, eval fixtures, P0/P4 guards, and assistant-dev plugin workflow scaffold mirror.
- Missing acceptance criteria: none.
- Extra scope: none. `.codex/task.md` and `.codex/context-map.md` are task-state artifacts; `plugins/assistant-dev/skills/assistant-workflow/**` was synced because aggregate P0/P4 requires plugin-local scaffold copies to match root source skills.
- Changed files mismatch: none after approved scaffold sync.
- Verification evidence mismatch: none. Focused hook, workflow contract, runtime gate, eval fixture, validator, aggregate P0/P4, diff hygiene, and `.DS_Store` hygiene evidence is recorded.
- Required fixes: none.

### Quality Review #2: Full Workflow Triage Recommendations
- Result: CLEAN
- Rubric required: true
- Rubric scores:
  | Dimension | Score | Weight | Justification |
  |---|---:|---:|---|
  | Correctness | 4.8 | 0.30 | Trigger routing, structured triage, clarification admissibility, runtime context, and eval guards match the approved behavior and are covered by focused plus aggregate tests. |
  | Code Quality | 4.6 | 0.20 | Changes follow existing markdown/YAML/bash test patterns; new rubric is separated into a reference file instead of crowding SKILL.md. |
  | Architecture | 4.7 | 0.20 | Triage metadata is represented in contracts, phase gates, handoffs, task journal, plan template, runtime context, and plugin scaffold without changing router semantics. |
  | Security | 4.5 | 0.15 | No secrets, permissions, auth, or network surface added; security/input gate pack strengthens future triage. |
  | Test Coverage | 4.9 | 0.15 | Added hook regressions, P0/P4 guards, skill eval fixtures, framework eval fixtures, validator coverage, and aggregate P0/P4 verification. |
  | Weighted | 4.70 | 1.00 | PASS. |
- Findings: none.
- Remaining items: none.

### Final result
- Result: CLEAN
- Review rounds: 2
- Final rubric score: 4.70 (PASS)
- Score progression: 4.70
- Drift incidents: none
- Total must-fix resolved: 0
- Total should-fix resolved: 1
- Should-fix deferred: none
- Nits noted: 0

## Component Verification Ledger
| Component | Task Packet | RED Status | Implementation Status | Verification Command/Result | Criteria Checked | Self-Check Result | Final Status |
|-----------|-------------|------------|-----------------------|-----------------------------|------------------|-------------------|--------------|
| C1: Trigger Routing And Regression Coverage | WF-TRIAGE-1 | N/A | done | `./tests/test-hooks.sh --filter skill-router` -> pass, 8 passed / 0 failed / 124 skipped | 3/3 passed | pass: changed files match packet and raw `code` is not a standalone trigger | VERIFIED |
| C2: Triage Rubric And Gate Packs | WF-TRIAGE-2 | N/A | done | `bash tests/p0-p4/workflow-contracts.sh` -> pass, 27 passed / 0 failed; `tools/skills/validate-skills.sh --skill assistant-workflow` -> pass | 4/4 passed | pass: rubric, contracts, journal template, and gate-pack guards are aligned | VERIFIED |
| C3: Clarification Cap And Runtime Context | WF-TRIAGE-3 | N/A | done | `./tests/test-hooks.sh --filter workflow-enforcer` -> pass, 35 passed / 0 failed / 98 skipped; `bash tests/p0-p4/runtime-phase-gate-contracts.sh` -> pass, 6 passed / 0 failed | 3/3 passed | pass: zero-question ready state does not activate clarification gate and runtime context exposes cap/admissibility | VERIFIED |
| C4: Eval And Aggregate Contract Coverage | WF-TRIAGE-4 | N/A | done | skill fixture validation -> pass; framework fixture validation -> pass; `bash tests/p0-p4/skill-eval-contracts.sh` -> pass, 24 passed / 0 failed; `bash tests/p0-p4/eval-contracts.sh` -> pass, 15 passed / 0 failed | 3/3 passed | pass: workflow and framework eval fixtures cover trigger and clarification admissibility behavior | VERIFIED |

## Final Verification
- `./tests/test-hooks.sh --filter skill-router` - passed; 8 passed, 0 failed, 124 skipped.
- `./tests/test-hooks.sh --filter workflow-enforcer` - passed; 35 passed, 0 failed, 98 skipped.
- `bash tests/p0-p4/workflow-contracts.sh` - passed; 27 passed, 0 failed.
- `bash tests/p0-p4/runtime-phase-gate-contracts.sh` - passed; 6 passed, 0 failed.
- `bash tests/p0-p4/skill-eval-contracts.sh` - passed; 24 passed, 0 failed.
- `bash tests/p0-p4/eval-contracts.sh` - passed; 15 passed, 0 failed.
- `tools/skills/validate-skills.sh --skill assistant-workflow` - passed.
- `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-workflow` - passed.
- `tools/evals/run-framework-instruction-evals.sh --validate-fixture` - passed.
- `bash tests/test-p0-p4-contracts.sh` - passed; 145 passed, 0 failed.
- `git diff --check` - passed.
- `find tests plugins -name .DS_Store -print` - passed with no output.

## Documentation / Closeout
- Narrowed assistant-workflow routing to concrete development verbs plus bounded command-style code phrasing; raw `code` is not a standalone workflow trigger.
- Added `references/triage-rubric.md` with structured task type, risk tier, required gates, required agents, size rules, and task-category gate packs.
- Wired triage metadata through input/output contracts, phase gates, handoffs, task journal template, plan template, and phase instructions.
- Added clarification cap/admissibility fields and runtime context output; caps are maximums, not quotas, and clear medium+ tasks may proceed with zero questions.
- Added hook tests, P0/P4 guards, workflow eval fixtures, framework instruction eval fixtures, and synced the assistant-dev plugin workflow scaffold.
- Preserved the single Plan approval gate and did not change skill-router matching semantics.
