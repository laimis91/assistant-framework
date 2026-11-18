# Design standard: SOLID structure and pattern machinery

Status: **Accepted** by the user 2026-11-18, including D-DV-1 to D-DV-4; D-DV-5 added after independent review. Implemented on branch `feature/design-for-variation`. Behavioural evaluation of the new cases is owed (R-DV-8).
Source: user requests of 2026-11-05 and 2026-11-18. The user's M1 game build came out with enums and switch statements choosing behaviour although assistant-workflow was active. A follow-up session had to plan a refactor.

## Problem and intended outcome

Before this change the framework's design guidance did not shape how code was written:

- `assistant-workflow` loaded `references/prompts/solid-principles.md` only as a "relevant prompt pack". In the M1 session it was never read; the transcript shows only `SKILL.md` and `phases/plan.md` loaded.
- The guidance was a checklist applied after writing, graded by task size: the open/closed check applied only to medium tasks and up.
- Review and pattern retrieval leaned against the standard: "KISS and YAGNI override pattern enthusiasm", and review did not flag enums that "represent a small, stable, closed set". The M1 enums `PathShape` and `EnemyKind` had three values each.

Intended outcome: code written under the framework is object-oriented, SOLID and extendable by default. A new kind is added as a new class or data, not by editing working code. Overengineering is held back by limiting pattern machinery, not by allowing unstructured code.

## Requirements

- **R-DV-1. Structure is always required.** Every code change follows the structure rules in `skills/assistant-workflow/references/prompts/solid-principles.md`: one responsibility per class; behaviour collaborators and external boundaries behind interfaces; no enum, string, flag or type check selecting behaviour; substitutable implementations; small interfaces. Task size does not reduce them. Explicit project or user instructions take precedence (D-DV-1).
- **R-DV-2. Machinery waits for a second variant.** Factories, registries, selection settings, kind enums and pattern combinations are added only when a second variant exists or is requested. A single variant gets its interface and one implementation (D-DV-2).
- **R-DV-3. Data or behaviour.** Kinds that differ only in values are one class with the values in data. Kinds that differ in behaviour are one class per kind.
- **R-DV-4. Guidance loads when code is written.** The workflow's `SKILL.md` Implement step names the guide, so it loads even when no phase reference does. Every workflow plan that changes code loads the guide and fills an extension points table: what varies, variants now or requested, machinery, revisit when; executable task packets carry the rows they touch. Build loads the guide before writing code and applies its writing check after each step (`phases.md`, `build-worker-protocol.md`, gate B8). Delegated writer, architect and reviewer role prompts point to the same standard.
- **R-DV-5. Refactor before extending.** Before the first edit to existing code, Build checks the guide's triggers (a second variant, a new case in behaviour selection, a repeated type-code check, and others). When one applies, the concept being extended is refactored first without behaviour change, then the new variant is added. Larger refactors need the approved plan.
- **R-DV-6. Review enforces both sides.** `skills/assistant-review/references/review-principles.md` flags missing structure (behaviour chosen by type code at any number of values; must-fix when a diff adds a case to existing selection) and unjustified machinery (machinery for one variant, classes without a role). It does not flag interfaces with one implementation for a role or boundary, data types without interfaces, or plain value enums.
- **R-DV-7. Library examples are not the style.** Pattern-library examples show one pattern in isolation; their supporting code is not copied. The guide's own snippets show patterns used together and are original to the framework (D-DV-3).
- **R-DV-8. Behavioural evidence.** Eval cases cover: CSV export (interface plus one class, no factory), adding an enemy kind to enum-based code (refactor first), the extension points table, and review findings for both sides. Improvement claims need a matched run with and without the change; the run needs the user's authorization because it calls models.

## Sources

- Martin Fowler, [Yagni](https://martinfowler.com/bliki/Yagni.html): YAGNI applies to presumptive features, and does not apply to effort that makes software easier to modify. Supports R-DV-1 and R-DV-2.
- Martin Fowler, [Replace Conditional with Polymorphism](https://refactoring.com/catalog/replaceConditionalWithPolymorphism.html): a switch on a type becomes one class per type. Supports R-DV-1 and R-DV-6.
- Martin Fowler, [An example of preparatory refactoring](https://martinfowler.com/articles/preparatory-refactoring-example.html), quoting Kent Beck: "make the change easy, then make the easy change". Supports R-DV-5.
- D. L. Parnas, "On the criteria to be used in decomposing systems into modules", Communications of the ACM 15(12), 1972: modules hide design decisions likely to change. Supports R-DV-1.
- Representative cases: the M1 game code (`RunPhase`, `CommandResult`, `PathShape`, `EnemyKind`, repeated `card.IsTile` checks) and a CSV export that later gains a second format.

These sources support the method. They do not show that the guidance changes model output; R-DV-8 owns that claim.

## Decisions

- **D-DV-1.** Chosen by the user 2026-11-18: SOLID structure is the framework default for every plugin install, not only a personal preference.
- **D-DV-2.** Chosen by the user 2026-11-18: there is no "plain code" level. Structure is always required; only machinery waits for evidence. Plain code is misunderstood by other developers and later sessions and then left as is.
- **D-DV-3.** Snippets are written for the framework instead of copied from the user's example library, to keep personal material and third-party course code out of the plugin.
- **D-DV-4.** The plugin ships skills only, so it cannot install a path-scoped rule. The README shows an optional personal rule that loads the guide when a C# file is touched.
- **D-DV-5.** The writer, architect and reviewer role prompts in `agents/` were aligned in the same change, after independent review found that "follow existing conventions exactly" and "no unrequested refactors" would make delegated writers extend enum-based code. Existing type-code patterns are not conventions to copy, and a refactor-before-extending step in the packet is requested work.

## Owners

- Writing guide: `skills/assistant-workflow/references/prompts/solid-principles.md`.
- Plan and Build loading: `skills/assistant-workflow/SKILL.md`, `references/phases.md`, `plan-template.md`, `build-worker-protocol.md`, `contracts/phase-gates.yaml` (B8).
- Review: `skills/assistant-review/references/review-principles.md` and `review-rubric.md`.
- Role prompts: `agents/claude/` and `agents/codex/` writer, architect and reviewer roles, synced into each skill's `references/roles/`.
- Pattern library use: `skills/assistant-workflow/references/design-pattern-retrieval.md`.
