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
- direct implementation with the checks selected by `verification_decision`
- a fresh self-review after validation

Shared fanout alone does not promote this Build lane. The light lane does not require Code Writer, Builder/Tester, Code Reviewer, or
Reviewer dispatch/direct-fallback evidence. Any security-sensitive, high-risk,
harness-capable, required-QA, non-localized, or otherwise promoted work uses the
standard/strict lane and its existing gates.

Expanded impact keeps this Build lane; Review records canonical
`assistant-review` final-summary and delegation-path refs.

Select `build_execution_lane` before dispatch:

- `bounded_executor` is the default for ordinary medium standard-risk work.
  One Code Writer/bounded executor owns implementation and selected checks;
  RED/GREEN/REFACTOR applies only to packets whose `tdd_applies` is true.
  Independent review is dispatched only
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

## Expanded-impact mutation authorization

Before any source/test mutation, including a regression-test write, or any
mutation dispatch, run or revalidate the common checker against the referenced
capture, independent expected context, and assessment for shared, unresolved,
or explicitly expanded impact. The current valid `pre_build` result must resolve
against the task packet; a status or result ref alone is insufficient. Reuse is
allowed only for demonstrably current same-input evidence.

After an earlier mutation, refresh this evidence before each subsequent
mutation dispatch. In particular, Builder/Tester must not reuse a Code Writer
pre-build result. The same rule applies to light work and direct fallback;
those paths may remain local without the expanded trigger.

## Standard/Strict Phase Evidence Gates

Before standard/strict Build can complete, the task journal Agent Dispatch Log
or equivalent carried-forward state contains only the selected Build-lane
evidence:

- `bounded executor dispatch/result` plus selected verification evidence and
  RED/GREEN evidence only when TDD is active for `build_execution_lane=bounded_executor`, or `Code Writer` and
  `Builder/Tester` dispatch/results when `separated_workers`

After Build, Review separately adds `Code Reviewer dispatch/result` (or legacy
Reviewer compatibility), `review_result`, and QA Evaluator evidence when QA is
required. Direct fallback follows the same phase split. Review evidence cannot
be used to satisfy a Build exit. `subagent_execution_mode=not_applicable` is invalid for
standard/strict source-changing Build. Silent fallback is invalid; Silent
fallback cannot complete.

For medium+ delegated work, record per-slice dispatch evidence before a slice is
marked `VERIFIED`.

### Build and test applicability

Resolve build and test applicability from the current due `CheckSpec`s and
resolved binding constraints, using each check's claim, oracle, and concrete
procedure. Do not infer applicability from file type, command presence, method,
or technique alone; missing or unresolved applicability is a gap. Keep
`build_result` required: use `not_applicable` only when no due selected or
binding build check applies and no build was executed, `passed` only for current
observed or admissibly reused successful build evidence, `failed` for an
executed failure, and `not_run` when a required build could not run and the
worker is `NEEDS_CONTEXT` or `BLOCKED`, when `FAILED_VERIFICATION` results from
a different executed required check, or when the required build is pending
GREEN during a valid `pre_production_red` stage with
`verification.result=partial`. Stage-only `not_run` never establishes final
Build sufficiency. A failed required build blocks completion. Keep
`test_summary` required; zero counts mean no tests were
executed, not that selected or binding tests passed. Every due selected or
binding check still needs a current result. A no-command check may return an
empty `verification.commands` list only when `verification.evidence` names the
concrete procedure performed and its observed result.

Resolve every command-based selected check independently by its `check_id` in
the unchanged `verification_decision`. Use that CheckSpec's literal
`command.argv` and explicit `command.cwd`; preserve each command separately in
the packet and result evidence. The legacy singular `verification_command` is
only a compatibility projection when the selected IDs resolve exactly one
command-based CheckSpec. Omit it when there are zero or multiple commands. Never
flatten commands, infer a working directory, reconstruct shell text, or attach a
result to a different check. Missing or ambiguous command context requires a
refreshed decision or a blocked result; non-command checks keep their concrete
procedure.

## Writer identity within the selected lane

Resolve `writer_selection` using `subagent-dispatch.md#concrete-writer-selection`
before dispatch. The Orchestrator validates all four mechanical evidence refs;
Architect proposals do not authorize selection. Carry the identical selection
through the task packet and inline CodeWriter context; packet context is
authoritative and conflicts block. Old packets remain valid with intelligent
compatibility semantics. New Claude and Codex dispatch defaults to intelligent-writer;
missing named definitions are a deployment mismatch, never silent generic fallback.
Claude uses the same intelligent/mechanical roles with native Opus/Sonnet aliases and explicit deprecated code-writer intelligent compatibility. Gemini retains native/default tiers and shared writer ownership; do not invent custom roles. Eligibility covers BOTH tests and implementation, including approved cases, expected values/oracles, negative cases and assertion/fixture patterns.

When mechanical evidence becomes stale, stop dependent mutations and return all
actual partial changes, observed evidence, truthful status and blocker fields.
Intelligent discretion stays within approved behavior and specialist boundaries.
The Orchestrator classifies failure from evidence, including baseline, hidden
dependency, environment and permission failures; no automatic capability
escalation or mandatory Luna-then-Sol chain. Both writers obey the existing
lane-specific checks/TDD/status guarantees and never independently review.

## Build Loop

For light work, implement the carried Discover scope/criteria or the inline plan
when `plan_mode=inline`, run selected checks and binding project checks, and record the
changed scope plus results in the inline packet. Then perform the compact fresh
self-review. Do not create worker or
independent-review dispatch evidence solely to satisfy the light lane.

For medium+ tasks with slices, execute source-changing slices sequentially in a shared or unknown workspace. Independently executable source-changing slices may overlap only when runtime evidence proves isolated workspaces. Each slice is the unit of implementation and verification.

Before starting a slice:

1. Load the approved task packet for the slice, including slice_id, observable
    increment, deliverable type, files, acceptance criteria, unchanged verification
   decision, selected checks, each command's literal argv/cwd bound by its
   check_id or its concrete non-command procedure, expected
   success signal, evidence to record, and deviation/rollback rule.
2. When harness-capable, confirm the task packet carries `done_contract_ref`,
   `harness_recipe_ref`, `harness_run_state_ref`, `trace_ledger_ref`,
   `replay_packet_ref`, and typed `artifact_refs`.
3. Confirm every `depends_on` prerequisite has final status `VERIFIED` before starting a dependent slice. In a shared or unknown workspace, do not start another source-changing slice while the active source-changing slice is unverified.
4. For concurrent source-changing slices, confirm runtime evidence proves their
   workspaces are isolated and their packets are independently executable.
5. Check constraints from the task journal against the slice files and criteria.

For each step, dispatch the selected lane owner for one task packet at a time
per worker. In active TDD, the bounded executor records actual RED, production,
GREEN, REFACTOR, and separate phase invocations in one canonical cycle log.
Active separated TDD first dispatches the selected writer `worker_stage=test_authoring` for selected tests only, without incoming RED. Stage-only DONE cannot complete Build or permit Review. Then dispatch Builder/Tester `pre_production_red` on those already authored tests, carrying
its typed RED and `tdd_cycle_log_ref` to the SAME Code Writer `worker_stage=production` for production, then uses
Builder/Tester `final_verification` for GREEN. Only after GREEN passes does the
same Code Writer `worker_stage=refactor` own REFACTOR; a second `final_verification` records separate
REFACTOR invocations. A GREEN-only return is partial with REFACTOR pending, not
final Build evidence. Inactive TDD runs the selected checks without adding a
RED step. Direct fallback follows the same selected lane. Never edit production
before observed meaningful RED when that packet applies TDD, refactor before
passing GREEN, or invent unstarted phase evidence.

For `separated_workers`, retain each worker's actual `changed_files` in its
dispatch result, including designated generated outputs/evidence logs and any prohibited authored mutations even when that worker later returns a failure. Builder/Tester is execution-only: no authored source, tests, fixtures, snapshots, helpers or test/build configuration. Route all fixes to the selected writer. Report prohibited mutations as DEVIATED (other due failures retain precedence), never suppress or silently restore them. Prose and Bash access do not enforce OS-level prevention. Union the actual Builder/Tester and
Code Writer file mutations into final workflow `changed_files` and the Review
scope, while keeping each mutation attributed to its producing worker. Omit
entries only when the work did not change a file; never invent or reassign a
worker's changes.

If implementation or verification fails and the cause is unclear, return to
`assistant-debugging` before another patch attempt. If the next fix is clear,
route verification through the selected build_execution_lane: the bounded
executor retries and verifies its focused loop; inactive-TDD separated workers
dispatch Code Writer then Builder/Tester; direct fallback performs the same
selected-lane responsibilities. For active separated-worker TDD, the selected writer authors or repairs tests in test_authoring before Builder/Tester owns the
pre_production_red execution stage, the SAME Code Writer worker_stage=production consumes its unchanged typed RED before
production edits, then Builder/Tester owns final_verification for GREEN. After
that current GREEN passes, the same Code Writer handles REFACTOR and Builder/
Tester runs final_verification again for a distinct REFACTOR invocation.

For every Code Writer return, preserve actual changed implementation or test
files even when a later `NEEDS_CONTEXT`, `BLOCKED`, `DEVIATED`, or
`FAILED_VERIFICATION` status ends the attempt. Accumulate the worker's actual
changes across retries, keep Builder/Tester ownership separate, and omit file
entries only when that worker changed no file.

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

After all slices are integrated, run the selected checks and binding project checks over the completed scope before fresh Review. Do not add an unselected full suite. Cross-slice validation applies only when slice_manifest contains more than one item; when it contains one item, record cross-slice validation as not_applicable using the one-item manifest and single_slice_rationale. Single-slice validation still covers the selected integration claim. Per-slice verification does not satisfy a distinct selected integration check.

After each implementation step, apply the relevant SOLID check from
`references/prompts/solid-principles.md` and fix material violations before
moving on.

## Conditional TDD Boundary

The canonical `verification_decision.tdd_choice.mode` records the task-wide TDD
decision independently from verification scope and method. Each packet derives
`tdd_applies` from the intersection of its due `selected_check_ids` and
`tdd_choice.applicable_check_ids`. Task type alone never activates TDD. For
unknown-cause bugfixes, complete debugging first; enter RED only for applicable
selected checks and when a meaningful assertion can fail for the intended reason.

When TDD is active, establish meaningful RED before production; only packets
with `tdd_applies=true` require it, otherwise follow the selected checks
without adding a RED step. Other packets still run their due selected checks
without manufacturing RED. When task-wide TDD is false, no packet applies TDD.

For an active workflow TDD packet, the selected inline or separated RED owner
records the observed authorizing invocation in the canonical assistant-tdd
`cycle_log` and retains a `tdd_cycle_log_ref` that resolves to that in-progress
entry before Code Writer makes any production edit. The entry must bind the
sole selected/applicable check ID, exact CheckSpec argv and cwd, test file and
name, current failed result, and the matching `meaningful_failure` oracle. A
planned tuple or later passing result cannot substitute for the observed RED;
the cycle may remain in progress without GREEN or REFACTOR at this gate. Keep
prior cycle history and every actual invocation. Before Review and workflow
completion, resolve the same reference to the full canonical completed cycle
log and validate its GREEN, REFACTOR, and current selected-check evidence.

When the task packet carries an Architecture Decision Pack, carry its typed
`architecture_test_obligations` into the selected Build owner handoff. The
selected owner returns `architecture_obligation_coverage` with each stable
`obligation_id` exactly once; unknown or duplicate ids fail the Build evidence
gate rather than being inferred from a passing wrapper test.

- `bounded_executor`: when TDD is active, the bounded executor adds or extends
  one assertion, records the observed intended failure and actual production
  file, verifies GREEN, then makes refactor edits only after GREEN passes and
  records separate REFACTOR invocations; with false TDD it runs only the
  selected verification plan.
- `separated_workers`: when TDD is active, the selected writer first owns test_authoring for tests only without incoming RED; Builder/Tester returns one typed
  authorizing RED and its current log reference in `pre_production_red`, the SAME Code
  Writer owns production and records `green.production_file`, then Builder/
  Tester `final_verification` records actual GREEN invocations. GREEN may return
  stage-only DONE with aggregate partial and pending REFACTOR rows; after it
  passes, the same Code Writer owns actual refactor changes or `none needed`,
  and Builder/Tester performs a separate REFACTOR invocation in a second
  `final_verification`. Preserve the same reference and actual history; no
  phase may be inferred. Inactive TDD stays Code Writer then Builder/Tester.
  Only the complete current cycle closes Build or Review. Reused checks do not force new tests or authoring stages. Changes to test/target/argv/cwd/oracle invalidate authorizing RED: preserve old history and observe current RED before dependent production. Refactor requires current GREEN and its canonical cycle ref.

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

1. In `bounded_executor`, the executor executes each due CheckSpec's
   `command.argv` in its explicit `command.cwd` or follows its concrete
   non-command procedure, and reuses a completed passing verification only after comparing
   exact argv and cwd, complete passing result/log, relevant
   source/test/config/dependency state, toolchain and relevant non-secret
   environment, and covered acceptance obligations. When executing argv, item 0
   is the executable and each remaining item is one literal argument; never
   reconstruct a shell command. Then run relevant focused checks. Record the
   original run and current comparison in the existing validation evidence, with
   the decision to reuse; do not claim a newly executed verification. Dispatch
   Builder/Tester only when `build_execution_lane=separated_workers`; direct
   fallback performs the same selected-lane verification responsibility.
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
   marking the slice `VERIFIED` or starting a dependent slice.
7. Mark the slice `VERIFIED` only after all criteria pass and evidence is
   recorded.

Unknown identity, freshness, or coverage requires rerun. Rerun when argv or cwd
changes; relevant production, test, config, dependency, toolchain, or
environment input changes; the prior run failed, was partial, or was skipped;
the user explicitly requests a fresh run; mutable external state is involved;
new integration coverage is required; or source changes after a fix. A supported
unrelated-doc change may reuse evidence only with recorded input-boundary
evidence showing that the change is outside the verification inputs. In a shared
or unknown workspace, start another source-changing slice only after the active
source-changing slice is fully verified; start a dependent slice only after all
its `depends_on` prerequisites are verified.

After all slices are verified and concurrent outputs are integrated, run the
selected checks and binding project checks over the completed scope before
fresh Review; do not add an unselected full suite. Cross-slice validation
applies only when slice_manifest contains more than one item, and for one item
is recorded as not_applicable using the one-item manifest and
single_slice_rationale. A selected single-slice integration check covers its
claim; per-slice evidence does not satisfy a distinct selected integration
check.
If implementation reveals a plan problem, print `>> PLAN DEVIATION DETECTED`,
record `pivot_restart_decision.reapproval_required=true` when scope/files/
behavior/risk/verification/acceptance changes, and wait for approval before
continuing the changed path.
