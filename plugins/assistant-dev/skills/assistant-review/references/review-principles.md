# Review Principles Lens

Use these principles as evidence lenses during code review. They are not standalone pass/fail laws. A finding is actionable only when it ties a specific observation to concrete risk and the smallest durable fix.

## SOLID

Apply SOLID primarily to object-oriented or dependency-heavy code:

- Single Responsibility: a unit should have one cohesive reason to change. Flag mixed policy, orchestration, I/O, formatting, persistence, and validation only when the mix makes change risky or tests brittle.
- Open/Closed: code should allow likely extension without repeatedly editing fragile core logic. Flag switch/if growth, scattered feature edits, or closed extension points when a current requirement already shows the pattern will churn.
- Liskov Substitution: subtypes, implementations, or strategy objects must preserve caller expectations. Flag implementations that narrow accepted inputs, weaken guarantees, throw unexpected exceptions, or require caller type checks.
- Interface Segregation: consumers should not depend on methods or data they do not use. Flag broad interfaces when they force no-op implementations, fake dependencies in tests, or unrelated callers to change together.
- Dependency Inversion: high-level policy should not be glued to low-level details at boundaries. Flag direct dependencies on infrastructure, time, randomness, network, filesystem, or framework APIs when they hide behavior or block testing.

## KISS

Prefer the simplest design that satisfies the verified requirement. Flag unnecessary layers, generic abstractions, configuration, indirection, state, branching, concurrency, or patterns when they make the current behavior harder to read, test, or change.

KISS does not mean under-design. If a small abstraction removes real duplication, isolates external side effects, or makes a current requirement safer, it may be the simpler design.

## DRY

DRY is about duplicated knowledge, not merely similar-looking code. Flag duplication when the same business rule, schema, validation rule, calculation, mapping, config, permission, or protocol detail has multiple authoritative representations that can diverge.

Do not force DRY on coincidental resemblance. If two similar blocks serve different concepts or change for different reasons, merging them can create hidden coupling.

## YAGNI

Avoid building capability for imagined future requirements. Flag speculative extension points, unused abstractions, dormant config, unused parameters, anticipatory generic types, and future-only branches when they add complexity without serving the current task.

YAGNI is not permission to neglect code health. Tests, refactoring that keeps the code malleable, and small seams around real side effects can be current needs.

## Readability

Readability is a human judgment of how easy code is to understand and safely maintain. Review for:

- names that reveal domain intent and avoid misleading abstractions
- small, cohesive functions/classes with explicit data flow
- straightforward control flow with low nesting and limited hidden state
- clear error paths and boundary behavior
- formatting and grouping that separate ideas without relying on comments
- comments that explain why, tradeoffs, or invariants rather than restating what
- tests that read as executable behavior examples

When reporting readability, cite the specific comprehension burden: ambiguous name, mixed abstraction levels, non-local state, long conditional path, duplicated concept, misleading comment, or test intent that cannot be inferred.

## Reporting Rule

Principle findings must include:

- lens: SOLID, KISS, DRY, YAGNI, readability, or a precise combination
- risk category: correctness, security, unsafe change surface, branching/responsibility growth, hidden dependency/ownership, brittle testing, poor extension seam, or readability/maintainability drag
- evidence: file, line, and observed behavior
- fix: the smallest durable change that removes the risk

Do not report vague findings such as "not clean", "violates SOLID", "not DRY", or "hard to read" without evidence and risk.
