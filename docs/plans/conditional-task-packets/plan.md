# Readiness plan: conditional decomposition and canonical task packets

Status: proposed plan; implementation not started.

Prepared: 2026-10-16. This plan accompanies [specification.md](specification.md), the [source snapshot](source-manifest.json), and the [typed preparation result](preparation.json). It records the proposed implementation sequence and its decision boundaries; it creates no executable packets, slice manifest, implementation-test selection, or downstream execution handoff.

Evidence identity: `docs/plans/conditional-task-packets/preparation.json#feature_preparation_evidence`.

## Intended result

Make the existing executable packet collection the canonical record of work. Default coherent implementation to one packet; use additional packets for useful acceptance, ownership/context, prerequisite, recovery/rollout, or binding protocol boundaries. Preserve the current direct/light and preparation-only paths.

The expected benefit is reduced duplicate representation. Runtime/token savings and equivalent control remain hypotheses until evaluated. Acceptance is defined by CP-01 through CP-14 in the specification, including its obligation preservation map.

## Preparation completed

- Inspected current workflow producers, task/worker projections, verification/dependency gates, state/recovery references, generated-view headings, role prompts, evaluator controls and relevant owning assertions.
- Recorded eight evidence rows, an Architecture Decision Pack and a source/consumer hash inventory. The Pack selects canonical task packets with conditional boundaries and remains `discover_only`.
- Distinguished current authority from the proposed change. Existing slicing rules still apply until an approved change is implemented.
- Preserved the other task's branch, dirty files, generated fixtures and `.codex/task.md`. No Build, runtime comparison, installation, code review or implementation completion is claimed.

## Proposed sequence after implementation authorization

### 1. Refresh the boundary and preserve unrelated work

Resolve the approved preparation unchanged, refresh the source inventory against the implementation starting point, and reconcile changed contracts/consumers. Use an isolated checkout when needed to preserve the existing cleanup work. Carry only this approved preparation and intended source changes. Source changes that invalidate the design require a refreshed decision rather than applying old hashes blindly.

Exit when the implementation scope, current source identity, preserved user work and shared-impact boundary are understood. Re-triage actual implementation risk and roles; this preparation's standard/no-Build selection does not preselect the execution lane.

### 2. Close the obligation-to-consumer comparison

Use the specification's preservation map to confirm where every existing acceptance, dependency, verification/TDD, approval, recovery, isolation and review obligation will live. Resolve legacy one-to-many cases and the distinction between worker status and coordinator VERIFIED state. Keep meaningful scope/count/budget/fallback checks in ordinary Plan review.

Exit when no mandatory control depends solely on an artifact proposed for retirement. A missing consumer is a design gap, not a reason to weaken acceptance.

### 3. Define one contract change across its owners

Prepare the versioned canonical packet/worker projections, conditional routing and bounded legacy-input admission together. Preserve specialist-owned verification objects and worker status semantics. The current packet must still be self-contained when materialized; the stored plan must not maintain a competing mutable copy of slice boundaries or selected decisions.

Exit when all producers, dispatch/resume consumers and terminal projections agree on packet identity, state, evidence, migration and failure behavior. The future implementation workflow selects and approves its actual execution packets under the rules active at that time; this readiness plan does not attempt to pre-author them.

### 4. Align implementation surfaces and maintained guidance

Apply the approved change across the source boundaries identified in the specification. Update conditional consumers without broadening their triggers. Regenerate focused views from canonical sources and preserve provider role identities, native routing, permission rules, and custom model/effort settings. Retire the standalone decomposition-review reference only after its remaining checks and inbound references have owners.

Exit when there is one authoritative work representation and all relevant active consumers use it. Historical evidence remains intact; a raw repository-wide replacement of the word “slice” is inappropriate.

### 5. Establish regression and integration evidence

Have assistant-verification select the smallest credible checks from refreshed sources and current policy before implementation fixes its verification obligations. Reuse the existing owning coverage for coherent routing, dependencies/isolation, verification identity, TDD, invalidation/resumption, preparation/progressive boundaries, migration and final integration. Preserve discriminating negative cases instead of duplicating mutable inventories or phrase-only assertions.

Exit when the selected focused evidence and applicable aggregate support the changed acceptance claims, generated distribution is aligned, and gaps/exclusions remain explicit. This plan does not claim that source/schema checks prove native execution or efficiency.

### 6. Resolve native capability and pilot permission

Check whether the existing evaluation path can observe the proposed native boundaries, including dispatch, evidence invalidation and resumption. Preserve `adapter_unavailable` and unobserved telemetry as gaps. Before model calls, obtain the bounded runtime/model, elapsed/token/call allowance and predeclared benefit threshold described in the specification.

Exit with either an executable bounded pilot decision or an explicit capability/cost gap. Do not install adapters, change telemetry infrastructure or consume model quota just to complete this stage without authorization.

### 7. Compare and decide whether to adopt

Use the proposed four paired scenarios only within the approved limits. Compare total delivery cost and acceptance, including planning, recovery and review. A control or acceptance regression stops promotion. Incomplete evidence or absent material benefit leads to further investigation or a new user decision, without an efficiency claim.

Exit with a qualified adoption decision tied to actual source/variant/model/runtime evidence. Keep this experiment out of ordinary task execution defaults.

### 8. Review and hand off the exact candidate

Obtain the required independent review after integrated verification, and QA only if its current independent triggers apply. Resolve actionable in-scope findings under the approved recovery allowance and obtain required fresh review evidence. Revalidate the shared-impact completion boundary and exact snapshot before the final handoff.

Exit only when the approved acceptance claims, current verification, review and any applicable QA are satisfied or the remaining blocker is stated. Commit/PR/installation delivery is a later explicit scope choice; this preparation requests none of those actions.

## Recovery allowance proposed for later approval

Within approved file scope, access, resources and acceptance, allow ordinary reversible corrections to contract wording, producer/consumer alignment, fixture/schema wiring and generated views. Refresh sources and rerun only invalidated evidence. Do not discard partial work or reset spent recovery attempts.

Retain the existing Build recovery limits: three total same-scope attempts and a two-attempt no-progress limit. This proposal adds no second retry budget. Stop sooner for a missing mandatory obligation, ambiguous legacy mapping, unknown-cause failure needing diagnosis, unsafe mutation, changed scope/risk/access/cost/acceptance, rejected approval, or inability to preserve user work.

The pilot has no automatic extra calls. An unavailable pair or exhausted allowance returns its exact gap; another trial, infrastructure change or broader budget requires a new decision. Current project approval and specialist rules remain authoritative.

## Evidence reuse and exclusions

Current source reads, observed artifact overlap, existing assertion inspection and the preceding peer-qualified research support preparation. They do not satisfy future execution, migration, native scheduling, performance, Build or independent review claims.

This preparation requires document/JSON consistency, complete evidence-row/claim bindings, resolvable local links, source freshness and a fresh semantic self-review. It adds no product tests and does not run the implementation aggregate. Repeating a large suite against unchanged implementation would not establish the proposal's future behavior.

## Open decisions and next state

1. Review and authorize the proposed specification/plan before implementation.
2. Before a comparative pilot, resolve supported capability and approve exact model/runtime, call/elapsed/token limits, stop conditions and the benefit threshold. The proposed initial ceiling is eight top-level task runs, justified by four distinct paired scenarios. Internal model turns and child-agent/review calls count toward the approved overall resources; no calls are made now.

Recommended next state: an authorized `implement_only` workflow consumes the exact typed preparation result, refreshes current sources and expanded impact evidence, selects its canonical verification/TDD decision, and obtains any still-required concrete implementation Plan approval before Build. Preparation itself is complete without waiting for that decision.
