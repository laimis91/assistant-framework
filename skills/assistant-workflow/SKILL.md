---
name: assistant-workflow
description: "Prepare, plan, build, or resume repository task state: feature/epic/story technical preparation, implementation, fixes, migrations, refactors, artifacts, backlog items, and intended-change ideas."
requires:
  - assistant-review
  - assistant-verification
  - assistant-tdd
---

# Development Workflow

## Shared operating guidance

Load [the common outcome guidance and shared stagnation policy](../../tools/progress/operating-guidance.md) for this activity. Keep specialist methods, authority and completion evidence below; single-pass work needs no progress artifact.


Complete the requested change with the smallest complete implementation and
credible evidence. Inspect callers, tests, configuration, and other affected
consumers before deciding the scope; reuse existing code and conventions. Carry
explicit reduced-testing instructions and sources through selection, workers,
review and resume; add tests only for distinct important uncovered behavior.
Use the reuse-first ordering in the Build reference before creating code or helpers.

## Ordinary path

1. **Inspect and resolve requirements.** Read the request, repository guidance,
   and relevant source. Preserve authoritative behavior and apply source-backed
   technical defaults. Ask only about remaining material intent, scope, safety,
   or acceptance choices; plan approval does not answer an unresolved product
   question. Use assistant-clarify for unclear intent and assistant-debugging
   for an unknown failure mechanism.
2. **Select verification and plan.** Before a Plan fixes verification obligations
   or direct Build begins, use assistant-verification to select or refresh the
   canonical decision for material claims, credible failures, and binding project
   requirements. Preserve its CheckSpecs and TddChoice. Trivial safe local work
   can proceed directly; bounded small work can use a short inline plan without
   waiting. Medium+, risky,
   destructive, public-contract/data/security, or material scope changes require
   an approved plan before implementation. Reuse existing approval within its
   scope. Split coherent work only for an actual acceptance, dependency,
   ownership/context, recovery, or protocol reason.
3. **Implement.** For selected checks with active TDD, obtain meaningful
   authorizing RED before the first production edit; assistant-tdd owns the
   RED/GREEN/REFACTOR cycle. Make the smallest durable change that meets the
   accepted criteria. Preserve dirty work and user constraints. Stop dependent
   work for material unknowns or a scope/risk change; refresh the decision and
   obtain renewed approval when required before further edits.
4. **Verify.** Run the selected and binding checks or reuse adequate current
   evidence, assess the results, and report gaps. Active TDD also requires
   passing GREEN and separate REFACTOR verification.
5. **Review.** Small low-risk local work uses a fresh self-review. Standard and
   strict work uses independent assistant-review after verification; expanded
   change impact also retains its canonical review evidence. QA runs only when
   required by its acceptance triggers. Fixes require current verification and
   a fresh review of the changed snapshot.
6. **Handoff.** State the outcome, changed files and purpose, checks and results,
   material limits, and any next action. Omit empty sections and internal
   routing fields from ordinary human responses.

## Select only the needed machinery

Use [triage-rubric.md](references/triage-rubric.md) and
[workflow-controller.md](references/workflow-controller.md) when risk, approval,
state, delegation, harness, or QA routing needs resolution. Light work stays
hands-on; ordinary medium+ work defaults to standard, non-harness, non-QA with
one Build owner. Required delegation follows
[the dispatch rules](references/subagent-dispatch.md) without a separate spawn
permission question; permitted fallback needs actual opt-out, policy, or
unavailability evidence. Separate writer/verifier ownership only when triggered.

Load generated `references/phases/<current-phase>.md` for the phase requiring
detail; use authoritative [phases.md](references/phases.md) if the view is missing
or unknown. Exact phase/triage markers are for strict control, explicit policy,
or user request. Other updates use concise natural language.

- Preparation-only work uses Discover → Preparation Completion without edits
  or execution claims. Load [feature preparation](references/feature-preparation-evidence.md)
  for existing-system preparation, every implement-only continuation, or carried
  future obligations. Preserve the exact approved result and source bindings.
- Load [architecture decisions](references/architecture-decision-pack.md) for
  actual boundary, ownership/lifecycle, public-contract, quality, or viable
  alternative uncertainty; retain its types, design-pressure checks, evidence,
  compatibility, and review bindings. Size alone is no trigger.
- Load [change impact](references/change-impact.md) for behavior/cosmetic or
  locality claims affecting verification. Shared, materially unresolved, or
  explicitly carried expanded work keeps common pre-Build/completion checks.
- Load [progressive discovery](references/progressive-discovery.md) for
  predecessor-unlocked unknowns or retained progressive markers. It remains a
  no-execution boundary; mutating prerequisites need a separate approved workflow.
  Completed state alone does not archive its protocol.
- Load [state reconciliation](references/task-state-reconciliation.md) before
  trusting persisted state. Create journals only for persistence, waits,
  delegated execution, strict/harness/QA, or genuine continuation needs.
- For explicit user/repository artifact schemas, load
  [the output contract](references/artifact-first-output-contract.md) before
  planning, direct Build, or output. Preserve exact paths, keys, types, ids, and
  supplied literals; external schemas override workflow-internal shapes.
- Load [candidate search](references/candidate-search.md) for real alternatives,
  optimization uncertainty, repeated failure, or a requested pivot; load
  [harness control](references/harness-controller.md) only after its trigger.
- Load assistant-security for auth, external input, secrets, persistence,
  network/shell calls, dependency/config changes, or external integrations.
- Load [AI usage policy](references/ai-usage-policy.md) for external services,
  installs, or sensitive data; external calls/writes, installs, destructive actions,
  and proprietary sharing retain explicit authorization boundaries.

## Consumed contracts and recovery

For canonical plans/task packets, persisted state, delegated handoffs, or
executable admission/evaluation, load `contracts/index.yaml` and the relevant
entry, current-phase, selected-handoff, packet-admission, and completion sets.
These existing v14 interfaces and prerequisites remain authoritative. Load
[build-worker-protocol.md](references/build-worker-protocol.md) for packet/worker
Build execution; generated size plans remain views of `references/plan-template.md`.
Use [legacy compatibility](references/legacy-compatibility.md) only when resuming
older packets. Missing/invalid selectors load the full named authoritative file.

Preserve unchanged CheckSpecs/TddChoice, task-wide `tdd_mode`, due selected IDs,
exact binding tuples, and canonical evidence assessment through actual consumers.
Derive packet `tdd_applies` from selected/applicable IDs; never fabricate RED or
infer old authorization. Admission needs its independently resolved authority
and supported Python runtime. Full serialized objects belong to these consumer
boundaries; an ordinary human update can summarize the same decision and evidence.

Repeated correction uses one shared task-level stagnation guard: three
consecutive completed unproductive semantic cycles. Productive work has no
cumulative attempt or round ceiling; record completed evidence before later blockers.
Scope, access, cost, safety, acceptance, or verification changes require a new
decision. Missing required evidence blocks completion. Medium+, strict, and
required-QA handoffs use [final-handoff.md](references/final-handoff.md); incomplete
review coverage or rejected/blocked QA cannot be reported complete.
