# Existing-System Feature Preparation Evidence

Use this provider-neutral reference when `feature_preparation_scope=existing_system`.
Prepare-only and end-to-end work capture evidence during Discover; implement-only
resolves the approved result before Build. Requirements may come from tickets,
briefs, issues, conversations, or local documents; design evidence may be supplied,
not applicable, or unavailable.


## Procedure

Create one `feature_preparation_evidence.items[]` row per scoped behavior or
proposed question.

1. Record requirement evidence and design disposition.
2. Trace the current path from entry through coordinator/service to every
   relevant observable effect. Record `inspected_absent` with bounded
   searches or `inaccessible` with the concrete access limitation instead of
   inventing a file, symbol, or behavior.
3. Inspect behavioral tests; name the assertion, inspected absence, or access
   limitation. When exact provenance is required by a hash-bound evaluator or
   downstream consumer, record the implementation trace's `content_sha256` and
   `inspection_event_ref`, plus each test's `file`, `content_sha256`, `test_name`,
   and `inspection_event_ref`. Each event ref resolves to the completed successful
   read-only inspection that produced its evidence.
4. Compare sources and classify both axes.
5. Treat `feature_preparation_evidence.ref` as the stable identity of the evidence artifact.
   It is carried unchanged into preparation plans, task packets,
   any applicable Architecture Decision Pack, diagrams, and documentation;
   `item_id` and claim bindings add row-level meaning without replacing that
   artifact identity.

For `execution_intent=prepare_only`, finish with `Execution not started` and do
not manufacture changed-files, Build, test-run, or code-review evidence. For
`execution_intent=end_to_end`, pass the same gate before Plan or Build. For
`execution_intent=implement_only`, consumes the approved result unchanged.
Existing-system work also resolves its evidence ref; not_applicable retains its
scope, gaps, decisions, implications, readiness, obligations, and next step.

Prepare-only routes from Discover to Preparation Completion. Readiness Plan
context is optional; Decompose, Design, Build, Review, implementation
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

Product questions fail closed. Requirements or design omissions are insufficient.

- Inspect implementation, behavioral tests, and available sources; ask only about
  materially unknown behavior without a safe default.
- Preserve existing observable behavior only within the actor, data, and
  authorization context supported by its sources. Adding a route does not itself
  change that context; a new audience or disclosure boundary may.
- Implementation or internal controls alone cannot establish policy for new audiences or data boundaries.
- Every response and task journal draft keeps each unanswered material choice
  unresolved alongside its provisional recommendation; do not record an
  applied default or confirmed criterion. Source-backed technical defaults remain automatic.
- Missing inspection or access is `evidence_gap`; contradictions are `source_conflict`,
  never `product_question`. Pair `behavior_status=source_conflict` with
  `work_status=source_conflict_resolution` until an authoritative source resolves it.

## Preparation-only completion

Preparation-only returns `feature_preparation_result` with
`execution_status=not_started`, exact scope, the evidence ref only for
existing-system work, evidence gaps, open decisions, implementation implications,
and a recommended next step. Medium+ may include a readiness plan without
waiting for implementation approval; record later approval or delegation in
`open_decisions` or `recommended_next_step`.
When an explicit QA/acceptance evaluation was
requested, keep it only in
`feature_preparation_result.future_qa_acceptance_obligation` while preparation
uses `qa_evaluation_mode=not_required`.
Later `implement_only` preserves `requested_scope` and
`execution_prerequisite` exactly as
`approved_feature_preparation_qa_acceptance_obligation`, then adds exactly one
source binding: the evidence ref for `existing_system`, or
`source_preparation_basis=not_applicable` without an evidence ref for
`not_applicable`. It sets `qa_evaluation_mode=required` and carries the
resulting enriched object unchanged through the task packet, Build,
verification, and the existing post-Build Code Reviewer then QA Evaluator lane.
When an explicit harness request or accepted independent harness evidence was
supplied, keep it only in `feature_preparation_result.future_harness_obligation`
with the exact requested scope, non-empty evidence basis, and the prerequisite
of an approved implementation workflow with accepted pre-Build Done Contract
and Harness Recipe. Preparation always keeps `harness_capable=false`; this
future obligation does not load harness guidance, activate runtime artifacts,
select a Build lane, or independently require strict/journal state.
Later `implement_only` preserves the three approved payload fields
(`requested_scope`, `evidence_basis`, and `execution_prerequisite`) exactly as
`approved_feature_preparation_harness_obligation`, then adds exactly one source
binding: the evidence ref for `existing_system`, or
`source_preparation_basis=not_applicable` without an evidence ref for
`not_applicable`. It promotes an initially small implementation to at least
`medium`, sets `harness_capable=true`, and carries the resulting enriched object unchanged through the
pre-Build Done Contract, Harness Recipe, and runtime-ref gates, task packets,
Build, and verification.
It does not return invented changed files,
Build, test-run, review, or final-handoff evidence.
