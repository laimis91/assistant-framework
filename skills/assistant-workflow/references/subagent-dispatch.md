# Subagent Dispatch — Roles and Rules

The main agent chooses direct execution or useful delegation for implementation,
mapping, architecture, testing and other execution work. Size/risk labels do not
mandate worker agents or prohibit main-agent edits. Optional roles retain their
scope, permissions, actual identities and verification responsibilities.

Formal plan, code, finding-closure and acceptance reviews always use newly created
agents with fresh context. Selected five-lens research requires five separate
sibling-blind lens agents and a new independent peer. These are the mandatory
isolation boundaries; author/main self-check and sequential role-play cannot
substitute. In Codex use `fork_turns=none` and one complete self-contained handoff.
Other providers use their supported isolation and report inability honestly.
Unavailable required isolation leaves the work incomplete; direct fallback never applies to these roles.

## Execution policy

`direct_main` is an ordinary lane, without a fallback exemption or child dispatch
log. Single-pass work keeps proportional direct evidence. Persisted/executable
consumers bind ExecutionActorBinding `{kind: main, actor_id, runtime_evidence_ref}`
from independently retained native authority, use `execution_stage`, and return
canonical plan/context with actual `execution_actor_id`. They omit worker-only
`current_task_packet`, `worker_role`, `worker_stage`, builder and child-native
fields. The executable `dispatch` boundary admits an action; it need not spawn.

Optional delegation selects `bounded_executor` or `separated_workers` when useful.
Only actual child work records native dispatch/result evidence and writer stages.
The same selected writer owns selected tests and production; Builder/Tester is
execution-only when selected. Source-changing work serializes in shared/unknown
workspaces; concurrency needs current isolated workspace and dependency evidence.
No lane bypasses approval, sandbox, secrets, costs, selected checks, meaningful RED,
progress history or acceptance. Required review is independent in every lane.

`subagent_policy_state=not_required` and `subagent_execution_mode=not_applicable`
may describe direct Build at any size. `delegation_triggered`/`delegated` describes
actual optional delegation or mandatory review/lens isolation. Historical fallback
records retain original labels and evidence; they cannot certify a current review
or Research v5 isolation. Trivial/small light work uses one newly created fresh-context reviewer covering
spec obligations and quality, plus one fresh re-review after a fix, and records the
compact result defined in `references/review-qa-router.md`; medium+ code/acceptance
review keeps at least two sibling-blind passes.

## QA evidence gate

QA required positive triggers: explicit QA/acceptance evaluation request, accepted Done Contract, harness-capable acceptance scope, domain-scored scope, or scoped UI/visual/product/UX/docs/DX acceptance.
QA non-triggers: template labels/placeholders, generic acceptance criteria labels, optional/not_required reasons, delegation/source-changing work alone, and ordinary medium+ code-review-only/source-changing work.
Required independent acceptance judgment follows current Build and Code Reviewer
evidence and uses a newly created QAEvaluator with fresh context and retained
native source/dispatch authority. It cannot substitute code-review authority or
certify author fallback. Pure QA/check execution remains discretionary.

## Roles

| Role | Claude (agent name) | Codex (agent name) | Access | Phase |
|---|---|---|---|---|
| **Code Mapper** | `code-mapper` | `code-mapper` | Read-only | Discover |
| **Explorer** | `explorer` | `explorer` | Read-only | Discover |
| **Architect** | `architect` | `architect` | Read-only | Decompose, Plan, Design |
| **Code Writer** | `intelligent-writer` default (Opus); eligible `mechanical-writer` (Sonnet) | `intelligent-writer` default; eligible `mechanical-writer` | Write | Build |
| **Builder/Tester** | `builder-tester` | `builder-tester` | Write | Build |
| **Code Reviewer** | `code-reviewer` | `code-reviewer` | Read-only | Review |
| **Reviewer** | `reviewer` | `reviewer` | Read-only | Review compatibility |
| **QA Evaluator** | `qa-evaluator` | `qa-evaluator` | Read-only | Review QA |

## Concrete writer selection

The logical `CodeWriter` and `orchestrator_to_code_writer` handoff stay canonical.
The Orchestrator owns `writer_selection`; Architect may propose it. New Claude and Codex
packets carry `agent` (`intelligent-writer` default or `mechanical-writer`) and a
`rationale` tied to remaining judgment and consequences. Mechanical selection also
carries `mechanical_eligibility` with all four refs: `recipe_or_example_ref`,
`resolved_decisions_ref`, `scope_and_dependencies_ref`, and
`correctness_expectations_ref`. Resolve actual current evidence before dispatch:
applicable approved recipe/example, resolved semantic/edge/compatibility decisions,
understood ownership/dependencies/baseline, and independently fixed correctness
expectations for BOTH tests and implementation, including fully specified cases, expected values/oracles, negative cases, assertion and fixture patterns. Unresolved test judgment selects intelligent. Nonempty refs or self-asserted labels do not establish eligibility.
Neither edit size nor file type/count nor a simple label selects the role.

Skill/contract semantics, grader/oracle/counterexample design, interacting
constraints, lifecycle/error handling and unresolved compatibility use intelligent
judgment. Approved exact wording or an exact existing pattern can be mechanical
only when every condition is substantiated. A one-line grader edit can require
intelligent-writer. Writers cannot invent desired behavior or replace specialist
ownership; missing requirements return `NEEDS_CONTEXT` to the Orchestrator.

Carry the identical object in each packet projection and inline CodeWriter
context. The materialized canonical `current_task_packet` wins over ambiguous inline prose when supplied; it never overrides the approved stored definition; packet/inline conflicts block
instead of being merged. Old packets without selection remain valid and use
intelligent compatibility semantics. Both writers retain exact scope, selected
checks and binding tuples, unchanged verification/TDD, statuses, partial changes,
and independent review. Stale eligibility stops dependent mutations and returns
actual changed files with observed evidence and the existing truthful blocker
status. Classify failures from evidence; no mandatory Luna-then-Sol cascade.

Codex has eleven normal roles and twelve transition TOMLs, including standalone
deprecated `code-writer` (Sol/high intelligent compatibility). New normal dispatches
use only the two new names. An explicit legacy request may use `code-writer`.
A missing new Claude or Codex definition is a deployment mismatch: report it and stop;
never silently substitute a generic worker or nearest coding agent. A separately
authorized bootstrap must record actual runtime role/model/effort and cannot
claim native activation. Keep compatibility for the transition release; removal
requires a later retirement decision and ownership-safe installed cleanup.

Claude has the same eleven normal roles and twelve transition definitions: intelligent-writer uses its native Opus alias and fully specified mechanical-writer uses Sonnet. Its standalone deprecated code-writer preserves intelligent compatibility for explicit legacy requests; do not silently alias or redirect. Keep user configuration untouched. Gemini has no custom
framework definitions: use its supported native/default route and existing tier
guidance, without inventing names or model preferences. The two-writer choice
adds no delegation requirement to otherwise direct lightweight work.


## Dispatch and independent evidence

Use the configured native role when delegation is selected; do not fabricate a
worker or silently change model/effort. Keep authorizations, verification decision,
exact selected CheckSpecs/bindings, input identities, partial failures and one
shared task guard through every handoff. Roles are capabilities, not a spawn chain.
Architect decisions may be resolved directly; high-risk challenge or QA acceptance
judgment uses a fresh review without requiring an extra execution-only worker.

Discovery reviewers receive original requirements, full current change, relevant
sources and actual verification, with no implementation rationale, sibling verdicts
or prior findings. A distinct closure reviewer receives its finding ledger. Required
facts and adverse results remain visible. Every review pass has fresh native creation
and source/context/handoff authority; a new task name on an old actor is insufficient.
Reviewers are disjoint from authors and prior reviewers. QA responsibilities remain
separate. Required plan review applies to requested/required plans before approval
and implementation, with fresh review after material fixes; never create a plan
solely to review planning. Already-running approved plans retain their authority.

Plan review dispatches with `review_subject=plan`. The final independent review
uses `review_subject=acceptance` and is the single owner of request, plan and
delivery reconciliation, including the spec obligations of
`references/prompts/spec-review.md`; no separate Spec reviewer is dispatched.
It reconciles original requirement IDs, approved plan, completion allocation and
task-wide work against current outcomes and verification. Missing work, findings
or coverage remains partial. Reuse existing ledgers/results; no second
plan-progress ledger or completion agent is required. Medium work needs at least
one plan reviewer plus a final batch at the canonical per-size count (medium 3) of sibling-blind passes. Plan
review is exactly one fresh pass with perspective `plan_coverage_and_feasibility`
(`topology.plan_review=true`); after a material plan fix, one newly created fresh
re-review of the same perspective receives the closure ledger on the structured path. Plan review records
the compact `plan_review_result` (`reviewer_identity`, PASS or
`{aggregate_finding_id, file_line, description}` rows, `request_plan_reconciliation`
coverage, `closure_results`); the compact re-reviewer receives the fixed rows as
`{aggregate_finding_id, description}`. Persisted/executable admission instead keeps
the structured plan batch and review-tools validation.

Review result consumption uses the existing pass_attempt_ledger/response_events,
complete raw bytes, native invocation, batch/snapshot/pass/attempt, producer version
and occurrence bindings. Deterministic review-tools.py validates return identity,
the terminal barrier and aggregate accounting; snapshot, frozen-manifest and exact
byte-copy tooling is not yet provided, so those bindings stay caller-recorded
evidence. Caller judgment owns truth, severity, coverage and completion. Identical replay is consumed once. Conflicts,
failed attempts, provenance and unknown history remain retained. Use notifications
and bounded waits; full inventories serve discovery/recovery, not repeated retrieval.
