# Workflow packet compatibility

Load only when resuming older serialized workflow packets. Current schemas remain
in `contracts/`; this reference does not reinterpret historical evidence.

- v12 → v13: refresh active separated TDD through `build-worker-protocol.md`
  and current handoff stage/selection contracts. Earlier verifier-authored RED
  remains historical; never relabel it or infer current authorization.
- v14 requires assistant-verification and preserves assistant-review. Use the
  `packet_admission` selector for verified v12/v13 slices; released13 and unreleased
  canonical13 are not interchangeable. Before Build, older packets need a current
  verification decision and matching TDD projection, never inferred checks or RED.
- Pack `selected_alternative_id` remains stable; verified `quality_scenario_id`
  resolves verification identity. `review_result` retains canonical references.
  Plan binds task/review refs as `downstream_bound` before Build (inline at pre-Build
  for `plan_mode=none`). Material invalidation clears them through refresh, re-plan,
  and reapproval.

Use current input/output/phase-gate/handoff and admission rules for the selected
boundary. A successful historical run is not evidence of current closure.

- v14 → v15: validate the original definition/approval first. `normalize_v14` retains source and normalized digests and fixed packet mapping; persist returned canonical_plan/canonical_context together. Preserve scope, exact checks/TDD, actors, inputs, running admission and results. Historical counts do not establish progress or grant a new window; reconstruct only retained observations or report the gap. No new business approval solely for equivalent representation.
