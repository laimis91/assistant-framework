# Review Batch Protocol

Audit/read-only: frozen batches.

1. Capture identity; mutation invalidates. Rebuild persisted 6.0 or incompatible 7.0 under 7.2 from a fresh snapshot before `CLEAN`/`ISSUES_FIXED`.
2. Plan a minimum of two independent narrow passes; medium adds integration, large architecture; max six. Security uses Code Reviewer `assistant-security`; Reviewer schema authoritative.
3. Unique IDs/scopes/obligations/concerns; exact tuples; sibling-blind; aggregate ledger.
4. Returns carry tuple/status/evidence; only `inspected_no_risk`/`finding` completes. Source IDs: `review_pass_id`; closure: `aggregate_finding_id`.
5. At most two attempts. `completed`/`needs_context`/`blocked` need one response; lifecycle failures need typed evidence. One repair, then stable `coverage_gap_id` per incomplete/invalid tuple. Audit: one batch. Do not aggregate, fix, exit, or report a clean result before the barrier.
6. Rehash; require exact equality between current `coverage_gap_id` values and unique coverage-gap `source_coverage_gap_ids`. Merge only the same locus, invariant, and failure mechanism. Invalid coverage is `HAS_REMAINING_ITEMS`, never `CLEAN`/`ISSUES_FIXED`.
7. Historical incomplete or invalidated batches remain in history but do not block CLEAN. `previously_fixed` closes by `aggregate_finding_id`.

Cap: ten started batches, including incomplete/invalidated. Sibling passes do
not consume rounds; round 10 is terminal.
