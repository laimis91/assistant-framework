# Requirement to Acceptance Map

Create this compact map after material clarification and before decomposition.
It is the single traceability spine from user intent to completion evidence;
slices and task packets consume it instead of inventing a second source of
truth.

Small work may use the compact `acceptance_criteria` list unless ambiguity,
risk, or multiple material requirements promote it to the durable map. When
`size == small and architecture_design_mode in [required, review_intensive]`,
Discover creates the canonical Requirement Acceptance Map so Architect PLAN's
required traceability context is satisfiable without generic small-task ceremony.

## Required shape

```text
Requirement Acceptance Map:
- intended_outcome: [one concise outcome]
- assumptions_and_defaults: [explicit inferred choices]
- open_material_questions: [none before Plan, or unresolved blockers]
- non_goals: [explicit exclusions]
- source_route_clear_handoff_ref: [conditional: source route-clear handoff when progressive route clearance is consumed and progressive_artifact_retention_state=retained]
- retired_or_excluded_deferred_uncertainty_traces: [conditional: every source retired/excluded uncertainty ref exactly once -> target_disposition non_goal | approved_exclusion -> target_ref to a concrete non_goals element or entries element with status=approved_exclusion]
- entries:
  - requirement_id: R1
    source: [user request, accepted default, policy, or local contract]
    requirement: [atomic observable requirement]
    acceptance_criterion: [binary pass/fail statement]
    verification_method: [test, command, inspection, review, or manual scenario]
    evidence_ref: [pending until verified, then stable result/path]
    manual_scenario_or_na: [numbered scenario or N/A with reason]
    status: pending | passed | failed | approved_exclusion
    exclusion_reason: [required only for approved_exclusion]
```

## Rules

- Give every accepted requirement a stable `requirement_id`.
- Split compound requirements when one criterion cannot prove the whole item.
- Mark inferred choices as assumptions/defaults; do not disguise them as user
  statements.
- Ask only about open questions that materially change implementation and lack
  a safe, discoverable default.
- Every slice and task packet references the requirement ids it advances.
- Spec Review checks that all accepted requirement ids have criteria and that
  no extra scope was introduced.
- Completion requires passed evidence for every accepted requirement id or an
  explicit approved exclusion with a reason.
- Updating a requirement updates this map first, then affected slices, tests,
  and handoffs. Do not silently fork acceptance criteria.
- During small progressive route clearance, Requirement Acceptance Map is not required while progressive_route_clear_consumption_state=pending; use the pending handoff and its current decision references to prepare the completed map. Requirement Acceptance Map is required when progressive_route_clear_consumption_state=consumed and progressive_artifact_retention_state=retained. Medium+ work still requires its map regardless of this progressive retention lifecycle.
- When this map consumes progressive route clearance, the source
  `route_clear_handoff.decisions` contains every current-map resolved decision
  exactly once through canonical decision_resolution.decision_item_ref values,
  while superseded/excluded current-map decisions appear exactly once in
  exclusions. decisions is non-empty when any current-map decision has
  status=resolved; retained historical resolutions for superseded/excluded
  current-map items are lineage evidence only and do not appear in decisions. Its
  `source_route_clear_handoff_ref` resolves to the source handoff and that
  handoff's `consumed_by_requirement_acceptance_map_ref` resolves back to this
  consuming map; these reciprocal references are not equal values. The handoff
  decisions and constraints are traced into applicable accepted map state;
  exclusions appear in non_goals or entries with status=approved_exclusion;
  every `retired_or_excluded_deferred_uncertainty_refs` entry appears exactly
  once through `retired_or_excluded_deferred_uncertainty_traces` as a non-goal
  or approved exclusion with a concrete target ref; and
  each acceptance_seed becomes an entries[].acceptance_criterion with binary
  acceptance. The only permitted `entries=[]` map is the exact all-excluded
  route: source `decisions=[]` and `acceptance_seed=[]`, no accepted
  requirement, and every excluded or retired source item traced exactly once to
  a concrete non-goal or approved-exclusion target; never fabricate an entry.
- Keep both reciprocal references while
  `progressive_artifact_retention_state=retained`. Before
  `progressive_artifact_retention_state=terminally_archived` is persisted or
  resumed, a present `progressive_terminal_archival` tombstone must bind the
  exact `current_task_identity` and
  `final_progressive_decision_map_ref`, record a typed final
  archival/termination basis and explicit final archival/termination evidence,
  and carry resolvable `evidence_refs` proving
  continuation and reference resolution are impossible. It must be present
  before progressive_artifact_retention_state=terminally_archived is persisted
  or resumed. Only that
  identity-valid, evidence-valid tombstone authorizes one atomic transition
  with uncertainty_shape=bounded and
  progressive_discovery_state=not_applicable;
  then the progressive reciprocal refs may be omitted even when a medium+
  Requirement Acceptance Map itself remains required. Missing, dangling, or
  mismatched tombstone evidence fails closed. `Task state: completed` does not
  qualify as final archival, and `terminally_archived` cannot revert.
