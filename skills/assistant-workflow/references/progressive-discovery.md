# Progressive Discovery

Load this reference only when `uncertainty_shape=progressive`. It is a
conditional Discover substate inside `assistant-workflow`, not a new skill or
workflow phase.

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
Each deferred uncertainty names its unlock condition. In every progressive
state where decision items exist, including mapping, at most one item may have
`status=active`. A decision frontier snapshot is not required during mapping;
once it exists, it reflects that same limit while recording multiple sequential
resolutions in one session. Keep decision resolutions canonical and carry the
cleared decisions, constraints, exclusions, and acceptance seed back toward
bounded Discover.

## Repeated Resolution Readiness

One active item and multiple sequential resolutions remain allowed. Before a
second/sequential activation, record a ready `loop_readiness_assessment` in the
existing journal/equivalent state tracking. It must set finite `max_iterations`
and `budget_limit`, name route-clear, cap, stagnation, or failure stop
conditions, detect an unchanged frontier/no-progress result, and specify
`retry_or_empty_result_handling`, `tool_error_handling`, and
`low_confidence_escalation`. At any exhausted limit or failed evidence route,
fail closed to `blocked/escalation`; do not activate another item or reset the
cap.

## Safety and Clearance

Progressive Discover is a no-execution boundary while mapping, resolving, or
blocked. Do not enter Decompose, Plan, or Build, and do not perform project/source
mutation, external writes, branch creation, or credential-location recording.
Any mutating prerequisite must run in a separate approved workflow and return
evidence; do not perform it inside progressive Discover. Recompute the frontier
after each resolution. Route clearance requires no open or blocked items and no
remaining deferred uncertainty except explicitly retired or excluded entries.
After clearance, carry the compact handoff to bounded Discover, where the normal
Requirement Acceptance Map and current gates still apply.

After the predecessor resolves enough context to state the unknown precisely,
return to bounded Discover and continue through the existing clarification and
planning flow.
