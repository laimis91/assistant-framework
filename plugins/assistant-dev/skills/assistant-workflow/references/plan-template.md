# Plan Templates

Three tiers — match ceremony to `plan_mode` and task size. `plan_mode=none`
does not load this template or create a plan artifact.

Harness details live in optional appendices. Base plans keep compact refs only:
load `references/plan-harness-appendix.md` for harness-capable work, otherwise
record `N/A: [reason]`.

## Small Tasks — Inline Plan (`plan_mode=inline`)

No separate plan document needed. Include directly in your response:

```markdown
**Goal:** [1 sentence]
**Artifact Contract:**
- Artifact type: [code | docs | report | dataset | chart | slide_deck | plan | eval | PR | config | other]
- Required files or deliverables: [exact paths or named artifact]
- Output format/schema: [format]
- Acceptance criteria: [binary checks]
- Verification command or method: [command / inspection / review]
- Expected success signal: [exact pass signal]
- Owner/consumer: [who uses it]
- Non-goals/exclusions: [what not to produce]
**Files:** [list of files to change]
**Architecture Decision Pack:** [ref, or N/A with concrete reason]
- **Pack handoff binding:** [`downstream_bound`; context/journal ref plus atomically bound task-packet and review-scope refs before Build]
- **Independent challenge evidence:** [required when Pack mode=review_intensive; challenge, dissent/validation, resolution, selected-design impact]
**Risks:** [what could go wrong]
**Tests:** [how to verify]
**SRP check:** [single responsibility confirmed / split needed]
```

## Executable Task Packet

For Medium and Large/Mega plans, write implementation work as executable task packets instead of descriptive step lists. Each packet is a self-contained brief that a Code Writer or Builder/Tester can execute without re-interpreting the plan in delegated mode, or that the main session can execute in direct fallback mode while preserving the same role evidence.

```markdown
### Task [ID]: [short name]
- name: [task packet name; must populate current_task_packet.name]
- Slice: [slice_id] [slice_name, or "N/A for small task"]
- Observable increment: [what becomes visible/verifiable after this slice]
- Deliverable type: [behavior | artifact | contract | docs | eval | config | migration | refactor]
- Requirement ids: [R# ids from the Requirement Acceptance Map]
- Architecture Decision Pack: [fresh pack ref, or N/A with concrete reason]
- QA evaluation mode: [carry triage value: not_required | optional | required]
- Harness capable: [carry triage value: true | false]
- Build execution lane: [carry triage value: inline_direct | bounded_executor | separated_workers]
- Workflow state mode: [carry triage value: inline | journal]
- Pack handoff binding: [discover_only only before Plan; otherwise downstream_bound | context/journal ref | plan/task-packet ref | review-scope ref]
- Plan-mode-none Pack binding: [before Build, atomically set downstream_bound with compact inline task-packet/execution and inline review-scope refs]
- Architecture test obligations: [when TDD applies to a Pack, carry each stable obligation_id, obligation kind, behavior, and verification into CodeWriter/BuilderTester; selected Build owner returns exact-once architecture_obligation_coverage]
- Behavior / acceptance criteria:
  - [R#] [binary observable behavior]
  - [R#] [binary observable behavior]
- Files:
  - Create: [exact paths or "none"]
  - Modify: [exact paths or "none"]
  - Test: [exact test paths or "none"]
- Enabling changes included:
  - [setup, contracts, wiring, or "none"]
- Depends on: [slice ids or "none"]
- TDD / RED step:
  - tdd_applies: [true/false]
  - TDD default: true for behavior changes, bugfixes with RED-ready evidence, and interface-affecting refactors; false only with explicit exception reason
  - RED command: [command or "N/A"]
  - Expected failure: [specific failing test/assertion or "N/A"]
  - Architecture test obligations: [N/A unless tdd_applies=true and an Architecture Decision Pack applies; otherwise stable obligation_id, Pack ref, kind, behavior, verification]
- Implementation notes / constraints:
  - implementation_notes:
    - [existing pattern to follow, dependency rule, non-goal, or boundary]
- Reuse search:
  - applicability: [applicable | not_applicable]
  - applicability_reason: [concrete reason]
  - searches: [query_or_path | scope | outcome; required when applicable]
  - candidates: [name | location | disposition: reuse | extend | intentional_duplicate | reject_coincidental | reject_independent | rationale]
  - no_candidate_reason: [required when applicable and candidates are empty]
  - decision: [reuse | extend | new | intentional_duplicate]
  - decision_rationale: [why this is the bounded existing-capability decision]
  - divergence_control: [required for intentional_duplicate]
- Verification:
  - verification_command: ["executable", "arg1", "arg2"]
  - argv rule: [one literal argument per item; execute directly without shell parsing]
  - Expected success signal: [exit code 0, passing test name, output marker, etc.]
- Evidence to record:
  - [test result, eval fixture, changed file, review note, or artifact proof]
- Loop / Experiment Routing:
  - controller_intensity: [light | standard | strict; standard keeps ordinary medium+ non-harness work out of harness/QA defaults]
  - workflow_experiment_ledger: [N/A unless explicit workflow experiment; otherwise ref]
  - progressive_activation_provenance: [on first activation atomically set positive activation_ordinal; never-activated items omit it; keep ordinals immutable and unique across retained canonical decision-map history, including activation-marked items outside current-map refs, so ascending ordinals reconstruct activated_decision_item_refs before the second activation]
  - progressive_blocked_recovery: [when progressive_discovery_state=blocked retain non-empty blocked_item_refs to canonical status=blocked items with typed recovery; readiness exhaustion uses blocker_kind=readiness_exhausted and keeps the item inactive]
  - loop_readiness_assessment: [N/A unless explicit repeat/optimization loop or second/sequential progressive decision activation; otherwise ref with progressive_sequence_readiness_state=active and progressive_artifact_retention_state=retained, stable identity/cap/history through pause/blocked/compaction/continuation/third+ activation, retry_or_empty_result_handling, tool_error_handling, low_confidence_escalation]
  - progressive_artifact_retention_state: [not_applicable | retained | terminally_archived; terminally_archived only after progressive_terminal_archival carries explicit final archival/termination evidence, binds current task identity, final decision-map ref, typed archival/termination basis, and resolvable evidence refs proving continuation and reference resolution are impossible as one atomic transition with uncertainty_shape=bounded and progressive_discovery_state=not_applicable; historical consumed and closed markers remain; Task state: completed does not qualify; terminally_archived cannot revert]
  - progressive_terminal_archival: [required when terminally_archived; typed tombstone with current_task_identity, final_progressive_decision_map_ref, final_archival_or_termination_basis, and evidence_refs; missing/dangling/mismatched evidence fails closed]
  - route-clear retired/excluded coverage: [retired_or_excluded_deferred_uncertainty_refs is ordered unique, resolves exactly once, exactly covers current-map deferred uncertainty status retired/excluded, and is traced into the consuming Requirement Acceptance Map as a non-goal or approved exclusion]
  - deferred uncertainty conversion: [each status=unlocked deferred_uncertainty records converted_decision_item_ref to an actionable canonical decision item appearing exactly once in the unlocking predecessor decision_resolution.newly_precise_item_refs]
  - route-clear decision partition: [route_clear_handoff.decisions lists every current-map resolved decision exactly once through canonical decision_resolution.decision_item_ref values; superseded/excluded decisions appear exactly once in exclusions; decisions is non-empty when any current-map decision has status=resolved, and retained historical resolutions for superseded/excluded current-map items are lineage evidence only and do not appear in decisions; decisions is empty only for a legitimate all-excluded route]
  - loop_harness_routing: [ordinary medium+ keeps harness_capable=false; loop artifacts alone do not require harness/QA artifacts]
- Harness routing: [N/A unless harness_capable=true or QA criteria independently apply; otherwise refs to appendix, Done Contract, Harness Recipe, run state, trace/replay, artifact ledger]
- Deviation / rollback rule:
  - [what to do if required files/behavior differ from plan; include rollback/revert boundary]
- Worker status / evidence:
  - Status: [pending/in_progress/done/blocked]
  - Evidence: [files changed, test result, review note, or "pending"]
```

## Slice Manifest

For Medium and Large/Mega plans, paste the approved Decompose slice manifest once and consume it directly in task packets. Do not rediscover boundaries in Plan; order packets from this manifest by dependency.

```markdown
## Slice manifest from Decompose

[paste the approved strict slice manifest verbatim; Plan consumes these slice_ids and does not rediscover boundaries]

- slice_id: [stable descriptive outcome/deliverable slug; never ordinal-only such as s1 or slice-2]
- name:
- observable_increment:
- deliverable_type: behavior | artifact | contract | docs | eval | config | migration | refactor
- requirement_ids:
- acceptance_criteria:
- files_to_create:
- files_to_modify:
- files_to_test:
- enabling_changes_included:
- depends_on:
- verification_command: ["executable", "arg1", "arg2"]
- expected_success_signal:
- evidence_to_record:
- deviation_rollback_rule:
- single_slice_rationale: [required only when exactly one slice exists]
```

## Medium Tasks — Standard Plan

Covers the essentials without Security/Operability overhead. Fill this in during Phase 3 (Plan).

```markdown
## Goal
- [1-3 sentence restated requirement from Discovery]

## Requirement Acceptance Map
- Intended outcome: [one outcome]
- Assumptions/defaults: [explicit inferred decisions]
- Open material questions: [none before approval]
- Non-goals: [exclusions]
- Entries: [requirement_id -> acceptance criterion -> verification method -> evidence pending -> manual scenario or N/A]

## Triage result
- Task type: [feature | bugfix | refactor | migration | rewrite | config | infra | security | docs | spike]
- Risk tier: [low | moderate | high | critical]
- Controller intensity: [light | standard | strict]
- Plan mode: [approval_required]
- QA evaluation mode: [not_required | optional | required]
- Harness capable: [true | false]
- Build execution lane: [inline_direct | bounded_executor | separated_workers]
- Workflow state mode: [inline | journal]
- Architecture design mode: [not_applicable | lightweight | required | review_intensive]
- Architecture trigger reasons: [concrete evidence, or N/A reason]
- Required gates: [common gates + task-category gate packs from references/triage-rubric.md]
- Required agents: [roles/skills selected from size, task type, and risk]
- Subagent policy state: [not_required | delegation_triggered | delegation_opted_out | subagents_unavailable | policy_disallowed]
- Subagent execution mode: [delegated | direct_fallback | not_applicable]
- Subagent trigger scope: [direct user | applicable AGENTS.md | active skill; covered roles/phases/actions, or none]
- Policy blocking source: [exact active rule plus confirmation that no applicable user, AGENTS, or skill exception permits delegation; required only for policy_disallowed]
- Search mode: [none | lightweight | candidate_search]

## Constraints & decisions (from Discovery)
- [Q&A question]: [chosen option and why]
- Assumed (not explicitly asked): [assumption and reasoning]
- Non-goals: [what's explicitly out of scope]
- Reuse search: [copy the CodeMapper result; not_applicable needs a concrete reason, otherwise include searches, candidates or no_candidate_reason, decision, and decision_rationale]

## Architecture Decision Pack
- Pack ref / mode: [ref] | [lightweight | required | review_intensive], or `N/A: [concrete reason]`
- Handoff binding: [discover_only: context/journal ref only; downstream_bound: context/journal, plan/task-packet, and review-scope refs atomically bound before Build]
- Freshness: [branch/HEAD or greenfield basis; source refs; invalidation conditions]
- Facts versus assumptions: [compact refs]
- Independent challenge evidence: [required for review_intensive: challenge, dissent/validation, resolution, selected-design impact]
- Design-pressure checks: [control/early exit, ownership/disposal, resource envelope, extension registration, representative path]
- Material design questions: [none before approval, or grouped question refs]
- Boundaries / ownership / lifecycle: [compact table or ref]
- Type Ledger: [semantic types, primitive exceptions with conversion points, and extension seams]
- Interface evolution: [consumer/owner, input, output/failure, compatibility/versioning/adapters]
- Quality scenarios: [attribute, workload, budget or explicit unknown, measurement, failure condition]
- Selected design / genuine alternatives: [decision and trade-offs]
- Verification / review scope: [command or method, success signal, failure condition, reviewer checks]

## Research (current state)
- Modules/subprojects: ...
- Key files/paths: ...
- Entrypoints: ...
- Configs/flags: ...
- Data models: ...
- Existing patterns: ...

## Architecture
- Current architecture: [identified or "new project"]
- Architecture for this change: [Clean/MVVM/Hexagonal/etc.]
- Layer rules: [key dependency boundaries]
- Dependency direction: [A → B → C]
- New files placement: [file → layer/folder rationale]
- SOLID notes: [SRP/OCP/DIP risks or N/A]

## Analysis
### Candidate search summary
- Candidate search summary: [N/A unless search_mode=candidate_search; otherwise selected candidate and why]
- Candidate archive: [{agent_state_dir}/candidate-search.md when local state is allowed, or inline plan section]
- Goal tree source: [acceptance criteria/slice criteria used]

### Options
1. [approach] — [tradeoff]
2. [approach] — [tradeoff]

### Decision
- Chosen: [#] because [reason]

### Risks / edge cases
- [risk]: [mitigation]

## Decomposition Plan Review

- Scope understanding: [pass/fix needed + evidence]
- Slice/subagent count: [count + sanity rationale]
- Step/cost budget: [budget or direct-fallback rationale]
- Dependency order: [summary]
- Output-plan match: [artifact/verification alignment]
- Fallback path: [subagent path or direct equivalent]
- Broad-split rejection: [required proof that layer-only, module-only, folder-only, feature-only, setup-only, contract-only, and broad component-style splits were rejected unless verified deliverable artifact slices]
- Decision: proceed | revise_decomposition | return_to_discover

## Artifact Contract

- Artifact type: code | docs | report | dataset | chart | slide_deck | plan | eval | PR | config | other
- Required files or deliverables: [exact paths or named external artifacts]
- Output format/schema: [markdown/json/yaml/csv/pdf/etc.]
- Acceptance criteria: [binary user-visible checks]
- Verification command or method: [command, inspection, manual validation, or review gate]
- Expected success signal: [exact passing output, created file, PR URL, green test, approved review]
- Owner/consumer: [user, reviewer, downstream tool, runtime]
- Non-goals/exclusions: [what must not be produced]

## Loop / Experiment Routing

Only for explicit workflow experiments, explicit repeat/optimization loops, or a
second/sequential progressive decision activation.
Ordinary medium+ tasks keep `harness_capable=false`; loop artifacts alone do not
require Done Contract, Harness Recipe, Trace Ledger, Replay Packet, Artifact
Reference Ledger, or QA evaluation.

- workflow_experiment_ledger: [N/A unless explicit workflow experiment; otherwise compact ref with hypothesis/intervention/signal/measurement/baseline/status/evidence/decision/next check]
- progressive_activation_provenance: [on first activation atomically set positive activation_ordinal; never-activated items omit it; keep ordinals immutable and unique across retained canonical decision-map history, including activation-marked items outside current-map refs and across resolved/blocked/superseded/excluded status and compaction, so ascending ordinals reconstruct activated_decision_item_refs before the second activation]
- progressive_blocked_recovery: [when progressive_discovery_state=blocked retain non-empty blocked_item_refs to canonical status=blocked items with blocker_kind/blocker_reason/unblock_condition; readiness exhaustion uses blocker_kind=readiness_exhausted and keeps the proposed item inactive]
- loop_readiness_assessment: [N/A unless explicit repeat/optimization loop or second/sequential progressive decision activation; otherwise compact ref with progressive_sequence_readiness_state=active and progressive_artifact_retention_state=retained, stable readiness identity/map/immutable cap/cumulative history; while active retain the same record through durable route-clear consumption, then set closed. After progressive_sequence_readiness_state becomes closed, retain the same record while the task remains active/resumable or compacts; only explicit final archival/termination transition to terminally_archived permits omission. Task state: completed does not qualify, and terminally_archived cannot revert. Never reopen or reset, loop type/trigger/verifier/stop/max iterations/budget/tool access/state tracking/retry_or_empty_result_handling/tool_error_handling/low_confidence_escalation/rollback/harness routing]
- progressive_artifact_retention_state: [not_applicable | retained | terminally_archived; terminally_archived only after progressive_terminal_archival carries explicit final archival/termination evidence, binds current task identity, final decision-map ref, typed archival/termination basis, and resolvable evidence refs proving continuation and reference resolution are impossible as one atomic transition with uncertainty_shape=bounded and progressive_discovery_state=not_applicable; historical consumed and closed markers remain; Task state: completed does not qualify; terminally_archived cannot revert]
- deferred uncertainty conversion: [each status=unlocked deferred_uncertainty records converted_decision_item_ref to an actionable canonical decision item appearing exactly once in the unlocking predecessor decision_resolution.newly_precise_item_refs]
- route-clear decision partition: [route_clear_handoff.decisions lists every current-map resolved decision exactly once through canonical decision_resolution.decision_item_ref values; superseded/excluded decisions appear exactly once in exclusions; decisions is non-empty when any current-map decision has status=resolved, and retained historical resolutions for superseded/excluded current-map items are lineage evidence only and do not appear in decisions; decisions is empty only for a legitimate all-excluded route]
- loop_harness_routing: [ordinary medium+ keeps harness_capable=false; loop artifacts alone do not require harness/QA artifacts]
- Progressive current map: [N/A for ordinary bounded work with progressive_route_clear_consumption_state=not_applicable and progressive_sequence_readiness_state=not_applicable, or after progressive_artifact_retention_state=terminally_archived; otherwise retain the retained canonical reference chain. The current map decision_item_refs and deferred_uncertainty_refs are non-empty, ordered unique, and each resolves exactly once to canonical typed entries; every current-map deferred uncertainty retains unlocking_decision_item_ref to a current-map predecessor; retired/excluded/history entries may remain outside current refs]

## Harness Appendix Routing

Required only for medium+ harness-capable work; otherwise use `N/A: [reason]`.
Load `references/plan-harness-appendix.md` for full harness and QA schemas.

- appendix_status: [required | N/A: reason]
- controller_intensity: [light | standard | strict + reason]
- done_contract_ref: [section/ref, or N/A: reason]
- harness_recipe_ref: [section/ref, or N/A: reason]
- harness_run_state_ref: [section/ref, or N/A: reason]
- trace_ledger_ref: [section/ref, or N/A: reason]
- replay_packet_ref: [section/ref, or N/A: reason]
- artifact_reference_ledger_ref: [section/ref, or N/A: reason]
- qa_evaluation_mode: [required | optional | not_required + reason]
- qa_trigger_reason: [QA required positive triggers: explicit QA/acceptance evaluation request, accepted Done Contract, harness-capable acceptance scope, domain-scored scope, or scoped UI/visual/product/UX/docs/DX acceptance. QA non-triggers: template labels/placeholders, generic acceptance criteria labels, optional/not_required reasons, delegation/source-changing work alone, and ordinary medium+ code-review-only/source-changing work.]

## Slice manifest from Decompose

Use the shared Slice Manifest structure above. Paste the approved Decompose manifest verbatim and keep `single_slice_rationale` when exactly one slice exists.

## Task packets
Use the Executable Task Packet structure above for each approved slice. Order packets by dependency, consume the slice manifest directly, and do not rediscover boundaries in Plan.

## Existing-system feature preparation (when `feature_preparation_scope=existing_system`)
- Feature-preparation evidence ref: [stable `feature_preparation_evidence.ref`]
- Behavior/work classification: [each scoped item id + behavior_status + work_status]
- Execution status: [`Execution not started` for prepare-only | evidence completed before Build for end-to-end | approved evidence ref resolved for implement-only]
- Plan/readiness result: [implementation steps or the exact evidence gap/conflict]
- Product questions: [only rows admitted by the canonical evidence matrix]

For `prepare_only`, return `feature_preparation_result` instead of an execution
handoff: scope, evidence ref when applicable, evidence gaps, open decisions,
implementation implications, recommended next step, and `execution_status=not_started`.
For medium+ preparation, an optional readiness plan may be recorded without
waiting for implementation approval; name that approval or delegation as the
next implementation state rather than treating it as a gate on preparation.

## Tests to run
- [command]: [what it validates]
```

## Large / Mega Tasks — Full Plan

Everything from Medium, plus Security and Operability sections. Use when the task touches auth, external inputs, infrastructure, or multi-module boundaries.

```markdown
Start with the Medium template, then add the sections below.

## Security considerations
- Data classification: [does this touch PII, auth, payments, external inputs?]
- Auth changes: [any changes to authentication or authorization?]
- Input validation: [new user inputs? how validated?]
- Secrets handling: [new secrets? where stored? how injected?]
- Threat model needed: [yes/no — yes if auth, PII, payments, or external inputs]
- Dependencies: [new packages? known vulnerabilities?]

## Operability
- SLO impact: [could this change affect service reliability?]
- Monitoring: [new metrics, dashboards, or alerts needed?]
- Instrumentation: [logging, tracing, telemetry for new code paths?]
- Rollback strategy: [how to undo this change safely?]
  - Feature flag: [yes/no]
  - DB migration reversible: [yes/no/N/A]
  - Revert commit sufficient: [yes/no]
- Runbook updates: [new on-call procedures needed?]

## Large/Mega addenda
- Triage result: include `Subagent policy state`, `Subagent execution mode`, `Subagent trigger scope`, and `Search mode` as in Medium.
- Architecture: include LSP and ISP in addition to SRP/OCP/DIP.
- Decomposition Plan Review: reuse Medium fields and keep `- Broad-split rejection:` proof for large/mega slice plans.
- Harness Appendix Routing: reuse the Medium compact refs and load `references/plan-harness-appendix.md` only when harness-capable.

## Tests to run
- [command]: [what it validates]
```

## Which tier to use

| Task Size | Template | When Security/Operability sections are needed anyway |
|-----------|----------|------------------------------------------------------|
| Small | Inline | Never — if it needs these, re-triage as Medium |
| Medium | Standard | Promote to Full if the task touches auth, PII, payments, or infra |
| Large | Full | Always |
| Mega | Full (per slice) | Always |


## Context Budget

- Exact/pinned: [goal, criteria, constraints, errors, scoped files, validation]
- Summarized: [logs, tool output, history, repetitive evidence]
- Omitted/deferred: [out-of-scope files/results and why]
- Split/delegation plan: [slice/task split when material exceeds one faithful context]

## Pattern Retrieval

- Similar patterns searched: [real repo paths or search queries; no placeholders]
- Canonical pattern used: [real repo path, or N/A with no-pattern rationale]
- Counterexample/edge case checked: [real repo path, or N/A with explanation]
- No-pattern rationale: [when no local pattern exists]
