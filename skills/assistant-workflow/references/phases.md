# Workflow Phases — Detailed Instructions

Loaded on demand by the orchestrator during each phase. Read only the phase you're executing.
Generated focused views in `references/phases/` are maintained by `tools/skills/sync-workflow-references.py`; this source remains authoritative fallback.

## Shared Controller Decisions

Load `references/workflow-controller.md` before phase-specific detail whenever
the task needs shared routing/default, movement, harness, review, QA, or
subagent separation decisions. This file owns phase execution mechanics; the
controller reference owns decision boundaries and ordinary workflow defaults.

For a behavior-bearing, cosmetic, or locality/shared-impact claim, load
`references/change-impact.md` before deciding the verification surface and record
compact applicability evidence. Only shared, materially unresolved, or
explicitly carried expanded work requires the common pre-build result and its
completion projection when `execution_intent != prepare_only`; prepare-only
work retains discovery applicability and artifact identity without implementation
completion claims. Evidenced local work keeps ordinary relevant verification, a
local self-check and fresh independent review without a Node gate. Shared fanout alone does not activate an
Architecture Decision Pack, strict controller, QA, or a different Build/delegation lane.

## Progress Updates

Phase markers are required only for `controller_intensity=strict`, explicit
project policy, or a user request. For light and standard work, translate every
`Print:` checkpoint example below into a concise natural progress update while
still executing every applicable logical phase and gate. Non-checkpoint wait,
deviation, dispatch, and verification signals remain explicit when applicable.

## Phase: Discover

Print: `--- PHASE: DISCOVER ---`

Resolve the intended outcome and material behavior before dependent planning or
coding. Read task-relevant repository guidance, source, callers, tests, and
configuration; compare current behavior with the request. Map files directly
when possible. Use Code Mapper only for unresolved scope/ownership boundaries,
and Explorer only for a remaining execution, lifecycle, failure, or coupling
question. Load `references/context-budget-and-pattern-retrieval.md` when the
material cannot be faithfully inspected in the current context.

Route unclear intent through assistant-clarify. For unknown-cause bugs, complete
assistant-debugging or retain its concrete blocked/inconclusive result before
choosing a repair. Recall lessons only when prior decisions or corrections can
materially affect this task. Check the environment needed for the work; a numeric
readiness score is not an implementation or completion gate.

Preserve an explicit reduced-testing instruction/source in accumulated task
constraints and verification `work_scope.source_refs`. Selection records the
qualitative boundary in `verification_decision.scope` and its exact source-bearing
instruction row in `evidence_assessment.scope_and_evidence_refs` (including planned
assessments; verification owns the row semantics), with important claims,
reuse/add rationale, exclusions, omissions and stop rule. Read existing assertions
first; do not invent a test count, all-layer default or TDD waiver. Surface
conflicting controlling checks with their sources; mandatory execution need not
mean new authoring.

### Requirements sufficiency

Distinguish requested intent, authoritative behavior, source-backed technical
defaults, proposed product assumptions, and unresolved choices. Inspect relevant
actor/data boundaries and behavior from initiation through cancellation/reversal,
including material failure/recovery paths. Missing or conflicting controlling
authority stays `evidence_gap`/`source_conflict`; do not invent it or reframe it as
a product preference. Internal fields/permissions do not establish policy for a
new audience or disclosure boundary.

Preserve authoritative behavior within its evidenced context. Apply only
source-backed technical defaults automatically, retaining topic, value, source,
and rationale in existing criteria/state. Ask every remaining material choice
that cannot be discovered or safely defaulted, grouped concisely with why it
matters, risk if guessed, and any proposed recommendation. No question quota or
universal questionnaire applies. Well-specified work needs no ritual question.
A recommendation, compatibility, reversibility, or Plan approval alone does not
settle intent. Keep unanswered choices and recommendations provisional; never
also record them as applied defaults or confirmed criteria.

Partial answers settle only answered choices. Explicit acceptance of displayed
recommendations (including `defaults`) is an answer, not an automatic technical
default. Free-form continuation alone is not an answer. Revisit dependent
choices when their predecessor is resolved. Record the accepted outcome before
dependent edits; an empty question list alone does not prove readiness.

### State and conditional discovery

Use `references/workflow-controller.md` for routing. When persisted state is
carried, reconcile newest intent and current source before trusting it. Use
`workflow_state_mode=journal` only for its actual waits, delegated execution,
continuation/persistence, strict, harness, or QA triggers; size alone is no trigger.
The existing `references/task-journal-template.md` owns the serialized fields.
When state files are unavailable or policy disallows them, retain equivalent
carried state. Framework-owned ignored state never authorizes project mutations.

Before asking/waiting, preserve clarification status, unresolved topics,
provisional recommendations, and actual technical defaults in that state.
For execution work, unresolved material topics mean `needs_clarification` and
prevent Decompose/Plan/Build. Once all are resolved, set `ready` and record the
request/source/default basis. Keep small clear checks inline without empty
field inventories. Medium+ or small work with material ambiguity/risk/multiple
requirements uses `references/requirement-acceptance-map.md`; otherwise compact
acceptance criteria suffice. Preserve stable IDs only where the map applies.

`uncertainty_shape=bounded` is default. Predecessor-unlocked outcome uncertainty
or retained progressive markers loads `references/progressive-discovery.md`.
Its mapping/resolving/route-clear/blocked substates are no-execution boundaries:
only framework-owned state updates are allowed. Mutating prerequisites use a
separate approved workflow that returns evidence. After clearance, resume bounded
Discover; completed task state alone does not archive retained progressive data.

When architecture is triggered, load `references/architecture-decision-pack.md`.
Retain current facts, material questions, ownership/lifecycle, design pressures,
Type Ledger/exceptions, quality evidence, compatibility, and invalidators.
Discover uses `discover_only` with `context_or_journal_ref` only; no future Plan
or Review refs. Use the existing progressive map for dependent design unknowns.

For existing-system preparation, every `implement_only`, or carried future
obligations, use `references/feature-preparation-evidence.md` before dependent
questions/Plan/Build. Preserve the exact approved result/source binding.
`prepare_only` may finish with open decisions in `feature_preparation_result`
and optional readiness context; do not claim readiness or start execution.
Keep QA/harness inactive and future obligations typed. It proceeds to Preparation
Completion, not implementation approval. Other execution intents wait for
remaining material answers before dependent work.

Confirm changed risk, approval, review, delegation, or verification routing from
actual source evidence; update carried state if the initial classification was
wrong. Before any required dispatch, resolve subagent policy/execution/trigger
scope through `references/subagent-dispatch.md`. No mapping/Architect role is
required merely by size.

Print: `--- PHASE: DISCOVER COMPLETE ---`

## Phase: Decompose

Run only when a concrete acceptance, ownership/context, prerequisite,
recovery/rollout or binding protocol purpose needs additional executable packets.
Coherent medium+ work goes directly to Plan with one packet; size alone does not
select multiple packets or Architect. Eligible light work remains direct.
Preparation-only and unresolved progressive discovery produce no executable work.

Resolve all applicable Discover exit assertions, the Requirement Acceptance Map,
current specialist verification decision and conditional Architecture Decision Pack
before refining boundaries. Every packet advances accepted requirement ids and
has observable deliverable, exact file scope, binary criteria, due CheckSpec ids,
exact binding tuples, success signal, evidence and deviation/rollback rule.
Layer-only, module-only, folder-only and broad feature/setup/component splits need
a concrete independently verifiable deliverable and execution purpose; enabling
work otherwise stays with its consuming outcome.

Refine `implementation_steps` directly using `references/plan-template.md`.
Dependencies name canonical `packet_id` values in prerequisite order; cycles,
unknown IDs and unresolved allocation block. Do not create a separate manifest,
single-item rationale or decomposition-review artifact. Ordinary Plan review
retains scope understanding, packet/agent count sanity, step/cost budget,
dependency order, criterion/check alignment, output-plan match and fallback.

Use Architect only for a concrete Pack/design uncertainty and applicable role
trigger; otherwise perform bounded refinement with equivalent evidence. Before
Plan fixes checks, preserve the unchanged assistant-verification decision and its
TDD choice. In the Architect Decompose handoff, carry the current canonical
`evidence_assessment` from selection/task state in its declared sibling when an
explicit reduced-testing instruction applies. Determine applicability from newest
authoritative instructions/task constraints, never from surviving rows; preserve
the exact source-bearing row even when planned. Reconcile missing/stale
provenance before dependent work without reconstructing it from scope prose.
With no applicable instruction the sibling may be omitted; any supplied canonical
assessment stays unchanged, including empty rows, without fabricating an
instruction. The row claims no execution/check closure, and planned is not
verification sufficiency. Store the decision's stable ref/full-object digest once
and derive local
`tdd_applies` from due selected IDs; multiple applicable TDD IDs require separate
packets. No boundary or packet count waives approval or downstream quality gates.

Carry the canonical collection into ordinary Plan approval; do not add a separate
Decompose approval wait.

## Phase: Plan

**Run condition:** `plan_mode` is `inline` or `approval_required`.

Print: `--- PHASE: PLAN ---`

For execution, enter only after material intent is settled and applicable Packs
are current with no blocking questions. `plan_mode=none` carries obvious scope,
criteria, constraints, and selected verification directly to Build; an applicable
Pack atomically binds compact task/execution and review refs as `downstream_bound`
at that pre-Build boundary. No synthetic plan is needed.

For `prepare_only`, Plan runs only when readiness planning was explicitly
requested, stays inline, and never waits for implementation approval. Preserve
open decisions and exact existing-system preparation evidence, or typed
`preparation_basis=not_applicable` without an invented evidence ref. Omit
Artifact Contracts, executable steps/packets, implementation blueprints, and
Done/Harness artifacts. Requested/required readiness plans receive fresh independent
review and fresh review after fixes; a review PASS grants no implementation approval.
Selected research lenses/peer retain their isolation. Load
`references/plans/prepare-only.md` and return to Preparation Completion.

### Execution plan

1. State the accepted outcome, affected files/consumers, concrete criteria,
   risks, and smallest implementation approach. Analyze alternatives only when
   they are viable. Preserve source-backed decisions and known limitations.
2. Use the existing Artifact Contract and plan views for a consumed executable
   plan: load `references/artifact-first-output-contract.md`, then
   `references/plans/<size>.md` (`mega` uses `large`). Missing/unknown views use
   authoritative `references/plan-template.md`. Inline small plans stay compact;
   medium uses Standard; large/mega uses Full. Preserve required Security and
   Operability content for the template's relevant risk/infra triggers.
3. Keep one canonical `implementation_steps` collection, with one coherent
   packet by default and only purpose-backed splits from Decompose. Map packets
   to accepted criteria/artifacts; preserve exact file ownership, prerequisites,
   checks, binding obligations, execution lane, and due `tdd_applies`. Bind the
   approved definition identity and run Plan admission with independently
   resolved authority. Do not create a second manifest.
4. Carry resolved routing fields in consumed plans/packets, including QA/harness,
   Build lane, state, approval, required gates/roles, delegation, and search.
   Do not print a field inventory for the human. Preserve the unchanged canonical
   verification decision and materialize it where consumers require it.
5. When architecture applies, retain the fresh Pack and its semantic types,
   primitive exceptions, design pressures, quality checks, compatibility, and
   reviewer scope. Plan atomically binds `downstream_bound` task/review refs
   before Build. Architect-level design is for a concrete unresolved Pack/boundary
   decision, not size alone; delegation follows its existing trigger.
6. Only `harness_capable=true` loads `references/harness-controller.md` and
   `references/plan-harness-appendix.md`; retain accepted Done Contract, Harness
   Recipe, runtime state/trace/replay, and Artifact Reference Ledger before Build.
   `search_mode=candidate_search` loads its reference; later material pivots need
   a new scope/approval decision.

Load only relevant prompt packs: `references/prompts/refactor-safety.md` for
refactor/parity risks, `migration.md` for DB/migration work, `test-strategy.md`
for selected automated checks, and `solid-principles.md` for applicable design
questions. Unknown causes use assistant-debugging first. Active packet TDD uses
assistant-tdd (or its available fallback) without changing task-wide `tdd_mode`.

### Approval gate

An inline bounded small plan proceeds without waiting. Medium+, risky,
destructive, public-contract/data/security, material architecture/scope, explicit
policy, or user approval triggers require `approval_required`. Before seeking
approval, a requested/required plan needs a validated fresh independent plan
review (PASS (compact) or CLEAN/ISSUES_FIXED (structured)) from a newly created reviewer through `assistant-review`
with `review_subject=plan`, bound to the current plan identity, as one fresh
`plan_coverage_and_feasibility` pass; a material plan fix gets one newly created
fresh re-review of the same perspective. Record the compact `plan_review_result`
(reviewer identity, PASS or finding rows, request/plan coverage, closure results)
unless persisted/executable admission applies, which keeps the structured plan
batch and review-tools validation. Then present the
concrete plan and wait before Build. Reuse existing approval for its unchanged
scope; a material change returns to Discover/Plan and reapproval as needed.
A readiness plan authorizes no implementation.

Print: `--- PHASE: PLAN COMPLETE ---`

Approval evidence is distinct from a phase-complete marker.

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

### Direct execution and plan review

Main-agent direct execution is permitted at every size/risk. Choose optional
execution delegation for concrete benefit. Required/requested plans receive fresh
independent review before approval and implementation: one fresh
`plan_coverage_and_feasibility` pass. Fix material plan findings and obtain one
fresh re-review; already-running approved plans keep their authority on
upgrade. Trivial work does not create a plan solely to review planning.
At the final acceptance review (`review_subject=acceptance`) reconcile original
request/approved plan and task-wide completion allocation against actual
evidence; missing work prevents a completed verdict.

### Reuse before creating

Before production code, tests, fixtures, config, scripts or helpers, inspect the
affected flow and callers. Choose the first sufficient option: omit capability
outside accepted scope; reuse a suitable project component/helper; use a platform
or standard-library capability; use a suitable installed dependency; then write
the smallest readable code for the remaining behavior. Sufficiency includes
compatibility, necessary error handling, trust validation, accessibility where
relevant, and affected consumers. Do not scan the whole repository by default,
add unsafe dependencies, compress unrelated jobs, or break architecture to shrink
a diff. New abstractions/options need a current purpose; one line is no target.

Carry source-bound reduced-testing scope and the unchanged decision to the Build
owner and verifier alongside the assessment. When an explicit reduced-testing
instruction applies, preserve its unchanged exact instruction row in every
materialized packet and when adding results; reconcile missing/stale applicable
provenance against newest intent. Without an applicable instruction, ordinary
assessments including empty arrays require no row. Instruction rows claim no
execution or selected-check closure. Additional test work needs a named important uncovered
failure and inadequate-evidence explanation; material expansion returns to
selection and existing approval. Keep selected TDD and controlling checks intact.

Load `references/build-worker-protocol.md` for canonical packet or worker Build
execution, active workflow TDD, or a repair requiring its carried protocol. It
owns delegated/direct fallback execution, Code Writer and Builder/Tester
evidence, selected verification, conditional TDD, Code Writer unexpected blockers, and per-slice
verification. Repeated work uses one task-level shared stagnation guard: three
consecutive unproductive semantic cycles, completed evidence before subsequent
blockers, and no cumulative attempt ceiling. Silent fallback cannot complete.

For medium+ harness-capable work, confirm the task journal or carried-forward
plan has compact refs for an accepted Done Contract, selected Harness Recipe,
Harness Run State, Trace Ledger, Replay Packet, and Artifact Reference Ledger
before dispatching Code Writer or Builder/Tester. Load
`references/harness-runtime-artifacts.md` for runtime artifact updates and
`references/task-journal-harness-appendix.md` for full schemas. If any required
ref is missing, stop Build and return to Plan or repair state using
`references/harness-controller.md` and `references/harness-runtime-artifacts.md`.

For medium+ tasks with slices, source-changing packets run sequentially in a
shared or unknown workspace. Independently executable source-changing packets
may overlap only with runtime-proven isolated workspaces; dependent packets wait
for every `depends_on` prerequisite to be `VERIFIED`. Print `>> Slice
[S]/[total]: [packet_id] [name]`. In `bounded_executor`, the bounded executor
owns selected implementation and verification; RED/GREEN/REFACTOR apply only
when the canonical decision activates TDD. In `separated_workers`, active TDD
runs SAME selected Code Writer `worker_stage=test_authoring` when selected assertions need authoring or repair (tests only, no incoming RED), then execution-only Builder/Tester `pre_production_red`; explicit reuse of unchanged assertions skips authoring without fabricated edits. It forwards unchanged current typed RED to that SAME actual writer `worker_stage=production`, then runs Builder/Tester GREEN. Only after current GREEN passes does that writer `worker_stage=refactor` return before Builder/Tester executed REFACTOR or validated unchanged GREEN reuse. Stage-only DONE never completes Build or permits Review; inactive TDD runs
Code Writer tests plus code then execution-only Builder/Tester `final_verification`. Verify each acceptance
criterion, record lane-matched canonical packet execution evidence, and mark the slice
`VERIFIED` before a dependent packet starts.

For `controller_intensity=light`, implementation may run inline/direct. Use the
plan-step loop with `workflow_state_mode=inline`,
`subagent_policy_state=not_required`, and
`subagent_execution_mode=not_applicable`; record selected automated or
non-command verification evidence and skip Code Writer, Builder/Tester, Code
Reviewer/Reviewer dispatch evidence. Skip task journal, slice ledger, metrics,
and manual verification ceremony unless an independent mode explicitly requires one.

For bugfixes with unknown cause, complete `assistant-debugging` first or record
a concrete blocked/inconclusive debugging result. Do not patch until
reproduction/root-cause evidence identifies a fix target or mitigation. Follow
the selected verification method; if TDD is active, carry meaningful RED, and
otherwise do not fabricate it.

Resolve build and test applicability from the current due CheckSpecs and
resolved binding constraints, using each check's claim, oracle, and concrete
procedure. Do not infer applicability from file type, command presence, method,
or technique alone; missing or unresolved applicability is a gap. For actual worker/packet consumers, keep
`build_result` required: `not_applicable` means no due selected or binding build
check applies and no build was executed; `not_run` means a required build could
not run and requires `NEEDS_CONTEXT` or `BLOCKED`; `passed` requires current
observed or admissibly reused success, and an executed failure is `failed` and
blocks completion. Keep `test_summary` required; zero counts mean no tests ran,
not that a selected or binding test passed. Every due selected and binding
check needs a current result. When a selected check has no command, an empty
`verification.commands` list is valid only with concrete procedure and observed
result evidence.

After all slices are integrated, run the selected checks and binding project
checks over the completed scope before fresh Review; do not add an unselected
full suite. Packet-local passes never waive integrated acceptance, selected and binding checks, fresh independent review, conditional QA/harness or the exact final snapshot. Packet count creates no exemption.
Apply the current-verification reuse rules in
`references/build-worker-protocol.md`: reuse only full matching
identity/coverage evidence and rerun every invalidated case. Per-slice evidence
does not satisfy new integration coverage; reused evidence records the original
run and current comparison without claiming a newly executed verification.

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

Summarize the completed change and observed verification once; omit empty test
counts and internal result fields from ordinary human updates. Consumer evidence
retains actual invocation/result identity, including zero counts when required.

Print: `--- PHASE: BUILD COMPLETE ---`

## Phase: Review

**Run condition:** `execution_intent != prepare_only`.

Print: `--- PHASE: REVIEW ---`

Load `references/review-qa-router.md`. Reused validation evidence never replaces
the final fresh acceptance review or a current final review snapshot. Light work records a compact review result. Local self-check prepares the required
newly created fresh-context independent reviewer (Codex `fork_turns=none`,
self-contained handoff); no author fallback certifies completion. Persisted/executable admission uses the structured review path; a Pack or expanded impact instead records canonical `assistant-review` final-summary and delegation-path refs, without changing light Build. Standard/strict work uses one final fresh acceptance review through `assistant-review` (`review_subject=acceptance`) that also owns the spec obligations; Stage 1 Spec Review is retired. Stage 3 QA Evaluation runs only
when `qa_evaluation_mode=required`. Always pass the triage `controller_intensity` to assistant-review.

Before any review lane, pass the unchanged `verification_decision`, current
`evidence_assessment`, actual selected-check results, and omitted-check
rationales alongside scope and changed files. Carry the source-bound reduced-testing
constraint and exact assessment instruction row through existing review
criteria/evidence/snapshot refs when an explicit reduced-testing instruction
applies; reconcile missing/stale applicable provenance against newest intent
before resume. Without an applicable instruction, ordinary assessments including
empty arrays require no instruction row. Generic more-coverage
advice or a score cannot expand scope without an important gap and the existing
selection/approval route. Preserve unresolved evidence gaps;
review cannot upgrade them to sufficient or replace validation.

For standard/strict work, run the stages in order (Stage 1 Spec Review is retired):

- Print `>> Stage 2: Acceptance Review - loading assistant-review SKILL.md`;
   load and follow `assistant-review` SKILL.md and contracts with
   `review_subject=acceptance`. Assign the `references/prompts/spec-review.md`
   obligations (original request, requirement IDs, approved plan and delivery)
   to a pass of this batch; a fix needs a fresh complete batch. When an Architecture Decision Pack applies, pass its fresh compact review projection, including design-pressure checks, and require `architecture_decision_pack_review_required=true`; assistant-review then owns the checklist result. assistant-review solely owns Reviewer
   and QAEvaluator packet schemas and any Reviewer compatibility routing.
- Print `>> Stage 3: QA Evaluation - loading assistant-review references/qa-evaluation-loop.md` only when QA is required.

After review, write `review_result` with current producer version, canonical
result/delegation refs, exact `final_review_snapshot_id`, and final identity
ref/object resolving within that result to the exact current final batch, plus
`architecture_decision_pack_review_ref` when a Pack applies and the
Verification Summary. Review owns independent reviewer evidence; it does
not create the developer handoff. Wait only when `manual_verification_mode=required`; optional manual
steps do not block and `not_required` proceeds directly to Document.

If QA rejects and a source fix follows, return to Build. Passed Build
validation, rehash evidence, and a fresh complete assistant-review batch on the
post-fix identity are required before QA resumes; reuse requires equal pre/post
digests, explicit equality evidence, and no changed-path fields.

Print: `--- PHASE: REVIEW COMPLETE ---`

## Phase: Document

**Run condition:** `execution_intent != prepare_only`.

Print: `--- PHASE: DOCUMENT ---`

Load `references/completion-controller.md` and, for medium+, strict, or
required-QA work,
`references/final-handoff.md`. They own small/full Document paths,
metrics JSON format, final harness refresh, the sole developer handoff creation
step, and Verified Skill Distillation routing.

Use the controller-intensity path and the completion modes. Metrics remain
optional and non-blocking. Refresh harness runtime artifacts only when
`harness_capable=true`.

Print: `--- PHASE: DOCUMENT COMPLETE ---`
Print `--- WORKFLOW COMPLETE ---` only when every Document assertion passes and
the applicable `final_handoff.review_completion.completion_disposition` is
`complete`. For remaining review items, incomplete coverage, rejected or
blocked QA, return the explicit non-complete status and next action instead.

## Phase: Preparation Completion

**Run condition:** `execution_intent=prepare_only` after Discover. Optional
readiness planning creates no executable packets or implementation-approval wait.
A fresh plan review is due only when that readiness plan was requested or is
required; never create a readiness plan solely to review it.
Print: `--- PHASE: PREPARATION COMPLETION ---` before the completion checks and
`--- PHASE: PREPARATION COMPLETE ---` after they pass. These exact markers are
declared by `contracts/phase-gates.yaml`; do not derive a synthetic
`PREPARATION_COMPLETION COMPLETE` marker.
Return `completion_policy`, `validation_results`, and `feature_preparation_result`
as required by PC1 and the `preparation_only` completion tier, plus complete
`feature_preparation_evidence` for existing-system work. Keep execution
`not_started`; do not claim Build, changed files, tests, post-Build review, final handoff,
or implementation documentation. Keep `qa_evaluation_mode=not_required` and
`harness_capable=false`. When explicitly requested future QA/acceptance or
harness work exists, return it only through the corresponding typed
`future_qa_acceptance_obligation` or `future_harness_obligation`; those fields
do not load execution controllers or artifacts.
A later approved `implement_only` workflow consumes the exact future harness
object as `approved_feature_preparation_harness_obligation`, binds the source
evidence ref for `existing_system` or `source_preparation_basis=not_applicable`
without an evidence ref for `not_applicable`, promotes an initially small
implementation to at least `medium`, sets `harness_capable=true`, and completes
the existing Done Contract, Harness Recipe, and runtime-ref entry gates before
Build.
When the preparation result carries `future_qa_acceptance_obligation`, the
later approved `implement_only` workflow consumes it as
`approved_feature_preparation_qa_acceptance_obligation`, preserves its two
payload fields exactly, binds the existing-system evidence ref or typed
`not_applicable` basis, sets `qa_evaluation_mode=required`, and carries it
unchanged through the packet, Build, verification, Code Reviewer, and the
existing QA Evaluator acceptance context. This does not activate QA during
preparation or add a pre-Build harness gate.
