# Task Journal Harness Appendix

Load this appendix only when the task journal is tracking medium+
harness-capable work, QA evaluation, typed artifact references, or a
Pivot/Restart Decision. The base task journal keeps compact refs and
`N/A: [reason]` fields so ordinary medium+ work does not inherit this detail.

## Done Contract

[required before Build for medium+ harness-capable work]

- done_when:
  - [binary outcome that proves done]
- not_done_when:
  - [failure state that blocks done]
- verification:
  - [command, inspection, review, or manual check]
- owner_consumer: [owner and downstream consumer]
- acceptance_criteria:
  - [explicit binary criterion]
- debate_record:
  - perspective: [role/subagent/direct perspective 1]
    concern_or_support: [concise point]
    resolution: [accepted, rejected, or changed]
  - perspective: [role/subagent/direct perspective 2]
    concern_or_support: [concise point]
    resolution: [accepted, rejected, or changed]
- accepted_by: [user/orchestrator/approved plan reference]

## Harness Recipe

[required before Build for medium+ harness-capable work]

- task_profile: [task type, size, slice count, TDD/debugging applicability]
- model_profile: [agent/model constraints, delegation mode, tool limits]
- risk_profile: [risk tier, safety gates, review depth, rollback needs]
- context_profile: [exact/summarized/omitted context and trace/replay needs]
- selected_recipe: [concise recipe label]
- recipe_rationale: [why this task/model/risk/context profile selects the recipe]
- required_artifacts: [Done Contract, task packet, verification, trace/handoff artifacts]
- corrective_action: [what to do if missing or stale]

## Harness Run State

[required for medium+ harness-capable work]

- task_id: [stable task/run id]
- task_name: [human-readable task name]
- phase: [TRIAGE | DISCOVER | DECOMPOSE | PLAN | DESIGN | BUILD | REVIEW | DOCUMENT | COMPLETE]
- slice: [current slice id/name, next pending slice, or N/A]
- status: [not_started | in_progress | blocked | verifying | reviewing | restarting | documenting | complete]
- blockers:
  - [current blocker, or none]
- last_verification:
  - command_or_check: [command/check, or pending/N/A]
  - result: [passed | failed | skipped | not_applicable | pending]
  - evidence: [concise evidence or reason]
- next_action: [exact next action]
- recovery_pointer: [task packet, trace entry, ledger row, file section, or artifact ref]
- pivot_restart_decision_ref: [Pivot/Restart Decision ref when active, or N/A]

## Trace Ledger

[required for medium+ harness-capable work; append-only ordered execution evidence]

| Seq | Timestamp/Order | Event Type | Actor | Summary | Artifact Refs |
|-----|-----------------|------------|-------|---------|---------------|
| 1 | [timestamp or ordered marker] | [agent_event/decision/verification/plan_deviation/pivot_restart/artifact_ref/blocker/recovery] | [role/subagent/user/automation] | [event, decision, command/result, deviation, blocker, pivot/restart, or recovery] | [file/section/dispatch id/command ref] |

## Replay Packet

[required for medium+ harness-capable work before compaction, failure handoff,
phase handoff, or end-of-turn]

- pinned_context:
  - [stable requirement, constraint, approved plan/slice id, or non-goal]
- artifact_refs:
  - [task journal/context map/plan/run state/trace/validation/changed file ref]
- validation_state:
  - completed_checks: [checks already completed]
  - pending_checks: [checks still pending]
  - last_result: [latest verification/review result]
- exact_next_action: [single concrete next action after replay]
- run_state_ref: [Harness Run State section/ref]
- trace_ledger_ref: [Trace Ledger section/ref]
- recovery_pointer: [where to resume]
- pivot_restart_decision_ref: [Pivot/Restart Decision ref when active, or N/A]

## Pivot/Restart Log

[append when review/QA stagnation, repeated drift/regression, rubric/domain
pivot, Code Writer blocker, verification blocker, plan deviation, or scope
change triggers recovery]

### Pivot/Restart Decision #N

- trigger: [STAGNATION | repeated_DRIFT | repeated_REGRESSION | pivot | code_writer_blocker | verification_blocker | plan_deviation | scope_change]
- evidence:
  - source: [review score entry, QA score entry, Code Writer blocker, verification failure, trace row, or task packet]
    detail: [concise evidence]
- affected_slice_or_round: [slice id/name, review round, QA round, or phase]
- options_considered:
  - option: [reset context / dispatch debugging / dispatch explorer / dispatch architect / candidate search / replan / restart slice / restart phase / block for user / accept with limitations]
    tradeoff: [why this option helps or risks the task]
    disposition: [selected | rejected | deferred]
- selected_action: [reset_context | return_to_build | dispatch_debugging | dispatch_explorer | dispatch_architect | run_candidate_search | replan | restart_slice | restart_phase | block_for_user | accept_with_limitations]
- reapproval_required: [true when scope/files/behavior/risk/verification/acceptance changes; otherwise false]
- next_agent: [Builder/Tester | Code Writer | Explorer | Architect | Reviewer | QAEvaluator | assistant-debugging | candidate-search | user | none]
- recovery_pointer: [task packet, trace row, replay packet, plan section, or file path]
- exact_next_action: [single concrete action after the decision]

## Artifact Reference Ledger

[required for medium+ harness-capable work when artifacts pass between agents;
typed producer/consumer records, not ad hoc strings]

| Artifact ID | Artifact Type | Producer | Consumer | Location Ref | Schema or Contract | Validation Status | Summary |
|-------------|---------------|----------|----------|--------------|--------------------|-------------------|---------|
| [id] | [done_contract/harness_recipe/harness_run_state/trace_ledger/replay_packet/pivot_restart_decision/changed_files/verification_evidence/plan_deviation/task_packet/context_map/test_result/review_result/qa_evaluation_result] | [role/subagent/automation] | [role/subagent/phase] | [file/section/dispatch/command ref] | [contract/template/fields] | [pending/valid/invalid/stale/not_applicable] | [concise state] |

## QA Evaluation Log

QA Evaluation is required only when `qa_evaluation_mode=required`. It runs after
build/test evidence and Code Reviewer or Reviewer compatibility evidence.

### QA Evaluation #1

- Round: 1 of 10
- Mode: required | optional | not_required
- Done Contract: [ref or N/A with reason]
- Acceptance criteria checked: [count]
- Verification evidence checked: [commands/checks/manual/review refs]
- Code Review evidence: [Code Reviewer/Reviewer result ref]
- Domain/rubric refs: [product/UX/UI/docs/DX/domain refs, or N/A when not scoped]
- Selected domain rubrics: [ui_visual_design | ux_product_acceptance | documentation_quality | developer_experience | domain_specific_craft | N/A]
- Domain quality scores: [rubric.dimension=score/action/evidence, or N/A when not scoped]
- QA scorecard: acceptance_coverage=[score] evidence_strength=[score] domain_quality=[score] final_readiness=[score]
- Weighted: [score]
- Score progression: [round1->...]
- Pivot/Restart decision: [ref if STAGNATION, repeated DRIFT, repeated REGRESSION, or domain action pivot occurred; otherwise N/A]
- Final verdict: accepted | accepted_with_concerns | rejected | blocked
- Acceptance findings:
  - [blocker|concern|observation] [criterion] - [evidence] -> [fix/defer/open question]

[...repeat QA Evaluation until accepted, accepted_with_concerns, blocked, or max round 10 reached...]
