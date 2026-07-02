# Harness Controller

Use this reference only for medium+ work that is harness-capable: long-running,
multi-slice, delegated, high-risk, subjective/domain-scored, trace/replay-ready,
or explicitly requested as harness work. Do not load it for small local fixes.

## Pre-Build Gate

Before Build starts, the approved plan must contain both:

- an accepted Done Contract
- a selected Harness Recipe
- refs for Harness Run State, Trace Ledger, and Replay Packet artifacts when
  the recipe is trace/replay-ready

If either is missing, block Build, return to Plan, add the missing artifact, and
record the corrective action in the task journal or carried-forward state.

## Done Contract

The Done Contract defines what "finished" means before implementation begins.

Required fields:

- `done_when`: pass/fail outcomes that prove the slice or task is complete
- `not_done_when`: explicit failure states that must block completion
- `verification`: commands, inspections, reviews, or manual checks that prove done
- `owner_consumer`: owner and downstream consumer of the artifact or behavior
- `acceptance_criteria`: explicit binary criteria copied from user/plan/slice scope
- `debate_record`: at least two perspectives considered before acceptance
- `accepted_by`: user, orchestrator, or approved plan reference

For subjective/domain-scored, product, UX, UI, docs, or DX work, carry any
scoped `domain_context` and `rubric_refs` into the QA Evaluator packet. These
refs enable conditional use of assistant-review `references/domain-rubrics.md`;
they are not required for unrelated code-review-only work.

Debate rules:

- Record at least two perspectives, such as implementer, tester, reviewer,
  architect, product, security, docs, or user.
- When `subagent_execution_mode=delegated` and relevant subagents are available,
  use subagent perspectives for the debate before Build.
- If delegated debate is unavailable, record the fallback reason and the direct
  role-equivalent perspectives used.
- Do not let the debate add scope. Scope changes are plan deviations.

## Harness Recipe

The Harness Recipe selects the controller shape from the task/model/risk/context
profile. It is a short routing decision, not a new plan.

Required profile fields:

- `task_profile`: task type, size, slice count, and whether TDD/debugging applies
- `model_profile`: agent/model constraints, delegation mode, and tool limits
- `risk_profile`: risk tier, safety gates, review depth, and rollback needs
- `context_profile`: exact context, summarized context, omitted/deferred context,
  and whether trace/replay or handoff artifacts are needed

Required recipe fields:

- `selected_recipe`: concise recipe label
- `recipe_rationale`: why the profile selects this recipe
- `required_artifacts`: Done Contract, task packet, verification, and any trace or
  handoff artifacts needed by later slices
- `corrective_action`: what to do if the recipe is missing or stops matching the
  task during Build
- Corrective action: the recorded recovery step for a missing or stale recipe

Selection rules:

- Use a lightweight guarded recipe for medium single-slice work with moderate risk
  and compact context.
- Use a slice-sequential recipe when independent slice verification is required.
- Use a review-intensive recipe for high/critical risk, weak tests, public
  contracts, or subjective acceptance.
- Use a trace/replay-ready recipe when context is large, work is long-running, or
  recovery after compaction/failure is likely.

## Runtime Artifacts

For medium+ harness-capable work, keep these first-class artifacts in the task
journal or equivalent carried-forward state and update them as execution
progresses. They are recovery artifacts, not extra planning ceremony.

### Harness Run State

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

### Trace Ledger

Records ordered or timestamped execution evidence:

- agent events
- decisions
- verification commands/results
- plan deviations
- artifact refs

### Replay Packet

Captures the minimum continuation packet needed after compaction, failure, or
handoff:

- pinned context
- artifact refs
- validation state
- exact next action
- run-state and trace-ledger refs
- recovery pointer

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
  `scope_conflict`, `tool_environment`, `permission_policy`, `tdd_red_missing`,
  or `other`
- verification blockers, plan deviations, or scope changes that make the
  approved packet stale

Required decision fields:

- `trigger`: the exact trigger category
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
- `next_agent`: the next role or agent to dispatch
- `recovery_pointer`: task packet, trace row, replay packet, plan section, or
  file path where recovery resumes
- `exact_next_action`: the single action to perform after the decision

When a decision is created, update Harness Run State, append a `pivot_restart`
Trace Ledger entry, refresh Replay Packet so `exact_next_action` matches the
decision, and add or update the Pivot/Restart Decision artifact ref. Round 20 remains terminal; the controller never creates round 21 behavior.

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
- Review or QA stagnation routes to reset context, candidate search, replan,
  or restart depending on the evidence; do not silently continue the loop.

## Typed Artifact References

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
current state. Consumer responsibility: validate `schema_or_contract` and
`validation_status` before relying on `location_ref`; invalid or stale refs block
phase advancement or trigger re-dispatch.

Use typed refs for Done Contract, Harness Recipe, Harness Run State, Trace
Ledger, Replay Packet, Pivot/Restart Decision, changed files, verification
evidence, and plan deviation refs when applicable.

## Corrective Actions

- Missing Done Contract: return to Plan, load this reference, write the contract,
  record debate with at least two perspectives, and wait for approval when the
  contract changes scope or acceptance.
- Missing Harness Recipe: return to Plan, classify task/model/risk/context
  profile, select a recipe, and record rationale plus corrective action.
- Missing debate perspectives: collect the missing perspective through delegated
  subagents when available, or record direct fallback perspective evidence.
- Missing run-state/trace/replay evidence: pause phase advancement, add or
  repair Harness Run State, Trace Ledger, and Replay Packet blocks with the
  required fields, append a corrective trace entry, and resume from the recorded
  exact next action.
- Pivot/restart trigger: pause the active loop, create the orchestrator-owned
  `pivot_restart_decision`, update run-state/trace/replay/artifact refs, and
  reapprove before continuing if scope, files, behavior, risk, verification, or
  acceptance criteria change.
- Recipe mismatch during Build: print `>> PLAN DEVIATION DETECTED`, update the
  recipe, and seek re-approval when files, behavior, scope, risk, or verification
  changes.
