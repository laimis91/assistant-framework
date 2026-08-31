# QA Evaluation Loop

Use this reference after build/test evidence and the Code Reviewer loop exist. QA evaluation is a separate acceptance lane: it decides whether the work satisfies the Done Contract, acceptance criteria, verification evidence, and scoped domain quality expectations. It does not replace code-reviewer.

## When QA Runs

QA required positive triggers: explicit QA/acceptance evaluation request, accepted Done Contract, harness-capable acceptance scope, domain-scored scope, or scoped UI/visual/product/UX/docs/DX acceptance.
A carried `approved_feature_preparation_qa_acceptance_obligation` also requires QA.
QA non-triggers: template labels/placeholders, generic acceptance criteria labels, optional/not_required reasons, delegation/source-changing work alone, and ordinary medium+ code-review-only/source-changing work.

Run QA evaluation when any of these are true:
- The user explicitly asks for QA or acceptance evaluation.
- The task has an accepted Done Contract.
- The task is harness-capable and acceptance evaluation is in scope.
- The task has domain-scored scope or scoped UI/visual/product/UX/docs/DX acceptance.
- Workflow Review needs a final acceptance verdict because one of the positive triggers above is present.

Skip QA evaluation when the task has no explicit QA request, Done Contract, harness-capable acceptance scope, domain-scored criteria, or UI/visual/product/UX/docs/DX scope, and the workflow output records `qa_evaluation_mode=not_required` with a reason. Template labels/placeholders, generic acceptance criteria labels, optional/not_required reasons, delegation/source-changing work alone, and ordinary medium+ code-review-only/source-changing work do not force QA.

## Inputs

The orchestrator provides:
- `done_contract`: done_when, not_done_when, verification, owner_consumer, acceptance_criteria, debate_record, accepted_by.
- `debate_record`: pre-build debate/subagent-perspective evidence from the Done Contract; required when a Done Contract exists.
- `acceptance_criteria`: binary criteria from the user request, approved plan, slice manifest, or Done Contract.
- `verification_evidence`: build/test/manual/check evidence already produced by Builder/Tester or direct fallback.
- `code_review_result`: final Code Reviewer or Reviewer compatibility result.
- `domain_context`: scoped UI/visual, product, UX, docs, DX, or domain notes when applicable.
- `rubric_refs`: explicit references to scoped domain rubric families from `references/domain-rubrics.md` when applicable.
- `round`: QA round number from 1 to 10.
- `previously_failed_acceptance_items`: failed acceptance items from earlier QA rounds.
- `qa_filter_policy`: acceptance findings require acceptance criteria, Done Contract, verification evidence, scoped domain-context support, and debate_record when Done Contract exists; speculative concerns stay non-blocking.
- `approved_feature_preparation_qa_acceptance_obligation` when carried: requested_scope, execution_prerequisite, and exactly one source_feature_preparation_evidence_ref or source_preparation_basis=not_applicable. It makes `qa_evaluation_mode=required`.

## Conditional Domain Rubrics

Load `references/domain-rubrics.md` only when `domain_context` or `rubric_refs` are present, or when acceptance criteria / Done Contract explicitly require subjective, product, UX, docs, DX, UI/visual, or domain craft judgment.

When loaded:
- Select only rubric families tied to acceptance criteria, Done Contract, `domain_context`, or explicit `rubric_refs`.
- Return `selected_domain_rubrics` and `domain_quality_scores`.
- Keep domain findings evidence-backed and scoped to acceptance impact.
- Use `not_applicable` only for an unscoped dimension, assign exactly 5.0, and state `not_applicable` or `unscoped` explicitly in its evidence.

When not loaded:
- Set `domain_quality` to 5.0 and state `not_applicable` in the score rationale.
- Do not invent domain rubrics, subjective standards, or extra acceptance bars.
- Do not penalize the work for missing domain evidence that was never scoped.

## Loop

```text
round = 1
previously_failed_acceptance_items = []
score_progression = []

while round <= 10:
  1. EVALUATE ACCEPTANCE
     Dispatch qa-evaluator in delegated mode, or use direct fallback with fresh QA context.
     Before dispatch and after any QA pause, rehash source material and require exact equality with the current complete final review batch. Source mutation requires validation, invalidation, and a fresh complete review batch before QA resumes; no stale review result may enter QA. When the carried obligation exists, verify execution_prerequisite before requested_scope; block if prerequisite or evidence is missing rather than dropping the obligation. Return its unchanged requested_scope, execution_prerequisite, feature_preparation_scope, and the exact conditional source ref or not_applicable basis with status/evidence.
     Check every acceptance criterion, Done Contract item, and Done Contract debate_record independently when a Done Contract exists.
     Compare verification evidence to the claimed outcome.
     Conditionally load and apply references/domain-rubrics.md only for scoped domain-quality acceptance.

  2. SCORE
     Return qa_scorecard with compact dimensions:
       acceptance_coverage, evidence_strength, domain_quality, final_readiness, weighted_score
     Compute `weighted_score = round_half_up((acceptance_coverage * 0.30) + (evidence_strength * 0.25) + (domain_quality * 0.20) + (final_readiness * 0.25), 2 decimal places)`.
     Return selected_domain_rubrics and domain_quality_scores when domain rubrics were selected.
     Record score_entry: round, weighted_score, failed_acceptance_count, delta, drift_status.
     Round 1 uses `delta=initial` and `drift_status=NOT_APPLICABLE` or `NEUTRAL`. Every later `delta` is the exact signed two-decimal difference from the immediately preceding weighted score. Derive status from that adjacent transition: a negative delta is REGRESSION; a positive delta with fewer failed items is GENUINE (SUSPICIOUS when greater than 1.00), otherwise a positive delta is DRIFT; two consecutive zero-score transitions with the same positive failed-item count end in STAGNATION; other zero deltas are NEUTRAL.
     If score progression reports terminal STAGNATION, two consecutive terminal DRIFT entries, two consecutive terminal REGRESSION entries,
     or selected domain rubric action pivot, return pivot_restart_signal to the
     orchestrator before another QA/build dispatch.

  3. DECIDE
     accepted: no failed acceptance items and evidence proves done.
     accepted_with_concerns: acceptance passes with documented non-blocking limitations.
     rejected: one or more acceptance or Done Contract items fail.
     blocked: required acceptance material or verification evidence is missing.

  4. FIX OR EXIT
     If rejected before round 10, return failed acceptance items to Build for fixes, then re-run QA.
     If blocked, return NEEDS_CONTEXT or BLOCKED with open_questions.
     If a carried obligation exists, accepted/CLEAN, accepted/ISSUES_FIXED, accepted_with_concerns/CLEAN, and accepted_with_concerns/ISSUES_FIXED require requested_scope_status=fulfilled, execution_prerequisite_status=met, exact carried binding, and evidence. Otherwise return rejected/HAS_REMAINING_ITEMS or blocked/BLOCKED. Only then may accepted or accepted_with_concerns exit with the final result.
     Round 10 is terminal; return remaining failed acceptance items instead of starting round 11.
     If pivot_restart_signal was returned, pause QA until the orchestrator
     records pivot_restart_decision with exact_next_action.
```

## Finding Rules

QA findings are about acceptance, not general code quality:
- Failed acceptance criterion.
- Done Contract item not proven or contradicted by evidence.
- Done Contract debate_record is missing, has fewer than two perspectives, or does not show pre-build debate/subagent-perspective evidence when a Done Contract exists.
- Verification evidence mismatch or missing proof.
- Product, UX, docs, DX, or domain issue only when scoped by acceptance criteria, Done Contract, domain_context, or rubric_refs.

Do not report generic code defects, architecture concerns, security issues, or test coverage gaps unless they directly cause an acceptance failure. Those remain Code Reviewer responsibility.

## Final Result

The QA loop returns one final result:
- `rounds`: 1-10.
- `final_verdict`: accepted, accepted_with_concerns, rejected, or blocked.
- `result`: CLEAN, ISSUES_FIXED, HAS_REMAINING_ITEMS, or BLOCKED.
- `acceptance_findings`: remaining or resolved acceptance findings with evidence.
- `qa_scorecard`: final compact scores.
- `selected_domain_rubrics`: selected rubric families when scoped domain rubrics were used; empty or omitted when not applicable.
- `domain_quality_scores`: per-family/per-dimension scores when scoped domain rubrics were used; empty or omitted when not applicable.
- `score_progression`: same canonical projection: `round` (int), `weighted_score` (float), `failed_acceptance_count` (int), exact adjacent `delta` (string), and derived `drift_status` (the canonical enum), per round.
- `pivot_restart_signal`: required when QA ends in STAGNATION, two consecutive terminal DRIFT entries, two consecutive terminal REGRESSION entries, or a scoped domain action pivot is detected; nonconsecutive historical entries do not trigger it.
- `evidence`: materials inspected and why they prove or fail acceptance.
- `open_questions`: required when blocked.

## Pivot/Restart Escalation

QA does not silently continue after stagnant or pivot-triggered acceptance loops.
When it returns `pivot_restart_signal`, the orchestrator records
`pivot_restart_decision` with trigger, evidence, affected_slice_or_round,
options_considered, selected_action, reapproval_required, next_agent,
recovery_pointer, and exact_next_action. Update harness trace/replay/run-state
when available. Reapproval is required when the selected action changes scope,
files, behavior, risk, verification, or acceptance criteria.
