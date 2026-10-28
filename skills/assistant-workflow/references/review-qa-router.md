# Review and QA Router

Internal reference for Review routing. Load during Review after Build evidence
exists. `references/phases.md` keeps the compact Review shell; this file owns
the final fresh acceptance review, its spec obligations, QA Evaluator routing,
status gates, pivot/shared stagnation handling, and verification-summary inputs
for Document.

## Review Lane Separation

Review has two distinct lanes:

1. The final fresh acceptance review (`assistant-review`,
   `review_subject=acceptance`) is the single owner of request, plan and
   delivery reconciliation. Code Reviewer owns code defects, security,
   architecture, test coverage, maintainability, and structural code risk; the
   same batch carries the spec obligations of
   `references/prompts/spec-review.md`. `reviewer` remains a compatibility
   route for existing/legacy handoffs.
2. QA Evaluator runs only when `qa_evaluation_mode=required` and only after
   build/test evidence plus Code Reviewer or Reviewer compatibility evidence
   exist. QA Evaluator owns acceptance, Done Contract readiness, verification
   evidence, final readiness, and scoped domain quality.

Quality findings alone cannot satisfy spec obligations: each obligation needs
its own covered result. QA Evaluation cannot substitute for the acceptance
review. Code Reviewer and QA Evaluator responsibilities stay separate.

## Review Authorization Gate

Before the acceptance review or source inspection/mutation, resolve
`assistant-review` mode from semantic modification authority. Clear report-only
intent selects audit. Explicit source-modification authorization, or a carried
active approved implementation workflow with bounded in-scope repairs, selects
review-fix. Authorship, branch/PR ownership, platform, and connector never
authorize edits. If audit versus editing remains materially unresolved, ask
exactly: "Should I only report findings, or also implement and verify fixes?"
and stop before reviewing or changing source until the user answers.

For light work, keep the review scope and evidence compact. A local self-check
is useful preparation, but formal completion review always uses a newly created
independent reviewer with fresh context. Trivial/small light work uses one such
reviewer covering spec obligations and quality, plus one fresh re-review after a
fix; medium+ code/acceptance review keeps at least two sibling-blind passes, with no
direct author fallback. Plan review is one fresh `plan_coverage_and_feasibility`
pass plus a fresh re-review after a material plan fix.

Ordinary light review and plan review record only a compact result: fresh
reviewer identity (actor id, native invocation id, lowercase `runtime`,
`fork_turns=none` on Codex), PASS or findings, evidence refs, and reviewed scope.
Each compact finding carries a stable id (for example `light-1`) plus file/line and
description; the lead keeps those ids. A fresh re-review after a fix uses a
reviewer distinct from the authors and first reviewer; it receives the fixed
findings as `{aggregate_finding_id, description}` rows, and its compact result
carries those resolved rows in `findings` and records `closure_results`
(`verified_closed`, `regressed` or `incomplete`) per `aggregate_finding_id` plus
`prior_reviewer_actor_ids`; closure ids equal the record's own finding ids, and
PASS requires every row `verified_closed`. Plan review records `plan_review_result`,
which adds `request_plan_reconciliation` coverage (required, observed and
unresolved requirement ids plus unresolved finding ids). Neither needs a batch plan,
ledgers, structured `fresh_dispatch` or review-tools validation. A
persisted/executable admission (for plan review, only that) or a carried
Architecture Decision Pack or expanded impact instead uses the structured
path; a Pack or expanded impact retains its existing canonical
`assistant-review/contracts/output.yaml#final_summary`, current snapshot and
`assistant-review/contracts/output.yaml#review_delegation_path` refs. Workflow
always passes its triage `controller_intensity` to assistant-review; a one-pass
light topology requires `controller_intensity=light` and
`topology.light_review=true`, while small standard/strict work keeps at least
two passes. Unavailable isolation is incomplete.

## Stage 1 - Retired Spec Review

Stage 1 is no longer a separate reviewer. Read historical `### Spec Review #N`
entries and `spec_review_result` records under their original labels; new
records come from the acceptance review's spec obligations.

## Stage 2 - Code Quality Review

Print: `>> Stage 2: Acceptance Review - loading assistant-review SKILL.md`
(historical records may read `Code Quality Review`).

Stage 2 applies to standard/strict work: the final fresh acceptance review. Light
work and plan review use the compact result above as their dispatch/result
evidence, unless the structured path applies. Load and follow `assistant-review`
SKILL.md and its contracts with `review_subject=acceptance` and the triage
`controller_intensity`. It is the sole owner of Reviewer and QAEvaluator worker
packet schemas. Use `Reviewer` only as compatibility routing inside
assistant-review. In every lane, including direct_main, never implement the
review loop inline; dispatch newly created fresh-context Code Reviewers and record
`Code Reviewer dispatch` plus `Code Reviewer result` evidence, or
`Reviewer dispatch` plus `Reviewer result` only for compatibility routing.

Assign the spec obligations of `references/prompts/spec-review.md` to a pass of
that batch, such as contract_and_test_oracle, with the original request,
requirement IDs, approved plan/task packets/slices and `git diff`. For bugfixes,
include the `assistant-debugging` reproduction/root-cause evidence and check
that the regression test or validation path covers the isolated failure
mechanism. Record the obligation result as `spec_review_result` (journal a
`### Spec Review #N` entry only when a task journal exists) (Result: PASS | FAIL, Missing acceptance criteria, Extra
scope, Changed files mismatch, Verification evidence mismatch, Required fixes)
bound to the same final batch. On a spec FAIL, in review-fix mode fix
only evidence-backed findings within authorized scope, re-test, and run a fresh
complete acceptance batch on the changed snapshot.
In audit mode, report the mismatch without source changes.

When `architecture_design_mode != not_applicable`, pass the current compact
Architecture Decision Pack projection (reference, freshness basis,
sourced facts, status/rationale/impact/source-ref assumptions,
material-question topic/why/risk/default/status, boundaries, design-pressure
checks, Type Ledger, quality scenarios, verification/rollback, invalidators, and
review-intensive challenge evidence) to assistant-review and set
`architecture_decision_pack_review_required=true`. The reviewer must return the
canonical Pack review evidence; workflow consumes its validated result rather
than duplicating the reviewer schema.

When reading a historical v15 direct-fallback record only, retain its original
`Code Reviewer direct evidence` (`Reviewer direct evidence` is compatibility)
labels; new records never write them, and current review requires a newly
created independent agent.

The `assistant-review` loop fixes must-fix and should-fix items, re-reviews
automatically only when review-fix authority is explicit or carried by the
active approved workflow, and only for evidence-backed findings within its
approved scope. Audit mode reports findings without source changes. A finding
that expands scope, requirements, architecture, files, risk, verification, or
acceptance criteria returns to planning or approval before any mutation. Light
small tasks use one compact fresh review covering spec obligations and quality.
Small strict/required-QA work and medium+ tasks require the full acceptance
batch with its spec obligations; medium+ also requires its one-pass plan review.

If code review reports shared semantic guard stagnation or a material scope/authority change, pause the loop and create an orchestrator-owned
`pivot_restart_decision` before another fix/review dispatch. The autonomous
quality loop uses the shared semantic progress guard, without a round ceiling.
Numeric score diagnostics alone do not require a decision.

## Stage 3 - QA Evaluation

Print: `>> Stage 3: QA Evaluation - loading assistant-review references/qa-evaluation-loop.md` when QA is required.

Run QA Evaluation only when `qa_evaluation_mode=required`.

QA required positive triggers: explicit QA/acceptance evaluation request, accepted Done Contract, harness-capable acceptance scope, domain-scored scope, or scoped UI/visual/product/UX/docs/DX acceptance.

QA non-triggers: template labels/placeholders, generic acceptance criteria labels, optional/not_required reasons, delegation/source-changing work alone, and ordinary medium+ code-review-only/source-changing work.

Load and follow assistant-review's QA loop. assistant-review owns newly created
fresh-context QAEvaluator dispatch, input/return validation, and the canonical
delegation-path/result artifacts; workflow records only validated refs. QA never
uses direct fallback: when fresh QAEvaluator isolation is unavailable, QA is
incomplete and the workflow does not complete.

When a carried feature-preparation QA obligation exists, a successful canonical
pair (`accepted` or `accepted_with_concerns` with `CLEAN` or `ISSUES_FIXED`) is
valid only when its obligation result records `requested_scope_status=fulfilled`,
`execution_prerequisite_status=met`, and the exact unchanged scope/source
binding. A blocked or failed obligation remains non-complete even when the
verdict/result pair otherwise looks successful.

assistant-review loads `references/domain-rubrics.md` only when its canonical
QA inputs require subjective/product/UX/docs/DX/UI/domain scoring. The canonical
QA output schema remains solely in `assistant-review/contracts/output.yaml`.

QA Evaluation focuses on acceptance and final result. It must not report general
code defects, security issues, architecture concerns, or test coverage gaps
unless they directly block an acceptance criterion or Done Contract item.

If the shared semantic guard reports genuine stagnation, retain the acceptance
evidence and have the orchestrator assess
an orchestrator-owned `pivot_restart_decision` before another QA/build dispatch.
Return failed acceptance items to authorized Build while the shared guard
permits corrective work; retain remaining failures at every ordinal.

QA rejection followed by a source fix returns to Build. Before another QA
round, record passed Build validation, recompute the source digest, and run a
fresh complete assistant-review batch on the post-fix identity. Reusing the
prior review is allowed only when equal pre/post digests and explicit equality
evidence prove no source change; changed-path fields must be absent.

## Status Gate

Enforce the review cycle before presenting results:

- Review Log or equivalent review result must exist.
- Standard/strict `review_result` must record validated refs to assistant-review
  `final_summary`, the current `producer_schema_version`, its exact current
  `final_review_snapshot_id` and `final_snapshot_identity`, and
  `review_delegation_path` plus their exact canonical contract ids.
  `final_snapshot_identity_ref` and `final_snapshot_identity` must resolve
  within the same `final_summary` and equal the current final batch;
  `final_review_snapshot_id` must equal the current final batch
  `review_snapshot_id` and identify the same canonical identity. Standard/strict
  Pack-backed `review_result` must also record validated refs to
  `assistant-review/contracts/output.yaml#architecture_decision_pack_review`;
  canonical review fields remain owned by assistant-review.
- Light Pack-backed or expanded-impact `fresh_review_result` must record
  validated refs to `assistant-review/contracts/output.yaml#final_summary`, its
  exact current final-batch `final_snapshot_identity`, and
  `assistant-review/contracts/output.yaml#review_delegation_path`.
  `assistant-review/contracts/output.yaml#architecture_decision_pack_review`
  remains required only for a Pack.
- Newly created fresh-context Code Reviewer dispatch/result evidence must be
  created in Review after Build completes; direct fallback never substitutes,
  and unavailable reviewer isolation leaves Review incomplete.
- When `qa_evaluation_mode=required`, workflow must record validated refs to
  assistant-review `qa_evaluation_result` and `qa_evaluation_delegation_path`,
  plus the current producer version and exact carried-obligation result ref when
  applicable.
- Every consumed `producer_schema_version` must equal
  `skills/assistant-review/contracts/index.yaml#schema_version`. Persisted
  mismatches invalidate canonical review/QA result, delegation, snapshot, and
  Pack refs and rerun the required current-contract lane.
- Pivot/Restart Decision must exist for evidenced shared semantic guard stagnation
  or a material change, including a source-backed domain pivot. Numeric score
  diagnostics alone do not require a decision or block finalization; acceptance
  failures and required QA verdict gates remain controlling.
- Final Result must be recorded.
- The full review cycle must complete before presenting results to the user.

## Verification Summary

After final review passes, write the Verification Summary in the task journal
when `workflow_state_mode=journal`, or in the inline completion packet:

- What changed: files and why
- What's tested: unit, integration, E2E, or inspection coverage
- Code Review result: clean, issues fixed, or remaining should-fix items
- QA Evaluation result when required: accepted, accepted with concerns,
  rejected, or blocked
- Known limitations
- Do not create `final_handoff` here; Document is its sole owner and consumes
  the completed Review result and verification summary.

Wait for manual verification only when `manual_verification_mode=required`.
Developer test instructions are documentation and do not create that wait.
This mode is limited to an explicit request, subjective/UI acceptance, external
effects, destructive/migration work, or inadequate automated verification.
Record the trigger and result evidence, then continue. With `optional`, present
steps without waiting. With `not_required`, proceed directly to Document after
review evidence is complete; user confirmation is not a ritual gate.

When required manual verification reports issues, add them to Review Notes,
re-enter Build and Review for those steps only, update the verification summary,
and present it again.

On genuine shared semantic stagnation or material change, retain the guard and
route the evidence-backed Pivot/Restart Decision Packet before corrective work.
Numeric score diagnostics alone do not require another decision.
