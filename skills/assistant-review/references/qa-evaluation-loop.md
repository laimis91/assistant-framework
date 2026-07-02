# QA Evaluation Loop

Use this reference after build/test evidence and the Code Reviewer loop exist. QA evaluation is a separate acceptance lane: it decides whether the work satisfies the Done Contract, acceptance criteria, verification evidence, and scoped domain quality expectations. It does not replace code-reviewer.

## When QA Runs

Run QA evaluation when any of these are true:
- Medium+ harness-capable work has a Done Contract.
- The task is subjective, domain-scored, UI/visual/product/UX/docs/DX-facing, or explicitly asks for QA.
- Workflow Review needs a final acceptance verdict beyond code/security/architecture/test-coverage review.

Skip QA evaluation only when the task is trivial/small, has no acceptance material beyond a direct code fix, and the workflow output records `qa_evaluation_mode=not_required` with a reason.

## Inputs

The orchestrator provides:
- `done_contract`: done_when, not_done_when, verification, owner_consumer, acceptance_criteria, debate_record, accepted_by.
- `debate_record`: pre-build debate/subagent-perspective evidence from the Done Contract; required when a Done Contract exists.
- `acceptance_criteria`: binary criteria from the user request, approved plan, slice manifest, or Done Contract.
- `verification_evidence`: build/test/manual/check evidence already produced by Builder/Tester or direct fallback.
- `code_review_result`: final Code Reviewer or Reviewer compatibility result.
- `domain_context`: scoped UI/visual, product, UX, docs, DX, or domain notes when applicable.
- `rubric_refs`: explicit references to scoped domain rubric families from `references/domain-rubrics.md` when applicable.
- `round`: QA round number from 1 to 20.
- `previously_failed_acceptance_items`: failed acceptance items from earlier QA rounds.
- `qa_filter_policy`: acceptance findings require acceptance criteria, Done Contract, verification evidence, scoped domain-context support, and debate_record when Done Contract exists; speculative concerns stay non-blocking.

## Conditional Domain Rubrics

Load `references/domain-rubrics.md` only when `domain_context` or `rubric_refs` are present, or when acceptance criteria / Done Contract explicitly require subjective, product, UX, docs, DX, UI/visual, or domain craft judgment.

When loaded:
- Select only rubric families tied to acceptance criteria, Done Contract, `domain_context`, or explicit `rubric_refs`.
- Return `selected_domain_rubrics` and `domain_quality_scores`.
- Keep domain findings evidence-backed and scoped to acceptance impact.
- Use `not_applicable` for unscoped dimensions.

When not loaded:
- Set `domain_quality` to 5.0 and state `not_applicable` in the score rationale.
- Do not invent domain rubrics, subjective standards, or extra acceptance bars.
- Do not penalize the work for missing domain evidence that was never scoped.

## Loop

```text
round = 1
previously_failed_acceptance_items = []
score_progression = []

while round <= 20:
  1. EVALUATE ACCEPTANCE
     Dispatch qa-evaluator in delegated mode, or use direct fallback with fresh QA context.
     Check every acceptance criterion, Done Contract item, and Done Contract debate_record independently when a Done Contract exists.
     Compare verification evidence to the claimed outcome.
     Conditionally load and apply references/domain-rubrics.md only for scoped domain-quality acceptance.

  2. SCORE
     Return qa_scorecard with compact dimensions:
       acceptance_coverage, evidence_strength, domain_quality, final_readiness, weighted_score
     Return selected_domain_rubrics and domain_quality_scores when domain rubrics were selected.
     Record score_entry: round, weighted_score, failed_acceptance_count, delta, drift_status.
     If score progression reports STAGNATION, repeated DRIFT, repeated REGRESSION,
     or selected domain rubric action pivot, return pivot_restart_signal to the
     orchestrator before another QA/build dispatch.

  3. DECIDE
     accepted: no failed acceptance items and evidence proves done.
     accepted_with_concerns: acceptance passes with documented non-blocking limitations.
     rejected: one or more acceptance or Done Contract items fail.
     blocked: required acceptance material or verification evidence is missing.

  4. FIX OR EXIT
     If rejected before round 20, return failed acceptance items to Build for fixes, then re-run QA.
     If blocked, return NEEDS_CONTEXT or BLOCKED with open_questions.
     If accepted or accepted_with_concerns, exit with final result.
     Round 20 is terminal; return remaining failed acceptance items instead of starting round 21.
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
- `rounds`: 1-20.
- `final_verdict`: accepted, accepted_with_concerns, rejected, or blocked.
- `result`: CLEAN, ISSUES_FIXED, HAS_REMAINING_ITEMS, or BLOCKED.
- `acceptance_findings`: remaining or resolved acceptance findings with evidence.
- `qa_scorecard`: final compact scores.
- `selected_domain_rubrics`: selected rubric families when scoped domain rubrics were used; empty or omitted when not applicable.
- `domain_quality_scores`: per-family/per-dimension scores when scoped domain rubrics were used; empty or omitted when not applicable.
- `score_progression`: score_entry per round.
- `pivot_restart_signal`: required when QA STAGNATION, repeated DRIFT, repeated REGRESSION, or scoped domain action pivot is detected.
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
