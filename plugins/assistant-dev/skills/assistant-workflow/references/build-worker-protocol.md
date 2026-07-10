# Build Worker Protocol

Internal reference for source-changing Build execution. Load when entering
Build for work that changes project source, tests, docs, config, hooks,
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

Standard/strict source-changing Build tasks infer `required_agents` with at
least Code Writer, Builder/Tester, and Code Reviewer. `reviewer` remains
compatibility routing for existing or legacy handoffs. Add QA Evaluator only
when `qa_evaluation_mode=required`.

Delegated mode (`subagent_execution_mode=delegated`):

- The orchestrator does not edit project source files or write
  implementation/test code directly.
- Framework-owned state artifacts (`{agent_state_dir}/task.md`,
  `{agent_state_dir}/context-map.md`, `{agent_state_dir}/session.md`, and
  `{agent_state_dir}/working-buffer.md`) are the exception only when configured
  and policy-allowed.
- Project source changes go through Code Writer.
- Build and verification go through Builder/Tester.
- Independent Review goes through Code Reviewer, or Reviewer compatibility only
  for existing/legacy handoffs.
- QA Evaluator runs only when `qa_evaluation_mode=required`.

For standard/strict work, Direct fallback mode
(`subagent_execution_mode=direct_fallback`) is allowed only for
`authorization_denied`, `subagents_unavailable`, or `policy_disallowed`.
Do not pretend delegation happened. Record `subagent_policy_state`,
`subagent_execution_mode`, the explicit direct fallback reason, and equivalent
Code Writer, Builder/Tester, Code Reviewer, and QA Evaluator evidence when QA is
required.

## Standard/Strict Evidence Gate

Before standard/strict Build/Review can complete, the task journal Agent
Dispatch Log or equivalent carried-forward state must contain:

- `Code Writer dispatch` and `Code Writer result`
- `Builder/Tester dispatch` and `Builder/Tester result`
- `Code Reviewer dispatch` and `Code Reviewer result`, or `Reviewer dispatch`
  and `Reviewer result` only for compatibility routing
- `QA Evaluator dispatch` and `QA Evaluator result` when
  `qa_evaluation_mode=required`

Direct fallback records the equivalent direct evidence fields instead:
`Code Writer direct evidence`, `Builder/Tester direct evidence`,
`Code Reviewer direct evidence`, and `QA Evaluator direct evidence` when QA is
required. `subagent_execution_mode=not_applicable` is invalid for
standard/strict source-changing Build. Silent fallback is invalid; Silent
fallback cannot complete.

For medium+ delegated work, record per-slice dispatch evidence before a slice is
marked `VERIFIED`.

## Build Loop

For light work, implement the inline plan directly, run relevant automated
validation/tests, and record the changed scope plus results in the inline
packet. Then perform the compact fresh self-review. Do not create worker or
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

For each non-TDD step, dispatch Code Writer for one plan step at a time in
delegated mode, then dispatch Builder/Tester for build and tests. In direct
fallback, perform the same responsibilities directly and record role-equivalent
evidence. Tests stay alongside code, not after it.

If implementation or verification fails and the cause is unclear, return to
`assistant-debugging` before another patch attempt. If the next fix is clear,
dispatch Code Writer again or perform the Code Writer responsibility directly in
fallback mode, then verify through Builder/Tester responsibility.

After each implementation step, apply the relevant SOLID check from
`references/prompts/solid-principles.md` and fix material violations before
moving on.

## TDD Sandwich

Workflow sets TDD active by default for behavior changes, bugfixes with
RED-ready reproduction/root-cause evidence, and interface-affecting refactors
unless a not-feasible exception is recorded. Unknown-cause bugfixes complete
debugging first, then enter RED once the failure mechanism is understood.

When `tdd_mode=true` or `tdd_applies=true`, use the TDD sandwich per step:

- Builder/Tester RED: write one failing behaviour test, run it, verify right failure reason, and return RED evidence.
- Code Writer GREEN: implement minimal production code only after RED evidence
  is present.
- Builder/Tester VERIFY/REFACTOR-SAFETY: run the targeted test, relevant suite,
  and regression checks; request Code Writer fixes for production failures.

In direct fallback, preserve those role boundaries in the evidence even when one
agent performs the work. For bugfixes, the RED test must trace to the original
reproduction/debugging evidence. If TDD is active and Builder/Tester RED
evidence is missing, Code Writer returns `NEEDS_CONTEXT` and makes no production
changes.

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
- `tdd_red_missing` -> return to Builder/Tester RED evidence
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

1. Dispatch Builder/Tester in delegated mode, or perform the Builder/Tester
   responsibility directly in fallback mode, to run the slice verification
   command and relevant build/test checks from the task packet.
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
