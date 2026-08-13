# Contract Design Checklist

Validate every new or modified skill against these 14 rules from the [contract design guide](skill-contract-design-guide.md). All must pass.

## The 14 Rules

### 1. Required fields have `on_missing` actions
- [ ] Every field with `required: true` has an `on_missing:` value
- [ ] Valid actions: `ask`, `infer`, `skip`, `fail`, `re-dispatch`
- [ ] `ask` fields have an `ask_prompt:`
- [ ] `infer` fields have an `infer_from:` rule

### 2. Enum types list all values
- [ ] Every `type: enum` field has `enum_values:` with all valid options
- [ ] No open-ended enums (no "etc.", "other", or catch-all values)

### 3. Validation rules are plain English
- [ ] No regex patterns in `validation:` fields
- [ ] No code snippets or framework-specific syntax
- [ ] Rules are readable by any developer

### 4. Phase gates are binary assertions
- [ ] Every `check:` is a statement that is either true or false
- [ ] No subjective criteria ("looks good", "seems correct")
- [ ] No compound assertions — split "A and B" into two separate checks

### 5. Handoff schemas match
- [ ] Producer's `return_fields` satisfy consumer's `context_fields`
- [ ] Field names match between producer output and consumer input
- [ ] Field types are compatible
- [ ] N/A for Utility and Analysis skills

### 6. Corrective actions are actionable
- [ ] No "fix it" or "handle this" corrective actions
- [ ] Each `on_fail:` describes a specific recovery step
- [ ] Recovery steps reference concrete actions (ask user, re-dispatch agent, add field)

### 7. Contracts grow within a major version
- [ ] Existing major versions do not remove or weaken required fields
- [ ] Breaking required-field changes bump the major `schema_version` and add a root `SKILL.md` migration note
- [ ] Consumers, evals, and mirrors are updated for the new major version
- [ ] New optional fields use `required: false` with a default or explicit inference rule
- [ ] N/A for brand-new skills (no prior version)

### 8. Conditional fields use `condition:`
- [ ] Fields that only apply in certain contexts use `required: conditional` with `condition:`
- [ ] Conditions are plain English and unambiguous
- [ ] No fields forced to `required: true` when they only apply sometimes

### 9. Ambiguous fields have `examples:`
- [ ] Fields where the description alone could be misinterpreted include `examples:`
- [ ] Examples are realistic, not placeholder values
- [ ] At least 2 examples per ambiguous field

### 10. Cross-phase invariants catch drift
- [ ] At least one `invariant:` with `scope: all_phases` (for Process/Analysis skills)
- [ ] Invariants cover things that must ALWAYS be true, not just at gates
- [ ] N/A for Utility skills (no phases)

### 11. Root instructions are outcome-shaped
- [ ] Non-trivial skills state Goal, Success criteria, Constraints, Output, and Stop rules
- [ ] Root `SKILL.md` stays compact; detailed examples live in `references/`
- [ ] The sections describe behavior-changing guidance, not decorative prose

### 12. Clarification prompts are admissible
- [ ] `on_missing: ask` is used only for missing data that materially changes the outcome
- [ ] The answer cannot be discovered from prompt, context, local files, or safe defaults
- [ ] Ask every unresolved material question, grouped by topic with why/risk/default; clear prompts proceed without ritual questions and no numeric quota suppresses material uncertainty

### 13. Semantic interfaces retain domain meaning
- [ ] Public/domain/lifecycle/unit/extension-bearing parameters, returns, collections, and callbacks use named semantic types rather than generic primitives
- [ ] A primitive exception is explicitly classified as local temporary, wire/storage, foreign/framework, or no-domain-semantics and has nearby conversion/validation
- [ ] Cohesive request/command types may evolve; public/serialized contracts have a versioning, adapter, compatibility, or migration path
- [ ] When an interface chooses control flow, resource ownership, or an extension seam, it records a representative producer-consumer path plus applicable early-exit, disposal, bounded-resource, and registration checks instead of inventing a generic engine

### 14. Loop controllers are explicit and bounded
- [ ] Loop-based Process skills define explicit bounded controller artifacts
- [ ] Code review and QA remain distinct responsibilities and handoffs
- [ ] Stagnation, repeated drift/regression, pivots, and blockers use explicit pivot/restart decisions
- [ ] Review, QA, and fix-verify loops terminate after at most 10 rounds

## Quick Reference: Contract Tier Requirements

| Tier | input.yaml | output.yaml | phase-gates.yaml | handoffs.yaml |
|---|---|---|---|---|
| **Utility** | Required | Required | - | - |
| **Analysis** | Required | Required | Required | - |
| **Process** | Required | Required | Required | Required |
