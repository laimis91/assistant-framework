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
still executing every applicable logical phase and gate. Non-checkpoint wait,
deviation, dispatch, and verification signals remain explicit when applicable.

## Phase: Discover

Print: `--- PHASE: DISCOVER ---`

**Goal:** Zero untracked unknowns. No planning or coding until ambiguity is resolved.

For material that cannot be faithfully inspected in the current working context, load `references/context-budget-and-pattern-retrieval.md` before mapping. Record what stays exact, what is summarized, what is omitted/deferred, and whether the work must be split/delegated instead of stuffed into one context. Create a **Code Mapper** context map (see `references/context-map-template.md`) only when the candidate scope scan, public/ownership boundary, or changed files cannot be resolved directly from local source. Resolve `subagent_policy_state`, `subagent_execution_mode`, and `subagent_trigger_scope` before any requested/required subagent spawn; otherwise create the same compact map directly. The map covers likely modified areas and behaviorally relevant callers, consumers, tests, docs, contracts, config, generated mirrors, and runtime surfaces. If local state artifacts are configured and policy-allowed, persist the map to `{agent_state_dir}/context-map.md`; otherwise carry it in the plan/task packet. Trace deeper execution paths with Explorer only when an unresolved lifecycle, failure, coupling, or behavior question remains after the compact map. Size can signal likely work, but neither role is automatic ceremony.

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
- `Clarification question policy: every admissible material question; no numeric cap or quota`
- `Clarification admissibility: satisfied | needs_clarification | not_applicable`
- `Unresolved clarification topics:` as a markdown list
- `Controller intensity: light | standard | strict`
- `Architecture design mode: not_applicable | lightweight | required | review_intensive`
- `Architecture Decision Pack ref: [current ref or N/A with concrete reason]`
- `Search mode: none | lightweight | candidate_search`
- `Candidate archive: {agent_state_dir}/candidate-search.md | inline | N/A`

For tasks needing durable state, keep the task journal or equivalent carried-forward state for the full task lifecycle even when Discover resolves without a clarification wait. Size alone does not create a journal requirement.

Workflow state artifacts (`{agent_state_dir}/task.md`, `{agent_state_dir}/context-map.md`, `{agent_state_dir}/session.md`, and `{agent_state_dir}/working-buffer.md`) are framework-owned, ignored state when an agent state directory is configured and policy allows local state files. The orchestrator may create and update them directly. If state files are unavailable, carry the equivalent state in the response/plan packet. This exception never applies to project source, docs, tests, config, or generated app artifacts.

Discover does not complete while `Clarification status: needs_clarification`. Clarification waiting is a Discover substate, not a separate workflow phase.

Route prompt-level ambiguity that matches `assistant-clarify` first; clear
prompts do not invoke it. Then classify the remaining implementation
uncertainty. `uncertainty_shape=bounded` is the default: fully specified tasks
remain bounded, and size alone is not a trigger. Use
`uncertainty_shape=progressive` only when a not-yet-precise outcome-shaping
unknown is unlocked by a predecessor; then load
`references/progressive-discovery.md` before continuing Discover. Precise,
answerable questions and deterministic safe defaults stay in the existing
workflow clarification path.

For progressive mapping, resolving, route_clear, or blocked state,
`references/progressive-discovery.md` defines the no-execution boundary. The
only permitted local state update is the framework-owned journal/equivalent
carried-state update required to record progressive state; it never authorizes
project/source mutation or an external write. Do not enter Decompose, Plan, or
Build and do not run a mutating prerequisite in this substate; use a separate
approved workflow that returns evidence. After route clearance, return to
bounded Discover for the normal Requirement Acceptance Map and current gates.

Print: `>> Dispatching Code Mapper → context map` only when a context map is required and delegated mapping is selected.
Print: `>> Direct local context map` when a context map is required but mapping remains direct.
Print: `>> Dispatching Explorer` only when an unresolved execution/lifecycle question remains and delegated analysis is selected.
Print: `>> Direct execution-path trace` when that question remains but analysis stays direct.

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
5. For each unresolved implementation-shaping field, apply and record a deterministic safe default without asking when repository evidence, policy, or a stable local convention makes one available. Record topic, value, source, and rationale; set `Clarification defaults applied: true`. Ask every remaining admissible clarification, grouped by decision topic: the answer affects correctness, scope, behavior, data, public contract, security, migration safety, or verification; cannot be discovered from code/context; has no safe default; and includes the risk if guessed. There is no numeric question cap.
6. When `architecture_design_mode != not_applicable`, load `references/architecture-decision-pack.md` and create or refresh the typed pack from the context map. Its facts name source evidence; its assumptions and questions remain explicit; it records boundary ownership, Type Ledger, interface evolution, falsifiable quality scenarios, verification, and invalidation. Discover uses discover_only with context_or_journal_ref only and forbids future refs. For predecessor-unlocked design uncertainty, use the existing progressive decision map rather than a second architecture workflow.
7. Restate requirements in 1-3 sentences after clarification is resolved. For medium+, small work promoted by ambiguity, risk, or multiple material requirements, or small work with architecture_design_mode required/review_intensive, create the Requirement Acceptance Map from `references/requirement-acceptance-map.md`; otherwise use compact `acceptance_criteria`. Assign stable requirement ids only when the durable map applies.
8. Confirm or revise `Task type`, `Risk tier`, `Controller intensity`, `Plan mode`, `QA evaluation mode`, `Harness capable`, `Architecture design mode`, `Build execution lane`, `Workflow state mode`, `Required gates`, `Required agents`, `subagent_policy_state`, and `subagent_execution_mode` from the saved Triage metadata after reading code/context. Carry forward `qa_evaluation_mode`, `harness_capable`, `build_execution_lane`, and `workflow_state_mode` together; if discovery changes any of them, print `>> Re-triage required` and update the task journal before continuing.
9. For `task_type: bugfix`, classify `debugging_mode`: if root cause is unknown or the reproduction path is unclear, load and follow `assistant-debugging` before planning a fix. Carry forward its reproduction status, hypotheses, root cause/confidence, and residual risks. If `assistant-debugging` is unavailable or policy-disallowed, do direct hypothesis-driven debugging with the same evidence requirements and record the fallback path.

**Clarification format:**
```
Need to know
1. [Question]?
   Why needed: [correctness/scope/behavior/security/verification impact]
   Risk if guessed: [what could break]
   Safe default: none
   a) [Option]  b) [Option]  c) [Option]
   --> Recommendation: b because [reason]

Reply with: "1b 2a" or "defaults" (`defaults` accepts the displayed recommendations).
```

**Clarification state rules:**
- For any task entering clarification wait, if no task journal/state packet exists yet, create one when local state artifacts are configured and policy-allowed; otherwise include the same state in the response before printing clarification questions or the clarification wait message.
- There is no question cap or quota. A well-specified task can and should record `Clarification questions asked: 0`; when questions are needed, ask every admissible material decision and group them by topic rather than truncating the set.
- Before printing questions, keep the workflow `Status` in Discover, update the task journal to `Clarification status: needs_clarification`, preserve the existing `Clarification defaults applied` value and recorded default entries, set `Clarification confidence: low | medium`, `Clarification questions asked: N`, `Clarification admissibility: needs_clarification`, and list only topics with no deterministic safe default.
- Print: `>> WAITING: Clarification answers required`
- Stop after the wait message. Do not continue into Decompose or Plan while clarification is pending.
- On resume, accept only:
  - explicit question/option answers covering the open question ids (example: `1b 2a`)
  - explicit `defaults`
- Do not infer answers from free-form continuation text.
- Every implementation-shaping field that is still unresolved must appear in `Unresolved clarification topics` until it is answered or a displayed recommendation is explicitly accepted.
- Treat clarification as pending whenever unresolved clarification topics are non-empty, even if `Clarification status` was previously recorded as `ready`.
- If the reply is `defaults`, record it as explicit compatibility acceptance of the displayed recommendations, not as an automatically applied safe default. Preserve `Clarification defaults applied` based only on recorded deterministic safe defaults, clear the answered topics, and set `Clarification status: ready`.
- If the reply is explicit answers, record the chosen options, preserve `Clarification defaults applied` based on recorded safe defaults, clear the answered topics, and set `Clarification status: ready`.
- If no questions are needed, record `Clarification status: ready`, `Clarification defaults applied: true` when safe defaults were recorded (otherwise false), `Clarification confidence: high`, `Clarification questions asked: 0`, `Clarification admissibility: not_applicable`, and explain what code/context or defaults made the task clear.

**Rules:**
- No commands, edits, or plans that depend on unknowns
- Read-only discovery (search, git log, browsing) is allowed
- Keep interaction concise by resolving one goal or file-oriented decision at a time, not by suppressing material questions.

Print: `--- PHASE: DISCOVER COMPLETE ---`

## Phase: Decompose

Print: `--- PHASE: DECOMPOSE ---`

**Goal:** Break the problem into the smallest iterable slices that can each be built, tested, reviewed against acceptance criteria, and verified before moving to the next slice.

A slice is not a layer, folder, module, broad feature bucket, setup step, or broad architectural component. It is the smallest deliverable increment that produces observable behavior, artifact output, contract surface, docs, eval coverage, config, migration, or refactor evidence.

**Skip condition:** Small tasks skip this phase entirely — they ARE the atomic unit.

**Entry rule:** Medium+ tasks do not enter Decompose until Discover has persisted `Clarification status: ready` and `Clarification defaults applied: true | false` is explicitly recorded.

When decomposition is needed because the task has multiple coherent slices, a Pack-backed boundary, or unresolved cross-slice acceptance risk, produce bounded slice boundaries from the context map, Requirement Acceptance Map, risk tier, required gate packs, Context Budget note, and the Architecture Decision Pack when it applies. Every slice names the requirement ids it advances. Dispatch **Architect** only when `subagent_execution_mode=delegated`; otherwise perform the same direct design work with equivalent criteria and evidence. The Architect consumes the Pack rather than recreating its facts, and each affected slice carries the Pack reference. Task size can signal possible decomposition, but never creates an Architect role by itself. When editing framework skills, contracts, evals, runtime integrations, or workflow patterns, retrieve similar local patterns first and record the canonical pattern path plus any counterexample/edge case checked.

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
- **Verification command:** `["executable", "arg1", "arg2"]` (canonical argv; one literal argument per item, no shell parsing)
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

**Run condition:** `plan_mode` is `inline` or `approval_required`. For
`prepare_only`, this is optional readiness planning and never waits for
implementation approval. When
`plan_mode=none` with `execution_intent=prepare_only`, Discover carries the
evidence ref and readiness implications directly to Preparation Completion;
do not create a Plan checkpoint, task-packet/execution refs, or
`plan_document`. For `plan_mode=none` with `execution_intent != prepare_only`,
Discover carries the obvious file scope, constraints, acceptance check, and
verification argv into its exit transition, which atomically sets
`handoff_binding_state=downstream_bound` with compact inline
task-packet/execution and inline review-scope refs before any Build action.

Print: `--- PHASE: PLAN ---`

**Goal:** Concrete, reviewable implementation plan for execution work, or a
bounded evidence-backed readiness plan for `prepare_only`.

Architect implementation blueprint and dispatch apply only when `execution_intent != prepare_only`. For that execution lane, when `architecture_design_mode` is `required` or `review_intensive`, or when a concrete unresolved boundary cannot be represented by the ordinary plan, produce an Architect-level implementation blueprint from existing patterns and the compact map. Dispatch **Architect** only when delegation is explicitly requested or otherwise applicable; otherwise perform the same bounded design work directly. Do not introduce an Architect role merely because the task is large.

For `prepare_only`, prepare_only does not create an implementation blueprint or dispatch **Architect** for implementation. It may retain current source-backed Architecture Decision Pack and readiness evidence without executable implementation artifacts.

Print: `>> Dispatching Architect` (when `execution_intent != prepare_only` and `subagent_execution_mode=delegated`)
Print: `>> Direct fallback Architect responsibility` (when `execution_intent != prepare_only` and `subagent_execution_mode=direct_fallback`)

**Entry rule:** Do not enter Plan while the saved clarification state is pending. Resume Plan only after Discover records `Clarification status: ready` and all implementation-shaping fields are explicit, automatically safe-defaulted with evidence, or explicitly accepted from a displayed recommendation. When architecture design applies, the Architecture Decision Pack must also be fresh for the current revision and have no unresolved blocking material questions.

For `prepare_only`, record only the evidence ref, readiness implications, open decisions, and recommended next implementation state. prepare_only readiness plans omit Artifact Contracts, executable implementation steps/task packets, and Done/Harness artifacts. They do not load implementation packet or harness planning requirements.

For `execution_intent != prepare_only`, Artifact Contracts, implementation steps/task packets, and Done/Harness guidance apply. Before writing that plan, load `references/artifact-first-output-contract.md` and define the Artifact Contract: artifact type, required files/deliverables, output format/schema, acceptance criteria, verification command or method, expected success signal, owner/consumer, and non-goals. Carry forward the exact Triage values separately: `qa_evaluation_mode`, `harness_capable`, `build_execution_lane`, and `workflow_state_mode`. When `architecture_design_mode != not_applicable`, load `references/architecture-decision-pack.md` and put its typed reference, semantic type commitments/primitive exceptions, quality verification, compatibility strategy, and reviewer scope into the plan and affected task packets. Apply `references/workflow-controller.md` for shared routing/default decisions. When `harness_capable=true`, load `references/harness-controller.md` plus `references/plan-harness-appendix.md`, then add compact Done Contract, Harness Recipe, Harness Run State, Trace Ledger, Replay Packet, and Artifact Reference Ledger refs before task packets. Then read `references/plan-template.md` and use the correct tier:
- `inline`: compact small plan (goal, files, risks, tests); do not wait.
- `approval_required` medium: standard plan (drop Security/Operability unless the task touches auth, PII, payments, or infra).
- `approval_required` large/mega: full plan (all sections including Security and Operability).

For `execution_intent != prepare_only`:

1. Research codebase: modules, patterns, entrypoints
2. Evaluate architecture proportionally: use the Architecture Decision Pack when triggered, otherwise record a concrete not-applicable reason; review_intensive carries independent challenge evidence into Plan and Review.
3. Analyze only genuine viable options with tradeoffs; use one evidenced path when alternatives are not real
4. Identify risks and edge cases
5. Put the Artifact Contract before task packets and map every medium+ task packet to at least one required artifact or acceptance criterion
6. For medium+ harness-capable work, put compact refs for Done Contract, Harness Recipe, run-state/trace/replay artifacts, and Artifact Reference Ledger before Build; load `references/plan-harness-appendix.md` for the full schemas. The base plan keeps `N/A: [reason]` for non-harness work.
7. For medium+ tasks: consume the Decompose slice manifest directly in the plan and align each task packet to exactly one slice_id without rediscovering boundaries
8. Write ordered implementation steps with file paths
9. For large/mega: fill in Security and Operability sections. For medium: only if the task touches auth, PII, payments, or infra (promote to Full tier per plan-template.md)
10. Carry `Task type`, `Risk tier`, `Controller intensity`, `Plan mode`, `qa_evaluation_mode`, `harness_capable`, `build_execution_lane`, `workflow_state_mode`, `Required gates`, `Required agents`, `subagent_policy_state`, `subagent_execution_mode`, `subagent_trigger_scope`, and `Search mode` into the plan. Each required gate must map to task packet criteria or explicit N/A rationale.
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

For `execution_intent=prepare_only`, record the optional readiness plan, return the required preparation evidence, and continue to Preparation Completion without waiting for implementation approval. Print: `--- PHASE: PLAN COMPLETE ---` when this optional Plan runs.

For `execution_intent != prepare_only` and `plan_mode=inline`, print the inline plan and continue directly to Build. If ambiguity, user-requested approval, destructive operations, public contract/data/security impact, or scope-changing choices appear, return to Triage and promote to `approval_required`.

For `execution_intent != prepare_only` and `plan_mode=approval_required`, print: `>> WAITING: Plan approval required`

Present the plan and WAIT:
```
Review the plan:
- "approved" -- I'll start implementation
- "approved with changes: [list]" -- I'll update first
- Questions -- I'll address before proceeding
```

Print: `--- PHASE: PLAN COMPLETE (approved) ---` for non-prepare-only approval-required plans, or `--- PHASE: PLAN COMPLETE ---` for non-prepare-only inline plans.

## Phase: Design (UI/UX only, skip for backend)

**Run condition:** `execution_intent != prepare_only`.

Print: `--- PHASE: DESIGN ---`

1. Define design direction (tone, palette, typography)
2. Propose design system (CSS variables, components)
3. Create visual mockup (HTML artifact)
4. Production checklist: states, responsive, accessibility

Print: `>> WAITING: Design approval required`

Show mockup and WAIT for approval.

Print: `--- PHASE: DESIGN COMPLETE (approved) ---`

## Phase: Build

**Run condition:** `execution_intent != prepare_only`.

Print: `--- PHASE: BUILD ---`

When `workflow_state_mode=journal`, create the task journal using
`references/task-journal-template.md` and keep it current through Build. When
`workflow_state_mode=inline`, keep carried Discover scope/criteria, any
applicable plan, and evidence in the active packet without creating a journal.
For cross-session handoffs when no task
journal exists, use `references/context-handoff-templates.md` and its context
engineering contract: preserve pinned context exactly, summarize compressible
logs/reasoning, prune stale or unsafe residue, and end with the exact next
action.

Capture **constraints** from Discovery/Plan (e.g. "don't touch ProjectA", "stay on .NET 8"). Check constraints before each step.

Load `references/build-worker-protocol.md` for source-changing Build work. It
owns delegated/direct fallback execution, Code Writer and Builder/Tester
evidence, the TDD sandwich, Code Writer unexpected blockers, and per-slice
verification. It also owns the ordinary bounded repair state with three total
same-scope attempts and a two-attempt no-progress limit. Silent fallback cannot
complete.

For medium+ harness-capable work, confirm the task journal or carried-forward
plan has compact refs for an accepted Done Contract, selected Harness Recipe,
Harness Run State, Trace Ledger, Replay Packet, and Artifact Reference Ledger
before dispatching Code Writer or Builder/Tester. Load
`references/harness-runtime-artifacts.md` for runtime artifact updates and
`references/task-journal-harness-appendix.md` for full schemas. If any required
ref is missing, stop Build and return to Plan or repair state using
`references/harness-controller.md` and `references/harness-runtime-artifacts.md`.

For medium+ tasks with slices, execute one slice at a time from the approved task
packet. Print `>> Slice [S]/[total]: [slice_id] [name]`. In
`bounded_executor`, the bounded executor owns edit, RED, GREEN, and focused
verification. In `separated_workers`, run Code Writer then Builder/Tester.
Verify each acceptance criterion, record lane-matched slice ledger evidence,
and mark the slice `VERIFIED` before advancing.

For `controller_intensity=light`, implementation may run inline/direct. Use the
plan-step loop with `workflow_state_mode=inline`,
`subagent_policy_state=not_required`, and
`subagent_execution_mode=not_applicable`; record relevant automated
build/test/validation evidence and skip Code Writer, Builder/Tester, Code
Reviewer/Reviewer dispatch evidence. Skip task journal, slice ledger, metrics,
and manual verification ceremony unless an independent mode explicitly requires one.

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

**Run condition:** `execution_intent != prepare_only`.

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
   load and follow `assistant-review` SKILL.md and contracts. When an Architecture Decision Pack applies, pass its fresh compact review projection, including design-pressure checks, and require `architecture_decision_pack_review_required=true`; assistant-review then owns the checklist result. Add Code Reviewer
   to `Required agents` before Stage 2; assistant-review solely owns Reviewer
   and QAEvaluator packet schemas and any Reviewer compatibility routing.
3. Print `>> Stage 3: QA Evaluation - loading assistant-review references/qa-evaluation-loop.md` only when QA is required.

After review, enforce the applicable status gate and write `review_result` as
validated canonical assistant-review result/delegation refs plus
`architecture_decision_pack_review_ref` when a Pack applies and the
Verification Summary. Review owns independent reviewer evidence; it does
not create the developer handoff. Wait only when `manual_verification_mode=required`; optional manual
steps do not block and `not_required` proceeds directly to Document.

Print: `--- PHASE: REVIEW COMPLETE ---`

## Phase: Document

**Run condition:** `execution_intent != prepare_only`.

Print: `--- PHASE: DOCUMENT ---`

Load `references/completion-controller.md` and, for medium+ work,
`references/final-handoff.md`. They own small/full Document paths,
metrics JSON format, final harness refresh, the sole developer handoff creation
step, and Verified Skill Distillation routing.

Use the controller-intensity path and the completion modes. Metrics remain
optional and non-blocking. Refresh harness runtime artifacts only when
`harness_capable=true`.

Print: `--- PHASE: DOCUMENT COMPLETE ---`
Print: `--- WORKFLOW COMPLETE ---`

## Phase: Preparation Completion

**Run condition:** `execution_intent=prepare_only` after Discover. Optional
readiness planning does not create executable packets or delay completion.
Print: `--- PHASE: PREPARATION COMPLETION ---` before the completion checks and
`--- PHASE: PREPARATION COMPLETE ---` after they pass. These exact markers are
declared by `contracts/phase-gates.yaml`; do not derive a synthetic
`PREPARATION_COMPLETION COMPLETE` marker.
Return `completion_policy`, `validation_results`, and `feature_preparation_result`
as required by PC1 and the `preparation_only` completion tier, plus complete
`feature_preparation_evidence` for existing-system work. Keep execution
`not_started`; do not claim Build, changed files, tests, review, final handoff,
or implementation documentation.
