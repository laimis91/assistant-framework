# Plan Templates

Three tiers — match ceremony to task size (don't get fancy when N is small).

## Small Tasks — Inline Plan

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
- Behavior / acceptance criteria:
  - [binary observable behavior]
  - [binary observable behavior]
- Files:
  - Create: [exact paths or "none"]
  - Modify: [exact paths or "none"]
  - Test: [exact test paths or "none"]
- Enabling changes included:
  - [setup, contracts, wiring, or "none"]
- Depends on: [slice ids or "none"]
- TDD / RED step:
  - tdd_applies: [true/false]
  - RED command: [command or "N/A"]
  - Expected failure: [specific failing test/assertion or "N/A"]
- Implementation notes / constraints:
  - implementation_notes:
    - [existing pattern to follow, dependency rule, non-goal, or boundary]
- Verification:
  - Command: [exact command]
  - Expected success signal: [exit code 0, passing test name, output marker, etc.]
- Evidence to record:
  - [test result, eval fixture, changed file, review note, or artifact proof]
- Harness refs:
  - done_contract_ref: [Done Contract section/ref, or N/A]
  - harness_recipe_ref: [Harness Recipe section/ref, or N/A]
  - harness_run_state_ref: [Harness Run State section/ref, or N/A]
  - trace_ledger_ref: [Trace Ledger section/ref, or N/A]
  - replay_packet_ref: [Replay Packet section/ref, or N/A]
- Typed artifact refs:
  - artifact_id: [stable task-local id]
    artifact_type: [done_contract | harness_recipe | harness_run_state | trace_ledger | replay_packet | changed_files | verification_evidence | plan_deviation | task_packet | context_map | test_result | review_result | qa_evaluation_result]
    producer: [role/subagent/hook/task packet]
    consumer: [role/subagent/hook/phase]
    location_ref: [typed location/ref pointer]
    schema_or_contract: [contract/template/required fields]
    validation_status: [pending | valid | invalid | stale | not_applicable]
    summary: [concise state]
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

- slice_id:
- name:
- observable_increment:
- deliverable_type: behavior | artifact | contract | docs | eval | config | migration | refactor
- acceptance_criteria:
- files_to_create:
- files_to_modify:
- files_to_test:
- enabling_changes_included:
- depends_on:
- verification_command:
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

## Triage result
- Task type: [feature | bugfix | refactor | migration | rewrite | config | infra | security | docs | spike]
- Risk tier: [low | moderate | high | critical]
- Required gates: [common gates + task-category gate packs from references/triage-rubric.md]
- Required agents: [roles/skills selected from size, task type, and risk]
- Subagent policy state: [not_required | authorization_required | delegation_authorized | authorization_denied | subagents_unavailable | policy_disallowed]
- Subagent execution mode: [delegated | direct_fallback | not_applicable]
- Subagent authorization scope: [roles/phases/actions explicitly authorized by the user, or none]
- Search mode: [none | lightweight | candidate_search]

## Constraints & decisions (from Discovery)
- [Q&A question]: [chosen option and why]
- Assumed (not explicitly asked): [assumption and reasoning]
- Non-goals: [what's explicitly out of scope]

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
- Layer rules:
  - [e.g., Domain has no external dependencies]
  - [e.g., ViewModels don't reference Views]
- Dependency direction: [A → B → C]
- New files placement:
  - [file → layer/folder rationale]
- SOLID design notes:
  - SRP: [which classes own which responsibility — flag any class with >1 reason to change]
  - OCP: [will new variants require modifying existing classes? If yes, plan extension points]
  - DIP: [which high-level modules depend on abstractions vs concrete implementations?]

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

## Done Contract

Required for medium+ harness-capable work before Build; omit with a brief N/A
rationale for non-harness work.

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

Required for medium+ harness-capable work; omit with a brief N/A rationale for
non-harness work.

- harness_run_state_ref: [where task_id/task_name/phase/slice/status/blockers/last_verification/next_action/recovery_pointer will be maintained]
- trace_ledger_ref: [where ordered agent events, decisions, verification results, plan deviations, and artifact refs will be appended]
- replay_packet_ref: [where pinned context, artifact refs, validation state, and exact next action will be refreshed]
- corrective_action: [what to do if run-state/trace/replay evidence is missing or stale]

## Artifact Reference Ledger

Required for medium+ harness-capable work when artifacts pass between agents.
Each row is a typed producer/consumer record, not an ad hoc string reference.

| Artifact ID | Artifact Type | Producer | Consumer | Location Ref | Schema or Contract | Validation Status | Summary |
|-------------|---------------|----------|----------|--------------|--------------------|-------------------|---------|
| [id] | [done_contract/harness_recipe/harness_run_state/trace_ledger/replay_packet/changed_files/verification_evidence/plan_deviation/task_packet/context_map/test_result/review_result/qa_evaluation_result] | [role] | [role/phase] | [file/section/dispatch/command ref] | [contract/template/fields] | [pending/valid/invalid/stale/not_applicable] | [concise state] |

## Slice manifest from Decompose

Use the shared Slice Manifest structure above. Paste the approved Decompose manifest verbatim and keep `single_slice_rationale` when exactly one slice exists.

## Task packets
Use the Executable Task Packet structure above for each approved slice. Order packets by dependency, consume the slice manifest directly, and do not rediscover boundaries in Plan.

## Tests to run
- [command]: [what it validates]
```

## Large / Mega Tasks — Full Plan

Everything from Medium, plus Security and Operability sections. Use when the task touches auth, external inputs, infrastructure, or multi-module boundaries.

```markdown
## Goal
- [1-3 sentence restated requirement from Discovery]

## Triage result
- Task type: [feature | bugfix | refactor | migration | rewrite | config | infra | security | docs | spike]
- Risk tier: [low | moderate | high | critical]
- Required gates: [common gates + task-category gate packs from references/triage-rubric.md]
- Required agents: [roles/skills selected from size, task type, and risk]
- Search mode: [none | lightweight | candidate_search]

## Constraints & decisions (from Discovery)
- [Q&A question]: [chosen option and why]
- [Q&A question]: [chosen option and why]
- Assumed (not explicitly asked): [assumption and reasoning]
- Non-goals: [what's explicitly out of scope]

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
- Layer rules:
  - [e.g., Domain has no external dependencies]
  - [e.g., ViewModels don't reference Views]
- Dependency direction: [A → B → C]
- New files placement:
  - [file → layer/folder rationale]
- SOLID design notes:
  - SRP: [which classes own which responsibility — flag any class with >1 reason to change]
  - OCP: [will new variants require modifying existing classes? If yes, plan extension points]
  - LSP: [any inheritance hierarchies? Do subtypes preserve base type contracts?]
  - ISP: [any interfaces? Are they minimal or do implementers need to stub methods?]
  - DIP: [which high-level modules depend on abstractions vs concrete implementations?]

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

## Artifact Reference Ledger

Required for medium+ harness-capable work when artifacts pass between agents.
Each row is a typed producer/consumer record, not an ad hoc string reference.

| Artifact ID | Artifact Type | Producer | Consumer | Location Ref | Schema or Contract | Validation Status | Summary |
|-------------|---------------|----------|----------|--------------|--------------------|-------------------|---------|
| [id] | [done_contract/harness_recipe/harness_run_state/trace_ledger/replay_packet/changed_files/verification_evidence/plan_deviation/task_packet/context_map/test_result/review_result/qa_evaluation_result] | [role] | [role/phase] | [file/section/dispatch/command ref] | [contract/template/fields] | [pending/valid/invalid/stale/not_applicable] | [concise state] |

## Slice manifest from Decompose

Use the shared Slice Manifest structure above. Paste the approved Decompose manifest verbatim and keep `single_slice_rationale` when exactly one slice exists.

## Task packets
Use the Executable Task Packet structure above for each approved slice. Order packets by dependency, consume the Decompose slice manifest directly, and keep each slice independently verifiable before the next slice starts.

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

- Exact/pinned: [goal, acceptance criteria, safety constraints, exact errors, files in scope, validation requirements]
- Summarized: [logs, tool output, conversation history, repetitive evidence]
- Omitted/deferred: [out-of-scope files/results and why]
- Split/delegation plan: [slice/task split when material exceeds one faithful context]

## Pattern Retrieval

- Similar patterns searched: [real repo paths or search queries; no placeholders]
- Canonical pattern used: [real repo path, or N/A with no-pattern rationale]
- Counterexample/edge case checked: [real repo path, or N/A with explanation]
- No-pattern rationale: [when no local pattern exists]
