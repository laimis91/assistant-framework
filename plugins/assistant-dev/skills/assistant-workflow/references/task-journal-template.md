# Task Journal Template

Write to `{agent_state_dir}/task.md` in the project root when a local state directory is configured and policy allows. If none is safe, keep the same content in the response/plan packet. This framework-owned ignored artifact is the task source of truth, survives compression/continuation when persisted, and may be updated by the orchestrator.

## When to create
- Any task that enters clarification wait: during Discover, before printing clarification questions or the wait message
- Medium+: during Discover, before leaving Discover even when no clarification wait is needed
- Small tasks without clarification wait: optional unless the task is multi-step

## When to update
- When clarification questions are asked, answered, or resolved via explicit `defaults`
- After each Build step: Progress, Artifact Registry, Milestones
- After key decisions, new user constraints, review passes, verification summary, or user review feedback
- After harness-capable events, Pivot/Restart Decisions, typed artifact refs, or QA results when applicable
- During Document, after review/build/user-correction evidence is checked for durable lessons

## Template

```markdown
## Task: [1-sentence description]
Created: [stable task identity, e.g. ISO timestamp created once]
Status: DISCOVERING | DECOMPOSING | PLANNING | BUILDING [step N/M] | REVIEWING | DOCUMENTING | DONE
Triaged as: [small | medium | large | mega]
Task type: [feature | bugfix | refactor | migration | rewrite | config | infra | security | docs | spike]
Risk tier: [low | moderate | high | critical]
Controller intensity: [light | standard | strict]
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
Loop / Experiment Routing:
- workflow_experiment_ledger: [N/A unless explicit workflow experiment; otherwise compact ref with id/hypothesis/intervention/signal/measurement/baseline/status/evidence/decision/next_check]
- loop_readiness_assessment: [N/A unless explicit repeat or optimization loop; otherwise compact ref with loop_type/trigger/verifier/stop/max_iterations/budget/tool_access/state_tracking/retry_or_empty_result_handling/tool_error_handling/low_confidence_escalation/rollback/harness_routing/evidence]
- loop_harness_routing: [ordinary medium+ keeps harness_capable=false; loop artifacts alone do not require Done Contract, Harness Recipe, Trace Ledger, Replay Packet, Artifact Reference Ledger, or QA evaluation; appendix only when harness_capable=true or QA criteria independently apply]
Plan approval: [yes/no + date]

## Agent Dispatch Log
[subagent evidence inspected by stop-review/phase gates]
- Required roles: Code Writer, Builder/Tester, Code Reviewer; QA Evaluator when required; Code Mapper/Explorer/Architect by size/risk; Reviewer for legacy compatibility.
- Execution mode: delegated | direct_fallback | not_applicable
- Codex lifecycle evidence: delegated Codex roles need hook-written protected workflow-state `SubagentStart`/`SubagentStop` records, task-bound to this journal's `Created:` identity; project-local `.codex/subagent-events.jsonl` is diagnostic only.
- Direct fallback reason: [authorization_denied | subagents_unavailable | policy_disallowed | N/A]
- Evidence shorthand: delegated refs | role-equivalent direct evidence | N/A only when role not required.
- Code Mapper dispatch/result/direct evidence: [delegated refs | direct evidence | N/A]
- Explorer dispatch/result/direct evidence: [delegated refs | direct evidence | N/A]
- Architect dispatch/result/direct evidence: [delegated refs | direct evidence | N/A]
- Code Writer dispatch/result/direct evidence: [delegated refs | direct evidence | N/A]
- Builder/Tester dispatch/result/direct evidence: [delegated refs | direct evidence | N/A]
- Code Reviewer dispatch/result/direct evidence: [delegated refs | Code Reviewer direct evidence | Reviewer legacy compatibility | N/A]
- Reviewer dispatch/result/direct evidence: [compatibility refs/direct evidence when used | N/A]
- QA Evaluator dispatch/result/direct evidence: [delegated QA refs | direct evidence | N/A when not required]
- Per-slice dispatch evidence: [medium+ delegated slice_id -> Code Writer + Builder/Tester refs; otherwise N/A: reason]

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

## Slice Verification Ledger
[required for medium+ tasks; update after each slice before starting the next]
do not start the next slice until the current one is `VERIFIED`
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

[...repeat until clean or max rounds reached...]
[Note: On test failure, skip this entry — write only "- Result: HAS_REMAINING_ITEMS" to Final result]

### QA Evaluation
- Mode: required | optional | not_required
- QA trigger reason: [QA required positive triggers: explicit QA/acceptance evaluation request, accepted Done Contract, harness-capable acceptance scope, domain-scored scope, or scoped UI/visual/product/UX/docs/DX acceptance. QA non-triggers: template labels/placeholders, generic acceptance criteria labels, optional/not_required reasons, delegation/source-changing work alone, and ordinary medium+ code-review-only/source-changing work.]
- QA Evaluator result: [final_verdict/result ref, or N/A: reason]
- Selected domain rubrics: [families used, or N/A]
- Domain quality scores: [compact scores, or N/A]
- Code Review evidence: [Code Reviewer/Reviewer result ref, or N/A: reason]
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

1. **Create** during Discover for clarification waits and all medium+ tasks.
2. **Triage** records task/risk/gates/agents/subagent fields before leaving Triage; re-triage if evidence changes them.
3. **Clarification** caps are maximums, not quotas. Waiting state stays `DISCOVERING`; explicit answers clear unresolved topics, while explicit `defaults` also sets `Clarification defaults applied: true`.
4. **Decompose/Plan** persists the slice manifest for medium+ work, captures approval, then updates `Plan approval`.
5. **Build** updates Progress, Artifact Registry, Key Decisions, Status, triggered harness refs, Milestones, and Slice Verification Ledger before the next slice.
6. **Review** runs Spec Review, then Quality Review, fixing/re-testing/re-reviewing until clean or routed by Pivot/Restart; fill Final Result.
7. **Document/Handoff** fills Verification Summary, Learning Controller, Review Notes, and user manual-test notes.
8. **Done** sets `Status: DONE`, records only evidence-backed durable lessons when allowed, and leaves the ignored state file unless cleanup is requested.

## Rules

- Keep entries concise — this is a log, not documentation
- Resume from clarification waits only on explicit numbered answers or explicit `defaults`
- Constraints are checked before each Build step
- Producer roles update Artifact Reference Ledger entries in `references/task-journal-harness-appendix.md` when they create or move artifacts; Consumer roles validate `schema_or_contract` and update `validation_status` before using them
- Pivot/Restart Decisions are append-only recovery records. If the selected action changes scope, files, behavior, risk, verification, or acceptance criteria, record `reapproval_required: true` and wait for approval before continuing.
- On context continuation: read the configured task journal FIRST when it exists, before any other action
- Never delete constraints unless the user explicitly removes them
- The Replay Packet in `references/task-journal-harness-appendix.md` replaces context-handoff templates during active harness work
