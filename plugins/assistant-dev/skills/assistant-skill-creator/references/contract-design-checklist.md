# Contract Design Checklist

Validate every new or modified skill against these 10 rules from the [contract design guide](skill-contract-design-guide.md). All must pass.

## The 10 Rules

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

### 7. Contracts only grow
- [ ] No removal of previously required fields (breaking change)
- [ ] New optional fields use `required: false` with defaults
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

## Quick Reference: Contract Tier Requirements

| Tier | input.yaml | output.yaml | phase-gates.yaml | handoffs.yaml |
|---|---|---|---|---|
| **Utility** | Required | Required | - | - |
| **Analysis** | Required | Required | Required | - |
| **Process** | Required | Required | Required | Required |
