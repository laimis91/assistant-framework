# Verified Skill Distillation

Use this when a completed workflow, review lesson, reusable procedure, or explicit user request should become a durable skill, checklist, contract, or eval rule.

Do not save task progress as a skill. Distill only reusable procedure.

## Required packet

```text
Verified Skill Distillation:
- Candidate workflow: [short name]
- Inputs: [what triggers it]
- Process steps: [reusable ordered steps]
- Output artifact: [what it produces]
- Verification gate: [tests/review/evidence required]
- Learned constraints: [rules that prevent prior failure]
- Scope and non-goals: [where it applies / does not apply]
- Evidence: [successful run, review result, eval, or repeated use]
- Verifier result: approved | rejected | needs_revision
- Promotion decision: create_skill | update_skill | add_constraint | skip
```

## Rules

- Require an independent verifier or blocker-only review before creating/updating skill files from a workflow lesson.
- `verifier_result` must be `approved` before promotion.
- Remove transient task status, PR numbers, issue IDs, commit SHAs, secrets, credentials, run logs, and stale facts.
- If the lesson is narrow, add a checklist/contract/eval instead of a new skill.
- If verification fails, return a revision checklist and do not write durable skill files.
