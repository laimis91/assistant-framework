# Review Batch Protocol

Audit/read-only: frozen batches.

1. Capture identity; mutation invalidates. Rebuild persisted 6.0 or incompatible 7.0/7.1/7.2/8.0 under 10.0 from a fresh snapshot before `CLEAN`/`ISSUES_FIXED`; retain raw history and complete closure tuples as historical evidence, and normalize only missing v6/7.0 closure identity fields before closure dispatch.
2. Plan trivial/small light review (`controller_intensity` light, `topology.light_review` true) as one `light_contract_and_runtime` pass covering both concerns (post-fix: one new pass with the closure ledger; historical two-pass batches stay readable); structured plan review (`topology.plan_review` true) is one `plan_coverage_and_feasibility` pass (post-fix: one new pass with the closure ledger); medium+ plans at least two independent narrow passes, medium adds integration, large architecture; max six. Each pass is newly created with fresh self-contained context (Codex fork_turns=none). Security uses Code Reviewer `assistant-security`; Reviewer schema authoritative.
3. Unique IDs/scopes/obligations/concerns; exact tuples; sibling-blind; aggregate ledger.
4. Returns carry tuple/status/evidence; only `inspected_no_risk`/`finding` completes. Source IDs: `review_pass_id`; closure: `aggregate_finding_id`.
5. Response correction uses the shared task guard. `completed`/`needs_context`/`blocked` need one response; lifecycle failures need typed evidence. Retain stable `coverage_gap_id` per incomplete/invalid tuple. Audit: one batch. Do not aggregate, fix, exit, or report a clean result before the barrier.
6. Rehash; require exact equality between current `coverage_gap_id` values and unique coverage-gap `source_coverage_gap_ids`. Merge only the same locus, invariant, and failure mechanism. Invalid coverage is `HAS_REMAINING_ITEMS`, never `CLEAN`/`ISSUES_FIXED`.
7. Historical incomplete or invalidated batches remain in history but do not block CLEAN. `previously_fixed` closes by `aggregate_finding_id`.

Observe all started batches, including incomplete/invalidated, under the same
task guard. Ordinals count batches, never sibling passes. Retain historical
batches; only a complete replacement current final snapshot supports clean.
Every active expected response and assigned coverage tuple requires exact closure.

Retain raw payload/SHA-256 and occurrence refs in caller evidence. Same-event
replay is idempotent; only byte-identical transport-complete returns deduplicate.
Preserve changed payloads/findings/conflicts. Stale/duplicate replies never close
coverage or advance progress. Use completion notifications/bounded waits, inventories
only for discovery/recovery.

Current v10 dispatch and terminal certification require independently retained
native creation/actor/context/handoff/source authority. Explicit historical v9
records remain readable/deduplicable under original native binding; dropping a
version or relabelling old evidence cannot certify current fresh review. Plan and
acceptance review use original request/approved-plan coverage through existing
scope and completion owners; unfinished work stays HAS_REMAINING_ITEMS.
