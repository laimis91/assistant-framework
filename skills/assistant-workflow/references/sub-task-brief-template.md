# Strict Slice Brief Template

Use this template when decomposing mega tasks into strict slice packets. Each approved slice gets its own brief that can be pasted into a new conversation.

## Decomposition rules

- Default to one coherent packet; extra packets require execution purpose, independent of size
- Do not split by layer, module, folder, broad feature bucket, setup step, or broad component unless that split is itself a verified deliverable artifact slice
- Contract-only work is valid only when it is the verified deliverable artifact slice
- Dependent slices start only after prerequisite slices are VERIFIED
- Source-changing packets in a shared or unknown workspace run sequentially, even when ownership does not overlap. Parallel source-changing packets require the runtime explicitly proves isolated workspaces; parallel read-only analysis remains allowed.
- UI slices include a Design step, backend slices skip it
- Slice packets add code comments but do NOT update README, CHANGELOG, or architecture docs

## Brief template

````markdown
## Slice Brief: [name]

### Agent
Agent: [Claude or Codex intelligent-writer | Claude or Codex mechanical-writer | explicit deprecated code-writer compatibility | Gemini native/default | architect | code-reviewer | qa-evaluator | reviewer | explorer | builder-tester | code-mapper]
Role: [Implementer | Architect | Code Reviewer | QA Evaluator | Reviewer compatibility | Explorer]

### Context
Project: [name]
Parent task: [one-sentence description of the mega task]
This is slice [N] of [total]. Other slice packets are handling: [list].
Execution intent: [prepare_only | implement_only | end_to_end]
Feature-preparation scope: [not_applicable | existing_system]
Approved preparation result: [for implement_only, copy the complete typed approved_feature_preparation_result unchanged, including optional readiness/future obligations; otherwise N/A]

### Strict slice packet (execution contract)
This brief is a deep current_task_packet projection of the authoritative packet; it is a projection of the exact approved canonical packet; it cannot redefine the stored Plan. Supporting context below cannot satisfy or override these fields. If any required field is missing, return `NEEDS_CONTEXT` instead of executing from loose Goal/Scope prose.

- packet_id: [exact canonical implementation_steps packet_id]
- approved_plan_identity: [current task/plan/approval/definition identity]
- verification_decision_ref: [stable ref and SHA-256 of full unchanged specialist decision]
- name: [canonical packet name]
- observable_increment: [what becomes visible/verifiable after this slice]
- deliverable_type: behavior | artifact | contract | docs | eval | config | migration | refactor
- files_to_create:
  - [exact path, or "none"]
- files_to_modify:
  - [exact path, or "none"]
- files_to_test:
  - [exact test path or verification target, or "none with reason"]
- enabling_changes_included:
  - [setup, contracts, wiring, config, or "none"]
- depends_on:
  - [slice id, or "none"]
- execution_intent: [implement_only | end_to_end]
- feature_preparation_scope: [not_applicable | existing_system]
- approved_feature_preparation_result: [required exact complete typed approved_feature_preparation_result unchanged when execution_intent=implement_only; otherwise N/A]
- feature_preparation_evidence_ref: [required unchanged evidence artifact ref when feature_preparation_scope=existing_system; otherwise not_applicable]
- feature_preparation_harness_obligation: [required exact approved object when the preparation result contains future_harness_obligation; include requested_scope, evidence_basis, execution_prerequisite, and exactly one source binding: source_feature_preparation_evidence_ref for existing_system or source_preparation_basis=not_applicable for not_applicable; otherwise not_applicable]
- feature_preparation_qa_acceptance_obligation: [required exact approved object when the preparation result contains future_qa_acceptance_obligation; include requested_scope, execution_prerequisite, and exactly one source binding: source_feature_preparation_evidence_ref for existing_system or source_preparation_basis=not_applicable for not_applicable; otherwise not_applicable]
- writer_selection: [new Claude or Codex: Orchestrator selects agent=intelligent-writer by default or mechanical-writer only with rationale and current substantiated recipe_or_example_ref, resolved_decisions_ref, scope_and_dependencies_ref, correctness_expectations_ref covering BOTH tests and implementation; legacy packets may omit with intelligent compatibility semantics; Gemini keeps native/default fallback; packet wins and inline conflict blocks]
- worker_stage: [test_authoring | production | refactor; the SAME selected writer owns selected tests and implementation]
- build_execution_lane: [bounded_executor | separated_workers; direct fallback preserves its selected lane and evidence]
- verification_decision: [canonical assistant-verification/contracts/output.yaml#verification_decision object, unchanged; preserve selected scope, CheckSpec entries, exclusions, rationales, and TddChoice]
- evidence_assessment: [current canonical assistant-verification/contracts/output.yaml#evidence_assessment object; reassess from actual selected-check results before Review]
- selected_check_ids: [due CheckSpec IDs assigned to this packet]
- binding_obligation_refs: [exact applicable due tuples `{kind,value,source_ref}`]
- tdd_applies: [true only when selected_check_ids intersects verification_decision.tdd_choice.applicable_check_ids]
- red_check_id: [when tdd_applies=true, the sole due selected/applicable CheckSpec ID]
- red_command: [when tdd_applies=true, that CheckSpec exact literal command.argv]
- red_cwd: [when tdd_applies=true, that CheckSpec exact command.cwd]
- expected_red_failure: [when tdd_applies=true, that CheckSpec exact meaningful_failure]
- red_evidence: [incoming exact typed seven-field independent RED only for separated_workers production; initial bounded_executor may have none]
- tdd_cycle_log_ref: [preserve the same canonical ref once RED begins; initial bounded dispatch may have no started cycle]
- acceptance_criteria:
  - [ ] [binary pass/fail criterion]
- selected_check_procedure: [for each CheckSpec, exact argv and cwd if command-based; otherwise concrete procedure and observable result; do not invent a command]
- expected_success_signal: [specific passing output, file, or review signal]
- evidence_to_record:
  - [selected-check result, eval fixture, changed file, review note, or artifact proof; RED only when tdd_applies=true]
- deviation_rollback_rule: [what to do if required files/behavior differ from this packet]

### Supporting context (not the execution contract)
- Execution intent, feature-preparation scope, and approved preparation result here are summaries only; the strict slice packet fields above are authoritative.
- Parent goal: [one-sentence description of the mega task]
- Adjacent slices: [what other slice packets are handling]
- Relevant files/modules: [context only; strict files_to_* fields above control execution]
- Architecture notes: [rules from the parent plan]

### Prerequisite slice outputs (already verified)
[Paste the interfaces, DTOs, schemas, generated artifacts, or config this slice must implement or consume.
Include the actual code/signatures or artifact paths, not just names.]

### Constraints
- Must not modify: [files owned by other slice packets]
- Must implement: [interface/contract/artifact from prerequisite slices]
- Must follow the strict slice packet; do not use supporting context as permission to expand scope
- Naming conventions: [from project]

### What to do
Read configured project-local memory/context (for example `{agent_state_dir}/memory.md`, or another documented equivalent) when available and policy-allowed before starting.
Run: Plan → [Design →] Build.
Implement only the strict slice packet fields above.
Follow project conventions.
Add code comments where intent isn't obvious.
Do NOT update README, CHANGELOG, or architecture docs —
that happens in the final Document phase after integration.

### Completion status

When the slice is complete, report status using one of these values:

| Status | Meaning | What happens next |
|---|---|---|
| `DONE` | Assigned stage met its criteria; final slice acceptance also requires complete current lane verification | Proceed only to the next authorized stage; integration follows VERIFIED |
| `DONE_WITH_CONCERNS` | Criteria met but there are trade-offs or risks worth noting | Orchestrator reviews concerns before integration |
| `NEEDS_CONTEXT` | Blocked by missing information not in the brief | Orchestrator provides context or adjusts the brief |
| `BLOCKED` | Cannot proceed — dependency issue, tooling failure, legacy blocker, or design conflict | Orchestrator classifies recovery and unblocks |
| `DEVIATED` | Work cannot follow the strict slice packet exactly | Orchestrator applies the deviation rollback rule and reapproval when scope/files/behavior/risk changes |
| `FAILED_VERIFICATION` | An ordinary due required CheckSpec failed after execution; retain its per-check failure evidence and any real outputs. This takes precedence over completion and deviation statuses. The exact matching authorizing RED in `verification_stage=pre_production_red` is stage evidence, not an ordinary verification failure. | Orchestrator reviews the failure evidence before recovery |

For active `separated_workers` TDD, preserve one selected writer across all writer stages.
When selected tests need creation or repair, the SAME selected writer first completes `worker_stage=test_authoring` with tests/fixtures/snapshots/helpers/test-build configuration only and no incoming RED.
Builder/Tester then returns `verification_stage=pre_production_red` from the already authored selected test, preserving exact typed failed RED and actual failed counts. The SAME writer implements in `worker_stage=production` only after current matching meaningful RED; Builder/Tester runs GREEN. Only after current passing GREEN does that SAME writer assess/refactor in `worker_stage=refactor`, followed by distinct Builder/Tester REFACTOR verification. A matching RED or first passing GREEN may finish its assigned stage with aggregate `partial` and explicit pending rows. Stage-only DONE never completes Build or permits Review.

For active separated_workers reuse: Reused selected tests proceed directly to independent RED without a new authoring stage.
For active TDD, initial `bounded_executor` dispatch carries the exact planned RED tuple without observed RED or a started cycle; that SAME executor authors/runs RED and records meaningful current RED with the canonical cycle ref before its FIRST production edit, then records GREEN, a post-GREEN refactor assessment, and a distinct REFACTOR invocation. Bounded/direct lanes preserve their canonical ownership and phase order without forced separated dispatches. Inactive TDD uses writer-owned selected tests and code, then the selected lane verification, without fabricated RED.

Builder/Tester is execution-only: it runs selected checks, diagnoses and returns evidence, and may write only designated generated outputs/evidence logs. The selected writer owns all authored tests, fixtures, snapshots, helpers, build configuration and production repairs.
Prohibited authored mutations are `DEVIATED` with actual changes retained; an ordinary due failed check retains `FAILED_VERIFICATION` precedence. Keep every worker actual `changed_files` and legacy `files_changed` across failures and retries. Union actual mutations into final changed files and Review scope with their true authorship; do not suppress, silently restore, or normalize prohibited verifier changes as approved writer-authored tests.

An unattempted `DEVIATED` return may omit `changed_files`, `files_changed`, `artifact_refs`, and `validation_results`. Do not invent these outputs; retain concrete evidence of the actual deviation.

Unexpected blockers must be classified. Use `blocker_type` values:
`legacy_code_bug`, `broken_baseline`, `hidden_dependency`, `missing_contract`,
`stale_plan`, `scope_conflict`, `tool_environment`, `permission_policy`,
`tdd_red_missing`, or `other`. Do not widen scope, patch around legacy blockers
blindly, or invent a new plan. Return evidence so the orchestrator can route to
debugging, explorer, architect, candidate search, replan, or restart.

**Report format:**
```text
## Slice Status: [DONE | DONE_WITH_CONCERNS | NEEDS_CONTEXT | BLOCKED | DEVIATED | FAILED_VERIFICATION]

### Summary
[1-3 sentences: what was accomplished]

### Concerns (if DONE_WITH_CONCERNS)
- [trade-off or risk worth noting]

### Blocker (if NEEDS_CONTEXT or BLOCKED)
- blocker_type: [legacy_code_bug | broken_baseline | hidden_dependency | missing_contract | stale_plan | scope_conflict | tool_environment | permission_policy | tdd_red_missing | other]
- blocker_evidence: [file paths, missing fields, baseline failure, tool/environment symptom, or scope conflict]
- What's needed: [specific missing information or resolution]

### Changes made
- [file]: [what changed]

### Slice evidence
- packet_id: [id]
- worker_stage: [test_authoring | production | refactor for the materialized writer only]
- verification_stage: [pre_production_red | final_verification for Builder only]
- writer_selection: [carried selection and actual runtime identity]
- build_execution_lane: [selected lane]
- tdd_cycle_log_ref: [same actual ref once RED starts; otherwise not_started]
- verification_decision: [unchanged canonical decision ref]
- selected_check: [CheckSpec id and method]
- command_or_procedure: [exact argv/cwd when command-based; otherwise concrete CheckSpec procedure]
- expected_success_signal: [observable check result]
- result: [pass/fail/blocker]
- evidence_recorded: [evidence from evidence_to_record]

### Deviation (if DEVIATED)
- deviation_rollback_rule applied: [yes/no + details]
```
````

## Execution strategies

**Parallel sessions (multiple conversations):**
Use for read-only analysis. Source-changing packets may run in parallel only when the runtime explicitly proves isolated workspaces; otherwise sequence source-changing packets in the shared or unknown workspace.

**Sequential sessions:**
Best when slices depend on each other. Complete one, carry verified output to next.

**Native subagents:**
Each agent receives the packet as its task context. Keep source-changing packets
sequential in a shared or unknown workspace. Dispatch independent source-changing
slices in parallel only when the runtime explicitly proves isolated workspaces;
keep dependent packets sequenced by `depends_on`.

## Decomposition rules

**Smallest iterable slice:** Each slice must deliver observable behavior, artifact output, contract surface, docs, eval coverage, config, migration, or refactor evidence that can be verified before a dependent slice starts.

**Invalid live splits:** Broad feature-only splits are invalid live decomposition output. Do not split by architectural layer, module, folder, feature bucket, broad component, standalone contract setup, or standalone setup work as the execution pattern. Contract-only/setup-only work is valid only when it is the deliverable artifact slice with acceptance criteria and verification evidence.

**Dependency handling:** Put enabling contracts, config, wiring, and setup inside the first slice that needs them unless they are themselves the verified deliverable.

## Integration phase prompt

```
All slice packets are verified. Now integrate:
1. Integrate the completed slice changes and resolve conflicts
2. Confirm verified prerequisite slice outputs are present and consumed
3. Run selected integration checks and binding project checks over the integrated scope
4. Run each due integrated selected/binding check irrespective of packet count
5. Run a broader suite only when it is selected or binding
6. Fix integration mismatches and request fresh review

After integration, run selected checks and binding project checks over the completed scope before fresh Review; do not add an unselected full suite. Integrated selected and binding checks remain due for one or multiple packets before fresh independent Review; packet-local evidence cannot waive them.

Verified slices completed:
- [name]: [what was built and verified]
- [name]: [what was built and verified]

Verified prerequisite slice outputs: [list]
```

## When decomposition goes wrong

| Problem | Sign | Fix |
|---|---|---|
| Too coupled | Every slice needs every other | Redraw boundaries |
| Contracts too vague | Lots of integration mismatches | Define as actual code signatures |
| Too small | Brief overhead exceeds the work | Merge slices |
| Too many | Coordination overhead kills gains | Merge into fewer smallest iterable slices |
| Missing slice | Integration reveals unowned gap | Add a slice or assign to integration |
| Context lost | New session misses conventions | Add project rules to each brief |
| Merge conflicts | Overlapping file modifications | Tighten scope around slice boundaries |
