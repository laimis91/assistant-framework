# Build Worker Protocol

Internal reference for source-changing Build execution. Load when entering
Build for work that changes project source, tests, docs, config, runtime integrations,
contracts, or generated artifacts. `references/phases.md` keeps the compact
Build shell; this file owns worker sequencing, evidence, TDD ownership,
unexpected blocker routing, and per-slice verification.

## Adaptive Source-Changing Role Ownership

Small, low-risk, localized source changes may use the light lane when they have
no public behavior, data, security, harness, or QA acceptance risk:

- `controller_intensity=light`
- `workflow_state_mode=inline`
- `subagent_policy_state=not_required`
- `subagent_execution_mode=not_applicable`
- direct implementation with relevant automated validation/tests
- a fresh self-review after validation

The light lane does not require Code Writer, Builder/Tester, Code Reviewer, or
Reviewer dispatch/direct-fallback evidence. Any security-sensitive, high-risk,
harness-capable, required-QA, non-localized, or otherwise promoted work uses the
standard/strict lane and its existing gates.

Select `build_execution_lane` before dispatch:

- `bounded_executor` is the default for ordinary medium standard-risk work.
  One Code Writer/bounded executor owns the focused RED, GREEN, edit, test, and
  refactor-safety loop during Build. Independent review is dispatched only
  after Build enters Review.
- `separated_workers` is used for high or critical risk, broad or noisy
  verification, environment-heavy validation, an explicit independent TDD
  evidence requirement, or explicit role separation. It uses Code Writer,
  Builder/Tester, and Code Reviewer.

Task size alone does not select separated workers. `reviewer` remains
compatibility routing for legacy handoffs. Add QA Evaluator only when
`qa_evaluation_mode=required`.

Delegated mode (`subagent_execution_mode=delegated`):

- The orchestrator does not edit project source files or write
  implementation/test code directly.
- Framework-owned state artifacts (`{agent_state_dir}/task.md`,
  `{agent_state_dir}/context-map.md`, `{agent_state_dir}/session.md`, and
  `{agent_state_dir}/working-buffer.md`) are the exception only when configured
  and policy-allowed.
- In `bounded_executor`, project/test changes and focused verification go
  through one bounded Code Writer executor.
- In `separated_workers`, project source changes go through Code Writer and
  build/verification goes through Builder/Tester.
- Independent Review goes through Code Reviewer, or Reviewer compatibility only
  for existing/legacy handoffs.
- QA Evaluator runs only when `qa_evaluation_mode=required`.

For standard/strict work, Direct fallback mode
(`subagent_execution_mode=direct_fallback`) is allowed only for
`delegation_opted_out`, `subagents_unavailable`, or `policy_disallowed`.
Do not pretend delegation happened. Record `subagent_policy_state`,
`subagent_execution_mode`, `build_execution_lane`, the explicit direct fallback
reason, matching bounded/separated evidence, independent Code Reviewer
evidence during Review, and QA Evaluator evidence when QA is required.

## Standard/Strict Phase Evidence Gates

Before standard/strict Build can complete, the task journal Agent Dispatch Log
or equivalent carried-forward state contains only the selected Build-lane
evidence:

- `bounded executor dispatch/result` plus focused RED/GREEN/verification
  evidence when `build_execution_lane=bounded_executor`, or `Code Writer` and
  `Builder/Tester` dispatch/results when `separated_workers`

After Build, Review separately adds `Code Reviewer dispatch/result` (or legacy
Reviewer compatibility), `review_result`, and QA Evaluator evidence when QA is
required. Direct fallback follows the same phase split. Review evidence cannot
be used to satisfy a Build exit. `subagent_execution_mode=not_applicable` is invalid for
standard/strict source-changing Build. Silent fallback is invalid; Silent
fallback cannot complete.

For medium+ delegated work, record per-slice dispatch evidence before a slice is
marked `VERIFIED`.

## Build Loop

For light work, implement the carried Discover scope/criteria or the inline plan
when `plan_mode=inline`, run relevant automated validation/tests, and record the
changed scope plus results in the inline packet. Then perform the compact fresh
self-review. Do not create worker or
independent-review dispatch evidence solely to satisfy the light lane.

For medium+ tasks with slices, execute one slice at a time. Each slice is the
unit of implementation and verification.

Before starting a slice:

1. Load the approved task packet for the slice, including slice_id, observable
   increment, deliverable type, files, acceptance criteria, verification command,
   expected success signal, evidence to record, and deviation/rollback rule.
2. When harness-capable, confirm the task packet carries `done_contract_ref`,
   `harness_recipe_ref`, `harness_run_state_ref`, `trace_ledger_ref`,
   `replay_packet_ref`, and typed `artifact_refs`.
3. Confirm prior slice status is `VERIFIED` before advancing; do not start the
   next slice while the current slice is unverified.
4. Check constraints from the task journal against the slice files and criteria.

For each step, dispatch the selected lane owner for one task packet at a time.
The bounded executor edits and runs focused verification in the same context.
Separated workers dispatch Code Writer, then Builder/Tester. In direct fallback,
perform the same selected-lane responsibilities and record equivalent evidence.
Tests stay alongside code, not after it.

If implementation or verification fails and the cause is unclear, return to
`assistant-debugging` before another patch attempt. If the next fix is clear,
route verification through the selected build_execution_lane: the bounded
executor retries and verifies its focused loop; separated workers dispatch Code
Writer and then Builder/Tester; direct fallback performs the same selected-lane
responsibilities.

### Ordinary Build repair controller

For ordinary non-harness same-scope repair, initialize and persist
`build_repair_state` before the second implementation attempt:

- `attempt` and `cumulative_attempt_count` (the cumulative same-scope count)
- fixed `max_attempts: 3`
- `no_progress_count` and fixed `no_progress_limit: 2`
- normalized `failure_signatures`
- concrete `progress_evidence`
- stable `plan_version`
- status and evidence reference

One initial attempt plus at most two repairs is the complete three-attempt
budget. Redispatch, context reset, compaction, handoff, or cross-session resume
must not reset `cumulative_attempt_count` for the same plan version. Increment no-progress when the
same normalized signature remains and no check newly passes, no failing scope
shrinks, and no new evidence isolates the cause. Reset it only for measurable
evidence-backed progress.

At attempt 3, or when `no_progress_count` reaches 2, do not patch again. Set
status to `terminal_pivot` or `blocked`, record `terminal_route`, and route to debugging, replan, restart
with reapproval, user input, or environment recovery through
`pivot_restart_decision` when applicable. A changed plan version starts a new
path only after required reapproval; it must not disguise a same-scope retry.

After each implementation step, apply the relevant SOLID check from
`references/prompts/solid-principles.md` and fix material violations before
moving on.

## TDD Sandwich

Workflow sets TDD active by default for behavior changes, bugfixes with
RED-ready reproduction/root-cause evidence, and interface-affecting refactors
unless a not-feasible exception is recorded. Unknown-cause bugfixes complete
debugging first, then enter RED once the failure mechanism is understood.

When `tdd_mode=true` or `tdd_applies=true`, preserve the behavior boundary in
both lanes: valid RED evidence must exist before production code.

- `bounded_executor`: the bounded executor writes/runs RED, records the
  right-reason failure, implements minimal GREEN, then runs focused and relevant
  regression verification.
- `separated_workers`: Builder/Tester owns RED, Code Writer owns GREEN, and
  Builder/Tester owns verify/refactor-safety.

For bugfixes, RED traces to the original reproduction/debugging evidence. A
missing or wrong-reason RED blocks production edits in either lane.

## Code Writer Unexpected Blockers

If Code Writer returns `NEEDS_CONTEXT`, `BLOCKED`, or `DEVIATED` because of a
legacy code bug, broken baseline, hidden dependency, missing contract, stale
plan, scope conflict, tool/environment issue, permission/policy issue, missing
RED evidence, or another unexpected blocker, do not ask Code Writer to improvise
through it blindly.

Use `references/workflow-controller.md` to decide whether the blocker should
move the task forward after a local fix, step back to Discover/Decompose/Plan,
or replan before another implementation attempt.

Require the return to include:

- `blocker_type`: `legacy_code_bug`, `broken_baseline`, `hidden_dependency`,
  `missing_contract`, `stale_plan`, `scope_conflict`, `tool_environment`,
  `permission_policy`, `tdd_red_missing`, or `other`
- `blocker_evidence`: file paths, missing contract fields, baseline failures,
  tool output summaries, scope conflict details, or task-packet mismatches

Recovery routing:

- `legacy_code_bug` or `broken_baseline` -> dispatch debugging before another
  implementation attempt
- `hidden_dependency` -> dispatch Explorer or refresh Code Mapper context
- `missing_contract` or `stale_plan` -> dispatch Architect or return to Plan
- `scope_conflict` -> record a plan deviation and seek reapproval when scope,
  files, behavior, risk, verification, or acceptance criteria change
- `tool_environment` -> route to Builder/Tester or environment recovery
- `permission_policy` -> request permission or return BLOCKED
- `tdd_red_missing` -> obtain valid RED evidence from the selected lane owner
- `other` -> create a conservative recovery route with evidence

Recovery route labels are: debugging, explorer, architect, candidate_search,
replan, restart, user_clarification, environment_fix, and permission_request.
When recovery requires pivot, replan, candidate search, or restart, use
`references/harness-runtime-artifacts.md` for the pivot/restart artifact update.

## Per-Slice Verification

Per-slice verification is a Build-phase gate. It does not replace the full
Review phase after Build completes.

After implementation for a slice is done, verify the slice against its
Decompose criteria before moving on:

1. In `bounded_executor`, the executor executes the slice verification argv
   directly, with item 0 as the executable and each remaining item as one
   literal argument; never reconstruct a shell command. Then run
   relevant focused checks. Dispatch Builder/Tester only when
   `build_execution_lane=separated_workers`; direct fallback performs the same
   selected-lane verification responsibility.
2. Check each acceptance criterion from the slice manifest independently; mark
   pass/fail with command, result, or inspection evidence.
3. Record verification evidence in the task journal slice verification ledger,
   including RED status when TDD was active, implementation status,
   command/result, criteria checked, self-check result, and final status.
4. For harness-capable work, update Harness Run State, append Trace Ledger
   verification/artifact refs, refresh Replay Packet validation_state plus
   exact_next_action, and update Artifact Reference Ledger entries for
   changed_files, verification_evidence, pivot_restart_decision, and
   plan_deviation refs when applicable.
5. Run a small self-check/local sanity check: compare changed files and behavior
   against the task packet, constraints, and deviation rule; record the result in
   the ledger.
6. If any criterion, command, runtime artifact, or self-check fails, fix before
   moving to the next slice.
7. Mark the slice `VERIFIED` only after all criteria pass and evidence is
   recorded.

Only proceed to the next slice after the current one is fully verified.

After all slices are verified, run integration tests across slice boundaries.
If implementation reveals a plan problem, print `>> PLAN DEVIATION DETECTED`,
record `pivot_restart_decision.reapproval_required=true` when scope/files/
behavior/risk/verification/acceptance changes, and wait for approval before
continuing the changed path.
