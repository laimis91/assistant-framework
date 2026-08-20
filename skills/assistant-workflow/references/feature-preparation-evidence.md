# Existing-System Feature Preparation Evidence

Use this reference whenever `feature_preparation_scope=existing_system`.
Prepare-only and end-to-end work produce the evidence during Discover;
implement-only work must resolve the approved evidence ref carried by its
packet before Build. It is provider-neutral: a
requirement source may be a ticket, brief, issue, conversation, or local
document; design evidence may be supplied, not applicable, or unavailable.

## Procedure

For each scoped behavior or proposed open question, create one
`feature_preparation_evidence.items[]` row.

1. Record the requirement evidence and the design disposition.
2. Trace the current execution path from entry point through coordinator/service
   to every relevant observable effect. Record `inspected_absent` with bounded
   searches or `inaccessible` with the concrete access limitation instead of
   inventing a file, symbol, or behavior.
3. Inspect the behavioral tests and name the assertion, inspected absence, or
   access limitation.
4. Compare the sources and classify the row on both axes.
5. Carry the stable `ref` into the preparation plan, any applicable Architecture
   Decision Pack, diagrams, and documentation.

For `execution_intent=prepare_only`, finish with `Execution not started` and do
not manufacture changed-files, Build, test-run, or code-review evidence. For
`execution_intent=end_to_end`, pass the same gate before Plan or Build. For
`execution_intent=implement_only`, consume the approved ref rather than
reconstructing missing preparation.

Prepare-only routes from Discover to Preparation Completion. Readiness
Decompose/Plan context is optional; Design, Build, Review, implementation
Document, and final-handoff gates are inapplicable.

## Classification

`behavior_status` records what should happen to behavior:

- `existing_behavior_to_preserve`
- `new_behavior`
- `explicit_change`
- `source_conflict`
- `materially_unknown`

`work_status` records what work or decision remains:

- `implementation_gap`
- `technical_design_decision`
- `source_conflict_resolution`
- `product_question`
- `evidence_gap`
- `no_open_decision`

These axes are independent. A requirement that adds a read-only VIEWING route
while the ACTIVE route already selects an object, highlights the map, and
focuses the viewport is normally
`existing_behavior_to_preserve + implementation_gap`: preserve those effects
for VIEWING without enabling editing.

## Product-question admissibility

Product question admissibility fails closed. Do not ask a Product question
merely because the requirements or design source omits a behavior.

- Inspect the current implementation path and relevant behavioral tests first.
- Preserve existing observable behavior unless a source explicitly changes it.
- If code or tests cannot be inspected, record `evidence_gap`, not
  `product_question`.
- If sources conflict, record `source_conflict`, not `product_question`.
- Pair `behavior_status=source_conflict` with
  `work_status=source_conflict_resolution` until an authoritative source
  resolves the conflict.
- Use `product_question` only when behavior remains materially unknown after
  the available requirements/design, implementation, and tests were inspected
  and no safe default exists.

## Preparation-only completion

Preparation-only completion returns `feature_preparation_result`: execution
status `not_started`, exact scope, the evidence ref only for existing-system
work, evidence gaps, open decisions, implementation implications, and a
recommended next step. Medium+ preparation may include an optional readiness
plan, but it does not wait for implementation approval: record the approval or
delegation required for a later implementation workflow in `open_decisions`
and/or `recommended_next_step`. It does not return invented changed files,
Build, test-run, review, or final-handoff evidence.
