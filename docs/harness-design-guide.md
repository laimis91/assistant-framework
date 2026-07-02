# Harness Design Guide

Design guide for the Assistant Framework harness controller: the planning,
artifact, review, QA, trace/replay, and recovery layer used for long-running
agent workflows.

**Reference:** [Anthropic Engineering - Harness Design for Long-Running Apps](https://www.anthropic.com/engineering/harness-design-long-running-apps)

---

## Core Concept

A harness lets one orchestration session coordinate specialized roles without
letting any role quietly absorb every responsibility. The current framework is a
controller, not a fixed role recipe:

1. **Define done before Build** with an accepted Done Contract.
2. **Select the controller shape** with a Harness Recipe.
3. **Carry state as artifacts** through run-state, trace, replay, and typed refs.
4. **Separate implementation, code review, and QA acceptance** into distinct
   responsibilities.
5. **Detect drift and stagnation** and route pivots/restarts through an explicit
   decision artifact.

The smallest useful harness still keeps these concerns distinct. Small tasks can
take a lightweight path, but medium+ harness-capable work must not enter Build
without the controller artifacts that make recovery and review possible.

---

## Pre-Build Controller

### Done Contract

The Done Contract defines what "finished" means before implementation starts.
It is required for medium+ harness-capable work and contains:

- `done_when`: observable outcomes that prove completion
- `not_done_when`: states that must block completion
- `verification`: commands, inspections, review, QA, or manual evidence needed
- `owner_consumer`: owner and downstream consumer of the artifact or behavior
- `acceptance_criteria`: binary criteria from the user, plan, or slice scope
- `debate_record`: at least two perspectives considered before acceptance
- `accepted_by`: user, orchestrator, or approved plan reference

When `subagent_execution_mode=delegated`, the debate should use relevant
subagent perspectives such as Architect, Builder/Tester, Code Reviewer, QA
Evaluator, Security, Docs, or Product. Direct fallback must record why subagents
were unavailable or unauthorized and which role-equivalent perspectives were
used. The debate cannot add scope; scope changes return to Plan.

### Harness Recipe

The Harness Recipe selects the controller shape from the current
task/model/risk/context profile. It is short routing metadata, not another plan.

Required profile fields:

- `task_profile`: task type, size, slice count, TDD/debugging needs
- `model_profile`: agent/model constraints, delegation mode, tool limits
- `risk_profile`: risk tier, safety gates, review depth, rollback needs
- `context_profile`: exact context, summarized context, omitted/deferred
  context, and trace/replay need

Required recipe fields:

- `selected_recipe`
- `recipe_rationale`
- `required_artifacts`
- `corrective_action`

Recipes normally fall into lightweight guarded, slice-sequential,
review-intensive, or trace/replay-ready variants. If the recipe stops matching
the task during Build, record `>> PLAN DEVIATION DETECTED`, repair the recipe,
and seek re-approval when files, behavior, scope, risk, verification, or
acceptance criteria change.

---

## Runtime Artifacts

Harness artifacts live in the task journal or equivalent carried-forward state.
They are recovery artifacts, not ceremony.

| Artifact | Purpose |
|---|---|
| Harness Run State | Current phase, slice, status, blockers, last verification, next action, recovery pointer |
| Trace Ledger | Ordered agent events, decisions, verification results, deviations, blockers, and artifact refs |
| Replay Packet | Minimum continuation packet after compaction, handoff, failure, or restart |
| Artifact Reference Ledger | Typed refs that let producers and consumers validate artifact location, schema, and freshness |
| Pivot/Restart Decision | Orchestrator-owned recovery decision when the active loop or handoff stops making safe progress |

### Typed Artifact References

When an artifact crosses an agent boundary, pass it as a typed Artifact
Reference instead of a loose string:

- `artifact_id`
- `artifact_type`
- `producer`
- `consumer`
- `location_ref`
- `schema_or_contract`
- `validation_status`
- `summary`

Use typed refs for Done Contract, Harness Recipe, Harness Run State, Trace
Ledger, Replay Packet, Pivot/Restart Decision, task packets, changed files,
verification evidence, review results, QA results, and plan deviations.
Producers create or update refs; consumers validate `schema_or_contract` and
`validation_status` before relying on them.

---

## Role Separation

The controller separates implementation, verification, code review, and QA
responsibilities:

| Role | Responsibility | Writes Source? |
|---|---|---|
| Code Writer | Implements the approved task packet and reports blockers without broadening scope | Yes |
| Builder/Tester | Runs builds, tests, and verification; requests Code Writer fixes for production failures | Tests/fixtures as assigned, not production code |
| Code Reviewer | Reviews code defects, security, architecture, test coverage, and structural code risk | No |
| QA Evaluator | Evaluates Done Contract, acceptance criteria, verification evidence, final readiness, and scoped domain quality | No |

`reviewer` remains a compatibility route for older handoffs, but new code review
dispatches should use `code-reviewer`. QA Evaluator does not replace Code
Reviewer; QA findings are about acceptance and evidence, not general code
quality. Both delegated mode and direct fallback must record Code Reviewer
evidence separately from QA Evaluator evidence.

### Conditional Domain Rubrics

QA loads `skills/assistant-review/references/domain-rubrics.md` only when the
Done Contract, acceptance criteria, `domain_context`, or explicit `rubric_refs`
scope UI/visual, product, UX, docs, DX, or domain craft quality. When no domain
rubric is scoped, QA records domain quality as not applicable instead of
inventing subjective bars.

---

## Review And QA Loops

The code-review loop and QA loop are bounded at **max 20 rounds**.

```text
round = 1
previously_fixed = []
score_history = []

while round <= 20:
  REVIEW   -> fresh Code Reviewer with diff, acceptance context, and prior fixes
  DECIDE   -> PASS, REFINE, or PIVOT from rubric score and findings
  FIX      -> Code Writer fixes actionable findings when REFINE
  VERIFY   -> Builder/Tester records build/test evidence
  round += 1
```

QA runs after build/test evidence and Code Reviewer evidence exist:

```text
round = 1
previously_failed_acceptance_items = []
score_progression = []

while round <= 20:
  EVALUATE -> QA Evaluator checks Done Contract, criteria, evidence, domain scope
  SCORE    -> qa_scorecard and score_entry
  DECIDE   -> accepted, accepted_with_concerns, rejected, or blocked
  FIX/EXIT -> return failed acceptance items to Build, or exit with final result
  round += 1
```

Round 20 is terminal. The controller reports remaining blockers or failed
acceptance items instead of starting round 21.

### Finding Filter

Review and QA findings must have concrete evidence and direct impact:

| Rounds | Blocking bar |
|---|---|
| 1-15 | Evidence-backed must-fix or should-fix findings |
| 16-19 | Must-fix or high-confidence should-fix findings |
| 20 | Terminal report of remaining blockers or acceptance items |

Speculative concerns stay non-blocking unless evidence connects them to
correctness, security, architecture, test reliability, or acceptance criteria.

---

## Drift, Stagnation, And Pivot/Restart

The controller tracks score progression and finding counts so rising scores do
not mask stale or worsening output.

| Signal | Meaning | Controller Response |
|---|---|---|
| GENUINE | Score improves and finding count decreases | Continue normally |
| SUSPICIOUS | Score jumps sharply while findings drop | Log and continue skeptically |
| DRIFT | Score improves while findings stay flat or rise | Reset evaluator with stricter context |
| REGRESSION | Score drops | Investigate; repeated regression triggers pivot/restart |
| STAGNATION | Findings remain across repeated unchanged scores | Create pivot/restart signal |

The orchestrator owns `pivot_restart_decision`. It records the trigger, evidence,
affected slice or round, options considered, selected action, reapproval need,
next agent, recovery pointer, and exact next action. After the decision, update
Harness Run State, append a trace entry, refresh Replay Packet, and update the
Artifact Reference Ledger.

### Code Writer Blocker Routing

Code Writer must report unexpected blockers instead of patching around them.
Controller routing:

- `legacy_code_bug` or `broken_baseline` -> assistant-debugging before another
  implementation attempt
- `hidden_dependency` -> Explorer or Code Mapper refresh
- `missing_contract` or `stale_plan` -> Architect or Plan repair
- `scope_conflict` -> replan and reapproval when scope changes
- `tool_environment` or `permission_policy` -> environment fix, permission
  request, or BLOCKED with evidence
- `tdd_red_missing` -> return to TDD RED evidence before production code is
  accepted

Review/QA stagnation, repeated drift/regression, domain action `pivot`,
verification blockers, and stale task packets all route through the same
Pivot/Restart Controller. Do not silently continue the loop after these signals.

---

## Gate Enforcement

The current enforcement path is:

- `assistant-workflow` loads `references/harness-controller.md` only for
  medium+ harness-capable work.
- Workflow contracts require Done Contract and Harness Recipe before Build.
- Task journal templates carry Harness Run State, Trace Ledger, Replay Packet,
  Pivot/Restart Decision, and Artifact Reference Ledger sections.
- `workflow-enforcer.sh` and `workflow-phase-gates.sh` surface
  `Prompt-time runtime gate warnings` for
  `BUILDING/VERIFYING/REVIEWING/DOCUMENTING`.
- `stop-review.sh` is the consolidated strict stop gate for plan approval,
  review, rubric/score, metrics, and final-result completion.
- `harness-gate.sh` remains only a legacy compatibility/reference script.

---

## Quick Reference: Framework Files

| Component | Key Files |
|---|---|
| Harness controller reference | `skills/assistant-workflow/references/harness-controller.md` |
| Workflow phase execution | `skills/assistant-workflow/references/phases.md` |
| Task journal template | `skills/assistant-workflow/references/task-journal-template.md` |
| Workflow contracts | `skills/assistant-workflow/contracts/{input,output,phase-gates,handoffs}.yaml` |
| Code review loop | `skills/assistant-review/SKILL.md` |
| QA loop | `skills/assistant-review/references/qa-evaluation-loop.md` |
| Domain rubrics | `skills/assistant-review/references/domain-rubrics.md` |
| Review rubric and score tracking | `skills/assistant-review/references/{review-rubric,score-tracking}.md` |
| Code Reviewer agents | `agents/{claude,codex}/code-reviewer.*` |
| QA Evaluator agents | `agents/{claude,codex}/qa-evaluator.*` |
| Runtime hooks | `hooks/scripts/{workflow-enforcer,workflow-phase-gates,stop-review}.sh` |
| Contract design guide | `docs/skill-contract-design-guide.md` |
