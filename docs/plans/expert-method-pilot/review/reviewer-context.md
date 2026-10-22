---
name: assistant-review
description: "Review code, fix actionable findings, and run one fresh re-review. Use for explicit code review or the workflow Review phase; QA runs only when required."
---

# Review

## Shared operating guidance

Load [the common outcome guidance and shared stagnation policy](../../tools/progress/operating-guidance.md) for this activity. Keep specialist methods, authority and completion evidence below; single-pass work needs no progress artifact.


Find concrete defects and regressions within scope. Read the diff and connected
callers, contracts, tests and configuration, including affected consumers outside
the diff. Findings require real input/situation, file/line evidence, impact,
calibrated confidence and the smallest useful fix. Style taste/speculation stays
non-blocking. Preserve carried reduced-testing boundary/source through criteria,
verification evidence and material snapshot refs. Additional tests require a
distinct important uncovered failure and inadequate-existing-evidence rationale;
scores/generic coverage advice cannot expand scope. Return material expansion
to selection/approval.

## Authority and scope

Resolve reviewed material from explicit scope, then uncommitted changes, carried
packet/journal, or current files. Block if required material is unavailable or
empty. A report-only request is audit; clear edit authorization permits review-fix
within its approved scope. If edit authority is materially unresolved, ask whether
to report only or implement and verify fixes; do not review or mutate while unresolved.
Ownership or access alone never grants edit authority.
Standalone `review this` does not require a task journal.

Use local company-safe diffs/checks; external scans, reviews, and installs retain
explicit approval. Redact secrets and private data. Preserve dirty work and return
out-of-scope findings to the composing workflow.

## Review process

Load `contracts/index.yaml` at the structured review boundary, then entry and
applicable architecture inputs. For behavior or cosmetic changes, a carried
change-impact artifact, or a locality/shared/unresolved decision, load
`change_impact` and [change-impact.md](references/change-impact.md) before planning
or dispatch. Keep this guidance outside Reviewer bundles.

Load [review-loop.md](references/review-loop.md) before the first batch; it owns
transitions, frozen snapshot identity, response
barriers, aggregation, and pivots. The current v9 protocol remains authoritative:

- Each frozen batch plans and attempts at least two independent, sibling-blind
  passes. Resolve `reviewer_context` for each pass, the selected handoff before
  dispatch/return, and `return_validation` before aggregation. Account for every
  expected pass; incomplete coverage returns `HAS_REMAINING_ITEMS`.
- Standalone review checks the user's specification. Audit retains mismatches
  as findings and finishes one read-only batch. Review-fix repairs authorized
  mismatches and requires Spec PASS before quality review. Workflow-composed
  review consumes carried Spec PASS and current due-check evidence.
- Review only relevant spec, regression, testing, maintainability, bugfix,
  semantic/behavioral contract, loop-safety, and security concerns. Fresh bundles
  use applicable sections of [review-checklists.md](references/review-checklists.md)
  and [review-principles.md](references/review-principles.md); do not fill every
  checklist for unrelated work. Medium+ retains its Design Coherence Pass.
- Review applicable Architecture Decision Packs, including invalid ones, for
  freshness, ownership/lifecycle, design pressures, types/primitive exceptions,
  quality evidence, compatibility, and handoff. Preserve independent challenge
  when `review_intensive` applies.
- Before workflow-composed mutation, preserve or refresh the canonical verification
  selection under `F_REVIEW_VERIFICATION_SELECTION`. An active TDD finding goes
  back to the Build owner with its identities, oracle, scope, IDs, and bindings;
  the review fixer cannot bypass RED. Standalone review-fix retains build/tests.
- After a fix, verify due selected/binding checks against the new source, freeze
  a fresh snapshot, and run a fresh complete review batch. No-build admission
  applies only when no fix is required/occurred and no due selected or executable
  binding check exists. A source fix forbids it.

The change-impact projection does not replace canonical snapshot/coverage closure. Missing/invalid
selectors load the full named contract. Load
[legacy-compatibility.md](references/legacy-compatibility.md) only for persisted
pre-v9 results; do not reinterpret historical evidence as a current clean batch.

## QA and stopping

QA stays separate from code review and runs after Build and Code Reviewer evidence
only when explicit QA/acceptance, accepted Done Contract, harness acceptance,
domain-scored scope, or scoped UI/visual/product/UX/docs/DX acceptance requires it.
Size, delegation, source changes, and generic acceptance labels do not trigger QA.
Load [qa-evaluation-loop.md](references/qa-evaluation-loop.md) when required and
[domain-rubrics.md](references/domain-rubrics.md) only for scoped domain quality.
Carry approved preparation QA obligations and exact result/source bindings.

Audit stops after its first started batch, without fixes. Review-fix runs round 1,
authorized fixes and validation, then fresh round 2. Round 3+ requires changed
files, unresolved findings, validation failure, regression/drift, or changed
hypothesis; score alone is insufficient. Productive rounds can continue beyond 10 under the same shared guard.
Medium+ score diagnostics use [score-tracking.md](references/score-tracking.md).
Require a recorded pivot/restart decision before another pass only for evidenced
shared semantic guard stagnation or an applicable material change. Score labels
alone do not require a decision, reset the evaluator, or pause productive work.

## Result

Report findings/fixes, scope, verification and material limits. No findings means
"No material findings within the reviewed scope and available evidence";
`CLEAN` is an enum, not proof. Consumers retain
`contracts/output.yaml`, canonical reviewed scope, batch/round evidence, required
checks and QA. `CLEAN`/`ISSUES_FIXED` require complete current coverage and no
remaining must-fix/should-fix items. Failed or blocked passes cannot claim clean.
Omit empty checklist and internal protocol sections from the human summary.

Load [review-finding-permanent-rule.md](references/review-finding-permanent-rule.md)
only for evidence of recurring process gaps or high-impact repeatable failures.
A finding does not automatically require a permanent rule or new framework.
Existing mapped all-ID distillation fixtures retain their consumed classification
envelope; that compatibility requirement does not govern ordinary human summaries.


# Applicability: structured review batches, worker handoffs, persisted results,
# and workflow/QA consumers use the canonical v9 protocol. Human summaries may
# omit empty/internal sections; frozen snapshots, independent passes, coverage,
# verification, authorization, and the shared semantic guard apply to every selected review.

schema_version: "9.0"
contract: index
skill: assistant-review

authoritative_contracts:
  - path: contracts/input.yaml
    contract: input
  - path: contracts/output.yaml
    contract: output
  - path: contracts/phase-gates.yaml
    contract: phase-gates
  - path: contracts/handoffs.yaml
    contract: handoffs

load_sets:
  entry:
    selectors:
      - id: review-entry-fields
        path: contracts/input.yaml
        section: fields
        key: name
        names: [review_scope, review_material_snapshot, scope_size, mode, change_kind, semantic_contract_review_required, behavioral_contract_review_required, agentic_loop_safety_review_required, architecture_decision_pack_review_required, architecture_design_mode, subagent_policy_state, subagent_execution_mode, subagent_trigger_scope, policy_blocking_source, harness_capable, qa_evaluation_mode, feature_preparation_scope, approved_feature_preparation_qa_acceptance_obligation, previously_fixed, persisted_v6_packet_migration, persisted_v7_0_packet_invalidation, persisted_v7_1_packet_invalidation, persisted_v7_2_packet_invalidation, persisted_v8_packet_invalidation]
    budget_words: 5000
  architecture_pack_input:
    selectors:
      - id: review-architecture-pack-input
        path: contracts/input.yaml
        section: fields
        key: name
        names: [architecture_decision_pack]
    budget_words: 3000
  change_impact:
    references: [references/change-impact.md]
    selectors:
      - id: review-change-impact-input
        path: contracts/input.yaml
        section: fields
        key: name
        names: [change_impact_applicability, change_impact_context]
      - id: review-change-impact-output
        path: contracts/output.yaml
        section: artifacts
        key: name
        names: [change_impact_applicability, change_impact_review_projection]
    budget_words: 2550
  current_round:
    selectors:
      - id: review-current-round-gate
        path: contracts/phase-gates.yaml
        section: gates
        key: phase
        name_from: active_review_step
        allowed_names: [ENTRY, REVIEW_STEP, EVALUATE_STEP, FIX_STEP, VALIDATE_STEP, QA_EVALUATION_STEP, EXIT]
      - id: review-round-invariants
        path: contracts/phase-gates.yaml
        section: invariants
        key: id
        names: [INV0, INV1, INV2, INV3, INV4, INV_BATCH, INV5, INV6, INV7, INV8, INV9, INV10, INV11, INV_CHANGE_IMPACT, INV_QA1, INV_QA2, INV_QA3, INV_QA4]
    budget_words: 12000
  selected_handoff:
    selectors:
      - id: review-selected-dispatch-context
        path: contracts/handoffs.yaml
        section: dispatch_context_bundles
        key: name
        name_from: selected_dispatch_context_name
        allowed_names: [fresh_reviewer_context, qa_evaluator_context]
    budget_words: 5000
  reviewer_context:
    references:
      - references/review-principles.md
      - references/review-checklists.md
      - references/review-rubric.md
    selectors:
      - id: fresh-reviewer-context-bundle
        path: contracts/handoffs.yaml
        section: dispatch_context_bundles
        key: name
        names: [fresh_reviewer_context]
    budget_words: 5653
  return_validation:
    selectors:
      - id: review-return-validation-bundle
        path: contracts/handoffs.yaml
        section: return_validation_bundles
        key: name
        name_from: selected_return_validation_name
        allowed_names: [reviewer_return_validation, qa_evaluator_return_validation]
    budget_words: 5000
  completion:
    selectors:
      - id: review-completion-artifact
        path: contracts/output.yaml
        section: artifacts
        key: name
        name_from: applicable_completion_artifact
        allowed_names: [review_delegation_path, qa_evaluation_delegation_path, pivot_restart_decision, review_finding_rule_distillation, final_summary, qa_evaluation_result, rubric_summary, agentic_loop_safety_review, behavioral_contract_review, semantic_contract_review, architecture_decision_pack_review, bugfix_evidence_review, build_verification, task_journal_entry, audit_report, change_impact_applicability, change_impact_review_projection]
    budget_words: 10000

fallback:
  on_missing_selector: load_full_authoritative_file
  on_invalid_selector: load_full_authoritative_file


---
name: fresh_reviewer_context
phase: REVIEW_STEP
selected_dispatch_context_ref: handoffs.orchestrator_to_reviewer.reviewer_pass_context_fields
review_evidence_pointer:
  required_refs:
  - pre_batch_criteria_ref
  - review_material_snapshot
  - build_test_verification_ref
context_fields_from_dispatch:
- review_preparation_mode
- pre_batch_criteria_ref
- build_test_verification_ref
- review_material_snapshot
- change_impact_applicability
- change_impact_evidence
- batch_id
- review_pass_id
- review_attempt_id
- review_perspective
- assigned_scope
- coverage_obligations
- review_focus
- scope_size
- round
- additional_round_reason
- previously_fixed
- finding_filter_policy
- project_type
- quality_principles_required
- reuse_search_instruction
- semantic_contract_review_required
- behavioral_contract_review_required
- agentic_loop_safety_review_required
- architecture_decision_pack_review_required
- architecture_design_mode
- architecture_decision_pack
- rubric_required
worker_references:
- path: references/review-principles.md
  sections:
  - all
- path: references/review-checklists.md
  sections:
  - name: Semantic Contract Review Checklist
    condition: semantic_contract_review_required is true
  - name: Behavioral Contract Review Checklist
    condition: behavioral_contract_review_required is true
  - name: Agentic Loop Safety Checklist
    condition: agentic_loop_safety_review_required is true
  - name: Architecture Decision Pack Review Checklist
    condition: architecture_decision_pack_review_required is true
  exclusion: Triggered only.
- path: references/review-rubric.md
  sections:
  - all
  condition: medium/large scope or rubric_required
direct_fallback: Sibling-blind; two passes.
excludes:
- review_batch
- pre_batch_findings
- sibling_outputs
worker_return_schema_selector:
  return_schema_ref: handoffs.orchestrator_to_reviewer.return_fields
  source_path: contracts/handoffs.yaml
  resolution: Worker recursively loads named handoff return_fields (bounded keys);
    worker_return_schema equals schema identified by return_schema_ref before response;
    else NEEDS_CONTEXT, no partial result.
  recursive_shape: Recursive required/conditional fields, types, enums, and cardinality.
  excludes: No sibling/batch state.
budget_words: 5653
budget_validation: SKILL plus index plus this selected bundle and its declared worst-case
  reference closure is strictly below 5653 words.


# Review Principles Lens

Use these principles as evidence lenses during code review. They are not standalone pass/fail laws. A finding is actionable only when it ties a specific observation to concrete risk and the smallest durable fix.

## SOLID

Apply SOLID primarily to object-oriented or dependency-heavy code:

- Single Responsibility: a unit should have one cohesive reason to change. Flag mixed policy, orchestration, I/O, formatting, persistence, and validation only when the mix makes change risky or tests brittle.
- Open/Closed: code should allow likely extension without repeatedly editing fragile core logic. Flag switch/if growth, scattered feature edits, or closed extension points when a current requirement already shows the pattern will churn.
- Liskov Substitution: subtypes, implementations, or strategy objects must preserve caller expectations. Flag implementations that narrow accepted inputs, weaken guarantees, throw unexpected exceptions, or require caller type checks.
- Interface Segregation: consumers should not depend on methods or data they do not use. Flag broad interfaces when they force no-op implementations, fake dependencies in tests, or unrelated callers to change together.
- Dependency Inversion: high-level policy should not be glued to low-level details at boundaries. Flag direct dependencies on infrastructure, time, randomness, network, filesystem, or framework APIs when they hide behavior or block testing.

## Design Coherence Pass

For every medium+ review, identify the affected unit, boundary, responsibility, and independent reasons to change. Assess hidden coupling/state and data/control flow. Record `principle_checks.design_coherence` as `no concrete risk found` or an evidence-backed finding with affected surface, risk, and smallest durable fix. Do not infer a finding from code size, structural diff shape, or familiar pattern alone; a cohesive unit may correctly conclude `no concrete risk found`.

## KISS

Prefer the simplest design that satisfies the verified requirement. Flag needless layers, abstractions, configuration, indirection, state, branching, concurrency, or patterns that make current behavior harder to read, test, or change. A small abstraction that removes real duplication, isolates side effects, or makes a current requirement safer may be simpler.

## DRY

DRY is about duplicated knowledge, not merely similar-looking code. Flag business rules, schemas, validation, calculations, mappings, config, permissions, or protocol details with multiple authoritative representations that can diverge. Do not merge coincidental or independently changing similarities into hidden coupling.

## Reuse Search and Authoritative Duplication

Before implementation and independently during review, search existing capabilities for business rules, validation, calculations/conversions, mappings, schema/config semantics, permissions, or protocol details. Duplicated authoritative behavior is should-fix, and must-fix when semantics differ or duplication caused the bug. Non-findings include coincidental similarity and independent concepts. Intentional boundary duplication needs divergence control. Check the Build reuse-first choice for sufficient affected consumers, validation
and error handling; shorter code alone proves nothing. Carried Mapper/task-packet evidence alone cannot satisfy review; record searches, candidates or no-candidate reason, decision, and rationale.

## YAGNI

Avoid imagined-future capability: flag speculative extension points, unused abstractions/config/parameters, anticipatory generic types, and future-only branches that add current complexity. YAGNI is not permission to neglect code health; it permits tests, health refactoring, and small seams around real side effects.

## State and Extensibility Modeling

### Nullable properties as hidden state

- Flag code when `null -> value` or `value -> null` represents a business or lifecycle transition, especially when rules, side effects, or required data depend on that change.
- Prefer named states and explicit transition methods or events that carry the required data.
- Do not flag nullable properties when `null` only means optional or missing data.

### Enums as extension points

- Flag an enum when it represents an open-ended feature set and adding a value requires changing switches or conditionals in several places.
- Prefer handlers, strategies, or another extensible design for open-ended cases.
- Do not flag enums that represent a small, stable, closed set.

## Readability

Readability is a human judgment of how easy code is to understand and safely maintain. Review for:

- names that reveal domain intent and avoid misleading abstractions
- small, cohesive functions/classes with explicit data flow
- straightforward control flow with low nesting and limited hidden state
- clear error paths and boundary behavior
- formatting and grouping that separate ideas without relying on comments
- comments that explain why, tradeoffs, or invariants rather than restating what
- tests that read as executable behavior examples

Report the specific comprehension burden: ambiguous name, mixed abstraction, non-local state, long conditional path, duplicated concept, misleading comment, or unclear test intent.

## Reporting Rule

Principle findings must include:

- lens: SOLID, KISS, DRY, YAGNI, readability, design coherence, or combination
- risk category: correctness, security, unsafe change surface, branching/responsibility growth, hidden dependency/ownership, brittle testing, poor extension seam, or readability/maintainability drag
- evidence: file, line, and observed behavior
- fix: the smallest durable change that removes the risk

Do not report vague findings without evidence and risk.


# Review Rubric

Structured scoring system for evaluator calibration. Replaces open-ended "find issues" with weighted dimensions and anchored examples.

## When to Use

- **Medium+ scope**: Full rubric scoring required — reviewer scores all 5 dimensions
- **Trivial/small scope**: Rubric scoring optional — reviewer may skip if review is a single-round clean pass
- **Audit mode**: Score but do not act on thresholds (report only)

## Dimensions

| Dimension | Weight | What It Measures |
|---|---|---|
| **Correctness** | 0.30 | Bugs, logic errors, edge cases, acceptance criteria met |
| **Code Quality** | 0.20 | Readability, naming, maintainability, right-sized SOLID/KISS/DRY/YAGNI adherence |
| **Architecture** | 0.20 | Layer boundaries, dependency direction, pattern consistency |
| **Security** | 0.15 | Injection, auth bypass, data exposure, OWASP top 10 |
| **Verification Evidence** | 0.15 | Selected verification methods, evidence quality, material gaps, and test quality when tests were selected |

## Clean-Code Principle Lens

Before scoring Code Quality and Architecture, load `references/review-principles.md`. Apply SOLID, KISS, DRY, YAGNI, and readability as concrete risk lenses. Do not score down for acronym-only preferences; score down when the reviewed material shows evidence of duplicated knowledge, speculative abstraction, hidden coupling, needless complexity, brittle responsibilities, or readability/maintainability drag.

## Score Anchors

Each dimension is scored 1-5. Use these anchors to calibrate:

### Correctness (weight: 0.30)

| Score | Anchor |
|---|---|
| **5** | All acceptance criteria met. Edge cases handled. No bugs found. Error paths are correct. |
| **4** | Core logic correct. Minor edge case missed but no user-facing impact. |
| **3** | Happy path works. 1-2 edge cases unhandled that could cause issues under specific conditions. |
| **2** | Core logic has a flaw that would manifest in normal usage. Regression risk. |
| **1** | Fundamental logic error. Would fail basic smoke testing. |

### Code Quality (weight: 0.20)

| Score | Anchor |
|---|---|
| **5** | Clear, self-documenting code. Names, control flow, responsibilities, and abstractions make intent easy to recover. SOLID/KISS/DRY/YAGNI are applied where they reduce real risk. |
| **4** | Readable and maintainable. Minor inconsistency or localized complexity, but no duplicated knowledge, speculative abstraction, or unclear responsibility that would meaningfully slow future change. |
| **3** | Works but some areas are hard to follow. Mixed abstraction levels, unclear names, mild duplication of knowledge, or slightly overbuilt seams create maintenance friction. |
| **2** | Multiple code smells. Large/mixed-responsibility units, misleading names, copy-paste business rules, unnecessary indirection, or speculative branches create concrete change risk. |
| **1** | Unmaintainable. Tangled logic, hidden state, broad interfaces, magic values, duplicated rules, or future-only architecture make safe modification impractical. |

### Architecture (weight: 0.20)

| Score | Anchor |
|---|---|
| **5** | Follows existing patterns exactly. Correct layer placement. Dependencies point inward. |
| **4** | Mostly aligned. One minor boundary concern (e.g., a helper in the wrong layer but low impact). |
| **3** | Works but introduces a new pattern where existing one applies. Or bypasses a layer for convenience. |
| **2** | Layer violation that will cause coupling issues. Domain depends on infrastructure. |
| **1** | Ignores project architecture entirely. Business logic in UI, SQL in controllers, circular deps. |

### Security (weight: 0.15)

| Score | Anchor |
|---|---|
| **5** | No security concerns. Inputs validated. Auth checked. Sensitive data handled correctly. |
| **4** | Secure by default. Minor hardening opportunity (e.g., could add rate limiting, not critical). |
| **3** | No active vulnerability but missing defense-in-depth (e.g., no input validation on internal API). |
| **2** | Exploitable vulnerability under specific conditions (e.g., SQL injection via crafted input). |
| **1** | Open vulnerability. Auth bypass, credential exposure, injection with no mitigation. |

### Verification Evidence (weight: 0.15; output key remains `test_coverage`)

| Score | Anchor |
|---|---|
| **5** | The selected methods address material claims with current, discriminating evidence; tests are meaningful and maintainable when selected; no material evidence gap is hidden. |
| **4** | Selected evidence is sound with one bounded noncritical gap, clearly recorded in the assessment. |
| **3** | Evidence supports the main claim but leaves a material boundary or scenario uncertain; the limitation is explicit. |
| **2** | Evidence is weak, stale, or poorly matched to selected claims, or tests selected for the change do not distinguish plausible wrong behavior. |
| **1** | Selected verification was skipped or misrepresented, or no available evidence supports the material claim. Absence of tests alone is not a failure when another selected method is adequate. |

## Calculating the Weighted Score

```
weighted_score = (correctness * 0.30) + (quality * 0.20) + (architecture * 0.20)
               + (security * 0.15) + (coverage * 0.15)
```

Example: correctness=4, quality=3.5, architecture=4, security=5, coverage=3
```
= (4 * 0.30) + (3.5 * 0.20) + (4 * 0.20) + (5 * 0.15) + (3 * 0.15)
= 1.20 + 0.70 + 0.80 + 0.75 + 0.45
= 3.90 → REFINE
```

## Threshold Actions

| Weighted Score | Action | What Happens |
|---|---|---|
| **4.0+** | **PASS** | Supports the findings-based exit. Minor nits remain non-blocking. |
| **3.0–3.9** | **REFINE** | Prioritizes existing evidence-backed findings. If none exist, record the score as residual risk and exit with the bounded claim. |
| **< 3.0** | **PIVOT** | Flag the evidence and strategy concern to the orchestrator. Another review pass still needs an allowed new-evidence reason. |

A score below threshold alone does not authorize round 3 or later. Rubric scores calibrate focus and residual risk; they do not manufacture findings, prove correctness, or justify repeated review without new evidence.

### Stable standards across rounds

Use the same severity, confidence and score anchors at every positive round
ordinal. Scores describe residual risk; PASS/REFINE/PIVOT are diagnostic labels,
not continuation authority. A low score or changing finding count cannot force
another pass, stop productive work, or manufacture findings. Apply the common
task guard using durable acceptance gains and useful new evidence.

## Reviewer Scoring Instructions

When scoring, the reviewer MUST:

1. **Score each dimension independently** — do not let one dimension's score influence another
2. **Reference specific code** — each score must cite at least one example from the reviewed material
3. **Use the anchors** — pick the anchor that most closely matches, then adjust +/- 0.5 if between anchors
4. **Never score higher than evidence supports** — when uncertain, round down
5. **Weight security appropriately** — a single critical vulnerability caps the weighted score at 2.0 regardless of other dimensions
6. **Apply principle checks with evidence** — use `references/review-principles.md`, but report SOLID/KISS/DRY/YAGNI/readability issues only when tied to concrete risk and the smallest durable fix

## Rubric Override: Critical Findings

Certain findings override the rubric score regardless of dimension scores:

| Finding Type | Effect |
|---|---|
| Active security vulnerability (exploitable) | Weighted score capped at 2.0 |
| Data loss risk | Weighted score capped at 2.0 |
| Build-breaking change | Weighted score capped at 1.0 |
| Test suite broken by changes | Weighted score capped at 2.5 |

## Output Format

The reviewer returns rubric scores in this structure:

```yaml
rubric_scores:
  correctness: 4.0
  code_quality: 3.5
  architecture: 4.0
  security: 5.0
  test_coverage: 3.0
  weighted_score: 3.90
  action: REFINE
  score_justification:
    correctness: "All CRUD operations correct. Edge case: bulk delete with empty list not handled (line 45)."
    code_quality: "Consistent naming. OrderService.Process() at 85 lines is borderline but acceptable."
    architecture: "Clean layer separation. Repository pattern matches existing conventions."
    security: "No user input reaches SQL. Auth middleware correctly applied to all new endpoints."
    test_coverage: "Happy path tested. Missing: concurrent access test for shared state in OrderCache."
```

Include `critical_override` only when a critical finding caps the score, as a string describing that override (for example, `Active SQL injection in SearchController:92 — caps score at 2.0`). Omit the field when no override applies.


## Semantic Contract Review Checklist

Use this checklist when reviewing changes to skills, workflow docs, contracts, evals, prompts, generated instructions, agent frameworks, or named-method adaptations. This is a semantic review, not just a YAML/Markdown syntax check.

1. **Inherited contract obligations**
   - If a specialized method/template is added inside an existing skill, confirm it still satisfies every base input/output artifact required by that skill.
   - If the method intentionally does not satisfy a base artifact, the base contract must be explicitly made conditional and evals must cover both paths.

2. **Template-contract alignment**
   - Check that method templates, `SKILL.md`, `contracts/output.yaml`, `contracts/input.yaml`, phase gates, handoffs, and references name the same artifacts and fields.
   - Required artifacts must include recovery guidance (`on_fail` or equivalent) where the contract design guide expects it.

3. **Eval coverage inheritance**
   - Evals for a new method must require both the new behavior and inherited base artifacts.
   - Machine expectations should fail on plausible incomplete responses, not only confirm the new section headings.

4. **External-method signature fidelity**
   - When adapting a named paper/tool/framework method, identify its defining loop before approving. Do not preserve only the visible surface shape.
   - Require a testable artifact proving the defining loop happened. Example: STORM requires perspective-guided questions, source-grounded answers, follow-up questions, then synthesis, not just fixed perspectives.

5. **High-stakes recommendation guard**
   - If the workflow can emit `do`, `wait`, `avoid`, approval, trade, legal, medical, security, safety, or other high-impact recommendations, require domain guardrails.
   - Guardrails should include educational/due-diligence framing where appropriate, risk/user-context caveats, verification requirements, and conservative defaults such as `investigate_further` unless stronger action is justified.

6. **Mirror surfaces**
   - Generated installer/global instruction templates, automation, docs, references, and eval contract tests must be synchronized with their canonical sources when they can drive the old behavior.

Treat missing inherited artifacts, template-contract drift, evals that pass incomplete outputs, method-signature drift, high-stakes recommendation guard gaps, or mirror-surface drift as must-fix or should-fix depending on release risk.

