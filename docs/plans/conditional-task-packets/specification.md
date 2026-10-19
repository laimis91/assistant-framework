# Conditional decomposition and canonical task packets

Status: proposed specification; implementation not started.

Prepared: 2026-10-16. Baseline: `622a58d493a3b17df0af9e632ba28287cdf41fd8` plus the inspected working tree. The current branch and unrelated cleanup changes are recorded in [source-manifest.json](source-manifest.json); they are not part of this proposal.

This specification prepares the recommendation requested in the conversation. It does not change the active workflow, authorize implementation, run a native evaluation, or establish a performance improvement. The companion [plan](plan.md) describes the readiness and adoption sequence. [preparation.json](preparation.json) contains the existing-system evidence matrix and the Architecture Decision Pack, with `execution_status=not_started` and `handoff_binding_state=discover_only`.

Canonical preparation evidence identity: `docs/plans/conditional-task-packets/preparation.json#feature_preparation_evidence`. Evidence-row identifiers below refine that identity; they do not replace it.

## Outcome and evidence

Use the existing executable task packet as the canonical unit of implementation ownership, dependencies, verification, progress, and recovery. Decompose work when an execution need justifies multiple packets. A coherent increment should not require a second one-item slice manifest, a single-slice rationale, or a separate decomposition review document.

The current contract requires medium+ slice manifests and a one-item rationale. Plan and worker contracts also carry outcome, file scope, dependencies, acceptance, and verification information. One inspected one-slice decomposition file has 659 lines and repeats an unchanged 16-check verification decision. These observations establish overlap; they do not measure avoidable cost. Evidence: CP-E1 and CP-E2.

Current contracts prescribe downstream slice consumers, and inspected worker-input artifacts propagate their identity. Trusted native execution, comparative benefit, and control equivalence have not been established. Evidence: CP-E3 through CP-E8. The prior research's five independent lenses and separate peer review support conditional consolidation as a design hypothesis. Its qualified conclusion and verified primary-source references are retained in [source-manifest.json](source-manifest.json).

External engineering experience supports revisiting scaffolding: [Anthropic removed sprint decomposition while retaining planning and evaluation](https://www.anthropic.com/engineering/harness-design-long-running-apps); [Cursor describes moving from rigid upfront planning to continuing planner-worker feedback](https://cursor.com/blog/self-driving-codebases). [CodePlan](https://arxiv.org/html/2309.12499v1) combines adaptive repository planning with dependency and impact analysis. Different tasks, models, and bundled interventions prevent treating these as a measured effect for this framework.

## Scope and exclusions

The proposed change covers workflow routing, canonical packet ownership, dispatch projections, dependency verification, recovery references, completion projections, relevant provider prompts, generated references, and their existing evaluation/contract owners. The source inventory identifies 47 discovered source/consumer paths; it is a freshness aid, not a requirement to modify every listed file.

Preserve the current small/light direct lane and preparation-only boundary. Preserve plan approval, verification selection, conditional TDD, workspace isolation, bounded recovery, progressive discovery, independent review, conditional QA/harness activation, security rules, and final snapshot binding.

Do not introduce a scheduler service, generic workflow engine, new skill, permanent migration ledger, new model policy, mandatory benchmark for ordinary tasks, or mandatory per-packet full test suite. Do not install into the real user home, publish a PR, edit unrelated cleanup work, alter historical evidence, or weaken `codex-rules/`. The candidate does not make every enabling change independently shippable.

## Requirements and acceptance

This table is the Requirement Acceptance Map. All criteria describe future implementation acceptance, not completed results. The evidence binding for each row uses the canonical preparation evidence identity above and the named item(s).

| ID | Required behavior | Binary acceptance and discriminating evidence | Evidence binding |
|---|---|---|---|
| CP-01 | Make decomposition conditional. | A coherent medium task without another execution/protocol boundary has one packet and no required separate manifest, single-slice rationale, or standalone decomposition-review artifact. Large size alone does not force multiple packets or an Architect. | CP-E1 |
| CP-02 | Preserve direct and preparation-only routes. | Existing small/light work remains direct; `prepare_only` creates no executable packets or Build/review evidence. | CP-E1, CP-E6 |
| CP-03 | Maintain one canonical work collection. | Plan, dispatch, progress, verification, recovery, and completion resolve the same `implementation_steps` packet identities; changing a worker projection cannot change the canonical plan. | CP-E2 |
| CP-04 | Give multiple packets an execution purpose. | Each extra packet has a concrete acceptance, ownership/context, prerequisite, recovery/rollout, or binding protocol reason recorded in ordinary Plan reasoning; arbitrary file/layer counts cannot force decomposition. | CP-E1, CP-E2, CP-E3 |
| CP-05 | Preserve verification and TDD identity. | Each due CheckSpec and binding tuple resolves to the unchanged task decision; commands retain literal argv and explicit cwd; non-command checks remain valid; active packets obey the existing one-applicable-TDD-check rule. | CP-E3 |
| CP-06 | Preserve dependency and workspace controls. | PENDING/RUNNING/BLOCKED/INVALIDATED prerequisites block dependents; VERIFIED prerequisites permit them subject to all other gates. Shared/unknown workspaces serialize source changes; overlap requires current runtime isolation evidence. | CP-E4 |
| CP-07 | Make verified state evidence-bound. | Worker `DONE` alone cannot verify a packet. Missing, failed, stale, partial, or mismatched evidence prevents VERIFIED and completion; relevant later edits invalidate affected evidence. | CP-E3, CP-E4, CP-E5 |
| CP-08 | Preserve scoped adaptation and resumption. | A resumed task resolves its exact plan/packet/check identities and freshness. Progressive discovery cannot dispatch work before existing readiness/route-clear gates. Material scope/risk/cost/access/acceptance changes follow current reapproval rules. | CP-E5 |
| CP-09 | Preserve integrated completion. | Selected and binding integrated checks precede fresh independent review where required. Packet count cannot waive integration with existing code, QA/harness triggers, canonical review state, or final snapshot identity. | CP-E4, CP-E6 |
| CP-10 | Preserve Plan checks with fewer records. | Scope understanding, dependency order, step/cost budget, criterion/check alignment, fallback, and decomposition-count sanity are checked in existing Plan review; no separate document is required for the one-packet route. | CP-E1, CP-E2, CP-E5 |
| CP-11 | Read legacy input safely. | Valid v12 one-to-one and one-to-many plans retain identities, obligations, dependency barriers and evidence references after normalization; ambiguous versions, IDs, mixed forms or conflicting evidence block execution. New producers emit only the canonical form. | CP-E7 |
| CP-12 | Keep consumers and generated distribution aligned. | Canonical contracts, applicable provider prompts, focused generated views, evaluator schema/grading, and completion references agree. Historical records are not rewritten to imitate the new contract. | CP-E2, CP-E6, CP-E7 |
| CP-13 | Demonstrate behavior rather than vocabulary. | Existing owning checks reject plausible unsafe packet states and accept correct coherent/multiple-packet routes; changing a label without changing decisions cannot satisfy the acceptance set. | CP-E3, CP-E4, CP-E7 |
| CP-14 | Bound adoption claims and cost. | No efficiency claim or default promotion is based solely on schema/static prose. A supported, approved comparative pilot records total cost/time and acceptance or explicitly records unavailable evidence. | CP-E8 |

Manual UI testing is not applicable to these contract and orchestration claims. Native task execution is separate evidence under CP-14, subject to its capability and resource gates.

## Routing decision

Apply these rules in order. The reasons for additional packets compose; the rows are not competing task categories.

1. **Preparation first:** `execution_intent=prepare_only` remains Discover → optional readiness planning → Preparation Completion. This proposal does not authorize executable decomposition during preparation.
2. **Respect readiness:** unresolved material behavior or active progressive discovery stays in the current clarification/discovery route. Do not turn unknown future work into apparently executable empty packets.
3. **Keep the direct lane:** an otherwise eligible small/light task uses its current inline/direct route. A trivial edit does not acquire a packet graph because the new schema exists.
4. **Default to one packet for a coherent increment:** for work already requiring executable packets, use one packet when one owner/context and a coherent set of acceptance obligations suffice. Skip Decompose and retain the applicable Plan approval and quality gates.
5. **Decompose for an execution need:** use the smallest useful set of packets when one or more reasons below apply. Decompose may refine boundaries before Plan; it does not create a separate copy of those boundaries or a separate approval wait.
6. **Apply protocol constraints:** allocation of selected checks must satisfy existing binding TDD/protocol rules. A coherent deliverable can therefore require multiple packets even when it has one final user-visible outcome. Do not weaken `INV_TDD_PROJECTION` to preserve a one-packet label.
7. **Approve and execute through existing gates:** task size/risk still selects approval, Build lane, independent review, and conditional QA/harness requirements. A packet count does not select a model, role, cost permission, or concurrent execution mode.

| Situation | Proposed route and concrete benefit | Constraint |
|---|---|---|
| One coherent refactor or change | One executable packet; no parallel manifest/rationale. | Its scope, acceptance, verification, budget and recovery still appear in ordinary Plan review. |
| Separately verifiable outcomes | Multiple packets when an intermediate result can change the next action or provide useful acceptance evidence. | Splitting solely to satisfy a count is invalid; enabling changes may remain with their consuming outcome. |
| Dependency-bearing changes | Packet dependencies name verified prerequisites, including meaningful contract or migration milestones. | A milestone needs a discriminating local oracle; final end-to-end integration is still due. |
| Independent delegated work | Bound packet ownership/context; independent work may proceed according to the current workspace policy. | Different files alone do not prove isolation or semantic independence. |
| Long or uncertain implementation | Keep coarse future outcomes in the existing Requirement Acceptance Map and refine the next executable packet after evidence. | Do not use progressive detailing to bypass readiness, exact pre-dispatch scope, approved limits, or deferred-acceptance coverage. |
| Multiple selected TDD obligations | Allocate packets to preserve the existing one applicable active check per packet and actual RED/GREEN/REFACTOR evidence. | Protocol boundaries need not be independently deployable features. |

An Architect remains conditional on genuine boundary/public-contract/design uncertainty. Removing a duplicate slice record neither requires nor eliminates that role.

## Canonical records and consumers

The existing Plan `implementation_steps[]` collection becomes the sole canonical collection of executable work. This retains the existing handoff collection rather than introducing a competing `slices`, `milestones`, or `task_packets` collection. A packet's `packet_id` replaces the live slice foreign key. Ordering remains display/scheduling information; dependencies use identity.

| Information | Canonical location and ownership |
|---|---|
| Stable identity, name, outcome/deliverable type, requirement IDs and acceptance allocation | One packet in `implementation_steps`; Orchestrator owns approval and mutation. IDs retain the existing descriptive, lowercase/digit/hyphen, path-safe, unique semantics. |
| Exact create/modify/test scope, constraints, enabling changes, writer selection and reuse decision | Existing packet fields, required before dispatch when applicable. Do not multiply packets simply because these fields span layers. |
| Dependencies | Packet-ID references on that same record; all targets resolve uniquely, with no self-reference or cycle. |
| Verification selection | One canonical task-level `verification_decision`, with a stable resolvable identity and immutable input snapshot/hash. The stored plan packet references it and carries due `selected_check_ids` and exact `binding_obligation_refs`. |
| Current verification/TDD context | Derive task-wide `tdd_mode` and local `tdd_applies` from the unchanged decision. The worker projection materializes the full canonical decision and current `evidence_assessment` where current worker contracts require them. |
| Execution progress and evidence | Update the same packet record or its existing state owner by reference, with status, native dispatch/result references, acceptance/self-check results and selected-check evidence. No second slice ledger or duplicate completion summary is authoritative. |
| Task-wide acceptance and integration | Existing Requirement Acceptance Map, canonical verification assessment and final integrated review/completion artifacts. Cross-packet obligations remain task-wide until their actual boundary is due. |

`current_task_packet` remains the self-contained, read-only projection delivered to an executor/verifier. It is materialized from the approved packet plus resolved canonical specialist objects. Copying a resolved decision into an invocation is allowed; maintaining a second mutable plan/decision is not. Missing, stale, unresolved, or conflicting references block dispatch. An inline fallback resolves the same inputs. References do not justify dropping worker context or reconstructing command strings.

Packet execution state uses a single closed vocabulary: `PENDING`, `RUNNING`, `VERIFIED`, `BLOCKED`, `INVALIDATED`. Reuse the existing coordinator/state machinery; no scheduler implementation is requested. Worker return statuses such as `DONE`, `DONE_WITH_CONCERNS`, and `FAILED_VERIFICATION` retain their existing meanings and remain inputs to the Orchestrator's state decision.

VERIFIED requires current acceptance coverage, all due selected/binding verification, required TDD evidence, a self-check, and the selected execution-lane evidence. A relevant source/input/requirement change invalidates affected results; dependents cannot start on an invalid prerequisite. Reuse unaffected evidence only through the existing exact-identity/coverage rules. Completing a later packet does not preserve earlier evidence that its edits actually invalidated.

Future outcomes without sufficient detail remain non-executable acceptance-map entries. Before each dependent dispatch, refine exact scope, checks, ownership and prerequisites through existing owners. Within approved limits this is routine planning/recovery; changing approved scope/files/behavior/risk/access/cost/acceptance uses the current deviation decision. An acceptance obligation cannot disappear because its packet is deferred.

## Obligation preservation map

Every row must remain mapped when the separate slice artifacts are retired. This is an obligation-to-consumer comparison, not a claim that equivalent control is already implemented.

| Existing obligation / current owner | Proposed owner or explicit retirement | Failure witness |
|---|---|---|
| User/requirement acceptance → requirement map → slice acceptance | Requirement map → packet acceptance allocation; task-wide integration obligations remain explicit. | A required behavior is neither assigned nor retained at a later task boundary. |
| Decompose scope/count/budget/dependency/fallback/output-plan review | Existing Plan review, for both one and multiple packets. | Plan admits unbounded work, incompatible checks or an unowned dependency. |
| Manifest identity → Plan → current worker packet | Canonical `implementation_steps[].packet_id` → materialized `current_task_packet`. | Dispatch selects another packet, stale projection or ambiguous identity. |
| Selected CheckSpecs, literal argv/cwd, binding tuples and TDD owner | Same specialist-owned task decision; exact packet subset and worker projection. | A default cwd, merged command, invented RED or omitted due binding passes. |
| VERIFIED prerequisite barrier and shared-workspace serialization | Packet dependency/state admission in existing workflow. | C starts while A is pending; shared writers overlap without trusted isolation. |
| Per-slice verification and self-check ledger | Packet state/evidence in the existing state owner. | Worker `DONE` without current acceptance/self-check evidence becomes VERIFIED. |
| Recovery budgets, plan deviations, exact next action and progressive lifecycle | Existing recovery/journal/context handoff and route-clear machinery, referencing packet IDs. | Resume skips a blocked obligation, resets spent attempts or executes unresolved discovery. |
| Full-scope/cross-slice validation before fresh Review | Task-wide selected integration coverage; cross-packet checks only when applicable, including integration with existing code for one packet. | Packet-local passes substitute for a newly due integrated check. |
| Review scope, canonical terminal state, QA/harness activation and snapshot binding | Existing assistant-review and completion owners; packet scopes replace slice lookup. | A CLEAN claim survives unresolved scope, changed snapshot or required blocked QA. |
| Separate one-item manifest, single-slice rationale, duplicate slice summary | Retire for newly produced canonical plans after the mapped obligations above have owners and evidence. | Renaming these records leaves the same duplicate authorship requirement. |

## Versioning and legacy preparation

Treat this as a workflow contract major version change from 12.0 to 13.0. Update the canonical contract headers/index and their active consumers together, including the root `SKILL.md` migration note required by the contract design guide. New serialized Plans state `plan_schema_version=13.0`; their canonical packet collection is `implementation_steps`. Do not create new live `slice_manifest`, `single_slice_rationale`, `slice_verification_summary`, or standalone `decomposition_plan_review` artifacts in that form.

Use a bounded **read-old/write-new** normalization at the existing resume/Plan/dispatch admission boundary and corresponding evaluator admission. Original approved artifacts, hashes, results and historical evidence remain unchanged. This is not permission to install over unrelated active work or silently translate an approved scope.

Legacy admission rules:

- Determine v12 from explicit producer contract/version evidence; an unversioned object with unverifiable provenance is not guessed into a schema.
- Validate the original v12 manifest, packets, checks, binding tuples, evidence and current approval before normalization. Old field presence alone does not establish validity or freshness.
- For one legacy packet per slice, map the validated `slice_id` to `packet_id`; retain source identity and an explicit source-to-target map in the existing reconciliation record.
- For several packets in one slice, require unique stable packet identities from the existing `task_id` or an unambiguous source-bound mapping. Resolve collisions explicitly; never merge/drop work. Preserve provider-local identifiers as source references when needed.
- Expand a dependency on a legacy slice to **all** mapped packets in that prerequisite slice, preserving the original slice-wide VERIFIED barrier. Preserve within-slice execution order unless independently established existing dependencies permit otherwise. Preserve exact verification allocation; slice-wide criteria stay explicit task-wide obligations until properly allocated.
- Conflicting canonical/legacy forms, duplicate IDs, unresolved mappings, cycles, missing obligations, changed verification identity or stale approval block dispatch. Return a truthful refresh requirement. A semantics-preserving refresh within existing authorization does not require duplicate user approval; material changes follow existing approval rules.
- Do not preserve obsolete duplicated records as a second authoritative store. The source mapping is compatibility provenance, not a new work ledger.

The transition supports v12 inputs for the v13 migration window. It does not authorize deleting older installed artifacts or adding an indefinite adapter platform. Later retirement of v12 admission is a separate compatibility decision after active consumers are inventoried. Existing worker status vocabularies and assistant-review/assistant-verification contracts are not independently version-bumped unless their actual serialized public shape changes.

## Affected source and coverage owners

Re-enumerate the exact paths before implementation; the inspected hashes are in [source-manifest.json](source-manifest.json). These are candidate edit boundaries, not changes already performed.

| Boundary | Owning files / required treatment |
|---|---|
| Root routing and typed contracts | `skills/assistant-workflow/SKILL.md`; `contracts/input.yaml`, `output.yaml`, `phase-gates.yaml`, `handoffs.yaml`, `index.yaml`. Replace unconditional slice conditions, producer/consumer foreign keys and completion requirements. |
| Canonical workflow references | `references/phases.md`, `plan-template.md`, `decomposition-plan-review.md`, `build-worker-protocol.md`, `workflow-controller.md`, `subagent-dispatch.md`, `subagent-roles.md`, `task-journal-template.md`, `task-state-reconciliation.md`, `context-handoff-templates.md`, `sub-task-brief-template.md`, `requirement-acceptance-map.md`, `final-handoff.md`, `completion-controller.md`, and `mega-and-patterns.md` where applicable. Fold still-needed decomposition checks into Plan; retire the duplicate-review reference only when inbound consumers are migrated. |
| Conditional consumers | Existing harness controller/runtime/plan/journal appendices, progressive-discovery and candidate-search references, change-impact projections, and assistant-review acceptance/scope descriptions. Update live foreign keys or assumptions only; preserve their trigger and lifecycle policies. |
| Provider role prompts | `agents/claude/architect.md`, `agents/codex/architect.toml` and any inspected applicable producer/consumer role prompt. Preserve role names, model/effort configuration and provider behavior. Gemini uses existing native/default support. |
| Generated distribution | `tools/skills/sync-workflow-references.py` and generated `references/phases/*` / `references/plans/*`. Update declared section headings when canonical manifest sections move; regenerate, never hand-edit generated views. Preserve installer substitution and source/installed parity. |
| Eval producers and admission | `skills/assistant-workflow/evals/cases.json`; `docs/evals/framework-instruction-cases.json`; `tools/evals/lib/skill-eval-fixtures.sh`, `skill-eval-grade.sh`, and the current structured-schema/assertion owners found during implementation. Preparation-only forbidden-artifact checks must include the new execution collection. |
| Existing owning suites and fixture builders | `tests/p0-p4/task-packet-contracts.sh`, `worker-status-contracts.sh`, `workflow-architecture-completion-contracts.sh`, `workflow-reference-loading-contracts.sh`, `adaptive-execution-contracts.sh`, `workflow-verification-reuse-contracts.sh`, `feature-preparation-evidence-contracts.sh`, `progressive-discovery-contracts.sh`, `skill-eval-contracts.sh`, and their affected `lib/*response-fixtures.sh` builders. Preserve meaningful negative controls; replace obsolete policy assertions rather than keeping a universal slice requirement. |
| Maintained documentation | `README.md` and `docs/evals/README.md`; the canonical `docs/skill-contract-design-guide.md` only if this changes a rule it owns, followed by its existing generated portable mirror. Do not repeat detailed contract rules in root prose. |

The inventory is not a blind replacement list. Historical slices, illustrative prose and domain-specific “slice” terminology may remain when they do not drive the new workflow. Conversely, references that require a second mutable execution source must migrate even if they use a different word.

## Verification design for later implementation

The implementation workflow must refresh sources and use assistant-verification to choose canonical CheckSpecs before fixing execution checks. The following is the acceptance coverage strategy, not an already selected or executed test plan.

Reuse and extend the current task-packet, worker-status, completion, preparation, verification-reuse and structured scheduling controls. Group negative variants around actual failure modes instead of creating one test per field or a mutable mirror of the discovery inventory:

1. Coherent medium work succeeds with one packet and no duplicate slice artifacts; a second authoritative manifest or a forced count does not satisfy CP-01/03.
2. A/B/C dependency and shared/isolated workspace cases accept safe scheduling and reject early C, missing isolation, bad IDs and cycles. Existing structured policy fixtures provide the baseline.
3. Missing/stale checks, command/cwd mismatch, uncovered binding tuples, worker-DONE-only results and invalidated prerequisites cannot become VERIFIED or complete.
4. One deliverable with several selected TDD obligations preserves the current packet allocation and real RED/GREEN/REFACTOR contract. Non-command/inactive-TDD work never invents tests or RED.
5. Interrupted/resumed work retains identity, spent recovery limits and remaining requirements; relevant edits invalidate evidence; unrelated changes reuse only demonstrably matching evidence.
6. Valid v12 one-to-one/one-to-many sources normalize with equivalent barriers and obligations; ambiguous mappings, mixed versions and missing provenance fail closed.
7. Preparation-only and unresolved progressive discovery reject executable packet output; small/light work remains lightweight; strict/QA/harness triggers and terminal review bindings remain intact.
8. Selected integration validation and fresh review remain due across one and multiple packets; packet evidence cannot close newly due task-wide coverage.

Static contract/reference checks establish structural consistency. Structured policy controls establish stated admission decisions. Neither establishes trusted native execution or comparative value. Avoid new text-only tests asserting that obsolete names disappear everywhere.

Future source/reference checks use the existing generator checks, owning suites through the P0–P4 harness, focused skill validation, then the applicable aggregate. The aggregate runner sources the owning suites; do not invent unsupported per-suite command flags. Source/portable-guide parity is checked if that guide changes. Installation observations, if selected, use an isolated destination and preserve real user settings.

## Comparative pilot and adoption

Keep the candidate out of default promotion until obligation coverage and regression evidence are satisfactory. First establish native capability and observable evidence. The documented isolation/overlap telemetry gap in the current Codex adapter remains a gap; narrative agent messages cannot repair it. Do not extend an adapter just to obtain a preferred answer without a separate scoped decision.

The proposed initial pilot covers four representative scenarios: coherent medium work, dependent A/B/C work, independent delegated work under the applicable workspace policy, and interruption/resumption with relevant evidence invalidation. One baseline/candidate pair per scenario gives **at most eight top-level native task runs**. A task run can contain many model turns and child-agent/review calls; all of them count toward the separately approved overall resources. Eight task runs is not an eight-inference-call cap. This is a bounded discovery pilot, not statistical proof. Use disposable synthetic/local tasks without proprietary uploads. Use equivalent clean starting states, identical requested model/version and tools, acceptance, verification and review policy, counterbalanced ordering, and retained source/variant identity. Disclose limits on attesting the actual backend model.

Before any calls, authorize exact runtime/model, total call/elapsed/token limits, stop conditions, and a materiality threshold appropriate to the measured baseline. Missing limits prevent execution. No automatic extra trials are authorized. A broken/unavailable pair is excluded and reported, not counted as model failure or positive evidence. Further calls or telemetry work require a new bounded decision.

Measure planning **plus** execution, recovery and review tokens/time; acceptance defects, uncovered obligations, rework and user review effort; and actual packet reads/dispatch/state decisions where the runtime exposes them. Static bytes/word counts remain a separate observation.

Do not promote when a mandatory control regresses, acceptance coverage decreases, evidence is incomplete, or the predeclared total-cost benefit is absent. Further evaluation or an explicit, bounded user decision about unresolved evidence is the next state; no binding control can be waived. Confirmed benefits are limited to the measured tasks/model/runtime. Ordinary workflow tasks do not inherit this pilot.

## Remaining evidence and approval

The design direction is specified. The remaining decisions are implementation authorization and, before any native pilot, supported capability, exact resources and the predeclared benefit threshold. There is no need for a ritual Product-question session about internal field choices.

The shared change-impact artifact identity is `conditional-task-packets-impact-20261016`. Preparation retains its discovery status as `gaps_reported`; no pre-Build/completion checker pass is claimed. A later approved implementation must capture/validate the current expanded universe and preserve that identity through its normal gates.

Actual performance, trusted runtime consumption, and successful legacy migration remain unverified future claims. The current branch belongs to another cleanup; refresh the baseline and preserve its dirty work before isolated implementation. Approval of preparation alone does not start Build, run paid/native calls, install, commit, publish or delete anything.
