# Architecture Decision Pack

Use this reference when `architecture_design_mode` is not `not_applicable`.
It makes architecture a compact, falsifiable implementation artifact rather
than a free-form essay or a permanent extra agent.

## Purpose

The Architecture Decision Pack (ADP) records the smallest set of facts,
decisions, semantic interface commitments, and verification needed to build a
single goal safely. It is AI-led: the agent discovers what it can from the
repository, asks every remaining material design question, and escalates to a
human only when a choice is materially irreversible, business-owned, or lacks
a safe default.

Use one pack per implementation goal. Keep it file- and boundary-oriented; do
not expand it into a project rewrite, a general knowledge base, or a standing
"architect" role.

## Applicability

Set `architecture_design_mode` during Triage:

| Mode | Use when |
|---|---|
| `not_applicable` | A localized change has one evidenced path and does not introduce or change a meaningful boundary, data lifecycle, public contract, resource target, or extension seam. Record the concrete reason. |
| `lightweight` | One local design decision needs an explicit owner, dependency, type, or verification rule. |
| `required` | A new system, cross-boundary/public contract, persistent data lifecycle, material extensibility concern, resource target, or genuinely viable design choice is present. |
| `review_intensive` | High-risk or conflicting drivers need independent challenge: for example memory versus throughput, compatibility versus type safety, or an irreversible public/data decision. |

Size alone never triggers a pack. Candidate Search and `assistant-thinking`
remain conditional tools: use them only when real alternatives or conflicting
drivers would change the outcome.

## AI-led question discovery

1. Read local code, tests, contracts, configuration, and the current revision
   before asking. Put source-backed observations in **Facts**.
2. Apply a safe default when it is reversible and repository evidence supports
   it. Record the source and rationale.
3. Ask every remaining material question. Group questions by decision topic;
   each question resolves one decision and states why it matters, risk if
   guessed, and a recommended default when one exists. There is no numeric
   question quota or cap.
4. Stop only when unresolved material questions block correctness, scope,
   public behavior, data, security, rollout, or verification. Do not ask
   questions that source inspection can answer.
5. Escalate to the user for business policy, irreversible commitments, cost or
   compliance choices, or a choice among valid alternatives with materially
   different outcomes. The agent owns ordinary technical synthesis.

## Semantic interface policy

The pack's **Type Ledger** is the contract for named concepts, not a demand to
wrap every primitive.

- Use a named semantic type, value object, request/result type, event, or
  discriminated result when a value has domain meaning, validation, unit,
  lifecycle, owner, security meaning, public contract meaning, or a likely
  extension seam. Avoid public/domain signatures such as bare `string`, `int`,
  `Action<string>`, or `IEnumerable<int>` when callers must know what those
  values mean.
- Prefer a cohesive input/command type over repeatedly extending unrelated
  parameters. Its fields must belong to one operation; do not create a generic
  property bag to hide an incoherent interface.
- Allow a primitive at a local temporary calculation, opaque external/wire or
  storage boundary, framework-required signature, or a value with demonstrably
  no domain semantics. Record the exception, conversion point, and validation
  rule in the Type Ledger. Convert into semantic types at the owned boundary.
- Public or serialized type changes name compatibility, versioning, adapters,
  and migration/rollback evidence. Strong typing must not silently break an
  external consumer.

## Design-pressure checks

Before selecting an interface or orchestration shape, resolve the small set of
pressure checks that could make an otherwise tidy abstraction expensive or
irreversible. These are evidence checks, not a demand for a speculative
framework:

- **Control and early exit:** Can a consumer stop early, cancel, seek, retry,
  or otherwise control production? Do not assume a push/outer engine when a
  real consumer needs pull or preemption.
- **Ownership and disposal:** Who owns buffers, streams, handles, cancellation,
  and cleanup? Record reuse, read/write access, disposal, and caller versus
  provider responsibility at the boundary.
- **Resource envelope:** When memory, throughput, CPU, or concurrency matters,
  name the bounded buffers, item size, concurrency, and workload before
  claiming efficiency.
- **Extension registration:** When formats, algorithms, transports, or other
  implementations may grow, identify the actual registration/selection seam
  instead of hardcoding a closed list or adding an abstract engine prematurely.
- **Representative path:** An interface may be designed before code is written,
  but it must name the concrete producer and consumer path it serves, its
  failure/cancellation behavior, and when the first real use will revalidate
  the abstraction. Do not create generic callbacks, collections, or engines
  solely because a future feature is imaginable.

Each check is marked resolved, not applicable with evidence, or a material
question. Keep the record to this goal; do not turn it into a broad redesign.

## Pack shape

Use the typed `architecture_decision_pack` contract. A readable plan/journal
view follows this compact shape:

The Pack `mode` must exactly equal canonical `architecture_design_mode`. In
`review_intensive` mode, `independent_challenge_evidence` is mandatory and the
nested Pack mode cannot be weakened to evade that evidence.

```markdown
## Architecture Decision Pack
- Pack id / mode: [stable id] | [lightweight | required | review_intensive]
- Single goal: [one outcome]
- Freshness: [branch/HEAD or greenfield basis, source checks, invalidated by]

### Facts and assumptions
- Fact: [claim] -- [source ref and command/path]
- Assumption/default: [statement] -- [safe default | pending question | validated]

### Existing-system feature-preparation evidence (when applicable)
- Evidence ref: [feature_preparation_evidence.ref]
- Carried Product question: [item id, only if its evidence row is admissible]
- Preserve/change classification: [behavior_status + work_status]
- Do not carry an unsupported Product question: incomplete inspection is an
  evidence gap and contradictory sources are
  `source_conflict + source_conflict_resolution` until resolved.

### Design-pressure checks
| Check | Evidence or material question | Decision implication |
|---|---|---|
| Control/early exit | [consumer stop/cancel/seek behavior] | [pull/push/cancellation decision] |
| Ownership/disposal | [buffer/resource/cleanup owner] | [reuse/access/disposal rule] |
| Resource envelope | [workload, item/buffer/concurrency bounds] | [budget or explicit unknown] |
| Extension registration | [actual formats/algorithms/implementations] | [registration seam or explicit none] |
| Representative path | [producer -> consumer -> failure/cancellation] | [interface rationale/revalidation point] |

### Material design questions
#### [topic]
1. [single decision question]
   - Why / risk if guessed: [...]
   - Recommended default: [...]

### Boundaries and ownership
| Boundary | Owner | Lifecycle / dependency direction | Evidence |
|---|---|---|---|

### Type Ledger
| Concept | Semantic type or primitive exception | Boundary | Extension / validation seam |
|---|---|---|---|

### Interface contracts
| Consumer/owner | Input | Output/failure | Evolution strategy |
|---|---|---|---|

### Quality scenarios
| Quality scenario id | Attribute | Workload | Budget/threshold or explicit unknown | Measurement | Failure condition | Status | Verification ref |
|---|---|---|---|---|---|---|---|

### TDD test obligations
When TDD applies, list each Pack-derived obligation with a stable `obligation_id`,
one assistant-tdd obligation kind, the behavior to falsify, and verification.
Carry this typed list unchanged into CodeWriter and BuilderTester task packets;
the selected Build owner returns exact-once `architecture_obligation_coverage`.

### Decision and verification
- Selected design: [choice and rationale; matches selected alternative when alternatives are non-empty]
- Alternatives: [only genuine viable alternatives and trade-offs; each has stable `alternative_id`, exactly one `disposition=selected`, and `selected_alternative_id` resolves to it; empty alternatives omit selected_alternative_id and evidence the single path]
- Verification: [each stable `verification_id`: command/manual method, success signal, failure condition; verified quality scenarios resolve exactly one verification ref]
- Handoff binding: [discover_only with context-map/journal ref, or downstream_bound with task-packet and review refs]
```

## Quality claims are falsifiable

Do not approve or claim a memory, performance, extensibility, reliability, or
operability benefit without a stated workload, target/budget or explicit
unknown, measurement method, and failure condition. For streaming/resource
work, define bounded ownership and queue/buffer limits before claiming memory
efficiency; `budget_or_explicit_unknown=unknown` permits only pending or unknown
quality status, never verified. A verified scenario has a concrete falsifiable
budget or threshold and resolves exactly one `verification_ref` to a stable
`verification_id`; for example, a resource envelope may be expressed as fixed process
cost plus bounded concurrency times bounded per-item buffers. This is a design
hypothesis until its stated verification runs.

## Freshness and propagation

- Repository facts name the branch/revision and source command/path used.
  Greenfield packs state their assumptions instead.
- A changed HEAD, requirement, public contract, quality target, or discovered
  contradictory fact invalidates the pack. Refresh it before Build; do not
  rely on stale architecture prose.
- During Discover, set `handoff_binding_state=discover_only` and retain only
  `context_or_journal_ref`; discover_only forbids invented
  `plan_or_task_packet_ref` and `review_scope_ref`. For `prepare_only`, retain
  discover_only through Preparation Completion even when optional readiness
  planning runs. For `execution_intent != prepare_only`, Plan atomically binds
  `plan_or_task_packet_ref` and `review_scope_ref` before Build by setting
  `handoff_binding_state=downstream_bound` when `plan_mode!=none`. For that
  execution lane with `plan_mode=none`, the Discover exit transition atomically
  binds compact inline task-packet/execution and inline review-scope refs before
  any Build action. Build, Review, and completion retain
  handoff_binding_state=downstream_bound. Material invalidation clears stale
  downstream refs through refresh, re-plan, and reapproval.
- A plan deviation that changes the selected design, semantic contract,
  resource budget, or verification target requires the normal deviation and
  re-approval path.

## Independent challenge

For `review_intensive` packs, or when multiple viable alternatives have
conflicting material drivers, use `assistant-thinking` Perspectives or Stress
Test and retain its `independent_challenge_evidence` dissent/validation result.
The typed evidence records `challenge_ref`, `dissent_or_validation`, `resolution`,
and `selected_design_impact`.
Carry that evidence in Discover, Plan, the journal, and the review projection.
Do not invoke it merely because the task is medium or because an ADP exists.
