---
name: assistant-skill-creator
description: "Create or update V1 skills and contracts. Use for skill scaffolding, contract design, or contract-compliance validation."
effort: medium
triggers:
  - pattern: "create skill|new skill|add contracts|skill contracts|scaffold skill|create a skill|make a skill|build a skill"
    priority: 75
    min_words: 3
    reminder: "This request matches assistant-skill-creator. You MUST invoke the Skill tool with skill='assistant-skill-creator' BEFORE creating skill files directly."
---

# Skill Creator

## Goal

Create compact, contract-backed V1 skills with precise routing, typed boundaries,
safe fallback behavior, and offline validation.

## Success Criteria

- The skill uses the correct Process, Analysis, or Utility contract tier.
- Root instructions state Goal, Success Criteria, Constraints, Output, and Stop Rules.
- Missing inputs ask only when outcome-shaping and otherwise infer, skip, or fail.
- Evals cover positive routing plus a false-positive or unsafe behavior case.

## Constraints

- Keep root `SKILL.md` concise and move detail to on-demand references.
- Analysis and Utility skills do not gain subagent handoffs.
- Memory, metrics, automation, subagents, external tools, and state paths stay
  optional/configurable and policy-gated unless the skill explicitly owns them.
- Keep examples agent-agnostic and free of secrets, private endpoints, customer
  data, and workplace-specific confidential details.

## Progressive Contract Loading

Canonical tier files are `contracts/input.yaml`, `contracts/output.yaml`, and
`contracts/phase-gates.yaml`.

Read `contracts/index.yaml` first and load only the active boundary:

- `entry` for purpose, category, triggers, dependencies, policy, and existing path;
- `current_phase` for CAPTURE, DESIGN, VERIFIED_DISTILLATION, BUILD, or VALIDATE;
- `contract_design` for ordinary contract design;
- `harness_design` only for loop-based Process skills;
- `verified_distillation` only when promoting a completed workflow/lesson;
- `validation` only for the final checklist; and
- `completion` only for the artifact being returned.

Missing or invalid selectors fall back to the full named canonical contract. Do
not load every contract or reference at entry.

The skill-local contract guide is generated from docs/skill-contract-design-guide.md;
edit the docs source, then run
`tools/skills/sync-skill-contract-guide.sh --apply`.

## Ownership

assistant-skill-creator owns skill contract design, routing precision, and
contract validation. Generic workflow may coordinate file edits and review, but
specialist gates are authoritative.

## Phases

### CAPTURE

Resolve name, purpose, category, triggers, dependencies, policy constraints, and
effort. **Existing skill shortcut:** when `existing_skill_path` exists, read the
current skill and proceed to DESIGN without asking for captured facts again.

Contract tiers:

- Utility: input + output
- Analysis: input + output + phase-gates
- Process: input + output + phase-gates + handoffs

### DESIGN

Load `contract_design`. Define typed input/output fields, recovery actions,
binary phase gates, invariants, and matching handoffs where applicable. Present
new or materially changed contract design for user review before BUILD. A small,
reversible existing-skill edit may proceed when direction is already explicit.

For a Process skill with multi-round review, QA, optimization, or restart loops,
load `harness_design` and apply `references/harness-patterns.md`: bounded rounds,
rubric/score progression, drift/stagnation handling, separate generation and
evaluation, and explicit completion/pivot artifacts.

### VERIFIED_DISTILLATION

When turning a completed workflow or lesson into a reusable skill, load
`verified_distillation`. Require `distillation_verification` with
`verifier_result: approved` before writing. Remove task progress, PR numbers,
secrets, logs, and stale facts; otherwise return a revision checklist.

### BUILD

Create `skills/<name>/SKILL.md`, required tier contracts, and focused evals.
Keep canonical contract headers and descriptions precise. Reuse repository
templates; add references only when they reduce root load.

### VALIDATE

Load `validation`; run the 13 contract design guide rules plus company-safety,
source validation, eval validation, sync checks, and relevant P0-P4 contracts.
Fix failures before reporting `VALIDATE COMPLETE`.

## Output

Return status, changed files, contract tier/summary, validation evidence,
policy-safety summary, and unresolved gaps.

## Stop Rules

- Stop when purpose/category ambiguity changes contract shape.
- Stop before skill work if the canonical contract guide was not read.
- Stop before BUILD when required design approval or verified distillation is absent.
- Stop before completion when contracts, evals, validation, or generated sync fail.
