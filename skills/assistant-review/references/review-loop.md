# Review Loop

Load this reference after review entry fields are resolved and before the first REVIEW step.

```
round = 1
previously_fixed = []
score_history = []

PREPARE
  - Workflow-composed review: consume the carried Spec Review PASS pointer and carried current build/test evidence refs.
  - Standalone review: no task journal is required. Run Spec Review against the user request and review scope, record `spec_review_pass_ref`, and do not dispatch Reviewer on FAIL; fix the scope mismatch and repeat Spec Review until PASS.
  - Populate required `build_test_verification_ref` with real current passed evidence whenever source fix/build work is in scope.
  - Use `not_applicable: audit_only|read_only|no_build_scope` only when no source fix or build is in scope.

while round <= 10:

  Before round 3 or later:
     - Require a recorded `additional_round_reason` with an evidence pointer created after the previous review began.
     - Allowed reasons are `changed_files`, `unresolved_finding`, `validation_failure`, `regression_or_drift`, or `changed_hypothesis`.
     - A score below the rubric threshold alone is insufficient to start round 3 or later.
     - If no allowed new evidence exists, exit and report the available result and residual risk instead of starting another round.

  1. REVIEW
     - Require the latest Spec Review result to be PASS before review dispatch.
     - At the moment this pass begins, resolve `reviewer_context` from `contracts/index.yaml`; its declared boundary closure must remain below 5619 words.
     - Create one fresh `fresh_reviewer_context` bundle with:
       - selected `dispatch_context_ref` for `orchestrator_to_reviewer.context_fields`
       - `review_evidence_pointer` covering Spec Review PASS evidence, review material, and required `build_test_verification_ref`
       - round number, `additional_round_reason` when round >= 3, previously_fixed, finding_filter_policy, and review-mode flags
       - `reuse_search_instruction`: independently during review, conduct the bounded capability search for rule-like changes; Carried Mapper/task-packet evidence alone cannot satisfy review
       - `references/review-principles.md`
       - `references/review-rubric.md` for the medium+ Reviewer
       - only triggered sections from `references/review-checklists.md`: Semantic Contract Review Checklist, Behavioral Contract Review Checklist, Agentic Loop Safety Checklist, and/or Architecture Decision Pack Review Checklist
     - Exclude every untriggered checklist section. If no checklist flag is true, include no checklist section.
     - In delegated mode, dispatch a fresh Reviewer with this bundle. In direct fallback, start a fresh isolated pass with the same bounded bundle and record fresh-context evidence; do not claim a subagent dispatch.
     - Treat speculative or low-evidence concerns as non-blocking Observations. Do not re-report previously_fixed items. If security-sensitive surfaces are present, hand off to `assistant-security`.
     - Do not include `orchestrator_to_reviewer.return_fields` in the dispatch bundle. Defer the return schema until return validation.
     - After the Reviewer/direct-fallback result exists, resolve the `reviewer_return_validation` selector and validate the canonical return fields before EVALUATE.

  2. EVALUATE
     a. Audit mode exits after round 1 and reports findings without edits or another review pass.
     b. Use findings as the execution gate:
        - No must-fix AND no should-fix on round 1, with no fixes this session -> EXIT CLEAN.
        - No must-fix AND no should-fix after fixes -> EXIT ISSUES FIXED.
        - Only nits -> use the applicable no-blocking-finding exit and report nits.
        - Remaining must-fix or should-fix on round 10 -> EXIT WITH REMAINING ITEMS.
        - Remaining actionable findings before round 10 -> continue to FIX.
     c. Use rubric scores to calibrate risk and focus, not to manufacture work:
        - PASS supports the applicable findings-based exit.
        - REFINE names improvement targets only when an evidence-backed finding exists.
        - PIVOT creates `pivot_restart_signal`; another round still requires a recorded allowed `additional_round_reason` and orchestrator-owned `pivot_restart_decision`.
        - A score below the rubric threshold alone is insufficient to start round 3 or later.
        - When findings permit exit but the score is below 4.0, exit with the evidence-bounded claim and record the score as residual risk; do not claim proof of correctness.

     Record in score_history: { round, weighted_score, finding_count, drift_status }
     (see `score-tracking.md` for drift detection rules)
     If score tracking reports STAGNATION, repeated DRIFT, repeated REGRESSION,
     or rubric action PIVOT, pause the loop and return a pivot_restart_signal to
     the orchestrator. The orchestrator records pivot_restart_decision with
     trigger, evidence, affected_slice_or_round, options_considered,
     selected_action, reapproval_required, next_agent, recovery_pointer, and
     exact_next_action before another fix/review dispatch. If the selected action
     changes scope, files, behavior, risk, verification, or acceptance criteria,
     reapproval is required. Before any round 3+ dispatch, also record the allowed
     `additional_round_reason` and its new evidence. Round 10 remains terminal and
     never starts round 11.

  3. FIX
     - Fix ALL must-fix and should-fix items (not just must-fix)
     - Prioritize lowest-scoring rubric dimensions first
     - Add each fixed item to previously_fixed with description

  4. VALIDATE
     - Run build + tests if applicable
     - If build/tests fail -> fix and re-verify before continuing
     - After any source fix, record real current passed build/test evidence. Every subsequent Reviewer round/dispatch requires that evidence; `not_applicable` is invalid after a source fix.
     - For C# projects: run the configured local cognitive-complexity check when available and policy-allowed, then flag methods exceeding threshold; if unavailable/disallowed, record that explicitly and use equivalent review evidence from source inspection, tests, and focused complexity reasoning.

  5. NEXT ROUND
     - After round 1 fixes and successful validation, start one fresh round 2 re-review.
     - After round 2 or later, create `additional_round_reason` from new evidence produced in the current cycle before incrementing.
     - Score below threshold alone cannot populate `additional_round_reason`.
     - round += 1 -> go to the pre-round gate.
```

The normal review-fix path is round 1 review, fixes and validation, then one fresh round 2 re-review. Audit mode always stops after one pass. Round 3+ requires a recorded `additional_round_reason`; it is exceptional and evidence-driven, while the hard cap remains 10.

When no must-fix or should-fix finding remains, use the evidence-bounded user-facing claim: **No material findings within the reviewed scope and available evidence.** The compatible `CLEAN` enum is workflow state, not proof of correctness.

When `qa_evaluation_mode=required`, load `qa-evaluation-loop.md` before dispatching QAEvaluator. That reference owns the detailed QA algorithm, score progression, domain-rubric routing, pivot/restart behavior, and terminal round-10 cap. QA runs only after build/test evidence and Code Reviewer or Reviewer compatibility evidence exist; it evaluates acceptance criteria, Done Contract evidence, verification evidence, scoped domain quality, score progression, and final readiness.
