# Domain Rubrics

Use this reference only for QA evaluation when scoped domain quality is part of acceptance. Domain rubric use is conditional and must be tied to at least one of: acceptance criteria, Done Contract, `domain_context`, or explicit `rubric_refs`. Do not load or apply these rubrics for code-review-only work, and do not invent new rubric families when the scope does not name or imply them.

## Selection Rules

- Select the smallest relevant rubric family set: `ui_visual_design`, `ux_product_acceptance`, `documentation_quality`, `developer_experience`, or `domain_specific_craft`.
- Score only selected dimensions that have evidence. Use `not_applicable` for unscoped dimensions instead of lowering the score.
- Evidence must cite acceptance criteria, Done Contract items, `domain_context`, `rubric_refs`, verification artifacts, screenshots, docs, commands, or concrete changed files.
- Return `selected_domain_rubrics` and `domain_quality_scores` when any family is selected.
- If a needed domain standard is not provided and cannot be discovered locally, return `NEEDS_CONTEXT` or `blocked` with open questions instead of fabricating the standard.

## Scoring

| Score | Meaning | QA action |
|---|---|---|
| 5 | Fully satisfies scoped expectations with direct evidence | accepted |
| 4 | Meets acceptance with minor non-blocking concerns | accepted_with_concerns |
| 3 | Partially meets scope; fixable gaps remain | refine |
| 1-2 | Core scoped expectation is contradicted or unproven | rejected or pivot |

Use `accepted` only when all selected dimensions are 4+ and no blocker acceptance findings remain. Use `refine` when gaps are concrete and fixable within the approved scope. Use `pivot` when the selected rubric exposes a wrong product/design/domain direction, missing domain authority, or repeated failure that needs a plan change.

## UI / Visual Design

Use when acceptance names UI, visual design, layout, responsive behavior, screenshots, design parity, or explicit `rubric_refs: [ui_visual_design]`.

| Dimension | Evidence examples | Pass / refine / pivot guidance |
|---|---|---|
| Layout and hierarchy | Screenshots, viewport checks, design refs, component files | Pass when priority and grouping match the task; refine overlaps, weak hierarchy, or cramped spacing; pivot if the visual model contradicts the requested design direction. |
| States and feedback | Loading, empty, error, hover/focus, disabled states | Pass when required states are represented; refine missing secondary states; reject if a required user path has no visible feedback. |
| Accessibility and readability | Keyboard/focus checks, contrast notes, text fit, labels | Pass when text is readable and controls are operable; refine low-risk contrast/text issues; reject blocked interaction, hidden labels, or clipped essential text. |
| Visual fit and consistency | Existing design system, tokens, component conventions | Pass when it fits the local system; refine inconsistent spacing/color/component usage; pivot if the implementation introduces a conflicting visual language. |

## UX / Product Acceptance

Use when acceptance names user workflow, product behavior, adoption/readiness, copy, or explicit `rubric_refs: [ux_product_acceptance]`.

| Dimension | Evidence examples | Pass / refine / pivot guidance |
|---|---|---|
| Goal completion | User journey, task criteria, manual scenario evidence | Pass when target users can complete the stated job; refine friction or avoidable extra steps; reject if the primary job cannot be completed. |
| Decision clarity | Labels, prompts, defaults, next-action visibility | Pass when choices and consequences are clear; refine ambiguous copy; reject misleading or destructive flows. |
| Edge and recovery paths | Empty/error states, undo/retry paths, validation messages | Pass when expected edge cases are handled; refine incomplete recovery; reject dead ends for scoped scenarios. |
| Product fit | Domain context, stakeholder criteria, non-goals | Pass when behavior matches product intent; refine minor mismatches; pivot if the implementation solves the wrong user problem. |

## Documentation Quality

Use when acceptance names docs, README, API docs, migration notes, runbooks, or explicit `rubric_refs: [documentation_quality]`.

| Dimension | Evidence examples | Pass / refine / pivot guidance |
|---|---|---|
| Accuracy | Compared code/config/contracts, command outputs, examples | Pass when docs match current behavior; refine stale or ambiguous details; reject false commands, wrong APIs, or unsafe guidance. |
| Completeness for task | Acceptance criteria, documented setup/use/troubleshooting path | Pass when the target reader can finish the task; refine missing edge notes; reject missing required setup or operation steps. |
| Structure and scanability | Headings, ordered procedures, tables, examples | Pass when information is easy to find; refine dense or duplicated sections; pivot if docs need a different artifact type. |
| Maintenance fit | Version notes, ownership, generated/manual boundaries | Pass when update path is clear; refine unclear ownership; reject docs that will drift from source of truth. |

## Developer Experience

Use when acceptance names CLI/API ergonomics, local setup, integration, maintainability for consumers, or explicit `rubric_refs: [developer_experience]`.

| Dimension | Evidence examples | Pass / refine / pivot guidance |
|---|---|---|
| Setup and run path | Commands, scripts, examples, env/config notes | Pass when a developer can start reliably; refine missing context; reject hidden prerequisites or broken commands. |
| Contract ergonomics | API shape, schema fields, handoff packets, error messages | Pass when contracts are predictable and typed; refine confusing names/defaults; reject ambiguous or incompatible contract behavior. |
| Debuggability | Logs, validation errors, trace/replay artifacts, failure messages | Pass when failures are diagnosable; refine thin evidence; reject silent failure or misleading diagnostics. |
| Change safety | Tests/evals/guards, migration notes, compatibility story | Pass when future edits have guardrails; refine narrow gaps; reject fake-pass coverage or unguarded public contract changes. |

## Domain-Specific Craft

Use when acceptance names a specialized domain, craft standard, industry rule, expert terminology, or explicit `rubric_refs: [domain_specific_craft]`.

| Dimension | Evidence examples | Pass / refine / pivot guidance |
|---|---|---|
| Domain rule fidelity | Done Contract, domain_context, standards, fixtures | Pass when required rules are preserved; refine minor omissions; reject contradictions to scoped domain rules. |
| Terminology and mental model | User language, docs, UI copy, schema names | Pass when terms match the domain audience; refine inconsistent wording; reject misleading terms that change meaning. |
| Expert edge cases | Provided edge cases, fixtures, acceptance examples | Pass when scoped edge cases are covered; refine low-risk omissions; reject missing high-impact edge cases. |
| Artifact craft | Generated asset, workflow, document, content, or domain output | Pass when artifact quality meets the named craft bar; refine polish gaps; pivot if the artifact type or approach is wrong. |

High-stakes domains still require the relevant specialist gate when applicable. This rubric does not replace security, legal, medical, financial, privacy, or compliance review.
