# BES Candidate Search Phase 2 Plan

## Goal

Extend candidate-search beyond `assistant-workflow` into the thinking, ideation, review, and reflexion skills while staying agent-agnostic, local-first, and company-safe.

## Context from Phase 1

Phase 1 added workflow-level `search_mode`, a candidate-search reference, candidate-search output artifact, phase gates, and plan-template hooks. It intentionally avoided runtime tools, MCP servers, Hermes-specific dependencies, and mandatory external search.

## Acceptance criteria

- `assistant-thinking` can run candidate search as a structured reasoning method when a thinking task is open-ended or high uncertainty.
- `assistant-ideate` supports candidate lineage and search operators without replacing its existing diverge/converge/refine flow.
- `assistant-review` can evaluate pre-code candidates with a dedicated candidate rubric instead of misusing the code-review rubric.
- `assistant-reflexion` can capture which search operator, verifier, or rubric dimension helped, when policy allows local lessons.
- Root skill changes are synchronized to plugin-local copies under `plugins/assistant-research`, `plugins/assistant-dev`, and `plugins/assistant-core` as applicable.
- Contracts, phase gates, handoffs, eval fixtures, and P0-P4 contract tests are updated together.

## Likely files

- `skills/assistant-thinking/SKILL.md`
- `skills/assistant-thinking/contracts/input.yaml`
- `skills/assistant-thinking/contracts/output.yaml`
- `skills/assistant-thinking/contracts/phase-gates.yaml`
- `skills/assistant-ideate/SKILL.md`
- `skills/assistant-ideate/contracts/*`
- `skills/assistant-review/SKILL.md`
- `skills/assistant-review/contracts/*`
- `skills/assistant-review/references/review-rubric.md` or a new `references/candidate-rubric.md`
- `skills/assistant-reflexion/SKILL.md`
- `skills/assistant-reflexion/contracts/*`
- matching plugin copies under `plugins/*/skills/*`
- `tests/p0-p4/*.sh`

## Implementation tasks

### Task 1: Thinking skill candidate-search method

- Add `search_mode: none | lightweight | candidate_search` or equivalent method enum to thinking contracts.
- Add a method section that builds a goal tree from the user's stated objective and constraints.
- Require candidate archive inline/local-state fallback, not external tools.
- Add phase gates for goal tree, candidate archive, scoring, selected candidate, and explicit uncertainty/residual-risk summary.

### Task 2: Ideation lineage and operators

- Add lineage fields to ideation outputs.
- Document operators: `mutate`, `rewrite`, `combine/crossover`, `translocate/graft`, `delete/ablate`, `repair`.
- Keep diverge/converge/refine behavior intact; operators are metadata and steering aids, not a new mandatory ceremony.

### Task 3: Review candidate rubric

- Add a pre-code rubric separate from code-quality review.
- Suggested dimensions: objective fit, verifiability, feasibility, risk, simplicity, reversibility.
- Make it clear that code review starts only after code exists.
- Add handoff/output fields for candidate-review verdicts when a reviewer requests a pivot.

### Task 4: Reflexion learning hook

- Add optional local lesson fields for useful search operators/rubric dimensions.
- Include policy gate: write only when local memory/reflexion is configured and allowed.
- Avoid storing rejected proprietary implementation details; summarize patterns and redactions.

### Task 5: Validation and parity

- Add P0-P4 tests for each skill's candidate-search contracts.
- Update eval fixtures for provider-neutral expected behavior.
- Sync plugin copies and run plugin parity.

## Verification

Run at minimum:

```bash
tools/skills/validate-skills.sh
git diff --check
bash ./tests/p0-p4/workflow-basics-contracts.sh
bash ./tests/p0-p4/eval-contracts.sh
bash ./tests/p0-p4/skill-eval-contracts.sh
bash ./tests/p0-p4/plugin-manifest-contracts.sh
```

Add focused tests for the modified thinking/ideation/review/reflexion contracts.

## Risks

- Over-ceremony: candidate search should remain opt-in and triggered by uncertainty, not every task.
- Rubric drift: keep pre-code candidate rubric separate from post-code review rubric.
- Plugin drift: root skill changes must be synced to plugin-local copies.
- Policy drift: do not add external tools or durable memory writes as requirements.
