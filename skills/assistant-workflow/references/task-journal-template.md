# Task Journal Template

Write to `{agent_state_dir}/task.md` in the project root when a local state directory is configured and policy allows. If none is safe, keep the same content in the response/plan packet. This framework-owned ignored artifact is a freshness-checked persisted claim that survives compression/continuation when reconciled, and may be updated by the orchestrator. Before using it, load `references/task-state-reconciliation.md` and compare it with the newest user request and current repository evidence.

## When to create
- When `workflow_state_mode=journal`: during Discover before the first wait,
  delegation handoff, cross-session/compaction boundary, or strict/harness/QA gate
- Clarification waits use journal mode when local state is available and allowed;
  otherwise carry the same state inline before waiting
- Medium+ size alone does not require a task journal; `workflow_state_mode=inline`
  keeps carried Discover scope/criteria, any applicable plan, and evidence in
  the active packet

## When to update
- When deterministic safe defaults are applied, or clarification questions are asked/answered (including compatibility `defaults` acceptance)
- After each Build step: Progress, Artifact Registry, Milestones
- After key decisions, new user constraints, review passes, verification summary, or user review feedback
- After harness-capable events, Pivot/Restart Decisions, typed artifact refs, or QA results when applicable

## Template

```markdown
## Task: [1-sentence description]
Created: [stable task identity, e.g. ISO timestamp created once]
Status: DISCOVERING | DECOMPOSING | PLANNING | BUILDING [step N/M] | REVIEWING | DOCUMENTING | DONE
Task state: active | stale | superseded | completed
Repository root: [absolute or stable workspace root, or unavailable with reason]
Recorded branch: [branch or N/A]
Recorded baseline / HEAD: [commit ids or N/A]
Latest user-goal reference: [latest request/correction identity]
Last reconciled: [time/result/reason/evidence]
Last verified milestone: [milestone plus evidence ref, or none]
Triaged as: [small | medium | large | mega]
Task type: [feature | bugfix | refactor | migration | rewrite | config | infra | security | docs | spike]
Risk tier: [low | moderate | high | critical]
Controller intensity: [light | standard | strict]
Plan mode: [none | inline | approval_required]
Architecture design mode: [not_applicable | lightweight | required | review_intensive]
Architecture Decision Pack ref: [ref, or N/A with concrete reason]
Slice promotion mode: [local | review_gated]
Slice topology: target_branch=[ref] | task_branch=[feature/<task>] | slice_branch format=[slice/<task>/<slice-id>]
Slice review evidence: [N/A | REVIEW_PENDING/REVIEW_APPROVED/REVIEW_REJECTED/REVIEW_STALE plus evidence refs]
Build execution lane: [inline_direct | bounded_executor | separated_workers]
Workflow state mode: [inline | journal]
Uncertainty shape: [bounded | progressive]
Progressive discovery state: [not_applicable | mapping | resolving | route_clear | blocked]
Decision map ref: [N/A for bounded work | compact journal/packet ref]
Manual verification mode: [not_required | optional | required]
Clarification status: [ready | needs_clarification]
Clarification defaults applied: [true | false]
Clarification defaults:
- Topic: [implementation-shaping topic]
  Value: [automatically selected value]
  Source: [user instruction, repository evidence, policy, or stable convention]
  Rationale: [why safe/reversible and not scope-changing]
Clarification confidence: [low | medium | high]
Clarification questions asked: [0+]
Clarification admissibility: [satisfied | needs_clarification | not_applicable]
Unresolved clarification topics:
- [none, or one short topic per line]
Required gates:
- [common gate or task-category gate from references/triage-rubric.md]
Required agents:
- [workflow role or skill required by size/risk/type]
Subagent policy state: [not_required | delegation_triggered | delegation_opted_out | subagents_unavailable | policy_disallowed]
Subagent execution mode: [delegated | direct_fallback | not_applicable]
Subagent trigger scope:
- [direct user | applicable AGENTS.md | active skill; covered roles/phases/actions, or none]
Policy blocking source: [exact active rule plus confirmation that no applicable user, AGENTS, or skill exception permits delegation; N/A unless policy_disallowed]
Candidate scope scan:
- Likely touched paths: [exact paths, directories, modules, or unknown]
- Symbols or terms searched: [search terms, commands, or none with reason]
- Adjacent surfaces: [tests/docs/contracts/config/mirrors/runtime surfaces to inspect]
- Confidence: [low | medium | high]
- Unknowns: [none, or one short scope/risk unknown per line]
Loop / Experiment Routing:
- workflow_experiment_ledger: [N/A unless explicit workflow experiment; otherwise compact ref with id/hypothesis/intervention/signal/measurement/baseline/status/evidence/decision/next_check]
- Progressive activation provenance: [on first activation set positive activation_ordinal atomically on the canonical decision item; never-activated items omit it; keep ordinals immutable and unique across retained canonical decision-map history, including activation-marked items outside current-map refs, so ascending ordinals reconstruct activated_decision_item_refs before the second activation]
- Progressive blocked recovery: [when progressive_discovery_state=blocked retain non-empty blocked_item_refs resolving to canonical status=blocked items with blocker_kind/blocker_reason/unblock_condition; readiness exhaustion keeps the proposed item inactive with blocker_kind=readiness_exhausted]
- loop_readiness_assessment: [N/A unless explicit repeat or optimization loop or second/sequential progressive decision activation; for loop_type=progressive_decision_sequence record progressive_sequence_readiness_state=active and progressive_artifact_retention_state=retained atomically with readiness_assessment_id/progressive_decision_map_ref/immutable max_iterations/cumulative_activation_count/ordered unique append-only activated_decision_item_refs/ordered unique resolved_decision_item_refs with canonical decision_resolution linkage; while active retain the same record through durable route-clear consumption, then set closed. After progressive_sequence_readiness_state becomes closed, retain the same record while the task remains active/resumable or compacts; only explicit final archival/termination transition to terminally_archived permits omission. Task state: completed does not qualify, and terminally_archived cannot revert. Never reopen or reset, plus trigger/verifier/stop/budget/tool_access/state_tracking/retry_or_empty_result_handling/tool_error_handling/low_confidence_escalation/rollback/harness_routing/evidence]
- loop_harness_routing: [ordinary medium+ keeps harness_capable=false; loop artifacts alone do not require Done Contract, Harness Recipe, Trace Ledger, Replay Packet, Artifact Reference Ledger, or QA evaluation; appendix only when harness_capable=true or QA criteria independently apply]
- Progressive current map: [N/A for ordinary bounded work with progressive_route_clear_consumption_state=not_applicable and progressive_sequence_readiness_state=not_applicable, or after progressive_artifact_retention_state=terminally_archived; otherwise retain the retained canonical reference chain. The current map decision_item_refs and deferred_uncertainty_refs are non-empty, ordered unique, and each resolves exactly once to canonical typed entries; every current-map deferred uncertainty retains unlocking_decision_item_ref to a current-map predecessor; retired/excluded/history entries may remain outside current refs]
Plan approval: [N/A for none/inline | yes/no + date for approval_required]

## Agent Dispatch Log
[subagent evidence required by completion gates]
- Required roles: bounded executor during ordinary medium Build; Code Writer + Builder/Tester during separated Build; Code Reviewer during Review for both standard/strict lanes; QA Evaluator when required; Code Mapper/Explorer/Architect by size/risk; Reviewer for legacy compatibility.
- Build execution lane: [inline_direct | bounded_executor | separated_workers]
- Execution mode: delegated | direct_fallback | not_applicable
- Native dispatch evidence: delegated roles reference the agent id, task name, thread, or tool result exposed by the runtime and bind it to this journal's `Created:` identity.
- Direct fallback reason: [delegation_opted_out | subagents_unavailable | policy_disallowed | N/A]
- Policy blocking source: [exact active rule plus no-applicable-exception confirmation; required when Direct fallback reason is policy_disallowed]
- Evidence shorthand: delegated refs | role-equivalent direct evidence | N/A only when role not required.
- Code Mapper dispatch/result/direct evidence: [delegated refs | direct evidence | N/A]
- Explorer dispatch/result/direct evidence: [delegated refs | direct evidence | N/A]
- Architect dispatch/result/direct evidence: [delegated refs | direct evidence | N/A]
- Code Writer dispatch/result/direct evidence: [delegated refs | direct evidence | N/A]
- Builder/Tester dispatch/result/direct evidence: [delegated refs | direct evidence | N/A when bounded_executor]
- Code Reviewer dispatch/result/direct evidence: [delegated refs | Code Reviewer direct evidence | Reviewer legacy compatibility | N/A]
- Reviewer dispatch/result/direct evidence: [compatibility refs/direct evidence when used | N/A]
- QA Evaluator dispatch/result/direct evidence: [delegated QA refs | direct evidence | N/A when not required]
- Per-slice Build dispatch evidence: [slice_id -> bounded executor ref, or Code Writer + Builder/Tester refs for separated_workers]
- Review-owned independent evidence: [Code Reviewer dispatch/result or fresh direct-fallback ref, created after Build]

## Constraints
- [user-stated boundaries, e.g. "Do not modify ProjectA"]
- [technical constraints, e.g. "Must stay on .NET 8"]
- [scope limits, e.g. "Backend only, no UI changes"]

## Plan
[paste approved plan verbatim — include slice manifest for medium+ tasks, plus task packets with slice_id and file paths]

## Requirement Acceptance Map
[paste or reference the canonical map from `references/requirement-acceptance-map.md` for medium+ work or retained route-clear consumption; every accepted requirement id must end passed or approved_exclusion. Requirement Acceptance Map is not required while progressive_route_clear_consumption_state=pending; prepare it from the pending handoff. Requirement Acceptance Map is required when progressive_route_clear_consumption_state=consumed and progressive_artifact_retention_state=retained; medium+ keeps the map after terminal archival]
- source_route_clear_handoff_ref: [N/A unless the map consumes progressive route clearance while progressive_artifact_retention_state=retained; otherwise resolves to the source route_clear_handoff after incorporating its decisions/constraints/exclusions/acceptance seed, with the handoff's consumed_by_requirement_acceptance_map_ref resolving back to this consuming map; terminally_archived permits omission]

## Architecture Decision Pack
[N/A only when architecture_design_mode=not_applicable with a concrete reason. Otherwise retain a typed reference, not a duplicate narrative.]
- Pack id / mode: [ref/id | lightweight | required | review_intensive]
- Freshness: [branch/HEAD or greenfield basis, source refs, invalidated_by]
- Boundary / design-pressure / Type Ledger / quality scenario refs: [compact refs]
- Material questions: [none before Plan, or grouped refs]
- Plan/task packet/review refs: [typed locations]

## Progressive Discovery
[N/A only for ordinary bounded work with both durable markers and progressive_artifact_retention_state not_applicable, or after typed terminal archival. Keep compact refs for the retained canonical reference chain here or in the equivalent carried state; do not duplicate full schemas.]
- progressive_route_clear_consumption_state: [not_applicable | pending | consumed; pending mirrors route_clear_handoff, consumed remains after bounded/not_applicable only after reciprocal map consumption]
- progressive_sequence_readiness_state: [not_applicable | active | closed; active retains the one progressive decision-map readiness record across pause/blocked/compaction/continuation and third+ activation; closed only after durable route-clear consumption or explicit task termination/final archival and cannot reopen/reset]
- progressive_artifact_retention_state: [not_applicable | retained | terminally_archived; retained while durable progressive references remain resumable; terminally_archived only after explicit final archival/termination evidence proves continuation and reference resolution are impossible as one atomic transition with uncertainty_shape=bounded and progressive_discovery_state=not_applicable; historical consumed and closed markers remain; Task state: completed does not qualify; terminally_archived cannot revert and is invalid while route consumption is pending or readiness is active]
- Decision map ref: [journal/packet ref; retain while progressive_artifact_retention_state=retained and either durable marker is pending/consumed or active/closed, so route_clear_handoff.decision_map_ref and loop_readiness_assessment refs resolve]
- Decision items ref: [journal/packet ref; retain every map-referenced canonical decision_item plus any activation_ordinal history entry needed before the second activation/readiness record]
- Deferred uncertainty ref: [journal/packet ref; retain every map-referenced canonical deferred_uncertainty with unlock_condition and unlocking_decision_item_ref; each status=unlocked entry records converted_decision_item_ref to the actionable canonical item listed exactly once in its predecessor resolution's newly_precise_item_refs; every current-map retired/excluded entry must retain its exact canonical predecessor resolution when that current predecessor is resolved, superseded, or excluded, preserving a concrete all-excluded route]
- Decision frontier ref: [journal/packet ref only for live progressive state; when progressive_discovery_state=blocked it retains non-empty blocked_item_refs with typed recovery, including blocker_kind=readiness_exhausted; it remains transient after live state ends]
- Decision resolutions ref: [journal/packet ref; retain exactly one canonical decision_resolution for every resolved item, including a mapping-state predecessor, every current-map retired/excluded deferred uncertainty predecessor, and every resolved item referenced by loop readiness]
- Route-clear handoff ref: [journal/packet ref; route_clear_handoff.decisions contains each current-map resolved decision exactly once through canonical decision_resolution.decision_item_ref values, while superseded/excluded current-map decisions appear exactly once in exclusions; decisions is non-empty when any current-map decision has status=resolved; retained historical resolutions for superseded/excluded current-map items are lineage evidence only and do not appear in decisions; route_clear_handoff remains required while progressive_route_clear_consumption_state in [pending, consumed] and progressive_artifact_retention_state=retained, with both reciprocal map refs resolvable during active/resumable continuation; terminally_archived permits omission]

## Key Decisions
- [decision]: [why] (Step N)

## Artifact Registry
[track every file created or modified — survives compression, prevents file-tracking loss]
| File | Purpose | Last Step |
|------|---------|-----------|
| [path] | [what and why] | Step N |

## Harness Appendix Routing
[required only for medium+ harness-capable work; otherwise `N/A: [reason]`; full schema in `references/task-journal-harness-appendix.md`]
- Appendix: `references/task-journal-harness-appendix.md`
- Controller intensity: [light | standard | strict + reason]
- Done Contract: [section/ref, or N/A: reason]
- Harness Recipe: [section/ref, or N/A: reason]
- Harness Run State: [section/ref, or N/A: reason]
- Trace Ledger: [section/ref, or N/A: reason]
- Replay Packet: [section/ref, or N/A: reason]
- Pivot/Restart Log: [section/ref when triggered, or N/A: reason]
- Artifact Reference Ledger: [section/ref when artifacts cross agents, or N/A: reason]
- QA Evaluation Log: [section/ref when qa_evaluation_mode=required, or N/A: reason]

## Milestones
[compression-safe boundaries — each marks a point where context can be safely truncated]
- [ ] M1: [milestone description] (after Step N)
- [ ] M2: [milestone description] (after Step N)

## Progress
- [x] Step 1: [what was done, files changed]
- [x] Step 2: [what was done, files changed]
- [ ] Step 3: [next]

## Build Repair State
[required only after an ordinary non-harness same-scope Build failure is retried]
- Attempt: [1..3]
- Max attempts: 3
- No-progress count: [0..2]
- No-progress limit: 2
- Failure signatures: [normalized current and prior signatures]
- Progress evidence: [new passing check, reduced failing scope, isolated cause, or explicit no progress]
- Plan version: [approved plan ref, or stable no-plan task identity]
- cumulative_attempt_count: [1..3; cumulative same-scope count, never reset by redispatch/context/compaction/continuation]
- Status: [repairing | recovered | terminal_pivot | blocked]
- terminal_route: [N/A | debugging | replan | restart_with_reapproval | block_for_user | block_for_environment]
- Evidence ref: [validation output or carried-forward evidence]

## Slice Verification Ledger
[required for medium+ tasks; update after each slice before starting the next]
do not start the next slice until the current one is `VERIFIED`
| Slice | Task Packet | RED Status | Implementation Status | Verification Command/Result | Criteria Checked | Self-Check Result | Final Status |
|-----------|-------------|------------|-----------------------|-----------------------------|------------------|-------------------|--------------|
| 1. [slice_id] [name] | [packet id] | [pass/fail/N/A] | [done/blocked] | `["executable", "arg"]` → [pass/fail + signal] | [X/Y passed] | [pass/fail + note] | [VERIFIED/BLOCKED] |

## Test Coverage
- Unit: [what's covered]
- Integration: [what's covered, or "N/A"]
- E2E: [what's covered, or "N/A"]

## Debugging Evidence (bugfixes)

- Debugging mode: [not_applicable | root_cause_unknown | root_cause_known | completed | blocked]
- Reproduction status: [yes | no | partial | blocked | N/A]
- Hypotheses considered: [count or N/A]
- Root cause / mitigation target: [summary or N/A]
- Transition to TDD: [ready | blocked | not_applicable]
- Residual risks: [list]

## Verification Summary
[filled after all build steps complete]

### What changed
- [file]: [what and why]

### What's tested
- [test]: [what it verifies]

### Manual test instructions
[N/A unless manual_verification_mode is optional/required; otherwise actionable steps]

### Manual Verification Result
- Mode: [not_required | optional | required]
- Trigger: [explicit_request | subjective_or_ui | external_effect | destructive_or_migration | automated_verification_inadequate | N/A]
- Result: [passed | optional_not_run | not_required | blocked]
- Evidence: [command, observation, user report, external result, or N/A]

### Known limitations
- [anything not covered or deferred]

## Review Log
[append entries; Spec Review first (structured PASS/FAIL from `references/prompts/spec-review.md`), then Quality Review (assistant-review quality loop); never overwrite previous entries]

### Spec Review #1
- Result: PASS | FAIL
- Scope reviewed: [plan step(s), task packet(s), or slice(s)]
- Missing acceptance criteria: [none, or list]
- Extra scope: [none, or list with file paths and disposition]
- Changed files mismatch: [none, or expected vs actual]
- Verification evidence mismatch: [none, or expected vs actual]
- Required fixes: [none, or ordered fix list]

### Quality Review #1
- Round: 1 of 10
- Previously fixed: 0 items from prior rounds
- Found this round: [count] must-fix, [count] should-fix, [count] nits (all fixed below)
- Rubric: correctness=[score] quality=[score] architecture=[score] security=[score] coverage=[score]
- Weighted: [score]
- Delta from previous: — (first round)
- Drift check: — (first round)
- Pivot/Restart decision: [ref if STAGNATION, repeated DRIFT, repeated REGRESSION, or PIVOT occurred; otherwise N/A]
- Complexity: [ran / skipped (not C#) / tool unavailable]
  - [method (line N): score X — refactored to Y, or "within threshold"]
- Must-fix:
  - [x] [file:line] — [issue] → [fix applied]
- Should-fix:
  - [x] [file:line] — [issue] → [fix applied or "deferred"]
- Re-test: PASS

### Quality Review #2 (autonomous re-review)
- Round: 2 of 10
- Previously fixed: [count] items from prior rounds
- Found this round: [count] must-fix, [count] should-fix, [count] nits (all fixed below)
- Rubric: correctness=[score] quality=[score] architecture=[score] security=[score] coverage=[score]
- Weighted: [score]
- Delta from previous: [+/- amount]
- Drift check: [GENUINE / SUSPICIOUS / DRIFT / REGRESSION / STAGNATION / NEUTRAL]
- Pivot/Restart decision: [ref if STAGNATION, repeated DRIFT, repeated REGRESSION, or PIVOT occurred; otherwise N/A]
- Must-fix:
  - [x] [file:line] — [issue] → [fix applied]
- Should-fix:
  - [x] [file:line] — [issue] → [fix applied or "deferred"]
- Re-test: PASS

[Round 3+ only when `additional_round_reason` records new changed files, an unresolved finding, validation failure, regression/drift, or a changed hypothesis; a low score alone is insufficient.]
[Note: On test failure, skip this entry — write only "- Result: HAS_REMAINING_ITEMS" to Final result]

### QA Evaluation
- Mode: required | optional | not_required
- QA trigger reason: [QA required positive triggers: explicit QA/acceptance evaluation request, accepted Done Contract, harness-capable acceptance scope, domain-scored scope, or scoped UI/visual/product/UX/docs/DX acceptance. QA non-triggers: template labels/placeholders, generic acceptance criteria labels, optional/not_required reasons, delegation/source-changing work alone, and ordinary medium+ code-review-only/source-changing work.]
- QA Evaluator result: [validated assistant-review qa_evaluation_result and qa_evaluation_delegation_path refs, or N/A: reason]
- Selected domain rubrics: [families used, or N/A]
- Domain quality scores: [compact scores, or N/A]
- Code Review evidence: [validated assistant-review final_summary and review_delegation_path refs, or N/A: reason]
- Full schema: `references/task-journal-harness-appendix.md#qa-evaluation-log` when required

### Final result
- Result: CLEAN | ISSUES_FIXED | HAS_REMAINING_ITEMS
- Review rounds: [count]
- QA result: [accepted | accepted_with_concerns | rejected | blocked | not_required]
- QA rounds: [count or N/A]
- QA score progression: [round1->round2->...roundN or N/A]
- Final rubric score: [weighted score] ([PASS/REFINE/PIVOT])
- Score progression: [round1→round2→...roundN] (e.g., 3.50→3.85→4.10)
- Drift incidents: [count, or "none"]
- Pivot/Restart decisions: [count and refs, or "none"]
- Total must-fix resolved: [count across all rounds]
- Total should-fix resolved: [count across all rounds]
- Should-fix deferred: [list any remaining]
- Nits noted: [count, not fixed]

## Review Notes
[filled during user review / handoff]
- [ ] [issue or change request]
- [ ] [issue or change request]
```

## Lifecycle

1. **Create** during Discover only when `workflow_state_mode=journal`; otherwise keep state inline. Record task and repository identity.
2. **Triage** records task/risk/gates/agents/subagent fields before leaving Triage; re-triage if evidence changes them.
3. **Clarification** has no numeric cap or quota. Apply deterministic safe defaults immediately with source/rationale and set the applied flag from those records. Ask every remaining admissible material question grouped by topic; waiting state stays `DISCOVERING` only for questions with no safe default; explicit `defaults` accepts displayed recommendations without changing automatic-default evidence.
4. **Decompose/Plan** persists the slice manifest for medium+ work. Plan is omitted only for eligible `plan_mode=none`, inline mode records a no-wait compact plan, and approval-required mode captures approval.
5. **Build** updates Progress, Artifact Registry, Key Decisions, Status, triggered harness refs, Milestones, bounded Build Repair State when activated, and Slice Verification Ledger before the next slice.
6. **Review** owns independent reviewer dispatch/result evidence, runs Spec Review, then one Quality Review pass; review-fix work fixes/validates and performs one fresh re-review. Round 3+ requires an evidence-backed `additional_round_reason`; fill Final Result but not the developer handoff.
7. **Document/Handoff** solely creates the developer handoff and fills Verification Summary, conditional Manual Verification Result, and Review Notes.
8. **Done** sets `Status: DONE` and `Task state: completed`, then leaves the ignored state file unless cleanup is requested.

## Rules

- Keep entries concise — this is a log, not documentation
- Resume from clarification waits only on explicit numbered answers or explicit `defaults`; apply deterministic safe defaults before any wait
- Constraints are checked before each Build step
- Producer roles update Artifact Reference Ledger entries in `references/task-journal-harness-appendix.md` when they create or move artifacts; Consumer roles validate `schema_or_contract` and update `validation_status` before using them
- Pivot/Restart Decisions are append-only recovery records. If the selected action changes scope, files, behavior, risk, verification, or acceptance criteria, record `reapproval_required: true` and wait for approval before continuing.
- On context continuation: read the configured task journal first without acting on it, then reconcile it against the newest user request and current repository evidence using `references/task-state-reconciliation.md`; resume only a reconciled active journal
- Never delete constraints unless the user explicitly removes them
- The Replay Packet in `references/task-journal-harness-appendix.md` replaces context-handoff templates during active harness work
