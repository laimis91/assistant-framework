# Harness Patterns for Loop-Based Process Skills

Reference pack for `assistant-skill-creator`. Load this when designing a
**Process** skill that includes a long-running controller, subagent dispatch,
multi-round review, QA/acceptance evaluation, retry loops, or autonomous
fix-verify cycles.

Skip this reference for single-pass Utility skills or Analysis skills without
delegation or loop control.

---

## Pattern 1: Done Contract

Use a Done Contract when "finished" needs to be known before Build or generation
starts.

Required fields:

- `done_when`: observable pass/fail outcomes.
- `not_done_when`: explicit failure states that block completion.
- `verification`: commands, inspections, reviews, QA, or manual checks.
- `owner_consumer`: artifact owner and downstream consumer.
- `acceptance_criteria`: binary criteria from user, plan, or slice scope.
- `debate_record`: at least two perspectives considered before acceptance.
- `accepted_by`: user, orchestrator, or approved plan reference.

Design rule: when `subagent_execution_mode=delegated`, use subagent perspectives
for the debate when relevant. Direct fallback must record why subagents were not
used and which role-equivalent perspectives were considered. The debate may
clarify acceptance; it must not add unapproved scope.

Contract placement:

- `output.yaml`: `done_contract` artifact for medium+ harness-capable work.
- `phase-gates.yaml`: a pre-Build assertion that the accepted Done Contract
  exists and includes debate evidence.
- `handoffs.yaml`: `done_contract_ref` for workers, reviewers, and QA.

---

## Pattern 2: Harness Recipe

Use a Harness Recipe to choose the controller shape from task/model/risk/context
profiles.

Required profile fields:

- `task_profile`: task type, size, slice count, TDD/debugging needs.
- `model_profile`: model/agent constraints, delegation mode, tool limits.
- `risk_profile`: risk tier, safety gates, review depth, rollback needs.
- `context_profile`: exact, summarized, omitted/deferred context and
  trace/replay need.

Required recipe fields:

- `selected_recipe`
- `recipe_rationale`
- `required_artifacts`
- `corrective_action`

Typical recipes:

- `lightweight_guarded`: medium single-slice, moderate risk, compact context.
- `slice_sequential`: independent slice verification before the next slice.
- `review_intensive`: high/critical risk, weak tests, public contracts, or
  subjective acceptance.
- `trace_replay_ready`: long-running, large-context, recovery-prone work.

Contract placement:

- `output.yaml`: `harness_recipe` artifact.
- `phase-gates.yaml`: pre-Build recipe selection assertion.
- `handoffs.yaml`: `harness_recipe_ref` for downstream workers.

---

## Pattern 3: Runtime State, Trace, And Replay

Long-running Process skills need first-class recovery artifacts.

| Artifact | Required When | Fields |
|---|---|---|
| Harness Run State | Medium+ harness-capable or delegated loops | task id/name, phase, slice, status, blockers, last verification, next action, recovery pointer |
| Trace Ledger | Any trace/replay-ready loop | agent events, decisions, verification results, deviations, blockers, artifact refs |
| Replay Packet | Compaction, restart, handoff, or failure recovery is likely | pinned context, artifact refs, validation state, exact next action, run-state/trace refs |

Contract placement:

- `output.yaml`: required artifacts or conditional artifacts for trace/replay
  workflows.
- `phase-gates.yaml`: assertions that state/trace/replay are current before
  phase advancement.
- `handoffs.yaml`: refs carried into worker packets when a role relies on them.

---

## Pattern 4: Typed Artifact References

When artifacts cross an agent boundary, pass typed refs instead of free-form
strings.

Each Artifact Reference entry includes:

- `artifact_id`
- `artifact_type`
- `producer`
- `consumer`
- `location_ref`
- `schema_or_contract`
- `validation_status`
- `summary`

Use refs for Done Contract, Harness Recipe, Harness Run State, Trace Ledger,
Replay Packet, Pivot/Restart Decision, task packets, changed files,
verification evidence, review result, QA result, and plan deviations.

Producer responsibility: create/update the artifact, assign a stable id and
location/ref, name the schema or contract, and summarize current state.
Consumer responsibility: validate `schema_or_contract` and
`validation_status` before relying on `location_ref`; invalid or stale refs block
phase advancement or trigger re-dispatch.

---

## Pattern 5: Code Review And QA Separation

Do not let one evaluator do every job.

| Role | Owns | Does Not Own |
|---|---|---|
| Code Reviewer | code defects, security, architecture, test coverage, structural code risk | final acceptance or subjective domain quality unless directly tied to a code defect |
| QA Evaluator | Done Contract, acceptance criteria, verification evidence, final readiness, scoped domain quality | generic code review, security architecture, or test coverage review |

`reviewer` can remain a compatibility route, but new skills should name the
canonical `code-reviewer` and optional `qa-evaluator` roles separately.

Contract placement:

- `handoffs.yaml`: distinct handoffs to Code Reviewer and QAEvaluator.
- `output.yaml`: separate `review_result` and `qa_evaluation_result`.
- `phase-gates.yaml`: QA starts only after build/test evidence and Code
  Reviewer or compatibility review evidence exist.

---

## Pattern 6: Conditional Domain Rubrics

Use domain rubrics only when acceptance scopes them. Load or model rubric fields
when the Done Contract, acceptance criteria, `domain_context`, or explicit
`rubric_refs` require UI/visual, product, UX, docs, DX, or domain craft quality.

When scoped, QA returns:

- `selected_domain_rubrics`
- `domain_quality_scores`
- evidence tied to acceptance criteria, Done Contract, `domain_context`,
  `rubric_refs`, verification artifacts, screenshots, docs, or changed files

When not scoped, QA records domain quality as `not_applicable` and must not
invent subjective rubrics.

Contract placement:

- `input.yaml`: optional `domain_context` / `rubric_refs`.
- `handoffs.yaml`: conditional `selected_domain_rubrics` and
  `domain_quality_scores`.
- `phase-gates.yaml`: invariant rejecting invented domain rubrics.

---

## Pattern 7: Bounded Review / QA Loops

Any autonomous review, QA, refinement, or fix-verify loop needs a hard cap. The
current framework cap is **max 20 rounds**.

```text
round = 1
while round <= 20:
  evaluate
  decide PASS / REFINE / PIVOT
  fix or exit
  round += 1
```

Round 20 is terminal. Return remaining blockers, findings, or failed acceptance
items instead of starting round 21.

Include these fields where applicable:

- `round`: current round number, validation `>= 1 and <= 20`.
- `max_rounds`: default `20`.
- `previously_fixed` or `previously_failed_acceptance_items`.
- `score_progression` or `score_entry`.
- `loop_exit_reason`.

---

## Pattern 8: Rubric Scoring And Drift Detection

Use scored rubrics when quality is subjective or multi-dimensional.

Scoring fields:

- 3-6 domain-relevant dimensions, weights summing to 1.0.
- Anchors for 1, 3, and 5.
- `weighted_score`.
- action enum such as `PASS`, `REFINE`, `PIVOT`.
- evidence for each score.

Drift classification:

| Signal | Condition | Action |
|---|---|---|
| GENUINE | score improves and findings decrease | continue |
| SUSPICIOUS | score jumps sharply while findings decrease | log warning |
| DRIFT | score improves while findings stay flat or rise | reset evaluator |
| REGRESSION | score drops | investigate |
| STAGNATION | findings remain across repeated unchanged scores | pivot/restart |

Add cross-phase invariants for drift and stagnation. Repeated `DRIFT`, repeated
`REGRESSION`, `STAGNATION`, or rubric action `PIVOT` must return a
`pivot_restart_signal`; the orchestrator records the actual
`pivot_restart_decision`.

---

## Pattern 9: Pivot / Restart Decisions

Use Pivot/Restart when the active loop or handoff no longer makes safe progress.

Triggers:

- review or QA `STAGNATION`
- repeated `DRIFT`
- repeated `REGRESSION`
- rubric/domain action `PIVOT`
- Code Writer blocker types such as `legacy_code_bug`, `broken_baseline`,
  `hidden_dependency`, `missing_contract`, `stale_plan`, `scope_conflict`,
  `tool_environment`, `permission_policy`, `tdd_red_missing`, or `other`
- verification blockers, plan deviations, or scope changes that stale the packet

Decision fields:

- `trigger`
- `evidence`
- `affected_slice_or_round`
- `options_considered`
- `selected_action`
- `reapproval_required`
- `next_agent`
- `recovery_pointer`
- `exact_next_action`

Routing examples:

- Legacy code bug or broken baseline -> debugging before another implementation
  attempt.
- Hidden dependency -> Explorer or Code Mapper refresh.
- Missing contract or stale plan -> Architect or Plan repair.
- Scope conflict or candidate pivot -> replan and reapproval when scope changes.
- Tool/environment/policy blocker -> environment fix, permission request, or
  BLOCKED with evidence.

---

## Pattern 10: Agentic Loop Safety

Apply this pattern to every repeated agent/tool/model loop.

Required design fields:

- bounded execution: max rounds, steps, timeout, or budget
- stop condition: success, clean exit, max-budget exit, blocker exit
- retry policy: capped retries for transient failures only
- empty-result handling: broaden once, fallback, report no evidence, ask, or exit
- tool-error routing: retry, fallback, blocker, or degraded result
- progress signal: new evidence, fewer findings, better score, or explicit state
- cost/token guard: paid model, subagent, and large-context loops need budget
  awareness

A loop without bounds, stop conditions, empty-result handling, tool-error
routing, and a progress signal is incomplete even when the happy path works.

---

## Decision Checklist

For a loop-based Process skill, require the matching patterns:

| Question | Apply |
|---|---|
| Does Build need a definition of done? | Done Contract |
| Does controller shape vary by task/risk/context? | Harness Recipe |
| Could context compaction, restart, or handoff happen? | Run State, Trace, Replay |
| Do artifacts cross role boundaries? | Typed Artifact References |
| Are code quality and acceptance both evaluated? | Code Reviewer / QA Evaluator split |
| Is subjective/domain quality part of acceptance? | Conditional Domain Rubrics |
| Does a loop run multiple rounds? | Max 20 loop cap, scoring, drift detection |
| Can the approach go stale or hit legacy blockers? | Pivot/Restart Decision |

Most loop-based Process skills use all of these. Simple retry-only skills still
need bounded execution, stop conditions, error routing, and progress signals.

Full rationale and implementation references live in
`docs/harness-design-guide.md` and
`skills/assistant-workflow/references/harness-controller.md`.
