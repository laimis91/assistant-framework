# Workflow Phases — Detailed Instructions

Loaded on demand by the orchestrator during each phase. Read only the phase you're executing.

## Shared Controller Decisions

Load `references/workflow-controller.md` before phase-specific detail whenever
the task needs shared routing/default, movement, harness, review, QA, or
subagent separation decisions. This file owns phase execution mechanics; the
controller reference owns decision boundaries and ordinary workflow defaults.

## Progress Updates

Phase markers are required only for `controller_intensity=strict`, explicit
project policy, or a user request. For light and standard work, translate every
`Print:` checkpoint example below into a concise natural progress update while
still executing every logical phase and applicable gate. Non-checkpoint wait,
deviation, dispatch, and verification signals remain explicit when applicable.

## Phase: Discover

Print: `--- PHASE: DISCOVER ---`

**Goal:** Zero untracked unknowns. No planning or coding until ambiguity is resolved.

For medium+ tasks or large review/research inputs, load `references/context-budget-and-pattern-retrieval.md` before mapping. Record what stays exact, what is summarized, what is omitted/deferred, and whether the work must be split/delegated instead of stuffed into one context. Resolve `subagent_policy_state`, `subagent_execution_mode`, and `subagent_authorization_scope` before spawning any subagent. For medium+ tasks, add Code Mapper to `Required agents` and produce a **Code Mapper** context map (see `references/context-map-template.md`) by dispatching Code Mapper only when `subagent_execution_mode=delegated`; otherwise produce the same map directly in fallback mode and record Code Mapper direct evidence. The Code Mapper maps likely modified areas and behaviorally relevant references: callers, consumers, tests, docs, contracts, config, generated mirrors, hooks, and runtime surfaces that can affect or describe the change. The Code Mapper returns context map markdown; if local state artifacts are configured and policy-allowed, the orchestrator persists that markdown to `{agent_state_dir}/context-map.md`. Otherwise, carry the context map forward in the plan/task packet. Code Writer and Architect use the map instead of re-exploring the codebase. For large/mega tasks, also add Explorer to `Required agents` and trace execution paths with Explorer in delegated mode or direct fallback in non-delegated mode.

When `workflow_state_mode=journal`, create or update
`{agent_state_dir}/task.md` during Discover when local state artifacts are
configured and policy-allowed. Journal mode is selected for clarification
waits, delegated work, cross-session/compaction persistence, explicit durable
state, strict work, harness work, or required QA. Otherwise keep the same state
inline before printing clarification questions or any wait. Medium+ size alone
does not require a task journal. Persist:
- `Clarification status: ready | needs_clarification`
- `Clarification defaults applied: true | false`
- `Clarification confidence: low | medium | high`
- `Clarification questions asked: N`
- `Clarification question cap: N` where the cap is a maximum, never a quota
- `Clarification admissibility: satisfied | needs_clarification | not_applicable`
- `Unresolved clarification topics:` as a markdown list
- `Controller intensity: light | standard | strict`
- `Search mode: none | lightweight | candidate_search`
- `Candidate archive: {agent_state_dir}/candidate-search.md | inline | N/A`

For medium+ tasks, keep the task journal or equivalent carried-forward state for the full task lifecycle even when Discover resolves without a clarification wait.

Workflow state artifacts (`{agent_state_dir}/task.md`, `{agent_state_dir}/context-map.md`, `{agent_state_dir}/session.md`, and `{agent_state_dir}/working-buffer.md`) are framework-owned, ignored state when an agent state directory is configured and policy allows local state files. The orchestrator may create and update them directly. If state files are unavailable, carry the equivalent state in the response/plan packet. This exception never applies to project source, docs, tests, config, or generated app artifacts.

Discover does not complete while `Clarification status: needs_clarification`. Clarification waiting is a Discover substate, not a separate workflow phase.

Print: `>> Dispatching Code Mapper → context map` (when `subagent_execution_mode=delegated`)
Print: `>> Direct fallback Code Mapper responsibility → context map` (when `subagent_execution_mode=direct_fallback`)
Print: `>> Dispatching Explorer` (when `subagent_execution_mode=delegated`)
Print: `>> Direct fallback Explorer responsibility` (when `subagent_execution_mode=direct_fallback`)

1. Read repo: README, CLAUDE.md, AGENTS.md, key files. Batch independent file reads/searches when the active tool policy supports parallel calls; use sequential reads otherwise.
2. Compare current state against request
3. **Recall lessons when relevant**: Recall prior lessons only when they can materially affect the current task, such as after a user correction, task recovery, or a request that depends on earlier project decisions. Incorporate high-confidence matches into constraints; otherwise skip memory retrieval.
   Print: `>> Found [N] relevant lessons from past tasks` only when recall ran and returned useful context.
4. **Agent readiness check** (medium+ tasks): Quick scan of the project environment. Score 0-5:
   - Linter config present? (eslint, .editorconfig, analyzers, etc.)
   - Build scripted/documented? (CI, Makefile, documented `dotnet build` command, etc.)
   - Test suite exists? (any test project or test files)
   - `CLAUDE.md` or `AGENTS.md` exists? (agent can orient itself)
   - Observability in place? (logging, telemetry, health checks)
   Print: `>> Agent readiness: [N]/5` followed by any gaps found.
   If score ≤ 2: recommend fixing environment gaps before feature work. The agent isn't broken — the environment is.
5. Ask structured clarification Q&A with recommendations for any unresolved implementation-shaping field only when the question is admissible. Admissible means the answer affects correctness, scope, behavior, data, public contract, security, migration safety, or verification; cannot be discovered from code/context; has no safe default; and includes the risk if guessed.
6. Restate requirements in 1-3 sentences after clarification is resolved
7. Confirm or revise `Task type`, `Risk tier`, `Controller intensity`, `Required gates`, `Required agents`, `subagent_policy_state`, and `subagent_execution_mode` from the saved Triage metadata after reading code/context. If discovery changes any of them, print `>> Re-triage required` and update the task journal before continuing.
8. For `task_type: bugfix`, classify `debugging_mode`: if root cause is unknown or the reproduction path is unclear, load and follow `assistant-debugging` before planning a fix. Carry forward its reproduction status, hypotheses, root cause/confidence, and residual risks. If `assistant-debugging` is unavailable or policy-disallowed, do direct hypothesis-driven debugging with the same evidence requirements and record the fallback path.

**Clarification format:**
```
Need to know
1. [Question]?
   Why needed: [correctness/scope/behavior/security/verification impact]
   Risk if guessed: [what could break]
   Safe default: [default, or "none"]
   a) [Option]  b) [Option]  c) [Option]
   --> Recommendation: b because [reason]

Reply with: "1b 2a" or "defaults".
```

**Clarification state rules:**
- For any task entering clarification wait, if no task journal/state packet exists yet, create one when local state artifacts are configured and policy-allowed; otherwise include the same state in the response before printing clarification questions or the clarification wait message.
- Question caps are maximums, not quotas. Small tasks usually ask 0-1 questions; medium tasks may ask 0-4; large/mega tasks may ask more only when each question is admissible. A well-specified medium+ task can and should record `Clarification questions asked: 0`.
- Before printing questions, keep the workflow `Status` in Discover, update the task journal to `Clarification status: needs_clarification`, `Clarification defaults applied: false`, `Clarification confidence: low | medium`, `Clarification questions asked: N`, `Clarification question cap: N`, `Clarification admissibility: needs_clarification`, and list each unresolved implementation-shaping topic.
- Print: `>> WAITING: Clarification answers required`
- Stop after the wait message. Do not continue into Decompose or Plan while clarification is pending.
- On resume, accept only:
  - explicit question/option answers covering the open question ids (example: `1b 2a`)
  - explicit `defaults`
- Do not infer answers from free-form continuation text.
- Every implementation-shaping field that is still unresolved must appear in `Unresolved clarification topics` until it is answered or explicitly defaulted.
- Treat clarification as pending whenever unresolved clarification topics are non-empty, even if `Clarification status` was previously recorded as `ready`.
- If the reply is `defaults`, print the defaults being applied, set `Clarification defaults applied: true`, clear the unresolved topics list, and set `Clarification status: ready`.
- If the reply is explicit answers, record the chosen options, set `Clarification defaults applied: false`, clear the unresolved topics list, and set `Clarification status: ready`.
- If no questions are needed, record `Clarification status: ready`, `Clarification confidence: high`, `Clarification questions asked: 0`, `Clarification admissibility: not_applicable`, and explain briefly what code/context made the task clear.

**Rules:**
- No commands, edits, or plans that depend on unknowns
- Read-only discovery (search, git log, browsing) is allowed
- Small tasks: 0-1 questions. Mega: full Q&A.

Print: `--- PHASE: DISCOVER COMPLETE ---`

## Phase: Decompose

Print: `--- PHASE: DECOMPOSE ---`

**Goal:** Break the problem into the smallest iterable slices that can each be built, tested, reviewed against acceptance criteria, and verified before moving to the next slice.

A slice is not a layer, folder, module, broad feature bucket, setup step, or broad architectural component. It is the smallest deliverable increment that produces observable behavior, artifact output, contract surface, docs, eval coverage, config, migration, or refactor evidence.

**Skip condition:** Small tasks skip this phase entirely — they ARE the atomic unit.

**Entry rule:** Medium+ tasks do not enter Decompose until Discover has persisted `Clarification status: ready` and `Clarification defaults applied: true | false` is explicitly recorded.

For medium+ tasks, produce Architect-level slice boundaries based on the context map, requirements, risk tier, required gate packs, and the Context Budget note. Dispatch **Architect** only when `subagent_execution_mode=delegated`; otherwise perform direct fallback with equivalent criteria and evidence. When editing framework skills/contracts/evals/hooks, retrieve similar local patterns first and record the canonical pattern path plus any counterexample/edge case checked.

Print: `>> Dispatching Architect → strict slice decomposition` (when `subagent_execution_mode=delegated`)
Print: `>> Direct fallback Architect responsibility → strict slice decomposition` (when `subagent_execution_mode=direct_fallback`)

### Decomposition rules

1. **One or more valid slices** — use exactly one slice when that is the smallest iterable increment and record the single-slice rationale.
2. **Reject broad splits** — layer-only, module-only, folder-only, feature-only, setup-only, contract-only, and broad component-style decomposition is invalid as live Decompose output unless the slice is a verified deliverable artifact.
3. **No setup-only slices** — contract-only, config-only, migration-only, docs-only, eval-only, or refactor-only work is valid only when it is the deliverable artifact slice and has acceptance criteria plus verification evidence.
4. **Each slice must be independently verifiable** — if you cannot write a binary pass/fail check and expected success signal for it, it is not a slice.
5. **Order by dependency** — independent slices first, dependent slices after every `depends_on` prerequisite.
6. **No circular dependencies** — if two slices require each other to become observable, merge them into the smallest single iterable slice.
7. **Gate packs become criteria** — every required task-category gate must appear in at least one slice or in the plan-level verification criteria.

### Slice manifest format

```
## Slice Manifest

### Slice [slice_id]: [name]
- **Observable increment:** [behavior, artifact, contract, docs, eval, config, migration, or refactor output this slice makes visible]
- **Deliverable type:** behavior | artifact | contract | docs | eval | config | migration | refactor
- **Acceptance criteria:**
  - [ ] [Binary pass/fail statement]
  - [ ] [Binary pass/fail statement]
- **Files to create:** [exact paths or "none"]
- **Files to modify:** [exact paths or "none"]
- **Files to test:** [exact test paths or verification targets]
- **Enabling changes included:** [setup, contracts, wiring, or "none"]
- **Depends on:** [slice ids, or "none"]
- **Verification command:** [exact command or inspection method]
- **Expected success signal:** [specific passing output, file, or review signal]
- **Evidence to record:** [ledger/eval/test/review artifacts]
- **Deviation rollback rule:** [what to do if scope/files/behavior differ]

Single-slice rationale: [required when the manifest has exactly one slice]
```

### Verification criteria rules

Each criterion must be:
- **Binary** — pass or fail, no "partially done"
- **Observable** — can be checked by running a test, a build, or inspecting output
- **Specific** — "endpoint returns 200 for valid input" not "endpoint works"

Good: `[ ] GET /api/items returns 200 with JSON array`
Bad: `[ ] API works correctly`

### Decomposition Plan Review

Before leaving Decompose for medium+ work, load `references/decomposition-plan-review.md` and review the slice/subagent plan. Record the Decomposition Plan Review packet: Broad-split rejection, scope understanding, slice/subagent count sanity, step/cost budget, dependency order, output-plan match, fallback path, and decision (`proceed`, `revise_decomposition`, or `return_to_discover`). Broad-split rejection must explicitly prove broad layer/module/folder/feature/setup/contract/component splits were rejected unless they are verified deliverable artifact slices. If the decision is not `proceed`, repair decomposition or return to Discover before Plan.

### Plan handoff

Persist the slice manifest and Decomposition Plan Review packet, then carry both into Plan. Do not wait for separate
slice approval in Decompose; the Plan approval gate covers the slice
manifest, decomposition review, implementation packets, file scope, verification criteria, and risks
together. If decomposition exposes ambiguity, scope expansion, or competing
valid approaches, return to Discover for clarification before planning.

Print: `--- PHASE: DECOMPOSE COMPLETE ---`

## Phase: Plan

Print: `--- PHASE: PLAN ---`

**Goal:** Concrete, reviewable implementation plan.

For large tasks, produce an Architect-level implementation blueprint from existing patterns and Code Mapper/Explorer output. Dispatch **Architect** only when `subagent_execution_mode=delegated`; otherwise produce the same blueprint directly in fallback mode.

Print: `>> Dispatching Architect` (when `subagent_execution_mode=delegated`)
Print: `>> Direct fallback Architect responsibility` (when `subagent_execution_mode=direct_fallback`)

**Entry rule:** Do not enter Plan while the saved clarification state is pending. Resume Plan only after Discover records `Clarification status: ready` and all implementation-shaping fields are explicit or explicitly defaulted.

Before writing the plan, load `references/artifact-first-output-contract.md` and define the Artifact Contract: artifact type, required files/deliverables, output format/schema, acceptance criteria, verification command or method, expected success signal, owner/consumer, and non-goals. Apply `references/workflow-controller.md` for shared routing/default decisions. When `harness_capable=true`, load `references/harness-controller.md` plus `references/plan-harness-appendix.md`, then add compact Done Contract, Harness Recipe, Harness Run State, Trace Ledger, Replay Packet, and Artifact Reference Ledger refs before task packets. Then read `references/plan-template.md` and use the correct tier:
- Small: inline plan (goal, files, risks, tests). Do not wait for approval unless risk, ambiguity, user instruction, or a scope-changing decision makes approval necessary.
- Medium: standard plan (drop Security/Operability unless the task touches auth, PII, payments, or infra)
- Large/Mega: full plan (all sections including Security and Operability)

1. Research codebase: modules, patterns, entrypoints
2. Evaluate architecture (see `playbooks/*.md` for project-type rules)
3. Analyze 1-3 options with tradeoffs, pick one
4. Identify risks and edge cases
5. Put the Artifact Contract before task packets and map every medium+ task packet to at least one required artifact or acceptance criterion
6. For medium+ harness-capable work, put compact refs for Done Contract, Harness Recipe, run-state/trace/replay artifacts, and Artifact Reference Ledger before Build; load `references/plan-harness-appendix.md` for the full schemas. The base plan keeps `N/A: [reason]` for non-harness work.
7. For medium+ tasks: consume the Decompose slice manifest directly in the plan and align each task packet to exactly one slice_id without rediscovering boundaries
8. Write ordered implementation steps with file paths
9. For large/mega: fill in Security and Operability sections. For medium: only if the task touches auth, PII, payments, or infra (promote to Full tier per plan-template.md)
10. Carry `Task type`, `Risk tier`, `Controller intensity`, `Required gates`, `Required agents`, `subagent_policy_state`, `subagent_execution_mode`, `subagent_authorization_scope`, and `Search mode` into the plan. Each required gate must map to task packet criteria or explicit N/A rationale.
11. If `search_mode: candidate_search`, load `references/candidate-search.md`, create the goal tree from acceptance/slice criteria, score candidates, record the archive location, and treat post-approval pivots as plan deviations requiring re-approval when scope/files/behavior/risk change.
12. Load prompt packs only when applicable:
   - Refactors: `references/prompts/refactor-safety.md`
   - Migrations/rewrites: `references/prompts/refactor-safety.md` plus any applicable migration or parity checklist
   - New code: `references/prompts/test-strategy.md`
   - DB changes: `references/prompts/migration.md`
   - Unknown-cause bugfix: use `assistant-debugging` first; only transition into TDD when reproduction/root-cause evidence can define a meaningful regression test.
   - TDD mode: use `assistant-tdd` skill (or `references/prompts/tdd-enforcement.md` if skill not installed)
   - **SOLID (plan phase):** Review `references/prompts/solid-principles.md` graduated enforcement table to fill SOLID design notes in the plan template's Architecture section (medium+ tasks).

### Approval gate

For small tasks, print the inline plan and continue directly to Build unless the task has unresolved ambiguity, user-requested approval, destructive operations, or scope-changing choices.

For medium+ tasks, print: `>> WAITING: Plan approval required`

Present the plan and WAIT:
```
Review the plan:
- "approved" -- I'll start implementation
- "approved with changes: [list]" -- I'll update first
- Questions -- I'll address before proceeding
```

Print: `--- PHASE: PLAN COMPLETE (approved) ---` for approved medium+ plans, or `--- PHASE: PLAN COMPLETE ---` for no-wait small plans.

## Phase: Design (UI/UX only, skip for backend)

Print: `--- PHASE: DESIGN ---`

1. Define design direction (tone, palette, typography)
2. Propose design system (CSS variables, components)
3. Create visual mockup (HTML artifact)
4. Production checklist: states, responsive, accessibility

Print: `>> WAITING: Design approval required`

Show mockup and WAIT for approval.

Print: `--- PHASE: DESIGN COMPLETE (approved) ---`

## Phase: Build

Print: `--- PHASE: BUILD ---`

When `workflow_state_mode=journal`, create the task journal using
`references/task-journal-template.md` and keep it current through Build. When
`workflow_state_mode=inline`, keep the approved plan and evidence in the active
packet without creating a journal. For cross-session handoffs when no task
journal exists, use `references/context-handoff-templates.md` and its context
engineering contract: preserve pinned context exactly, summarize compressible
logs/reasoning, prune stale or unsafe residue, and end with the exact next
action.

Capture **constraints** from Discovery/Plan (e.g. "don't touch ProjectA", "stay on .NET 8"). Check constraints before each step.

Load `references/build-worker-protocol.md` for source-changing Build work. It
owns delegated/direct fallback execution, Code Writer and Builder/Tester
evidence, the TDD sandwich, Code Writer unexpected blockers, and per-slice
verification. Silent fallback cannot complete.

For medium+ harness-capable work, confirm the task journal or carried-forward
plan has compact refs for an accepted Done Contract, selected Harness Recipe,
Harness Run State, Trace Ledger, Replay Packet, and Artifact Reference Ledger
before dispatching Code Writer or Builder/Tester. Load
`references/harness-runtime-artifacts.md` for runtime artifact updates and
`references/task-journal-harness-appendix.md` for full schemas. If any required
ref is missing, stop Build and return to Plan or repair state using
`references/harness-controller.md` and `references/harness-runtime-artifacts.md`.

For medium+ tasks with slices, execute one slice at a time from the approved task
packet. Print `>> Slice [S]/[total]: [slice_id] [name]`, run the
Code Writer -> Builder/Tester loop, verify each acceptance criterion, record
slice ledger evidence, and mark the slice `VERIFIED` before advancing.

For `controller_intensity=light`, implementation may run inline/direct. Use the
plan-step loop with `workflow_state_mode=inline`,
`subagent_policy_state=not_required`, and
`subagent_execution_mode=not_applicable`; record relevant automated
build/test/validation evidence and skip Code Writer, Builder/Tester, Code
Reviewer/Reviewer dispatch evidence. Skip task journal, slice ledger, metrics,
reflexion, memory, and manual verification ceremony unless an independent mode
explicitly requires one of them.

For bugfixes with unknown cause, complete `assistant-debugging` first or record
a concrete blocked/inconclusive debugging result. Do not patch until
reproduction/root-cause evidence identifies a fix target or mitigation. Tests
stay alongside code, not after.

After all slices are verified, run integration tests across slice boundaries.

**Loop-back rule:** If implementation reveals a plan problem, STOP:
```
>> PLAN DEVIATION DETECTED
Plan assumed: [X]. Reality: [Y].
Options: a) Adjust step [N]  b) Rethink approach
```

Never silently deviate from the plan. If the selected recovery action changes
approved scope, files, behavior, risk, verification, or acceptance criteria,
record `pivot_restart_decision.reapproval_required=true`, update harness runtime
artifacts when applicable, and wait for approval before continuing the changed
path.

Print: `>> Build complete — all [N] steps implemented`
Print: `>> Running final build + tests`
Print: `>> Build: [passed/failed] | Tests: [N passed, M failed]`

Print: `--- PHASE: BUILD COMPLETE ---`

## Phase: Review

Print: `--- PHASE: REVIEW ---`

Load `references/review-qa-router.md`. Light work uses its compact fresh-review
lane as a fresh self-review without worker or independent-review dispatch
evidence. Standard/strict work uses Stage 1 Spec Review and Stage 2 independent
Code Quality Review through `assistant-review`; Stage 3 QA Evaluation runs only
when `qa_evaluation_mode=required`.

For standard/strict work, run the stages in order:

1. Print `>> Stage 1: Spec Review`; load `references/prompts/spec-review.md`
   and require Spec Review PASS before quality review.
2. Print `>> Stage 2: Code Quality Review - loading assistant-review SKILL.md`;
   load and follow `assistant-review` SKILL.md and contracts. Add Code Reviewer
   to `Required agents` before Stage 2; use `Reviewer` only as compatibility
   routing.
3. Print `>> Stage 3: QA Evaluation - loading assistant-review references/qa-evaluation-loop.md` only when QA is required.

After review, enforce the applicable status gate and write the Verification
Summary. Wait only when `manual_verification_mode=required`; optional manual
steps do not block and `not_required` proceeds directly to Document.

Print: `--- PHASE: REVIEW COMPLETE ---`

## Phase: Document

Print: `--- PHASE: DOCUMENT ---`

Load `references/completion-controller.md`. It owns small/full Document paths,
Learning Controller fields, optional reflexion/memory behavior, metrics JSON
format, final harness refresh, and Verified Skill Distillation routing.

Use the controller-intensity path and the three completion modes. The Learning
Controller is required only when `learning_capture_mode=required`, or when
`auto` sees concrete review findings, build/test failures, user corrections, or
memory trend signals. Metrics, reflexion, and memory are optional/non-blocking.
Refresh harness runtime artifacts only when `harness_capable=true`.

Print: `--- PHASE: DOCUMENT COMPLETE ---`
Print: `--- WORKFLOW COMPLETE ---`
