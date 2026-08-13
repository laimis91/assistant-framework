# Review Principles Lens

Use these principles as evidence lenses during code review. They are not standalone pass/fail laws. A finding is actionable only when it ties a specific observation to concrete risk and the smallest durable fix.

## SOLID

Apply SOLID primarily to object-oriented or dependency-heavy code:

- Single Responsibility: a unit should have one cohesive reason to change. Flag mixed policy, orchestration, I/O, formatting, persistence, and validation only when the mix makes change risky or tests brittle.
- Open/Closed: code should allow likely extension without repeatedly editing fragile core logic. Flag switch/if growth, scattered feature edits, or closed extension points when a current requirement already shows the pattern will churn.
- Liskov Substitution: subtypes, implementations, or strategy objects must preserve caller expectations. Flag implementations that narrow accepted inputs, weaken guarantees, throw unexpected exceptions, or require caller type checks.
- Interface Segregation: consumers should not depend on methods or data they do not use. Flag broad interfaces when they force no-op implementations, fake dependencies in tests, or unrelated callers to change together.
- Dependency Inversion: high-level policy should not be glued to low-level details at boundaries. Flag direct dependencies on infrastructure, time, randomness, network, filesystem, or framework APIs when they hide behavior or block testing.

## Design Coherence Pass

For every medium+ review, identify the affected unit, boundary, responsibility, and independent reasons to change. Assess hidden coupling/state and data/control flow. Record `principle_checks.design_coherence` as `no concrete risk found` or an evidence-backed finding with affected surface, risk, and smallest durable fix. Do not infer a finding from code size, structural diff shape, or familiar pattern alone; a cohesive unit may correctly conclude `no concrete risk found`.

## KISS

Prefer the simplest design that satisfies the verified requirement. Flag needless layers, abstractions, configuration, indirection, state, branching, concurrency, or patterns that make current behavior harder to read, test, or change. A small abstraction that removes real duplication, isolates side effects, or makes a current requirement safer may be simpler.

## DRY

DRY is about duplicated knowledge, not merely similar-looking code. Flag business rules, schemas, validation, calculations, mappings, config, permissions, or protocol details with multiple authoritative representations that can diverge. Do not merge coincidental or independently changing similarities into hidden coupling.

## Reuse Search and Authoritative Duplication

Before implementation and independently during review, search existing capabilities for business rules, validation, calculations/conversions, mappings, schema/config semantics, permissions, or protocol details. Duplicated authoritative behavior is should-fix, and must-fix when semantics differ or duplication caused the bug. Non-findings include coincidental similarity and independent concepts. Intentional boundary duplication needs divergence control. Carried Mapper/task-packet evidence alone cannot satisfy review; record searches, candidates or no-candidate reason, decision, and rationale.

## YAGNI

Avoid imagined-future capability: flag speculative extension points, unused abstractions/config/parameters, anticipatory generic types, and future-only branches that add current complexity. YAGNI is not permission to neglect code health; it permits tests, health refactoring, and small seams around real side effects.

## State and Extensibility Modeling

### Nullable properties as hidden state

- Flag code when `null -> value` or `value -> null` represents a business or lifecycle transition, especially when rules, side effects, or required data depend on that change.
- Prefer named states and explicit transition methods or events that carry the required data.
- Do not flag nullable properties when `null` only means optional or missing data.

### Enums as extension points

- Flag an enum when it represents an open-ended feature set and adding a value requires changing switches or conditionals in several places.
- Prefer handlers, strategies, or another extensible design for open-ended cases.
- Do not flag enums that represent a small, stable, closed set.

## Readability

Readability is a human judgment of how easy code is to understand and safely maintain. Review for:

- names that reveal domain intent and avoid misleading abstractions
- small, cohesive functions/classes with explicit data flow
- straightforward control flow with low nesting and limited hidden state
- clear error paths and boundary behavior
- formatting and grouping that separate ideas without relying on comments
- comments that explain why, tradeoffs, or invariants rather than restating what
- tests that read as executable behavior examples

Report the specific comprehension burden: ambiguous name, mixed abstraction, non-local state, long conditional path, duplicated concept, misleading comment, or unclear test intent.

## Reporting Rule

Principle findings must include:

- lens: SOLID, KISS, DRY, YAGNI, readability, design coherence, or combination
- risk category: correctness, security, unsafe change surface, branching/responsibility growth, hidden dependency/ownership, brittle testing, poor extension seam, or readability/maintainability drag
- evidence: file, line, and observed behavior
- fix: the smallest durable change that removes the risk

Do not report vague findings without evidence and risk.
