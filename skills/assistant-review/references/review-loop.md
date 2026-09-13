# Review Loop

Load this reference before the first REVIEW step.

```
round = 1
previously_fixed = validated_entry.previously_fixed || []
score_history = []

PREPARE
  - Validate entry fields, then seed `previously_fixed` from the validated entry value; use `[]` only when it is absent. Retain raw persisted history. For an invalidated persisted 7.1 packet, retain every aggregate_finding_id, source_finding_ids, and source_provenance entry while invalidating current result/delegation/snapshot/Pack/QA/plan/coverage refs. Before closure dispatch, normalize only records missing any canonical identity tuple field: preserve complete v6, 7.0, 7.1, and current tuples unchanged; for a partial v6/7.0 tuple, preserve a supplied aggregate_finding_id and fill only missing source_finding_ids with it and missing source_provenance with review_pass:persisted-v6-migration or review_pass:persisted-v7-0-migration. When the aggregate ID is absent, use the matching UTF-8 NFC(description)/SHA-256/collision rule and legacy-v6:<fixed_in_round>:<first-24-hex> or legacy-v7-0:<fixed_in_round>:<first-24-hex>, then fill only missing source_finding_ids and source_provenance. Invalidate persisted 6.0/7.0/7.1 score-tracking refs before rebuilding the fresh 7.2 batch.
  - Infer review mode before review or mutation. Report-only selects audit;
    in-scope authority selects review-fix. If unresolved, ask
    exactly: "Should I only report findings, or also implement and verify fixes?"
  - Standalone Spec Review on scope. Validate FIX_STEP entry_assertions before repair or mutation dispatch. On mismatch, run only in review-fix mode to repair evidence-backed must-fix and should-fix items. In audit, retain and stay read-only. Dispatch every planned read-only Reviewer pass with sanitized criteria; never expose the mismatch details to discovery siblings. Return it to the composing workflow for planning or approval when it changes scope, risk, or acceptance.
  - Workflow consumes Spec PASS/current build evidence; after a fix, `not_applicable` is invalid.

while round <= 10:
  Round 3+ requires a recorded `additional_round_reason` with new evidence.
  A score below the rubric threshold alone is insufficient to start round 3 or later.

  1. REVIEW
     - Freeze snapshot/manifest/identity; mutation invalidates. Rebuild persisted 6.0/7.0/7.1 under 7.2 before clean while retaining raw history and complete closure tuples. Load `references/review-batch.md` before batch planning.
     - Derive canonical discovery passes. Without trigger, trivial/small uses two purpose-specific isolated direct-fallback passes; trigger delegates scope. Security/post-fix closure are additive, max six.
     - First resolve `reviewer_context` from `contracts/index.yaml` strictly below 5653 words; carry bounded selector before response; siblings are blind; only closure gets ledger.
     - Load principles/rubric/triggered checklist sections. Medium+ returns Design Coherence evidence or `no concrete risk found`. Run a bounded independent capability search; carried Mapper evidence cannot satisfy review.
     - Dispatch every expected Reviewer. Security uses Code Reviewer with the `assistant-security` checklist/perspective; Reviewer return schema stays authoritative. In direct fallback, start a fresh isolated pass with the same bounded bundle. One repair; exhaustion is failed/timed_out coverage. At barrier/final exit rehash, wait for all expected responses, require terminal accounting, and validate exact multiset closure. Response-backed completed/needs_context/blocked require one active response; timed_out/failed/invalidated may have none only with typed failure evidence. Only `inspected_no_risk`/`finding` completes; `blocked`/`not_applicable` is incomplete.

  2. EVALUATE
     - Incomplete coverage -> `HAS_REMAINING_ITEMS`, never CLEAN/ISSUES_FIXED; history does not block replacement. Audit exits after one started terminal batch; retry exhaustion never starts another.
     - Complete aggregate exits if actionable items are absent; otherwise fix before round 10 or report remaining. Rubric never manufactures work.
     - PIVOT/STAGNATION/DRIFT/REGRESSION: orchestrator records pivot_restart_decision.

  3. FIX / VALIDATE
     - Validate FIX_STEP entry_assertions before source/test mutation or dispatch. Only review-fix repairs authorized evidence; record closure.
     - Run build/tests; mutation invalidates the batch and requires new evidence.

  4. NEXT ROUND
     - After round 1 fixes, start fresh round 2. Round 3+ needs new evidence. The round counts started review batches, not individual perspective passes, including incomplete or invalidated batches; round 10 is terminal after its started batch.
```

The normal review-fix path is round 1 review batch, fixes and validation, then one fresh round 2 re-review batch. Audit mode exits after one started batch reaches terminal accounting, complete or incomplete; incomplete is `HAS_REMAINING_ITEMS`, never a replacement batch. Rounds count started batches, including incomplete/invalidated, not passes. With complete coverage: **No material findings within the reviewed scope and available evidence**. `CLEAN` is not proof.

When required, load `qa-evaluation-loop.md` before dispatching QAEvaluator. That reference owns the detailed QA algorithm. Rehash before QA; mutation requires validation, invalidation, and a fresh complete review batch before QA resumes, except exact snapshot digest equality. QA is the separate acceptance lane.
