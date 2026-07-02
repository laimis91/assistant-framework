# Task Journal Template

Write to `{agent_state_dir}/task.md` in the project root when a local agent state directory is configured and policy allows local state artifacts. If no safe state directory is available, keep the same content in the response/plan packet. This state is the single source of truth for the current task — it survives context compression and session continuations when persisted. It is a framework-owned ignored state artifact, so the orchestrator may create and update it directly when allowed.

## When to create
- Any task that enters clarification wait: during Discover, before printing clarification questions or the wait message
- Medium+: during Discover, before leaving Discover even when no clarification wait is needed
- Small tasks without clarification wait: optional unless the task is multi-step

## When to update
- When clarification questions are asked, answered, or resolved via explicit `defaults`
- After each Build step completes (update Progress, Artifact Registry, and check off Milestones)
- After each medium+ harness event that changes phase, slice, status, blockers, verification, next action, decisions, deviations, or artifact refs
- After any Pivot/Restart Decision, including review/QA stagnation, repeated drift/regression, Code Writer blockers, or selected restart/replan action
- After any producer creates/updates a typed artifact reference or any consumer changes `validation_status`
- When key decisions are made
- When constraints are added by the user
- After each review cycle pass (append to Review Log — never overwrite)
- At verification summary (all steps done)
- During user review feedback
- During Document, after review/build/user-correction evidence has been checked for durable lessons

## Template

```markdown
## Task: [1-sentence description]
Status: DISCOVERING | DECOMPOSING | PLANNING | BUILDING [step N/M] | REVIEWING | DOCUMENTING | DONE
Triaged as: [small | medium | large | mega]
Task type: [feature | bugfix | refactor | migration | rewrite | config | infra | security | docs | spike]
Risk tier: [low | moderate | high | critical]
Clarification status: [ready | needs_clarification]
Clarification defaults applied: [true | false]
Clarification confidence: [low | medium | high]
Clarification questions asked: [0+]
Clarification question cap: [0+; maximum, not quota]
Clarification admissibility: [satisfied | needs_clarification | not_applicable]
Unresolved clarification topics:
- [none, or one short topic per line]
Required gates:
- [common gate or task-category gate from references/triage-rubric.md]
Required agents:
- [workflow role or skill required by size/risk/type]
Subagent policy state: [not_required | authorization_required | delegation_authorized | authorization_denied | subagents_unavailable | policy_disallowed]
Subagent execution mode: [delegated | direct_fallback | not_applicable]
Subagent authorization scope:
- [roles/phases/actions covered by user authorization, or none]
Candidate scope scan:
- Likely touched paths: [exact paths, directories, modules, or unknown]
- Symbols or terms searched: [search terms, commands, or none with reason]
- Adjacent surfaces: [tests/docs/contracts/config/mirrors/hooks/runtime surfaces to inspect]
- Confidence: [low | medium | high]
- Unknowns: [none, or one short scope/risk unknown per line]
Plan approval: [yes/no + date]

## Agent Dispatch Log
[strict subagent evidence inspected by stop-review/phase gates]
- Required roles: Code Writer, Builder/Tester, Code Reviewer [Reviewer remains compatibility routing; plus QA Evaluator when QA is required; plus Code Mapper/Explorer/Architect when required by size/risk]
- Execution mode: delegated | direct_fallback | not_applicable
- Codex lifecycle evidence: delegated Codex roles must have matching `.codex/subagent-events.jsonl` `SubagentStart` + `SubagentStop` records; dispatch/result entries must cite the matching `agent_id`; journal text alone is not proof.
- Direct fallback reason: [authorization_denied | subagents_unavailable | policy_disallowed | N/A]
- Code Mapper dispatch: [subagent/tool/run id, mapping packet, timestamp, or N/A only in direct_fallback/not required]
- Code Mapper result: [context map summary/evidence, or N/A only in direct_fallback/not required]
- Code Mapper direct evidence: [role-equivalent context map evidence when direct_fallback, else N/A]
- Explorer dispatch: [subagent/tool/run id, exploration packet, timestamp, or N/A only in direct_fallback/not required]
- Explorer result: [execution path/dependency evidence, or N/A only in direct_fallback/not required]
- Explorer direct evidence: [role-equivalent exploration evidence when direct_fallback, else N/A]
- Architect dispatch: [subagent/tool/run id, architecture/decomposition packet, timestamp, or N/A only in direct_fallback/not required]
- Architect result: [slice/blueprint/design evidence, or N/A only in direct_fallback/not required]
- Architect direct evidence: [role-equivalent decomposition/architecture evidence when direct_fallback, else N/A]
- Code Writer dispatch: [subagent/tool/run id, prompt/packet, timestamp, or N/A only in direct_fallback/not required]
- Code Writer result: [returned files/summary/evidence, or N/A only in direct_fallback/not required]
- Code Writer direct evidence: [role-equivalent implementation evidence when direct_fallback, else N/A]
- Builder/Tester dispatch: [subagent/tool/run id, verification packet, timestamp, or N/A only in direct_fallback/not required]
- Builder/Tester result: [commands/results/success signal returned, or N/A only in direct_fallback/not required]
- Builder/Tester direct evidence: [role-equivalent build/test/validation evidence when direct_fallback, else N/A]
- Code Reviewer dispatch: [code-reviewer subagent/tool/run id or assistant-review dispatch, or N/A only when Reviewer compatibility/direct_fallback/not required]
- Code Reviewer result: [spec/quality review result evidence returned, or N/A only when Reviewer compatibility/direct_fallback/not required]
- Code Reviewer direct evidence: [fresh review/spec+quality evidence when direct_fallback, else N/A]
- Reviewer dispatch: [compatibility reviewer subagent/tool/run id or assistant-review dispatch, or N/A only in direct_fallback/not required]
- Reviewer result: [compatibility spec/quality review result evidence returned, or N/A only in direct_fallback/not required]
- Reviewer direct evidence: [compatibility fresh review/spec+quality evidence when direct_fallback, else N/A]
- QA Evaluator dispatch: [qa-evaluator subagent/tool/run id or assistant-review QA dispatch, or N/A only when qa_evaluation_mode=not_required/direct_fallback]
- QA Evaluator result: [acceptance final_verdict/result, score_progression, and evidence returned, or N/A only when qa_evaluation_mode=not_required/direct_fallback]
- QA Evaluator direct evidence: [fresh acceptance/Done Contract/verification QA evidence when direct_fallback, else N/A]
- Per-slice dispatch evidence: [medium+ delegated only: slice_id -> Code Writer dispatch/result + Builder/Tester dispatch/result; direct_fallback records sequential role-equivalent slice evidence]

## Constraints
- [user-stated boundaries, e.g. "Do not modify ProjectA"]
- [technical constraints, e.g. "Must stay on .NET 8"]
- [scope limits, e.g. "Backend only, no UI changes"]

## Plan
[paste approved plan verbatim — include slice manifest for medium+ tasks, plus task packets with slice_id and file paths]

## Key Decisions
- [decision]: [why] (Step N)

## Artifact Registry
[track every file created or modified — survives compression, prevents file-tracking loss]
| File | Purpose | Last Step |
|------|---------|-----------|
| [path] | [what and why] | Step N |

## Done Contract
[required before Build for medium+ harness-capable work; otherwise record N/A with reason]
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
[required before Build for medium+ harness-capable work; otherwise record N/A with reason]
- task_profile: [task type, size, slice count, TDD/debugging applicability]
- model_profile: [agent/model constraints, delegation mode, tool limits]
- risk_profile: [risk tier, safety gates, review depth, rollback needs]
- context_profile: [exact/summarized/omitted context and trace/replay needs]
- selected_recipe: [concise recipe label]
- recipe_rationale: [why this task/model/risk/context profile selects the recipe]
- required_artifacts: [Done Contract, task packet, verification, trace/handoff artifacts]
- corrective_action: [what to do if missing or stale]

## Harness Run State
[required for medium+ harness-capable work; otherwise record N/A with reason]
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
| 1 | [timestamp or ordered marker] | [agent_event/decision/verification/plan_deviation/pivot_restart/artifact_ref/blocker/recovery] | [role/subagent/user/hook] | [event, decision, command/result, deviation, blocker, pivot/restart, or recovery] | [file/section/dispatch id/command ref] |

## Replay Packet
[required for medium+ harness-capable work before compaction, failure handoff, phase handoff, or end-of-turn]
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
[append when review/QA stagnation, repeated drift/regression, rubric/domain pivot, Code Writer blocker, verification blocker, plan deviation, or scope change triggers recovery; otherwise record N/A with reason]

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
[required for medium+ harness-capable work when artifacts pass between agents; typed producer/consumer records, not ad hoc strings]
| Artifact ID | Artifact Type | Producer | Consumer | Location Ref | Schema or Contract | Validation Status | Summary |
|-------------|---------------|----------|----------|--------------|--------------------|-------------------|---------|
| [id] | [done_contract/harness_recipe/harness_run_state/trace_ledger/replay_packet/pivot_restart_decision/changed_files/verification_evidence/plan_deviation/task_packet/context_map/test_result/review_result/qa_evaluation_result] | [role/subagent/hook] | [role/subagent/phase] | [file/section/dispatch/command ref] | [contract/template/fields] | [pending/valid/invalid/stale/not_applicable] | [concise state] |

## Milestones
[compression-safe boundaries — each marks a point where context can be safely truncated]
- [ ] M1: [milestone description] (after Step N)
- [ ] M2: [milestone description] (after Step N)

## Progress
- [x] Step 1: [what was done, files changed]
- [x] Step 2: [what was done, files changed]
- [ ] Step 3: [next]

## Slice Verification Ledger
[required for medium+ tasks; update after each slice before starting the next]
| Slice | Task Packet | RED Status | Implementation Status | Verification Command/Result | Criteria Checked | Self-Check Result | Final Status |
|-----------|-------------|------------|-----------------------|-----------------------------|------------------|-------------------|--------------|
| S1: [slice_id] [name] | [packet id] | [pass/fail/N/A] | [done/blocked] | `[command]` → [pass/fail + signal] | [X/Y passed] | [pass/fail + note] | [VERIFIED/BLOCKED] |

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
1. [step-by-step for the user to verify]

### Known limitations
- [anything not covered or deferred]

## Review Log
[append an entry each time a review stage runs — never overwrite previous entries]

### Spec Review #1
- Result: PASS | FAIL
- Scope reviewed: [plan step(s), task packet(s), or slice(s)]
- Missing acceptance criteria: [none, or list]
- Extra scope: [none, or list with file paths and disposition]
- Changed files mismatch: [none, or expected vs actual]
- Verification evidence mismatch: [none, or expected vs actual]
- Required fixes: [none, or ordered fix list]

### Quality Review #1
- Round: 1 of 20
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
- Round: 2 of 20
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

[...repeat until clean or max rounds reached...]
[Note: On test failure, skip this entry — write only "- Result: HAS_REMAINING_ITEMS" to Final result]

### QA Evaluation #1
- Round: 1 of 20
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
  - [blocker|concern|observation] [criterion] — [evidence] → [fix/defer/open question]

[...repeat QA Evaluation until accepted, accepted_with_concerns, blocked, or max round 20 reached...]

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

## Document Log

### Learning Controller
- Memory trend checked: [checked | backend_unavailable | policy_disallowed | not_configured]
- Learning evidence reviewed:
  - [review_finding | build_test_failure | user_correction | memory_trend | none]: [source reference] — [summary, or none-with-reason]
- Review findings considered:
  - [finding summary and lesson decision, or none-with-reason]
- Build/test failures considered:
  - [failure summary and lesson decision, or none-with-reason]
- User corrections considered:
  - [correction summary and lesson decision, or none-with-reason]
- Durable lesson decision: [durable_saved | durable_updated | skipped_not_durable | backend_unavailable | policy_disallowed | refused_sensitive]
- Persistence evidence: [memory_reflect/memory_add_insight/backend evidence when saved or updated, else N/A]
- No-save rationale: [required when no durable write occurred; do not use ad hoc markdown as cross-session memory when backend is available]

## Review Notes
[filled during user review / handoff]
- [ ] [issue or change request]
- [ ] [issue or change request]
```

## Lifecycle

1. **Created** during Discover when clarification state must be tracked. Any task that enters clarification wait creates it before the wait; medium+ tasks also create it before leaving Discover even when no clarification wait is needed.
2. **Triage metadata** — record `Task type`, `Risk tier`, `Required gates`, `Required agents`, `Subagent policy state`, `Subagent execution mode`, and `Subagent authorization scope` before leaving Triage. Discovery may re-triage these fields when code/context evidence changes the risk or required gates.
3. **Clarification** updates — question caps are maximums, not quotas. Clear medium+ tasks may record `Clarification questions asked: 0` with `Clarification confidence: high`. While waiting, keep `Status: DISCOVERING`, set `Clarification status: needs_clarification`, set `Clarification defaults applied: false`, set confidence/cap/admissibility fields, and list every unresolved implementation-shaping topic. On explicit answers, clear unresolved topics, keep `Clarification defaults applied: false`, and set `Clarification status: ready`. On explicit `defaults`, print the applied defaults, clear unresolved topics, set `Clarification defaults applied: true`, and set `Clarification status: ready`.
4. **Decompose** — medium+ tasks set `Status: DECOMPOSING` after Discover is ready, then persist the slice manifest before moving on to planning. Small tasks skip this state.
5. **Plan approval** — once ready to plan, set `Status: PLANNING`, include the slice manifest in the plan for medium+ tasks, capture the approved plan, and update `Plan approval`.
6. **Build** each step — update Progress, Artifact Registry, Artifact Reference Ledger, Key Decisions, Status, Harness Run State, Trace Ledger, Replay Packet, and Pivot/Restart Log when triggered after each step. For medium+ tasks, update the Slice Verification Ledger after each slice and do not start the next slice until the current one is `VERIFIED`. Check off Milestones when reached.
7. **Review cycle** when all steps done — Spec Review first (structured PASS/FAIL from `references/prompts/spec-review.md`), then Quality Review (assistant-review quality loop), fix must-fix → re-test → re-review until clean or a Pivot/Restart Decision routes recovery, fill Final Result
8. **Document** after review cycle passes — fill Verification Summary, add the Learning Controller block, Status: DOCUMENTING
9. **Handoff** to user — they test manually and add Review Notes
10. **Review fixes** — fix issues, re-test, re-review, update Progress
11. **Done** — Status: DONE, promote only evidence-backed durable lessons to approved local memory if available, record backend_unavailable/policy_disallowed/no-save rationale when not saved, and leave the ignored state file in place unless the user asks for cleanup

## Rules

- Keep entries concise — this is a log, not documentation
- Resume from clarification waits only on explicit numbered answers or explicit `defaults`
- Constraints are checked before each Build step
- Producer roles update Artifact Reference Ledger entries when they create or move artifacts; Consumer roles validate `schema_or_contract` and update `validation_status` before using them
- Pivot/Restart Decisions are append-only recovery records. If the selected action changes scope, files, behavior, risk, verification, or acceptance criteria, record `reapproval_required: true` and wait for approval before continuing.
- On context continuation: read the configured task journal FIRST when it exists, before any other action
- Never delete constraints unless the user explicitly removes them
- The Replay Packet replaces the need for context-handoff templates during active harness work
