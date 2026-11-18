# Review Principles Lens

Use these principles during code review. The SOLID structure and behaviour-selection rules below are the default standard for changed code; the other principles are evidence lenses. A finding is actionable only when it ties a specific observation to concrete risk and the smallest durable fix.

## SOLID

SOLID, object-oriented and extendable structure is the framework's default standard for every code change, unless explicit project or user instructions say otherwise. Structure is required; pattern machinery is not (see [Behaviour selection and machinery](#behaviour-selection-and-machinery)).

- Single Responsibility: a unit should have one cohesive reason to change. Flag classes or methods that mix policy, orchestration, I/O, formatting, persistence, or validation.
- Open/Closed: a new kind should be addable without editing existing kinds. Flag switch/if growth on a type code, scattered feature edits, and changes that add a case to existing behaviour selection.
- Liskov Substitution: subtypes, implementations, or strategy objects must preserve caller expectations. Flag implementations that narrow accepted inputs, weaken guarantees, throw unexpected exceptions, or require caller type checks.
- Interface Segregation: consumers should not depend on methods or data they do not use. Flag broad interfaces when they force no-op implementations, fake dependencies in tests, or unrelated callers to change together.
- Dependency Inversion: high-level policy should not be glued to low-level details at boundaries. Flag behaviour collaborators used as concrete classes, and direct dependencies on infrastructure, time, randomness, network, filesystem, or framework APIs, when callers cannot depend on an interface instead.

## Design Coherence Pass

For every medium+ review, identify the affected unit, boundary, responsibility, and independent reasons to change. Assess hidden coupling/state and data/control flow. Record `principle_checks.design_coherence` as `no concrete risk found` or an evidence-backed finding with affected surface, risk, and smallest durable fix. Do not infer a finding from code size, structural diff shape, or familiar pattern alone; a cohesive unit may correctly conclude `no concrete risk found`.

## KISS

Prefer the simplest design that satisfies the verified requirement within the SOLID structure; KISS never justifies mixed responsibilities or behaviour chosen by type code. Flag needless layers, abstractions, configuration, indirection, state, branching, concurrency, or patterns that make current behavior harder to read, test, or change. A small abstraction that removes real duplication, isolates side effects, or makes a current requirement safer may be simpler.

## DRY

DRY is about duplicated knowledge, not merely similar-looking code. Flag business rules, schemas, validation, calculations, mappings, config, permissions, or protocol details with multiple authoritative representations that can diverge. Do not merge coincidental or independently changing similarities into hidden coupling.

## Reuse Search and Authoritative Duplication

Before implementation and independently during review, search existing capabilities for business rules, validation, calculations/conversions, mappings, schema/config semantics, permissions, or protocol details, plus file/state-rewriting operations. Duplicated authoritative behavior is should-fix, and must-fix when semantics differ or duplication caused the bug. Non-findings include coincidental similarity and independent concepts. Intentional boundary duplication needs divergence control. Check the Build reuse-first choice for sufficient affected consumers, validation
and error handling; shorter code alone proves nothing. Carried Mapper/task-packet evidence alone cannot satisfy review; record searches, candidates or no-candidate reason, decision, and rationale.

## YAGNI

Avoid imagined-future capability: flag pattern machinery for a single variant, unused abstractions/config/parameters, anticipatory generic types, classes without a nameable role, and future-only branches that add current complexity. YAGNI does not apply to SOLID structure: an interface with one implementation for a behaviour role or an external boundary is required structure, not speculation.

## State and Extensibility Modeling

### Nullable properties as hidden state

- Flag code when `null -> value` or `value -> null` represents a business or lifecycle transition, especially when rules, side effects, or required data depend on that change.
- Prefer named states and explicit transition methods or events that carry the required data.
- Do not flag nullable properties when `null` only means optional or missing data.

### Behaviour selection and machinery

Missing structure:

- Flag a value that identifies a kind or mode (enum, string code, bool flag, or type check) and selects behaviour, whatever the number of values. Ordinary conditions on state are not type codes, and a registry or factory at the composition boundary may pick an implementation by key. The fix is one class per kind behind a shared interface, or data when kinds differ only in values. Should-fix; must-fix when the diff adds a case, value, or branch to existing behaviour selection, even a small one, because that edits working code to add a kind instead of refactoring first.
- Flag kinds that differ only in values but are modelled as separate classes or branches; the fix is one class with the values in data.

Unjustified machinery:

- Flag a factory, registry, selection setting, kind enum, or empty variant class when only one variant exists or is requested. The fix is to remove the machinery and keep the interface and its one implementation.
- Flag a class or interface that has no nameable role, such as a pass-through wrapper.

Do not flag:

- an interface with one implementation that represents a behaviour role or an external boundary;
- interfaces missing from data types such as records, value objects, or DTOs;
- an enum that is a plain list of values with no behaviour attached, or an external API's enum.

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
- risk category: correctness, security, unsafe change surface, branching/responsibility growth, hidden dependency/ownership, brittle testing, poor extension seam, unjustified machinery, or readability/maintainability drag
- evidence: file, line, and observed behavior
- fix: the smallest durable change that removes the risk

A simplification, reuse, altitude or workaround finding also states:

- actual cost, with file:line: what is duplicated or wasted, or what it makes
  harder to change. A finding that cannot name its cost is a nit.
- why the code is not an intentional boundary, such as a compatibility shim, staged
  migration, vendored-code isolation or documented divergence. Check history,
  comments, consumers and docs first; the divergence-control rule in Reuse Search
  and Authoritative Duplication applies. When intent cannot be determined, keep the
  finding low-confidence and non-blocking, unless the duplicate changes
  authoritative semantics or causes an observed defect: then the Reuse Search
  severity applies.

Do not report vague findings without evidence and risk.
