# Progress wire boundary

Consumed only by persisted/executable progress admission, history and completion.
Caller authority and source-bound shared guard remain controlling.

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
`action_lineage` certifies exact admission, packet/member, input and approved
definition for verification, active promotion and completion. Historical actions may differ from
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
historical pair/member retirement, allowing obsolete input/definition while
INVALIDATED; new active work needs its genuinely admitted input and definition. A compacted predecessor followed by a
tail checkpoint has known order; two different summarized pairs require archive
reconstruction (`progress_history_missing`). Validate after dispatch materializes
its admission. Unchanged pairs permit carrier-free resume, with completion still
requiring recorded closure.
Accepted results provide `canonical_plan`, `canonical_context` and, when present,
`canonical_progress_state`. A later blocked dispatch still returns completed
progress. Commit before spawn; retain events only once.

A singleton's optional `action.packet_definition_digest` binds its admitted
canonical packet definition, excluding execution. The workflow owner enriches
new proposals from already validated approved work, rejects explicit contradictions
and returns the same bound action in the canonical carrier and admission. Existing
unbound live or closed admissions remain readable; current continuation or
certification requires reconstruction from independently retained original work,
never the changed candidate. Reconstruction preserves the pair, history and counts.
Unrelated plan/approval metadata does not change an unchanged packet's binding.

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

## Migration

Validate original v14 or v15 approval and definition against independent
authority before the fixed v14 → v15 and identity-only v15 → v16 normalization.
Preserve original approval/source digest, normalized digest, mapping provenance,
task/plan version, scope, full CheckSpecs/ref/TDD tuple, dependencies, current
input, actors, running stage and results. Supported v12/v13 sources use their
verified mapping first. Use the returned canonical context with the canonical
plan; equivalent representation needs no new business approval.

A genuinely known initial RUNNING action can retain its original admission with
ordinal/count zero and no invented completed checkpoints. Source authority must
establish that initial baseline.
