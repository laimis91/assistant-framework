# Progressive Discovery

Load this reference when `uncertainty_shape=progressive`,
`progressive_route_clear_consumption_state in [pending, consumed]`,
`progressive_sequence_readiness_state in [active, closed]`, or
`progressive_artifact_retention_state=terminally_archived`. The durable markers load validation regardless of whether progressive_artifact_retention_state is missing, not_applicable, or retained, so invalid carried state fails closed instead of releasing artifacts. Retained state remains active/resumable after
`uncertainty_shape=bounded`; fully specified bounded work with `not_applicable`
markers does not load this reference. It is a conditional Discover substate
inside `assistant-workflow`, not a new skill or workflow phase.

## Routing

Prompt-level ambiguity belongs to `assistant-clarify` when its routing matches.
Clear prompts do not invoke it. Precise, answerable implementation questions
and deterministic safe defaults remain owned by workflow Discover. When an
Architecture Decision Pack applies, use the same progressive decision items for
predecessor-unlocked design unknowns; do not create a second decision graph or
a permanent architecture memory.

## Classification

After prompt-level routing, classify the remaining implementation uncertainty.
`bounded` is the default. Use it when outcome-shaping uncertainty is already
precise enough for ordinary clarification, a safe default, or normal planning.
Tasks that are fully specified remain bounded, and size alone is not a trigger.

Use `progressive` only for a not-yet-precise outcome-shaping unknown that is
unlocked by a predecessor. The predecessor must be identifiable; otherwise
keep the task bounded and resolve any precise, answerable question through the
existing workflow clarification path.

## Typed State

Keep progressive state in the existing task journal or equivalent carried
state. `progressive_discovery_state` is `mapping`, `resolving`, `route_clear`,
or `blocked`; bounded work is `not_applicable`. The decision map holds outcome
and scope anchors plus compact refs to decision items and deferred uncertainty.
The current map decision_item_refs and deferred_uncertainty_refs are non-empty,
ordered unique, and each resolves exactly once to its canonical typed entry;
retired, excluded, or history entries may remain outside current refs.
Each decision_item.dependencies list is ordered unique canonical decision_id
refs. Every dependency ref resolves exactly once to another canonical
decision_item.decision_id; no self dependency or circular dependency is
allowed. An item is eligible or active only after every dependency has
status=resolved; otherwise leave it pending or blocked and recompute the
frontier after the predecessor resolves.
Each deferred uncertainty names its unlock condition and
`unlocking_decision_item_ref`. Every current-map uncertainty points to a
current-map predecessor, and every ref resolves exactly once to a canonical
decision item. When an uncertainty is unlocked, retired, or excluded, retain
that predecessor's canonical decision resolution. An unlocked uncertainty also
records `converted_decision_item_ref`, which resolves exactly once to an
actionable canonical decision item and appears exactly once in the unlocking
predecessor decision_resolution.newly_precise_item_refs. In every progressive state
where decision items exist, including mapping, at most one item may have
`status=active`. A decision frontier snapshot is not required during mapping;

`collaborative` means a joint agent+human/user contribution, not an agent
decision awaiting a later acknowledgement. Before a collaborative decision is
`status=resolved` or can enter route_clear, its canonical decision resolution
records typed `contributor_evidence` with at least one `agent` and one
`human_or_user` contribution, each tied to an evidence ref. `human_required`
remains distinct: it requires `human_confirmation_ref` and cannot self-resolve.
once it exists, it reflects that same limit while recording multiple sequential
resolutions in one session. When a mapping item becomes resolved, retain its
canonical decision resolution with evidence and effects before dependent
eligibility or frontier recomputation. Carry cleared decisions, constraints,
exclusions, and the acceptance seed back toward bounded Discover. Keep ordered
unique canonical effect refs: newly precise not superseded/excluded; superseded
status=superseded.
Every blocked item records blocker_kind, blocker_reason, and
unblock_condition. The blocked_item_refs resolve to decision_item entries so a
resumed journal knows why work stopped and what evidence or state change permits
retry. If a later decision becomes blocked after another resolves, keep the
canonical decision resolutions so resumption preserves the prior history. At
`progressive_discovery_state=blocked`, require non-empty blocked_item_refs to at
least one canonical `status=blocked` item. When readiness exhaustion selects
this state before another activation, keep the proposed item inactive as
`status=blocked`, use `blocker_kind=readiness_exhausted`, and record a concrete
reason and unblock condition rather than persisting a sequence-only stop. At
route clear, create `route_clear_handoff` with `consumption_state=pending` and
set `progressive_route_clear_consumption_state=pending` plus
`progressive_artifact_retention_state=retained` to mirror that handoff
while keeping typed `uncertainty_shape=progressive` /
`progressive_discovery_state=route_clear` while preparing the bounded-Discover
Requirement Acceptance Map. Every current-map retired/excluded deferred uncertainty must retain its exact canonical predecessor decision_resolution even when that predecessor is superseded or excluded. route_clear_handoff.decisions and exclusions account for every current-map decision: each status=resolved decision appears exactly once through its canonical decision_resolution.decision_item_ref, and each superseded or excluded decision appears exactly once in exclusions. decisions is non-empty when any current-map decision has status=resolved and empty only for a legitimate all-excluded route. Retained historical resolutions for current-map superseded or excluded items are lineage evidence only and do not appear in decisions. Requirement Acceptance Map is not required while progressive_route_clear_consumption_state=pending; that marker carries the handoff and preparation state rather than a completed map. The map must
trace the handoff decisions and constraints into applicable accepted map state,
bind every source `retired_or_excluded_deferred_uncertainty_refs` ref exactly
once through `retired_or_excluded_deferred_uncertainty_traces` to a concrete
`non_goals` or `entries` target with `status=approved_exclusion`,
turn each acceptance seed into an `entries[].acceptance_criterion` with binary
acceptance, then record `source_route_clear_handoff_ref` resolving to the
source handoff. That handoff records `consumed_by_requirement_acceptance_map_ref`
resolving back to the consuming map; these are reciprocal pointers, not equal
values. Record that consumption_state=consumed and
`progressive_route_clear_consumption_state=consumed` before the atomic typed-state
transition to bounded/not_applicable. Requirement Acceptance Map is required when progressive_route_clear_consumption_state=consumed and progressive_artifact_retention_state=retained. The marker remains consumed after that
transition. route_clear_handoff remains required while progressive_route_clear_consumption_state in [pending, consumed] and progressive_artifact_retention_state=retained. After
bounded/not_applicable, retained state keeps the consumed handoff and both
reciprocal refs in active/resumable continuation.
While `progressive_artifact_retention_state=retained` and either durable marker
is pending/consumed or active/closed, retain the
**retained canonical reference chain**: the `decision_map`; every referenced
`decision_item` and `deferred_uncertainty`; and each canonical
`decision_resolution` for a resolved item and every exact retained predecessor
resolution required by a current-map retired/excluded deferred uncertainty. The
`route_clear_handoff.decision_map_ref` and every applicable
`loop_readiness_assessment` reference must continue to resolve to those
canonical artifacts across compaction and active/resumable continuation. The
`decision_frontier` remains transient after live progressive state ends; it is
not part of the retained chain. The typed `progressive_terminal_archival`
tombstone must already be recorded before
`progressive_artifact_retention_state=terminally_archived` is persisted or
resumed. Only then omit the handoff, reciprocal refs, readiness assessment,
and retained chain. The tombstone binds current task identity,
final decision-map ref, typed final archival/termination basis, and resolvable
evidence refs proving continuation and reference resolution are impossible.
Missing, dangling, or mismatched tombstone evidence fails closed and cannot
release the retained chain. This is one atomic transition with uncertainty_shape=bounded and progressive_discovery_state=not_applicable; historical consumed and closed markers remain durable lifecycle history. `Task state: completed` does not qualify as that
evidence. `terminally_archived` is invalid while route consumption is pending
or sequence readiness is active, is terminal, and cannot revert to `retained`
for the same task and decision map.
Ordinary bounded small work stays
`progressive_route_clear_consumption_state=not_applicable`.

## Repeated Resolution Readiness

One active item and multiple sequential resolutions remain allowed. On first
activation, set a positive `activation_ordinal` atomically on the canonical
decision item; never-activated items omit it. Retain that immutable ordinal
across resolved, blocked, superseded, or excluded status and compaction.
Ordinals stay unique across retained canonical decision-map history, including
activation-marked items outside current-map refs. Use ascending ordinals before
the second activation to reconstruct the ordered unique
`activated_decision_item_refs`, so status alone never has to prove that the
first item was active. Before a
second/sequential activation, record one ready `loop_readiness_assessment` with
`loop_type=progressive_decision_sequence` in the existing journal/equivalent
state tracking and atomically set
`progressive_sequence_readiness_state=active` plus
`progressive_artifact_retention_state=retained`. Its stable `readiness_assessment_id` and
`progressive_decision_map_ref` identify one cumulative sequence across
continuation or compaction. It must set immutable finite `max_iterations`,
`cumulative_activation_count`, ordered unique append-only
`activated_decision_item_refs` including the first activation, and ordered
unique `resolved_decision_item_refs` as a subset mapped exactly once to
canonical decision resolutions. It must set `budget_limit`, name route-clear,
cap, stagnation, or failure stop conditions, detect an unchanged
frontier/no-progress result, and specify
`retry_or_empty_result_handling`, `tool_error_handling`, and
`low_confidence_escalation`. Another activation atomically appends one ref and
increments the cumulative count only while it remains below the cap. At equality,
inconsistency, an exhausted limit, or failed evidence route, fail closed to
`blocked/escalation`; do not activate another item or reset the cap. While
active, retain the same readiness record through pause, blocked state,
compaction, continuation, route-clear preparation, third+ activation proposals,
and durable route-clear consumption. Only then set
`progressive_sequence_readiness_state=closed`. After
progressive_sequence_readiness_state becomes closed, retain the same record
while `progressive_artifact_retention_state=retained` and the task remains
active/resumable or compacts. Only the explicit final archival/termination
transition to `terminally_archived` permits omission. `Task state: completed`
does not qualify, and terminally archived retention cannot revert. Closed cannot
reopen or reset the same decision-map record.

## Safety and Clearance

Progressive Discover is a no-execution boundary while mapping, resolving, route_clear, or blocked. Do not enter Decompose, Plan, or Build, and do not
perform project/source mutation, external writes, branch creation, or
credential-location recording. The only permitted local state update is the framework-owned journal/equivalent carried-state update required to record progressive state, including a route-clear handoff or its consumption; it is
not project/source mutation or an external write.
Any mutating prerequisite must run in a separate approved workflow and return
evidence; do not perform it inside progressive Discover. Recompute the frontier
after each resolution. Route clearance requires no open or blocked items and no
remaining deferred uncertainty except explicitly retired or excluded entries.
After clearance, `route_clear_handoff.retired_or_excluded_deferred_uncertainty_refs`
must be ordered unique, resolve exactly once, and exactly cover every current
decision-map deferred uncertainty with status `retired` or `excluded`; it is
empty if and only if none exist. Carry each reference into the consuming
Requirement Acceptance Map as a non-goal or approved exclusion. Use the pending compact handoff to prepare the bounded-Discover
Requirement Acceptance Map while typed progressive route_clear persists. Do not
allow empty, duplicate, dangling, or partially resolvable current map refs to
reach route clear or bounded planning, record the atomic bounded/not_applicable
transition, or omit the handoff until
the map records its source reference resolving to the handoff and the handoff
records the reciprocal consuming-map reference, then consumes the carried
decisions, constraints, exclusions, and acceptance seed. Until then, do not enter
Decompose, Plan, or Build.

After the predecessor resolves enough context to state the unknown precisely,
return to bounded Discover and continue through the existing clarification and
planning flow.
