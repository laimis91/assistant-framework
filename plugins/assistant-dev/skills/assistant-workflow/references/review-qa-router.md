# Review and QA Router

Internal reference for Review routing. Load during Review after Build evidence
exists. `references/phases.md` keeps the compact Review shell; this file owns
Spec Review, Code Quality Review, QA Evaluator routing, status gates,
pivot/round-10 handling, verification summary, and user handoff.

## Review Lane Separation

Review has three distinct lanes:

1. Spec Review checks approved scope, task packets, slices, acceptance criteria,
   changed files, and verification evidence.
2. Code Quality Review loads and follows `assistant-review` SKILL.md and its
   contracts. Code Reviewer owns code defects, security, architecture, test
   coverage, maintainability, and structural code risk. `reviewer` remains a
   compatibility route for existing/legacy handoffs.
3. QA Evaluator runs only when `qa_evaluation_mode=required` and only after
   build/test evidence plus Code Reviewer or Reviewer compatibility evidence
   exist. QA Evaluator owns acceptance, Done Contract readiness, verification
   evidence, final readiness, and scoped domain quality.

Quality review cannot satisfy Spec Review. QA Evaluation cannot substitute for
Spec Review or Code Quality Review. Code Reviewer and QA Evaluator
responsibilities stay separate.

For `controller_intensity=light`, use the compact lane instead: compare the
diff with the inline plan/criteria, run a fresh review pass after validation,
record PASS plus the reviewed scope/evidence, and fix any findings before
completion. Light work does not load the full rubric/QA loop unless risk or an
independent trigger promotes it. This is a fresh self-review and does not
require Code Reviewer, Reviewer, Code Writer, or Builder/Tester dispatch/direct
fallback evidence.

## Stage 1 - Spec Review

Print: `>> Stage 1: Spec Review`

Load and follow `references/prompts/spec-review.md`. Compare implementation
against the approved plan, approved task packets, and approved slices before
Stage 2. For bugfixes, include the `assistant-debugging`
reproduction/root-cause evidence in the review material and check that the
regression test or validation path covers the isolated failure mechanism.

Spec Review must:

1. Walk through each approved plan step, task packet, or slice against `git diff`.
2. Check missing acceptance criteria.
3. Check extra scope unless approved as a deviation.
4. Check changed files mismatch.
5. Check verification evidence mismatch against the required command, expected
   success signal, and criteria checked.
6. Append a `### Spec Review #N` entry to the task journal Review Log with:
   Result: PASS | FAIL, Missing acceptance criteria, Extra scope, Changed files
   mismatch, Verification evidence mismatch, and Required fixes.
7. On Spec review FAIL, fix required items, re-test, and re-run Spec Review
   before Stage 2.
8. On Spec review PASS, proceed to Stage 2.

Print: `>> Spec Review: [PASS / FAIL - found N required fixes]`

## Stage 2 - Code Quality Review

Print: `>> Stage 2: Code Quality Review - loading assistant-review SKILL.md`

Load and follow `assistant-review` SKILL.md and its contracts. Add Code Reviewer
to `Required agents` before Stage 2. Use `Reviewer` only as compatibility
routing for existing/legacy handoffs. Do not implement the review loop inline
when `subagent_execution_mode=delegated` and a delegated review agent is
authorized; dispatch Code Reviewer and record `Code Reviewer dispatch` plus
`Code Reviewer result` evidence, or `Reviewer dispatch` plus `Reviewer result`
only for compatibility routing.

In direct fallback, preserve fresh-review evidence and record
`Code Reviewer direct evidence`; `Reviewer direct evidence` is compatibility
evidence only.

The `assistant-review` loop fixes must-fix and should-fix items, re-reviews
automatically, and returns a final clean/remaining summary. For small tasks, a
quick spec check plus one clean review round is acceptable. For medium+ tasks,
run full Spec Review plus the autonomous code quality loop.

If code review reports STAGNATION, repeated DRIFT, repeated REGRESSION, or rubric action PIVOT, pause the loop and create an orchestrator-owned
`pivot_restart_decision` before another fix/review dispatch. The autonomous
quality loop is bounded to max 10 rounds.

## Stage 3 - QA Evaluation

Print: `>> Stage 3: QA Evaluation - loading assistant-review references/qa-evaluation-loop.md` when QA is required.

Run QA Evaluation only when `qa_evaluation_mode=required`.

QA required positive triggers: explicit QA/acceptance evaluation request, accepted Done Contract, harness-capable acceptance scope, domain-scored scope, or scoped UI/visual/product/UX/docs/DX acceptance.

QA non-triggers: template labels/placeholders, generic acceptance criteria labels, optional/not_required reasons, delegation/source-changing work alone, and ordinary medium+ code-review-only/source-changing work.

Dispatch `qa-evaluator` in delegated mode, or record direct-fallback QA evidence
when delegation is denied, unavailable after a real spawn failure, or
policy-disallowed.

The QA Evaluator packet includes Done Contract when present, acceptance
criteria, verification evidence, code review result, `domain_context` and
`rubric_refs` when applicable, round 1-10, previously failed acceptance items,
and `qa_filter_policy`.

QA Evaluator loads assistant-review `references/domain-rubrics.md` only when
acceptance criteria, Done Contract, domain_context, or explicit rubric_refs
require subjective/product/UX/docs/DX/UI/domain scoring. It returns
final_verdict/result, acceptance_findings, qa_scorecard,
selected_domain_rubrics/domain_quality_scores when scoped, score_progression or
score_entry, evidence, and open_questions when blocked.

QA Evaluation focuses on acceptance and final result. It must not report general
code defects, security issues, architecture concerns, or test coverage gaps
unless they directly block an acceptance criterion or Done Contract item.

If QA score progression reports STAGNATION, repeated DRIFT, repeated REGRESSION,
or any scoped domain rubric returns action `pivot`, pause the QA loop and create
an orchestrator-owned `pivot_restart_decision` before another QA/build dispatch.
Round 10 remains terminal: return the final QA verdict and remaining failed
acceptance items instead of starting round 11.

## Status Gate

Enforce the review cycle before presenting results:

- Review Log or equivalent review result must exist.
- QA Evaluation result must exist when qa_evaluation_mode=required.
- Pivot/Restart Decision must exist when Review or QA reported STAGNATION,
  repeated DRIFT, repeated REGRESSION, or pivot action.
- Final Result must be recorded.
- The full review cycle must complete before presenting results to the user.

## Verification Summary and Handoff

After final review passes, write the Verification Summary in the task journal
when `workflow_state_mode=journal`, or in the inline completion packet:

- What changed: files and why
- What's tested: unit, integration, E2E, or inspection coverage
- Code Review result: clean, issues fixed, or remaining should-fix items
- QA Evaluation result when required: accepted, accepted with concerns,
  rejected, or blocked
- Manual test instructions only when `manual_verification_mode` is optional or required
- Known limitations

Wait for manual verification only when `manual_verification_mode=required`.
This mode is limited to an explicit request, subjective/UI acceptance, external
effects, destructive/migration work, or inadequate automated verification.
Record the trigger and result evidence, then continue. With `optional`, present
steps without waiting. With `not_required`, proceed directly to Document after
review evidence is complete; user confirmation is not a ritual gate.

When required manual verification reports issues, add them to Review Notes,
re-enter Build and Review for those steps only, update the verification summary,
and present it again.
