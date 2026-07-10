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

  1. REVIEW
     - Require the latest Spec Review result to be PASS before review dispatch.
     - At the moment this pass begins, resolve `reviewer_context` from `contracts/index.yaml`; its declared boundary closure must remain below 5000 words.
     - Create one fresh `fresh_reviewer_context` bundle with:
       - selected `dispatch_context_ref` for `orchestrator_to_reviewer.context_fields`
       - `review_evidence_pointer` covering Spec Review PASS evidence, review material, and required `build_test_verification_ref`
       - round number, previously_fixed, finding_filter_policy, and review-mode flags
       - `references/review-principles.md`
       - `references/review-rubric.md` for the medium+ Reviewer
       - only triggered sections from `references/review-checklists.md`: Semantic Contract Review Checklist, Behavioral Contract Review Checklist, and/or Agentic Loop Safety Checklist
     - Exclude every untriggered checklist section. If no checklist flag is true, include no checklist section.
     - In delegated mode, dispatch a fresh Reviewer with this bundle. In direct fallback, start a fresh isolated pass with the same bounded bundle and record fresh-context evidence; do not claim a subagent dispatch.
     - Treat speculative or low-evidence concerns as non-blocking Observations. Do not re-report previously_fixed items. If security-sensitive surfaces are present, hand off to `assistant-security`.
     - Do not include `orchestrator_to_reviewer.return_fields` in the dispatch bundle. Defer the return schema until return validation.
     - After the Reviewer/direct-fallback result exists, resolve the `reviewer_return_validation` selector and validate the canonical return fields before EVALUATE.

  2. EVALUATE
     a. Check rubric score (medium+ scope):
        - PASS (weighted >= 4.0) AND no must-fix AND no should-fix -> EXIT CLEAN
        - PIVOT (weighted < threshold for round) -> escalate to orchestrator-owned pivot_restart_decision
        - REFINE (weighted below 4.0 but not PIVOT), including zero findings -> continue to step 3
          using lowest-scoring rubric dimensions as the improvement targets
        - Medium+ CLEAN and ISSUES_FIXED require weighted >= 4.0 and zero
          must-fix/should-fix findings
     b. No rubric (small scope): use findings-based exit:
        - No must-fix AND no should-fix -> EXIT CLEAN
        - Only nits -> EXIT CLEAN (note nits in final report)
     c. round == 10 with remaining must-fix or should-fix -> EXIT WITH REMAINING ITEMS
     d. round == 10 with issues fixed and now clean -> EXIT ISSUES FIXED
     e. Otherwise -> continue to step 3

     Record in score_history: { round, weighted_score, finding_count, drift_status }
     (see `score-tracking.md` for drift detection rules)
     If score tracking reports STAGNATION, repeated DRIFT, repeated REGRESSION,
     or rubric action PIVOT, pause the loop and return a pivot_restart_signal to
     the orchestrator. The orchestrator records pivot_restart_decision with
     trigger, evidence, affected_slice_or_round, options_considered,
     selected_action, reapproval_required, next_agent, recovery_pointer, and
     exact_next_action before another fix/review dispatch. If the selected action
     changes scope, files, behavior, risk, verification, or acceptance criteria,
     reapproval is required. Round 10 remains terminal and never starts round 11.

  3. FIX
     - Fix ALL must-fix and should-fix items (not just must-fix)
     - Prioritize lowest-scoring rubric dimensions first
     - Add each fixed item to previously_fixed with description

  4. VALIDATE
     - Run build + tests if applicable
     - If build/tests fail -> fix and re-verify before continuing
     - After any source fix, record real current passed build/test evidence. Every subsequent Reviewer round/dispatch requires that evidence; `not_applicable` is invalid after a source fix.
     - For C# projects: run the configured local cognitive-complexity check when available and policy-allowed, then flag methods exceeding threshold; if unavailable/disallowed, record that explicitly and use equivalent review evidence from source inspection, tests, and focused complexity reasoning.

  5. round += 1 -> go to step 1
```

When `qa_evaluation_mode=required`, load `qa-evaluation-loop.md` before dispatching QAEvaluator. That reference owns the detailed QA algorithm, score progression, domain-rubric routing, pivot/restart behavior, and terminal round-10 cap. QA runs only after build/test evidence and Code Reviewer or Reviewer compatibility evidence exist; it evaluates acceptance criteria, Done Contract evidence, verification evidence, scoped domain quality, score progression, and final readiness.
