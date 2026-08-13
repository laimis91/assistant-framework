---
name: assistant-workflow
description: "Run proportional development phases and resume persisted task state. Use to plan, build, implement, fix, migrate, refactor, or continue project artifacts."
effort: high
triggers:
  - pattern: "rewrite|implement|fix|migrate|refactor|continue|resume|recover|build feature|build the|build a|build an|create feature|add feature|(create|make) (a |an |the |new )*(rest |api )?(endpoint|dashboard|screen|page|component|service|tool|app|feature)|idea into (an |a )?(implementation plan|implementation|plan|code|feature)|how should i approach|break this down|start working on|let.s (build|create|implement|add|make|fix|migrate|refactor|rewrite)|phase [0-9]|code (this|that|it|the|a|an|up)"
    priority: 40
    min_words: 2
    reminder: "Read this SKILL.md and contracts/index.yaml, load only the active selector, scale phases, test changes, and verify before completion."
---

# Development Workflow

## Goal

Move project work from the newest accepted requirement to a verified,
reviewed, reconstructable outcome with the least process that safely fits the
risk.

## Success Criteria

- Run the proportional phase path: Discover -> optional Decompose -> optional Plan ->
  optional Design -> Build -> Review -> Document. Scale phases; do not omit
  their applicable gates.
- Reconcile persisted state against the newest user request and current
  repository evidence before using its next action.
- If resume reconciliation classifies persisted state as stale, superseded, or completed,
  update the framework-owned `{agent_state_dir}/task.md` before acting or returning; record the classification and reason, current task identity, and repaired exact next action.
- Ask only about material, undiscoverable implementation choices with no safe
  default. Otherwise state the default and proceed.
- For medium+, create stable requirement ids with binary criteria and
  verification methods; small work keeps compact acceptance unless promoted by
  ambiguity, risk, or multiple material requirements.
- Select `plan_mode`: trivial safe work uses `none`, bounded small work may use
  `inline`, and medium+, risky, destructive, or scope-shaping work uses
  `approval_required` and waits before Build.
- Behavior changes use valid RED -> minimal GREEN -> refactor-safe verification,
  or record an approved non-behavior exception.
- Ordinary medium work uses one bounded edit/test executor plus independent
  Code Reviewer. Separate Writer and Builder/Tester only when risk or broad,
  noisy, environment-heavy, or explicitly independent verification requires it.
- Complete applicable Spec, quality, security, and QA routes. QA is required
  only by its explicit acceptance triggers.
- Build repair owns implementation/verification failures; Review owns review-fix
  and fresh re-review. Document is the sole owner of `final_handoff`.
- Medium+ output follows `references/final-handoff.md`; every accepted
  requirement has passed evidence or an approved exclusion.

## Constraints

- Explicit user or repository artifact schemas override workflow-internal shapes; preserve exact paths, keys, types, ids, and supplied literals.
- Preserve user changes, secrets, permissions, and company data boundaries.
- Prefer repository-native commands and patterns. Do not install or call
  external services without approval.
- Keep scope changes explicit. Replan and seek approval when files, behavior,
  risk, verification, or acceptance changes materially.
- Treat SOLID, KISS, DRY, YAGNI, and patterns as evidence lenses. Refactor only
  for a concrete correctness, security, ownership, testing, extension, or
  maintainability risk.
- Exact phase markers are required only by strict mode, project policy, or user
  request; otherwise use concise progress updates.

## Contract Loading

Read `contracts/index.yaml` first. Canonical contracts remain authoritative;
load only the active selector:

- `entry` for task inputs and triage;
- `current_phase` for the active transition and invariants;
- `selected_handoff` before dispatch and return validation;
- `completion` before final exit.
- `delegation` before dispatch for indexed role/trigger fields.

Missing or invalid selectors use `load_full_authoritative_file` and record the
recovery. Load `references/workflow-controller.md` for cross-phase routing and
`references/phases.md` for phase mechanics. Load other references only when
their named condition applies.

Migration: workflow v4 uses `subagent_trigger_scope`; `verification_command`
remains non-empty argv `string[]`. assistant-review v5 owns Reviewer/QA packets
and returns `final_summary` / `qa_evaluation_result`.

## Execution

1. Triage size, risk, gates, state, lane, review/QA, and delegation triggers.
2. Discover the relevant code and constraints; reconcile state. Create the
   Requirement Acceptance Map when its medium+/promotion condition applies.
3. Apply `plan_mode`: skip Plan for `none`, keep `inline` concise, and for
   `approval_required` decompose as needed and obtain approval before edits.
4. Build tests-first where behavior changes, verify each slice, and record
   deviations instead of improvising scope.
5. Run Spec Review then independent quality review. Audit normally uses one
   pass; review-fix normally uses one fresh post-fix re-review. Round 3+ needs
   new evidence and an `additional_round_reason`; round 10 is terminal.
6. Complete documentation and the evidence-bounded final handoff.

## Output

For medium+, return status, changed areas, requirement evidence, verification,
review claim, architecture decisions, manual scenarios or explicit N/A,
limitations, rollback/recovery, and one next step. Small work returns status,
changed areas, compact acceptance/verification, material risks, and next step.

## Stop Rules

- Stop for a material unknown with no safe discoverable default.
- Stop before unapproved medium+ Build or material plan deviation.
- Stop before completion when accepted requirement evidence, validation,
  required review, or final-handoff fields are missing.
- Report blockers and residual uncertainty; never replace evidence with
  “should work,” categorical cleanliness, or guessed completion.
