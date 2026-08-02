# Requirement to Acceptance Map

Create this compact map after material clarification and before decomposition.
It is the single traceability spine from user intent to completion evidence;
slices and task packets consume it instead of inventing a second source of
truth.

Small work may use the compact `acceptance_criteria` list unless ambiguity,
risk, or multiple material requirements promote it to the durable map.

## Required shape

```text
Requirement Acceptance Map:
- intended_outcome: [one concise outcome]
- assumptions_and_defaults: [explicit inferred choices]
- open_material_questions: [none before Plan, or unresolved blockers]
- non_goals: [explicit exclusions]
- source_route_clear_handoff_ref: [conditional: source route-clear handoff when progressive route clearance is consumed]
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
- When this map consumes progressive route clearance, its
  `source_route_clear_handoff_ref` resolves to the source handoff and that
  handoff's `consumed_by_requirement_acceptance_map_ref` resolves back to this
  consuming map; these reciprocal references are not equal values. The handoff
  decisions and constraints are traced into applicable accepted map state;
  exclusions appear in non_goals or entries with status=approved_exclusion; and
  each acceptance_seed becomes an entries[].acceptance_criterion with binary
  acceptance.
