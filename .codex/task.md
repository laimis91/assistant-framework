# Task Journal

Task: Complete first-class skill eval coverage
Status: DONE
Current phase: DOCUMENT COMPLETE
Triaged as: medium

Clarification status: ready
Clarification defaults applied: false
Unresolved clarification topics:

## Requirements
- Expand Level 4 provider-neutral per-skill eval coverage from 10 of 15 first-class assistant skills to all 15.
- Add focused fixtures for `assistant-diagrams`, `assistant-docs`, `assistant-ideate`, `assistant-reflexion`, and `assistant-telos`.
- Update P0/P4 contracts and docs so complete first-class coverage is guarded from drift.
- Keep local-only `unity-*` skills excluded from default inventory unless `--include-local` is used.

## Constraints
- Keep all evals offline, provider-neutral, and based on local fixture validation/listing/emission/grading.
- Do not add provider SDKs, model calls, network requirements, or runner behavior changes.
- Keep fixtures skill-local at `skills/<skill>/evals/cases.json`.
- Describe coverage as complete for first-class `assistant-*` skills, not complete for local-only Unity skills.
- Match machine expectations to exact skill contract labels and casing.
- Check docs drift with short factual phrases rather than wrapped prose.
- No subagent dispatch was explicitly requested; discovery and planning are local while preserving workflow artifacts.

## Discovery Notes
- Existing default fixtures cover 10 first-class skills.
- Remaining first-class skills without fixtures are:
  - `assistant-diagrams`
  - `assistant-docs`
  - `assistant-ideate`
  - `assistant-reflexion`
  - `assistant-telos`
- `assistant-diagrams` contracts require `diagram_type`, `scope`, valid `diagram_code`, diagram type echo, and description; SKILL output also includes evidence, placement, and gaps.
- `assistant-docs` contracts require `doc_type`, `scope`, `files_updated`, `doc_coverage`, and `review_needed`; SKILL requires code-derived docs and evidence.
- `assistant-ideate` contracts require UNDERSTAND/DIVERGE/CONVERGE/REFINE/DECIDE, at least 8 ideas, all scoring criteria, refined candidates, and user decision.
- `assistant-reflexion` contracts require action, reflect lessons with confidence/applies_to, stored insight evidence, and recalled lessons with confidence/date/project.
- `assistant-telos` contracts require action/entity resolution, core TCF sections for create/update, review findings for review, and confirmation.
- `tests/p0-p4/skill-eval-contracts.sh` currently guards 10-skill coverage, representative rows, prompt emission, and docs coverage wording.
- README, eval docs, top-level contract guide, and bundled skill-creator contract guide currently describe ten-skill coverage and five remaining first-class skills.
- Agent readiness: 4/5. The repo has documented eval commands, shell P0/P4 suites, skill contracts, and workflow artifacts; no separate linter baseline was inspected for this docs/fixture slice.

## Requirements Restatement
Add five skill-local eval fixture suites for the remaining first-class assistant skills, then update P0/P4 assertions and coverage docs so default first-class eval coverage is complete for all 15 `assistant-*` skills while local-only Unity skills remain outside the default inventory.

## Component Manifest
Approval status: approved by user on 2026-05-08

### Component 1: Diagram And Docs Fixtures
- **What:** Add provider-neutral fixtures for code-derived diagram and documentation generation skills.
- **Files:** create `skills/assistant-diagrams/evals/cases.json`; create `skills/assistant-docs/evals/cases.json`.
- **Depends on:** none.
- **Verification criteria:**
  - [ ] `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-diagrams --skill assistant-docs` validates both fixture files.
  - [ ] `tools/evals/run-skill-evals.sh --list --skill assistant-diagrams --skill assistant-docs` lists cases covering code evidence, Mermaid/diagram output, docs coverage, and review-needed output.
  - [ ] Machine expectations include required and forbidden substrings for code-derived evidence, no hallucinated/aspirational docs, output artifacts, placement, gaps, and review flags.

### Component 2: Ideate, Reflexion, And Telos Fixtures
- **What:** Add provider-neutral fixtures for structured ideation, post-task learning, lesson recall, and Telos context workflows.
- **Files:** create `skills/assistant-ideate/evals/cases.json`; create `skills/assistant-reflexion/evals/cases.json`; create `skills/assistant-telos/evals/cases.json`.
- **Depends on:** none.
- **Verification criteria:**
  - [ ] `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-ideate --skill assistant-reflexion --skill assistant-telos` validates all three fixture files.
  - [ ] `tools/evals/run-skill-evals.sh --list --skill assistant-ideate --skill assistant-reflexion --skill assistant-telos` lists cases covering ideation phases, scoring, reflection storage, lesson recall, TCF creation, and TCF review.
  - [ ] Machine expectations include contract labels for 8+ ideas, scoring criteria, refined candidates, `memory_reflect`, lessons confidence, TCF core sections, review findings, and confirmation.

### Component 3: P0/P4 Eval Contract Expansion To 15
- **What:** Extend existing skill-eval contracts so all 15 first-class fixture suites and representative new rows are guarded.
- **Files:** modify `tests/p0-p4/skill-eval-contracts.sh`.
- **Depends on:** Components 1 and 2.
- **Verification criteria:**
  - [ ] `bash tests/p0-p4/skill-eval-contracts.sh` passes and asserts all 15 first-class fixture suites.
  - [ ] Generated all-required responses pass with the expanded dynamic default case count.
  - [ ] Targeted selection includes at least one newly covered skill from this slice.
  - [ ] Prompt emission checks include representative prompts for all five new skills.

### Component 4: Complete First-Class Coverage Documentation
- **What:** Update public and design docs from ten-skill expanded coverage to complete first-class coverage.
- **Files:** modify `README.md`; modify `docs/evals/README.md`; modify `docs/skill-contract-design-guide.md`; modify `skills/assistant-skill-creator/references/skill-contract-design-guide.md`.
- **Depends on:** Components 1 through 3.
- **Verification criteria:**
  - [ ] Docs list or describe coverage for all 15 first-class `assistant-*` skills.
  - [ ] Docs continue to state local-only Unity fixtures remain excluded unless `--include-local` is passed.
  - [ ] Docs continue to describe local heuristic grading as a provider-neutral proxy, not semantic judgment.

## Plan
Plan approval: yes, approved by user on 2026-05-08

## Goal
- Complete provider-neutral per-skill eval fixture coverage for all 15 first-class `assistant-*` skills.
- Add skill-local fixtures for `assistant-diagrams`, `assistant-docs`, `assistant-ideate`, `assistant-reflexion`, and `assistant-telos`.
- Update P0/P4 contracts and docs so the complete first-class coverage state is visible and guarded.

## Constraints & decisions from Discovery
- The eval runner stays local and provider-neutral; no model calls, provider SDKs, or network behavior are added.
- Fixtures stay beside the skills at `skills/<skill>/evals/cases.json`.
- Default inventory continues to include first-class `assistant-*` fixtures and exclude local-only `unity-*` fixtures unless `--include-local` is passed.
- Coverage should be described as complete first-class assistant-skill coverage, not complete local-only Unity coverage.
- Machine expectations should use stable contract labels and exact casing.
- Non-goal: semantic LLM judging, provider-specific adapters, or a coverage-report command in this slice.

## Research
- Modules/subprojects: shell eval runner under `tools/evals/`; skill instructions under `skills/assistant-*`; P0/P4 contracts under `tests/p0-p4/`; docs under `README.md`, `docs/evals/README.md`, and contract design guides.
- Key files/paths:
  - `tools/evals/run-skill-evals.sh`
  - `tests/p0-p4/skill-eval-contracts.sh`
  - `README.md`
  - `docs/evals/README.md`
  - `docs/skill-contract-design-guide.md`
  - `skills/assistant-skill-creator/references/skill-contract-design-guide.md`
  - `skills/assistant-diagrams/SKILL.md`
  - `skills/assistant-docs/SKILL.md`
  - `skills/assistant-ideate/SKILL.md`
  - `skills/assistant-reflexion/SKILL.md`
  - `skills/assistant-telos/SKILL.md`
- Existing patterns:
  - Fixtures use `schema_version`, `suite_id`, `skill`, provider-neutral flags, `recommended_use`, and `cases`.
  - Each case includes `id`, `title`, `category`, `purpose`, `prompt`, `setup_context`, `expected_behavior`, `pass_criteria`, `fail_signals`, and `machine_expectations`.
  - P0/P4 keeps total fixture and case counts dynamic while asserting representative rows, prompt files, inventory fixture paths, and docs wording.

## Architecture
- Current architecture: skill-local JSON fixtures are discovered and validated by a shell runner; docs and P0/P4 contracts describe the supported surface.
- Architecture for this change: add five more fixture suites using the existing schema, then update tests/docs. No runner changes are planned.
- Layer rules:
  - Skill behavior examples live with each skill.
  - Generic runner/schema logic stays under `tools/evals/lib/`.
  - P0/P4 checks guard stable public behavior, representative default inventory rows, and coverage docs.
  - Docs describe actual implemented coverage and keep local-only exclusions explicit.
- Dependency direction: skill fixtures -> runner validation/listing/emission/grading -> P0/P4 contracts -> docs.
- New files placement:
  - `skills/assistant-diagrams/evals/cases.json`
  - `skills/assistant-docs/evals/cases.json`
  - `skills/assistant-ideate/evals/cases.json`
  - `skills/assistant-reflexion/evals/cases.json`
  - `skills/assistant-telos/evals/cases.json`
- SOLID design notes:
  - SRP: fixtures describe observable skill behavior only; runner code continues to own execution mechanics.
  - OCP: adding full coverage should require fixture/docs/test additions only, not modifying discovery internals.
  - DIP: docs and contract tests depend on runner outputs and fixture paths, not hidden runner internals.

## Analysis
### Options
1. Add only the five fixture files. Fast, but docs and P0/P4 would understate implemented coverage.
2. Add fixtures plus focused P0/P4 and docs updates. Bounded and keeps drift guarded.
3. Build a coverage-report command first. Useful soon, but larger than this coverage-completion slice.

### Decision
- Chosen: option 2. It completes first-class fixture coverage without changing the runner and keeps public coverage statements test-backed.

### Risks / edge cases
- Required substrings can become too brittle. Mitigation: use stable contract/output labels rather than full prose sentences.
- Docs/diagrams fixtures can imply unsupported hallucinated outputs. Mitigation: require source evidence, gaps, review-needed, and forbid memory-only/aspirational claims.
- Ideation fixtures can be large. Mitigation: enforce phase and count labels rather than every generated idea.
- Telos fixtures can imply writing user files in tests. Mitigation: fixture prompts test output discipline; runner remains offline and does not execute skill side effects.
- Docs can overstate coverage. Mitigation: say all 15 first-class skills are covered while local-only Unity skills remain excluded by default.

## Task packets

### Task 1: Diagram And Docs Fixtures
- Behavior / acceptance criteria:
  - `assistant-diagrams` has cases covering code-derived architecture diagrams and ambiguous diagram scope/input handling.
  - `assistant-docs` has cases covering code-derived architecture documentation and changelog/source-history documentation.
  - Both fixtures validate through the existing schema with non-empty required and forbidden machine expectations.
- Files:
  - Create: `skills/assistant-diagrams/evals/cases.json`, `skills/assistant-docs/evals/cases.json`.
  - Modify: none.
  - Test: runner validation/listing through `tools/evals/run-skill-evals.sh`.
- TDD / RED step:
  - Applies: no. This component adds eval fixture data and validates it with the existing runner.
  - RED command: N/A.
  - Expected failure: N/A.
- Implementation notes / constraints:
  - Use stable labels such as `diagram_type`, `diagram_code`, `mermaid`, `Evidence`, `Placement`, `Gaps`, `files_updated`, `doc_coverage`, and `review_needed`.
  - Forbidden substrings should catch memory-only diagrams, aspirational boxes, hallucinated features, and generic docs not tied to code.
- Verification:
  - Command: `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-diagrams --skill assistant-docs && tools/evals/run-skill-evals.sh --list --skill assistant-diagrams --skill assistant-docs`
  - Expected success signal: exit code 0 and list rows for both new skills.
- Deviation / rollback rule:
  - If a behavior cannot be represented with deterministic substrings, move brittle wording into human pass criteria and keep machine expectations on stable output labels.
- Worker status / evidence:
  - Status: pending.
  - Evidence: pending.

### Task 2: Ideate, Reflexion, And Telos Fixtures
- Behavior / acceptance criteria:
  - `assistant-ideate` has cases covering diverge-before-converge discipline and decision/refinement output.
  - `assistant-reflexion` has cases covering post-task reflection storage and pre-task lesson recall.
  - `assistant-telos` has cases covering TCF creation core sections and TCF review findings.
  - All fixtures validate through the existing schema with non-empty required and forbidden machine expectations.
- Files:
  - Create: `skills/assistant-ideate/evals/cases.json`, `skills/assistant-reflexion/evals/cases.json`, `skills/assistant-telos/evals/cases.json`.
  - Modify: none.
  - Test: runner validation/listing through `tools/evals/run-skill-evals.sh`.
- TDD / RED step:
  - Applies: no. This component adds eval fixture data and validates it with the existing runner.
  - RED command: N/A.
  - Expected failure: N/A.
- Implementation notes / constraints:
  - Use stable phase and output labels such as `UNDERSTAND`, `DIVERGE`, `CONVERGE`, `REFINE`, `DECIDE`, `8 ideas`, `memory_reflect`, `lessons`, `confidence`, `TCF`, `problems`, `mission`, `goals`, `review_findings`, and `confirmation`.
  - Avoid implying real memory or TCF writes are performed by the offline eval runner.
- Verification:
  - Command: `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-ideate --skill assistant-reflexion --skill assistant-telos && tools/evals/run-skill-evals.sh --list --skill assistant-ideate --skill assistant-reflexion --skill assistant-telos`
  - Expected success signal: exit code 0 and list rows for all three new skills.
- Deviation / rollback rule:
  - If output labels differ between SKILL.md and contracts, prefer the contract terms and add docs/test wording consistently.
- Worker status / evidence:
  - Status: pending.
  - Evidence: pending.

### Task 3: P0/P4 Eval Contract Expansion To 15
- Behavior / acceptance criteria:
  - Default validation output explicitly includes all 15 first-class fixture suites.
  - List output includes representative rows for all five newly covered skills.
  - Generated all-required response grading passes with the expanded dynamic default case count.
  - Targeted selection coverage includes a newly covered skill from this slice.
  - Prompt emission checks include representative prompts for all five newly covered skills.
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
  - Avoid duplicating fixture schema validation logic.
  - Use representative exact rows that are stable and useful for drift detection.
- Verification:
  - Command: `bash tests/p0-p4/skill-eval-contracts.sh`
  - Expected success signal: suite exits 0 and reports all skill eval contract tests passed.
- Deviation / rollback rule:
  - If exact row assertions become noisy, assert fixture path presence plus targeted output for one stable case per new skill group.
- Worker status / evidence:
  - Status: pending.
  - Evidence: pending.

### Task 4: Complete First-Class Coverage Documentation
- Behavior / acceptance criteria:
  - README and eval docs state current default coverage is all 15 first-class `assistant-*` skills and list or name the five new fixtures.
  - Docs continue to say local-only Unity skills are excluded by default unless `--include-local` is passed.
  - Contract design guides describe complete first-class per-skill coverage while preserving the provider-neutral heuristic grading limitation.
- Files:
  - Create: none.
  - Modify: `README.md`, `docs/evals/README.md`, `docs/skill-contract-design-guide.md`, `skills/assistant-skill-creator/references/skill-contract-design-guide.md`.
  - Test: docs are covered by inspection plus P0/P4 docs-drift assertions.
- TDD / RED step:
  - Applies: no. This component updates documentation; contract tests from Task 3 cover executable behavior.
  - RED command: N/A.
  - Expected failure: N/A.
- Implementation notes / constraints:
  - Do not claim semantic LLM judging.
  - Do not claim local-only Unity skills are part of default coverage.
  - Keep command examples unchanged unless required by the expanded coverage.
- Verification:
  - Command: `bash tests/test-p0-p4-contracts.sh && git diff --check`
  - Expected success signal: aggregate P0/P4 exits 0 and whitespace check exits 0.
- Deviation / rollback rule:
  - If docs need a new coverage phrase, keep it consistent across README, eval docs, top-level contract guide, and bundled skill-creator guide before continuing.
- Worker status / evidence:
  - Status: pending.
  - Evidence: pending.

## Tests to run
- `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-diagrams --skill assistant-docs`
- `tools/evals/run-skill-evals.sh --list --skill assistant-diagrams --skill assistant-docs`
- `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-ideate --skill assistant-reflexion --skill assistant-telos`
- `tools/evals/run-skill-evals.sh --list --skill assistant-ideate --skill assistant-reflexion --skill assistant-telos`
- `tools/evals/run-skill-evals.sh --validate-fixture`
- `tools/evals/run-skill-evals.sh --list`
- `bash tests/p0-p4/skill-eval-contracts.sh`
- `bash tests/test-p0-p4-contracts.sh`
- `git diff --check`

## Build Progress
- Component 1: Diagram And Docs Fixtures - DONE.
- Component 2: Ideate, Reflexion, And Telos Fixtures - DONE.
- Component 3: P0/P4 Eval Contract Expansion To 15 - DONE.
- Component 4: Complete First-Class Coverage Documentation - DONE.

## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved four-component plan; five new skill-local fixture suites; expanded P0/P4 contract; README/eval docs/contract-guide coverage wording; workflow task artifacts.
- Missing acceptance criteria: none.
- Extra scope: none outside expected `.codex/` workflow state artifacts.
- Changed files mismatch: none.
- Verification evidence mismatch: none.
- Required fixes: none.

### Quality Review #1
- Result: ISSUES_FOUND
- Rubric required: true
- Rubric scores:
  | Dimension | Score | Weight | Justification |
  |---|---:|---:|---|
  | Correctness | 4.5 | 0.30 | Product fixtures, P0/P4 assertions, and docs matched the approved scope; `.codex/context-map.md` still described pre-build 10/15 coverage as current. |
  | Code Quality | 5.0 | 0.20 | Fixture JSON and shell assertions follow existing naming, structure, and deterministic substring patterns. |
  | Architecture | 5.0 | 0.20 | Fixture data stayed skill-local and did not change runner/provider architecture. |
  | Security | 5.0 | 0.15 | Offline fixture/docs changes add no secret, network, auth, or data-exposure surface. |
  | Test Coverage | 5.0 | 0.15 | Direct fixture validation/listing, expanded P0/P4, aggregate P0/P4, and whitespace checks cover the slice. |
  | Weighted | 4.85 | 1.00 | REFINE due to one workflow-artifact correctness issue. |
- Findings:
  - SHOULD-FIX: `.codex/context-map.md` used "Current Eval Surface" while still saying default coverage was 10 of 15 and listing the five new skills as remaining. Risk category: correctness; affected surface: task workflow artifact and handoff context. Fix: update the context map to describe complete 15-skill first-class coverage and name the five skills as newly covered.
- Fixed in round:
  - Updated `.codex/context-map.md` coverage and tests/docs bullets to the post-build state.
- Validation after fix:
  - `git diff --check` passed.

### Quality Review #2
- Result: CLEAN
- Rubric required: true
- Rubric scores:
  | Dimension | Score | Weight | Justification |
  |---|---:|---:|---|
  | Correctness | 5.0 | 0.30 | All approved acceptance criteria are implemented and recorded; context artifacts now match the completed coverage state. |
  | Code Quality | 5.0 | 0.20 | Changes remain data/docs/test-contract focused and consistent with existing fixture and P0/P4 style. |
  | Architecture | 5.0 | 0.20 | No runner internals or provider behavior changed; coverage extension uses the existing skill-local fixture architecture. |
  | Security | 5.0 | 0.15 | No executable security-sensitive surface was added; local-only Unity opt-in remains explicit. |
  | Test Coverage | 5.0 | 0.15 | Expanded direct P0/P4, aggregate P0/P4, fixture validation/listing, and final whitespace validation are clean. |
  | Weighted | 5.00 | 1.00 | PASS. |
- Findings: none.
- Remaining items: none.

### Final Review Result
- Result: ISSUES_FIXED
- Rounds: 2
- Spec review result: PASS
- Quality review result: CLEAN

## Documentation / Closeout
- README now states complete first-class skill eval coverage for all 15 tracked `assistant-*` skills and keeps local-only Unity skills opt-in through `--include-local`.
- `docs/evals/README.md` lists all 15 first-class fixture paths and describes local heuristic grading as a provider-neutral proxy rather than semantic judgment.
- Top-level and bundled skill-creator contract design guides now describe complete first-class per-skill eval fixtures.
- Task workflow artifacts record component verification, Spec Review PASS, and rubric-scored Quality Review CLEAN.

## Final Verification
- `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-diagrams --skill assistant-docs` - passed.
- `tools/evals/run-skill-evals.sh --list --skill assistant-diagrams --skill assistant-docs` - passed; listed four cases.
- `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-ideate --skill assistant-reflexion --skill assistant-telos` - passed.
- `tools/evals/run-skill-evals.sh --list --skill assistant-ideate --skill assistant-reflexion --skill assistant-telos` - passed; listed six cases.
- `tools/evals/run-skill-evals.sh --validate-fixture` - passed; 15 fixtures validated.
- `tools/evals/run-skill-evals.sh --list` - passed; 30 cases listed.
- `bash tests/p0-p4/skill-eval-contracts.sh` - passed; 24 checks.
- `bash tests/test-p0-p4-contracts.sh` - passed; 117 checks after removing stray generated `tests/.DS_Store`.
- `git diff --check` - passed.
- `find tests -type f -name .DS_Store -print` - passed with no output.

## Component Verification Ledger
| Component | Status | Command / Evidence | Criteria |
|---|---|---|---|
| 1. Diagram And Docs Fixtures | VERIFIED | `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-diagrams --skill assistant-docs` passed; `tools/evals/run-skill-evals.sh --list --skill assistant-diagrams --skill assistant-docs` listed four cases. | Both fixture files validate; list output includes diagram and docs behavior cases; machine expectations include code-derived evidence, Mermaid/diagram output, docs coverage, placement, gaps, and review-needed output. |
| 2. Ideate, Reflexion, And Telos Fixtures | VERIFIED | `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-ideate --skill assistant-reflexion --skill assistant-telos` passed; `tools/evals/run-skill-evals.sh --list --skill assistant-ideate --skill assistant-reflexion --skill assistant-telos` listed six cases. | All three fixture files validate; list output includes ideation, reflexion, and Telos cases; machine expectations include phase labels, scoring criteria, memory_reflect, lessons confidence, TCF core sections, review findings, and confirmation. |
| 3. P0/P4 Eval Contract Expansion To 15 | VERIFIED | `tools/evals/run-skill-evals.sh --validate-fixture` passed with 15 fixtures; `tools/evals/run-skill-evals.sh --list` listed 30 cases; `bash tests/p0-p4/skill-eval-contracts.sh` passed 24 checks. | Default validation includes all 15 first-class fixture suites; representative rows and prompt packets cover all five new skills; generated all-required responses pass; targeted selection includes `assistant-telos`. |
| 4. Complete First-Class Coverage Documentation | VERIFIED | `bash tests/test-p0-p4-contracts.sh` passed 117 checks after removing stray generated `tests/.DS_Store`; `git diff --check` passed. | Docs describe complete coverage for all 15 first-class `assistant-*` skills, keep local-only Unity exclusion explicit, and retain provider-neutral heuristic grading language. |
