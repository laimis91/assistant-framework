# Plan Harness Appendix

Load this appendix only for medium+ harness-capable work: explicit harness work,
long-running or trace/replay-ready multi-slice work, high-risk harness work,
accepted Done Contract/Harness Recipe work, domain-scored work, or
scoped UI/visual/product/UX/docs/DX acceptance. For ordinary medium+ source
changes, keep the base plan's harness fields as `N/A: [reason]`.

## Task Packet Harness Fields

Use these fields inside an executable task packet only when the task is
harness-capable.

```markdown
- Harness refs:
  - done_contract_ref: [Done Contract section/ref, or N/A: reason]
  - harness_recipe_ref: [Harness Recipe section/ref, or N/A: reason]
  - harness_run_state_ref: [Harness Run State section/ref, or N/A: reason]
  - trace_ledger_ref: [Trace Ledger section/ref, or N/A: reason]
  - replay_packet_ref: [Replay Packet section/ref, or N/A: reason]
  - artifact_reference_ledger_ref: [Artifact Reference Ledger section/ref, or N/A: reason]
- Typed artifact refs:
  - artifact_id: [stable task-local id]
    artifact_type: [done_contract | harness_recipe | harness_run_state | trace_ledger | replay_packet | pivot_restart_decision | changed_files | verification_evidence | plan_deviation | task_packet | context_map | test_result | review_result | qa_evaluation_result]
    producer: [role/subagent/hook/task packet]
    consumer: [role/subagent/hook/phase]
    location_ref: [typed location/ref pointer]
    schema_or_contract: [contract/template/required fields]
    validation_status: [pending | valid | invalid | stale | not_applicable]
    summary: [concise state]
```

## Done Contract

Required for medium+ harness-capable work before Build.

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

Required for medium+ harness-capable work before Build; selected from
task/model/risk/context profile per `references/harness-controller.md`.

- task_profile: [task type, size, slice count, TDD/debugging applicability]
- model_profile: [agent/model constraints, delegation mode, tool limits]
- risk_profile: [risk tier, safety gates, review depth, rollback needs]
- context_profile: [exact/summarized/omitted context and trace/replay needs]
- selected_recipe: [concise recipe label]
- recipe_rationale: [why this profile selects the recipe]
- required_artifacts: [Done Contract, task packet, verification, trace/handoff artifacts]
- corrective_action: [what to do if missing or stale]

## Runtime Harness Artifacts

Required for medium+ harness-capable work when the recipe needs recovery,
handoff, or trace/replay evidence.

- harness_run_state_ref: [where task_id/task_name/phase/slice/status/blockers/last_verification/next_action/recovery_pointer will be maintained]
- trace_ledger_ref: [where ordered agent events, decisions, verification results, plan deviations, and artifact refs will be appended]
- replay_packet_ref: [where pinned context, artifact refs, validation state, and exact next action will be refreshed]
- corrective_action: [what to do if run-state/trace/replay evidence is missing or stale]

## Artifact Reference Ledger

Required for medium+ harness-capable work when artifacts pass between agents.
Each row is a typed producer/consumer record, not an ad hoc string reference.

| Artifact ID | Artifact Type | Producer | Consumer | Location Ref | Schema or Contract | Validation Status | Summary |
|-------------|---------------|----------|----------|--------------|--------------------|-------------------|---------|
| [id] | [done_contract/harness_recipe/harness_run_state/trace_ledger/replay_packet/pivot_restart_decision/changed_files/verification_evidence/plan_deviation/task_packet/context_map/test_result/review_result/qa_evaluation_result] | [role] | [role/phase] | [file/section/dispatch/command ref] | [contract/template/fields] | [pending/valid/invalid/stale/not_applicable] | [concise state] |

## QA Routing

QA Evaluator remains separate from Code Reviewer. Use this routing only when
`qa_evaluation_mode=required`: explicit QA/acceptance evaluation,
harness-capable acceptance scope, accepted Done Contract, domain-scored work, or
scoped UI/visual/product/UX/docs/DX acceptance.

QA required positive triggers: explicit QA/acceptance evaluation request, accepted Done Contract, harness-capable acceptance scope, domain-scored scope, or scoped UI/visual/product/UX/docs/DX acceptance.
QA non-triggers: template labels/placeholders, generic acceptance criteria labels, optional/not_required reasons, delegation/source-changing work alone, and ordinary medium+ code-review-only/source-changing work.

- qa_evaluation_mode: [required | optional | not_required]
- qa_trigger_reason: [explicit QA request, accepted Done Contract, harness acceptance scope, domain-scored, scoped UI/visual/product/UX/docs/DX acceptance, or N/A: reason]
- code_review_result_ref: [Code Reviewer/Reviewer compatibility result ref]
- qa_evaluation_result_ref: [QA Evaluator result ref, or N/A: reason]
- domain_context_ref: [domain/rubric context ref, or N/A: reason]
