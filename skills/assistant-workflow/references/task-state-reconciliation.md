# Task State Reconciliation

Treat persisted task state as a **freshness-checked persisted claim**, not as
authority that can override the newest user request or current repository.
Run this check before resuming from a journal, context map, replay packet, or
carried-forward plan.

## Required identity

Record or recover:

- stable task identity and latest user-goal reference;
- repository root;
- recorded branch, baseline, and HEAD when Git is available;
- last verified milestone and its evidence;
- last reconciliation time and result.

## Reconciliation order

1. Read the persisted state without acting on its next step.
2. Read the newest user request and later corrections.
3. Inspect the current repository root, branch, HEAD, worktree, and relevant
   artifact evidence when available.
4. Compare task identity, goal, repository identity, and verified milestone.
   For persisted review/QA wrappers, compare each `producer_schema_version`
   with `skills/assistant-review/contracts/index.yaml#schema_version`.
5. Classify the state as `active | stale | superseded | completed`.
6. Resume only an `active` state. Repair `stale`, archive or replace
   `superseded`, and do not restart `completed` work without a new request.
7. Before acting or returning, persist any `stale`, `superseded`, or `completed`
   classification to the framework-owned `{agent_state_dir}/task.md`, including its reason,
   current task identity, and repaired exact next action.

## Classification

- `active`: goal and repository identity still match and no newer evidence
  invalidates the recorded next action.
- `stale`: the goal still applies, but repository identity, progress, or
  verification evidence changed, or a persisted assistant-review producer
  version differs. Invalidate every affected canonical result, delegation,
  snapshot, Pack-review, and QA ref; rerun review, QA, or both under the current
  contract before continuing. Do not infer another packet shape.
- `superseded`: a newer user request or approved plan replaced the recorded
  objective or scope. Create/reconcile state for the newer task.
- `completed`: repository and verification evidence show the recorded goal is
  already complete. Report that evidence or start a distinct follow-up task.

## Authority and recovery rules

- Newest explicit user intent outranks persisted prose. Reconcile reduced-testing
  scope/source against stale plans before dependent work; carry it through existing
  constraints, decision scope and reviewer refs. When an explicit reduced-testing
  instruction applies, preserve its exact instruction object row in `evidence_assessment.scope_and_evidence_refs` alongside the
  unchanged decision in materialized packets and result updates, even when
  planned. Resolve its evidence_ref/qualitative claim_scope against the newest
  user instruction before marking freshness current; missing/stale applicable source
  provenance requires reconciliation before dependent work. With no
  applicable instruction, ordinary assessments including empty arrays require
  no instruction row. Instruction rows claim no execution/check closure. Expansion needs a named important
  uncovered failure and the existing selection/approval route.
- Preserve cumulative same-scope repair counts across changing tests, checks,
  workers and sessions; a new failing expectation needs classification, not a
  fresh window. Retain the same outcome guard and assessed history.
- Current repository and verification evidence outrank unverified progress
  claims.
- A branch or HEAD change is evidence to inspect, not automatic invalidation.
- Never discard user-authored files while reconciling framework-owned state.
- Record the classification, reason, evidence, and repaired exact next action.

If repository identity is unavailable, reconcile against the newest user
request and available artifact evidence, state the limitation, and lower
confidence rather than pretending the journal is current.

## Canonical packet resumption

Resolve the exact approved_plan_identity and canonical implementation_steps by
packet_id before resume. Use scripts/task-packet-admission.py with the independently
retained previous_plan, current relevant-input identities and resolved current
owner evidence. Independently retained VERIFIED state cannot be downgraded by the caller; only helper reconciliation invalidates it when current inputs, prerequisites or evidence change. A helper-returned INVALIDATED snapshot can become the retained previous_plan for repeated resume without duplicating history. Relevant changes invalidate affected packets and dependents that
consume their results; preserve historical evidence and spent repair counters.
A journal display or worker DONE cannot override coordinator execution state.
Read-old/write-new v12/released-v13 input requires verified producer/version provenance,
immutable source identity, complete source-bound mapping/allocation and conservative
all-prerequisite expansion described in plan-template.md. Block unknown/mixed/stale,
unsafe or ambiguous forms; retain original artifacts/results unchanged and record
normalization mapping in this reconciliation provenance, never a permanent ledger. Genuine verified normalization creates initial provenance. Later direct canonical Plan, resume, dispatch, verification and completion require the independently retained accepted previous_plan whenever either snapshot carries provenance; compare provenance presence and canonical JSON digest, including scalar types. Fresh canonical plans cannot invent it, and migrated canonical calls cannot alter or discard it.

Review result consumption reuses v9 `pass_attempt_ledger`/`response_events` and
caller evidence: canonical complete raw UTF-8 payload/ref/SHA-256, task/native
invocation, batch/snapshot/pass/active attempt, producer identity/version and
occurrence event bindings. Same-event replay is idempotent; only distinct
byte-identical complete delivery is duplicate. Changed payloads retain both raw
returns and validated findings; unresolved conflicts use existing repair/failure
accounting, never a new wire disposition. Stale/duplicate replies cannot close
coverage or advance progress. Carry these bindings, unresolved conflicts and
archive refs across compaction; on resume reconcile source/producer freshness
and resolve/rehash archives. Missing history is unknown. Use completion
notifications/bounded waits; reserve full agent inventories for discovery/recovery,
not repeated retrieval. Host-injected reports remain; measure avoidable processing.
