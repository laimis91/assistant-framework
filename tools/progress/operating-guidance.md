# Outcome guidance and shared stagnation policy

Establish the intended result, purpose and consumer, authoritative context,
constraints, authorization, suitable method and credible completion evidence.
Resolve discoverable answers first. State harmless assumptions; ask only about
remaining consequential choices requiring the user's judgment or authority.
Preserve unresolved consequential intent. Use applicable skills and general
reasoning for unfamiliar or mixed activities. Development phases apply to
authorized repository implementation; ordinary research, writing and other work
do not acquire a Build lane, harness, schema, test suite or score threshold.

Complete routine in-scope corrections while they produce meaningful progress.
Analysis agreement never authorizes implementation. Existing permission,
read-only, preparation, external-action, safety, scope, access, cost and acceptance
boundaries remain controlling. A material change requires its applicable new
decision. Do not repeatedly request equivalent approval for productive authorized
work. Finish when the intended outcome has credible evidence; report material
limits honestly.

## One guard for repeated work

Use one task-level outcome/guard identity across Build, review, QA, debugging,
discovery, research, response repair, generic handoff redispatch, repeat or
optimization work, workers, phases, sessions and plan versions. The default
window is **three consecutive completed semantic cycles** with neither a verified
acceptance gain nor useful new evidence. There is no cumulative attempt or
review-round ceiling. Ordinals are positive observations, not policy limits.
User budgets and evidenced resource policies may impose different bounds with
their source and accurate exit reason; workers cannot raise them to escape a stall.

A semantic cycle includes a correction together with due and executable
verification/review, or a completed investigation or response repair and its
assessment. An observed failure can end the cycle before stages whose
prerequisites failed. Required rechecks are part of that cycle, not independent
reset opportunities. Expected TDD RED may be useful new evidence; it does not
replace actual GREEN, separate REFACTOR verification or independent review.

The lead assesses substantive progress from domain evidence. A verified gain is
a durable acceptance improvement. Useful new evidence resolves material
uncertainty, rules out a plausible cause, exposes a previously unknown concrete
defect or establishes a consequential capability limit that changes the next
useful action. Useful negative evidence counts. Unsupported novelty, a new
worker, renamed checks/tactics, changing scores, cosmetic churn, repeated
sources, and freshness-only rechecks of recurring A/B states cannot reset the
guard. Preserve the frontier, acceptance losses and oscillation history. A rising
finding count may be useful evidence; a falling count alone proves no gain.

Record each completed cycle and its evidence exactly once **before** considering
blockers on subsequent work, even when a tool, sibling, transport or cleanup
then fails. A productive disposition resets the consecutive count to zero;
otherwise increment it. At the source-bound effective window (default three), retain the stall and stop corrective work.
Intentional waiting and unfinished asynchronous work create no checkpoint.
Preserve known results; reconcile lost results as unknown and repeat only
authorized, idempotent unresolved work. Parent/child and concurrent observations
must be deduplicated at a meaningful coordinator barrier. A delegate performing
internal correction cycles reports their checkpoints before another cycle.

## Continuation and material unblock

Continuation and compaction retain the same identity, frontier, evidence novelty,
count and stable history references. A generic request to continue does not erase
a stall. A material-unblock event requires independently checked changed
information, authority or capability; bind it to the blocker it resolves and
the exact newly feasible action. It sets `reactivated` under the same guard
without resetting the count/ordinal/history or granting another window.

Apply completed work before next-work blockers. Check current authority,
readiness, dependency, input, workspace, native actor and TDD stage gates before
consuming a material unblock. Failed gates preserve the updated progress and
leave the unblock unconsumed. Only accepted new action admission consumes it;
the caller commits the state before spawning. Replays are rejected. Later stages
of the same RUNNING action reuse its existing admission. When that action ends,
real progress resets normally; otherwise increment the retained count and return
to `stagnant` immediately when already at the threshold.

The guard cannot certify completion or approve delivery. Failed checks, incomplete
review coverage, unresolved acceptance failures, stale snapshots and unavailable
evidence remain explicit. Review confidence/severity standards do not depend on
round ordinal; concrete findings and complete coverage remain mandatory. Audit
retains its authorized one-batch read-only scope. Scores are diagnostic only.

## State and executable boundary

Single-pass work needs no progress file, CLI invocation or new artifact. When
repeated/persisted work has a consumer, use existing journal, trace, inline state
or equivalent carried context. One canonical ProgressState v1 contains guard and
outcome, policy/window/source, work ordinal, consecutive count, status
(`active`, `stagnant`, action-bound `reactivated`), baseline/frontier, retained
history/evidence refs and any current action admission. Do not put mutable state
at approved Plan top level or create another allowance per phase.

`stagnation.py` is a pure Python 3.9+ helper, not a semantic evaluator or controller.
Its frozen request/result and semantic values validate the JSON wire boundary;
structurally resolved references do not establish truth or materiality. The
caller owns source resolution, substantive assessment, authority, persistence
and actual runtime facts. No new dependency or CLI is required.

Workflow admission carries `context.progress = {state, resolved_sources, action,
event?}`. `resolved_sources` maps stable refs to independently retained facts;
never derive that authority from candidate counts/status or a narrative.
`state` is parsed by `ProgressState.parse`; `event` is a completed
`work_checkpoint`, `material_unblock` or `policy_change`. Events bind stable identity, predecessor,
ordinal, action, assessment and observed evidence. Checkpoints bind the current
admission; unblocks bind changed circumstances, resolved blocker and exact action.
Execution carries `progress_guard_ref`, `action_ref`, `action_admission_ref`.
Further dispatch retains the shared carrier whenever any current or previous
task execution has these markers; all marked executions bind the same guard.
Closing a checkpoint copies the actual admission into optional `closed_admission`;
compaction preserves known bindings in optional `closed_admissions`.
`action_lineage` certifies exact admission, packet/member and relevant input for
verification, active promotion and completion. Historical actions may differ from
the latest proposal. Old UNKNOWN bindings remain readable; certification needs
authoritative reconstruction (`progress_history_missing`). Full grouped history
may use matching barrier/member authority. Every marked VERIFIED execution needs
historical action identity; guard identity cannot certify closure. No-pair completion recovers
historical `admission_ref` from its full checkpoint or validated `closed_admissions`,
then uses exact lineage; known mismatches yield `progress_mismatch`.
Unmarked legacy and retained PENDING proposals remain compatible.
Canonical promotion retains each committed pair or proves forward succession:
close the predecessor, then bind a live successor to that packet/member/input
or show a strictly later full checkpoint. `predecessor_lineage` establishes only
historical pair/member retirement, allowing obsolete input to refresh while
INVALIDATED; new active work still needs its genuine admitted input. A compacted predecessor followed by a
tail checkpoint has known order; two different summarized pairs require archive
reconstruction (`progress_history_missing`). Validate after dispatch materializes
its admission. Unchanged pairs permit carrier-free resume, with completion still
requiring recorded closure.
Accepted results provide `canonical_plan`, `canonical_context` and, when present,
`canonical_progress_state`. A later blocked dispatch still returns completed
progress. Commit before spawn; retain events only once.

Optional `action.member_scope = {source_ref, members}` freezes a coordinator
cycle's members; each binding has `packet_id`, `packet_definition_digest` and
`input_identity`. The anchor appears exactly once with its original input.
An independently retained `coordinator_action_scope` source binds guard, outcome,
action, current approved Plan, exact members and a resolved grouping decision.
Admission checks all member definitions/inputs against the canonical Plan.
Omitting membership preserves the singleton wire. Membership grants no dependency,
workspace, actor, authority or TDD exemption.

The first member creates one admission. Another declared PENDING member joins
that unchanged admission once; commit its execution references before spawn.
Retained `previous_plan` prevents deleting a committed join. RUNNING stages reuse
it. Joining spends no additional unblock, checkpoint or count. A grouped material
unblock also binds `action_scope_ref` in its event, assessment and changed
circumstance; an action reference alone cannot authorize a changed group.

The lead's one `work_checkpoint.coordinator_barrier_ref` resolves a
`coordinator_barrier` artifact binding guard/outcome, action/admission,
`action_scope_ref` and exactly one `member_results` entry per declared member.
Each entry has `packet_id`, `result` and independently retained `evidence_refs`.
Evidence binds packet/result, `lifecycle: terminal_cycle` and actual
`invocation_ref` or `lifecycle_evidence_ref`. Domain owners establish terminal
cycle truth. For incoming closure, each terminal fact also binds `action_ref` and
`admission_ref` to the actual current admission and barrier. Missing binding is
`progress_history_missing`; a contradictory pair is `progress_mismatch`.
Historical unbound facts remain readable but cannot certify a new closure.
Fresh independently assessed no-progress cycles may reuse supporting check refs;
those refs cannot establish productive novelty or replace current member lifecycle
facts. Terminal results include failed checks or
evidenced cancellation/blocking; VERIFIED packet completion is unnecessary.
Partial results wait without checkpoints and remain retained. Missing, duplicate
or undeclared results cannot close the cycle. Closing clears one admission;
child evidence cannot also count a separate parent cycle. Closed coordinator and
member replay remain rejected through ordinary history and compaction. Later
corrections need a distinct action and newly fixed group scope.

Compaction may use `history_base_ref` to an independently resolved retained
summary while keeping unresolved events in the history tail. The summary binds
guard/outcome/policy, work ordinal, consecutive count, frontier, last event,
seen event/action/observation/frontier/unblock-change/policy-authority refs and unresolved oscillation
refs. It preserves the semantic frontier and novelty/replay protection; it is
never a new baseline or window. Keep pending material-unblock/admission events
resolvable. There is no per-task history-length or iteration quota; genuine
parser/transport limits retain their separate operational exit reason.

Useful evidence cannot resolve the same exact `resolved_uncertainty_ref` twice
through fresh observations or assessments. Retain those identities in the optional
summary array `seen_resolved_uncertainty_refs`, combined with the history tail.
A present empty array means known empty; absence means UNKNOWN. Legacy retained
useful checkpoints remain readable, including for no-progress work, verified gains
and otherwise-valid completion. Only a new incoming useful-evidence checkpoint
across unknown inventory returns `progress_history_missing` without consuming it.
The caller must reconstruct the authoritative archive inventory without resetting
history or counts. Distinct supported resolution identities remain valid; the
helper does not establish truth or equivalence between differently named claims.

Explicit user changes to the guard are recorded as `policy_change` events in
this same history, never productive checkpoints. Preserve guard/outcome,
predecessor, work ordinal, observations/assessment and exact `previous_policy`,
`new_policy`, `authority_ref`. Independently resolved user authority must bind
the exact guard/outcome/old/new policies; the new policy source binds that same
authority. Replaying authority or raising a candidate window without its record
is invalid. Replay historical work/unblocks under their then-effective policy,
including a compacted base's policy, and apply changes prospectively. Counts,
frontier/novelty and pending or consumed admission/unblock identities survive.
A change from 3 to 5 at count 3 leaves two unproductive cycles before stopping,
never five extra cycles. Find a pending unblock by retained identity across
intervening policy records. Compacted summaries include `seen_action_refs` and
`seen_policy_authority_refs`, including empty arrays when none, to preserve
closed-action and policy replay protection. Keep pending unblock events in the
history tail and retain policy sources and unresolved oscillation identities.

## Migration and preserved bounds

Workflow v15, review v9 and five-lens research v4 consume this policy. Historical
records retain their original protocol labels. Validate original v14 approval
and definition against independent authority before the fixed v14 → v15
normalization. Preserve original approval/source digest, normalized digest,
mapping provenance, task/plan version, scope, full CheckSpecs/ref/TDD tuple,
dependencies, current input, actors, running stage and results. Supported v12/v13
sources use their verified mapping first. Use the returned canonical context
with the canonical plan; equivalent representation needs no new business approval.

Historical attempt totals remain observations. They neither prove a genuine
stall nor authorize a clean reset. Reconstruct only from retained observations;
missing/conflicting history is an explicit evidence gap. Authorized read-only
reconciliation can establish a frontier; it does not authorize corrective mutation.
A genuinely known initial RUNNING action can retain its original admission with
ordinal/count zero and no invented completed checkpoints. Source authority must
establish that initial baseline.

User budgets, host restrictions, subprocess deadlines, fetch bounds, API
backoff/rate limits and application/product-loop policies keep their own owners
and accurate exit reasons. This policy changes framework correction controls.

Source tests and installer parity prove bounded structural behavior only.
Native activation, reduced friction, outcome quality, time or cost claims need a
bounded matched observation with frozen outcome oracles, current source/host
identity, calls/time, avoidable interruptions and explicit limits. Do not claim
those benefits from prompt size or green checks alone.
