# Harness Runtime Artifacts

Internal reference for harness-only runtime artifacts and recovery handling.
Load only after `references/workflow-controller.md` or carried-forward phase
state establishes `harness_capable=true`. Ordinary medium work avoids Done
Contract, Harness Recipe, Trace Ledger, Replay Packet, Artifact Reference
Ledger, and QA unless explicit controller criteria apply.

## Runtime Artifact Rule

For medium+ harness-capable work, keep these first-class artifacts in the task
journal or equivalent carried-forward state and update them as execution
progresses. They are recovery artifacts, not extra planning ceremony.

Use `references/plan-harness-appendix.md` and
`references/task-journal-harness-appendix.md` when full task packet or journal
schemas are needed.

## Harness Run State

Records the current task/run position:

- `task_id`
- `task_name`
- `phase`
- `slice`
- `status`
- `blockers`
- `last_verification`
- `next_action`
- `recovery_pointer`

Update Harness Run State after each slice/step, blocker, verification result,
phase transition, or next-action change.

## Trace Ledger

Records ordered or timestamped execution evidence:

- agent events
- decisions
- verification commands/results
- plan deviations
- artifact refs
- pivot/restart decisions

Append Trace Ledger entries for agent events, decisions, verification
commands/results, plan deviations, pivot/restart decisions, and artifact refs.

## Replay Packet

Captures the minimum continuation packet needed after compaction, failure, or
handoff:

- pinned context
- artifact refs
- validation state
- exact next action
- run-state and trace-ledger refs
- recovery pointer

Refresh the Replay Packet before context compaction, failure handoff, phase
handoff, end-of-turn, completion, or restart with pinned context, artifact refs,
validation state, and the exact next action.

## Artifact Reference Ledger

When a harness artifact crosses an agent boundary, pass it as an Artifact
Reference entry instead of an ad hoc string. Each entry carries:

- `artifact_id`
- `artifact_type`
- `producer`
- `consumer`
- `location_ref`
- `schema_or_contract`
- `validation_status`
- `summary`

Producer responsibility: create or update the artifact, assign its stable id and
location/ref pointer, name the contract or schema it follows, and summarize its
current state.

Consumer responsibility: validate `schema_or_contract` and `validation_status`
before relying on `location_ref`; invalid or stale refs block phase advancement
or trigger re-dispatch.

Use typed refs for Done Contract, Harness Recipe, Harness Run State, Trace
Ledger, Replay Packet, Pivot/Restart Decision, changed files, verification
evidence, and plan deviation refs when applicable.

## Pivot/Restart Controller

The Pivot/Restart Controller is owned by the orchestrator. It runs when a
quality loop or Build handoff is no longer making safe progress.

Trigger it for:

- review or QA `STAGNATION`
- repeated `DRIFT`
- repeated `REGRESSION`
- rubric or domain action `pivot`
- Code Writer `blocker_type` returns such as `legacy_code_bug`,
  `broken_baseline`, `hidden_dependency`, `missing_contract`, `stale_plan`,
  `scope_conflict`, `tool_environment`, `permission_policy`,
  `tdd_red_missing`, or `other`
- verification blockers, plan deviations, or scope changes that make the
  approved packet stale

Required decision fields:

- `trigger`: exact trigger category
- `evidence`: score entries, findings, blocker evidence, verification failures,
  or trace refs proving the trigger
- `affected_slice_or_round`: current slice id/name, review round, QA round, or
  workflow phase
- `options_considered`: at least two recovery options unless policy or missing
  approval leaves only one safe path
- `selected_action`: reset context, return to Build, dispatch debugging,
  dispatch explorer, dispatch architect, run candidate search, replan, restart
  the slice, restart the phase, block for user, or accept with limitations
- `reapproval_required`: true whenever scope, files, behavior, risk,
  verification, or acceptance criteria change
- `next_agent`: next role or agent to dispatch
- `recovery_pointer`: task packet, trace row, replay packet, plan section, or
  file path where recovery resumes
- `exact_next_action`: single action to perform after the decision

When a decision is created, update Harness Run State, append a `pivot_restart`
Trace Ledger entry, refresh Replay Packet so `exact_next_action` matches the
decision, and add or update the Pivot/Restart Decision artifact ref. Round 10
remains terminal; the controller never creates round 11 behavior.

Routing rules:

- Code Writer legacy code bugs or broken baselines route to debugging before
  another implementation attempt.
- Hidden dependencies route to Explorer or Code Mapper refresh.
- Missing contracts or stale task packets route to Architect or Plan repair.
- Scope conflicts, plan deviations, and candidate pivots route to replan and
  reapproval when scope, files, behavior, risk, verification, or acceptance
  criteria change.
- Tool, environment, permission, or policy blockers route to environment fix,
  permission request, or BLOCKED with evidence.
- Review or QA stagnation routes to reset context, candidate search, replan, or
  restart depending on the evidence; do not silently continue the loop.

## Corrective Actions

- Missing run-state/trace/replay evidence: pause phase advancement, add or
  repair Harness Run State, Trace Ledger, and Replay Packet blocks with the
  required fields, append a corrective trace entry, and resume from the recorded
  exact next action.
- Missing or stale Artifact Reference Ledger: update refs with producer,
  consumer, location_ref, schema_or_contract, validation_status, and summary
  before any consumer relies on them.
- Pivot/restart trigger: pause the active loop, create the orchestrator-owned
  `pivot_restart_decision`, update run-state/trace/replay/artifact refs, and
  reapprove before continuing if scope, files, behavior, risk, verification, or
  acceptance criteria change.
- Recipe mismatch during Build: print `>> PLAN DEVIATION DETECTED`, update the
  recipe, and seek re-approval when files, behavior, scope, risk, or
  verification changes.
- Document completion for harness work: refresh Harness Run State, append final
  Trace Ledger entries for review/document decisions, include Pivot/Restart
  Decision refs when triggered, and update Replay Packet validation_state plus
  exact_next_action before completion or handoff.
