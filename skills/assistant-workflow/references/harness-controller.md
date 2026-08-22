# Harness Controller

Use this reference only for medium+ work that is explicitly harness-capable:
long-running, trace/replay-ready multi-slice, high-risk harness, subjective,
domain-scored work or UI/visual/product/UX/docs/DX-facing work, or explicitly
requested as harness work. Do not load it for small local fixes, ordinary
medium+ source changes, or delegation alone.

`harness_capable` defaults to false. Set it to true only when one of the
explicit criteria above is present in the request, approved plan, task packet,
or accepted Done Contract/Harness Recipe evidence.

Base plan and task-journal templates keep compact refs and `N/A: [reason]`
fields. Load `references/plan-harness-appendix.md` and
`references/task-journal-harness-appendix.md` only when the full harness,
typed artifact, pivot/restart, or QA schemas are needed.

## Pre-Build Gate

When `harness_capable=true`, before Build starts the approved plan must contain
both:

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

## Runtime and Recovery Artifacts

Load `references/harness-runtime-artifacts.md` when harness-capable work needs
detailed Harness Run State, Trace Ledger, Replay Packet, Pivot/Restart
Decision, or Artifact Reference Ledger schemas.

This file owns the harness entry decision, Done Contract, and Harness Recipe.
`references/harness-runtime-artifacts.md` owns runtime updates, pivot/restart
artifact handling, typed artifact refs, and corrective actions for missing or
stale runtime evidence.

Required runtime refs for trace/replay-ready harness work remain Harness Run
State, Trace Ledger, Replay Packet, and Artifact Reference Ledger. They stay
conditional on `harness_capable=true` and are not ordinary medium+ requirements.

## Corrective Actions

- Missing Done Contract: return to Plan, load this reference, write the contract,
  record debate with at least two perspectives, and wait for approval when the
  contract changes scope or acceptance.
- Missing Harness Recipe: return to Plan, classify task/model/risk/context
  profile, select a recipe, and record rationale plus corrective action.
- Missing debate perspectives: collect the missing perspective through delegated
  subagents when available, or record direct fallback perspective evidence.
- Missing run-state/trace/replay evidence: load
  `references/harness-runtime-artifacts.md` and follow its corrective action.
- Pivot/restart trigger: load `references/harness-runtime-artifacts.md`, create
  the orchestrator-owned `pivot_restart_decision`, update
  run-state/trace/replay/artifact refs, and reapprove before continuing if
  scope, files, behavior, risk, verification, or acceptance criteria change.
- Recipe mismatch during Build: print `>> PLAN DEVIATION DETECTED`, update the
  recipe, and seek re-approval when files, behavior, scope, risk, or verification
  changes.
