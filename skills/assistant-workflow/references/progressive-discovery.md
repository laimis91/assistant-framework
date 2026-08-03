# Progressive Discovery

Load this reference when `uncertainty_shape=progressive`,
`progressive_route_clear_consumption_state in [pending, consumed]`, or
`progressive_sequence_readiness_state in [active, closed]`. The retained
markers remain active/resumable after `uncertainty_shape=bounded`; fully
specified bounded work with `not_applicable` markers does not load this
reference. It is a conditional Discover substate inside `assistant-workflow`,
not a new skill or workflow phase.

## Routing

Prompt-level ambiguity belongs to `assistant-clarify` when its routing matches.
Clear prompts do not invoke it. Precise, answerable implementation questions
and deterministic safe defaults remain owned by workflow Discover.

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
Each deferred uncertainty names its unlock condition. In every progressive
state where decision items exist, including mapping, at most one item may have
`status=active`. A decision frontier snapshot is not required during mapping;
once it exists, it reflects that same limit while recording multiple sequential
resolutions in one session. Keep decision resolutions canonical and carry the
cleared decisions, constraints, exclusions, and acceptance seed back toward
bounded Discover. Every blocked item records blocker_kind, blocker_reason, and
unblock_condition. The blocked_item_refs resolve to decision_item entries so a
resumed journal knows why work stopped and what evidence or state change permits
retry. If a later decision becomes blocked after another resolves, keep the
canonical decision resolutions so resumption preserves the prior history. At
route clear, create `route_clear_handoff` with `consumption_state=pending` and
set `progressive_route_clear_consumption_state=pending` to mirror that handoff
while keeping typed `uncertainty_shape=progressive` /
`progressive_discovery_state=route_clear` while preparing the bounded-Discover
Requirement Acceptance Map. The map must
trace the handoff decisions and constraints into applicable accepted map state,
place exclusions in `non_goals` or entries with `status=approved_exclusion`,
turn each acceptance seed into an `entries[].acceptance_criterion` with binary
acceptance, then record `source_route_clear_handoff_ref` resolving to the
source handoff. That handoff records `consumed_by_requirement_acceptance_map_ref`
resolving back to the consuming map; these are reciprocal pointers, not equal
values. Record that consumption_state=consumed and
`progressive_route_clear_consumption_state=consumed` before the atomic typed-state
transition to bounded/not_applicable. The marker remains consumed after that
transition so the map stays required. route_clear_handoff remains required while progressive_route_clear_consumption_state in [pending, consumed]. After
bounded/not_applicable, retain the consumed handoff and both reciprocal refs in
active/resumable continuation. Omit it only after explicit task termination or
final archival where continuation and reference resolution are impossible.
While either durable marker is pending/consumed or active/closed, retain the
**retained canonical reference chain**: the `decision_map`; every referenced
`decision_item` and `deferred_uncertainty`; and each canonical
`decision_resolution` for a resolved item. The
`route_clear_handoff.decision_map_ref` and every applicable
`loop_readiness_assessment` reference must continue to resolve to those
canonical artifacts across compaction and active/resumable continuation. The
`decision_frontier` remains transient after live progressive state ends; it is
not part of the retained chain. This entire chain may be omitted only after
explicit final archival/termination makes continuation and reference resolution
impossible.
Ordinary bounded small work stays
`progressive_route_clear_consumption_state=not_applicable`.

## Repeated Resolution Readiness

One active item and multiple sequential resolutions remain allowed. Before a
second/sequential activation, record one ready `loop_readiness_assessment` with
`loop_type=progressive_decision_sequence` in the existing journal/equivalent
state tracking and atomically set
`progressive_sequence_readiness_state=active`. Its stable `readiness_assessment_id` and
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
while the task remains active/resumable or compacts; only explicit final
archival/termination permits omission. Closed cannot reopen or reset the same
decision-map record.

## Safety and Clearance

Progressive Discover is a no-execution boundary while mapping, resolving, or
blocked. Do not enter Decompose, Plan, or Build, and do not perform project/source
mutation, external writes, branch creation, or credential-location recording.
Any mutating prerequisite must run in a separate approved workflow and return
evidence; do not perform it inside progressive Discover. Recompute the frontier
after each resolution. Route clearance requires no open or blocked items and no
remaining deferred uncertainty except explicitly retired or excluded entries.
After clearance, use the pending compact handoff to prepare the bounded-Discover
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
