# Document Review

Use instead of code sections for a specification, plan, ticket, refinement item or tests.
Provisional until derived per `assistant-skill-creator/references/expert-method-design.md`.

1. **Intent**: restate it. Each requirement or step must be testable and traceable to it; flag unsourced claims.
2. **Gaps**: conflicts, unstated assumptions, missing failure paths, dependencies, owners. Per plan step: rollback and verification. Run a pre-mortem ("it failed; why?").
3. **Plan versus code**: trace both ways, step to code and tests. Unplanned behavior is scope creep or a missing requirement.
4. **Ticket**: testable criteria, linked dependencies, open questions. Proposed ticket text stays local; Jira write-back needs approval.
5. **Tests**: could each fail for the right reason against a plausible wrong implementation?
