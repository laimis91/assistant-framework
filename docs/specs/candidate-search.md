# Candidate search design requirements

Status: historical design requirements extracted from the former Phase 2 and Phase 3 development plans. Optional tooling directions remain proposals; this document makes no implementation or usage-benefit claim. Inspect current skill sources before changing behavior.

## Skill integration requirements

### Goal

Extend candidate-search beyond `assistant-workflow` into the thinking, ideation, and review skills while staying agent-agnostic, local-first, and company-safe.

### Context from Phase 1

Phase 1 added workflow-level `search_mode`, a candidate-search reference, candidate-search output artifact, phase gates, and plan-template hooks. It intentionally avoided runtime tools, MCP servers, Hermes-specific dependencies, and mandatory external search.

### Acceptance criteria

- `assistant-thinking` can run candidate search as a structured reasoning method when a thinking task is open-ended or high uncertainty.
- `assistant-ideate` supports candidate lineage and search operators without replacing its existing diverge/converge/refine flow.
- `assistant-review` can evaluate pre-code candidates with a dedicated candidate rubric instead of misusing the code-review rubric.
- Contracts, phase gates, handoffs, eval fixtures, and P0-P4 contract tests are updated together.


## Detailed skill requirements

### Thinking skill candidate-search method

- Add `search_mode: none | lightweight | candidate_search` or equivalent method enum to thinking contracts.
- Add a method section that builds a goal tree from the user's stated objective and constraints.
- Require candidate archive inline/local-state fallback, not external tools.
- Add phase gates for goal tree, candidate archive, scoring, selected candidate, and explicit uncertainty/residual-risk summary.

### Ideation lineage and operators

- Add lineage fields to ideation outputs.
- Document operators: `mutate`, `rewrite`, `combine/crossover`, `translocate/graft`, `delete/ablate`, `repair`.
- Keep diverge/converge/refine behavior intact; operators are metadata and steering aids, not a new mandatory ceremony.

### Review candidate rubric

- Add a pre-code rubric separate from code-quality review.
- Suggested dimensions: objective fit, verifiability, feasibility, risk, simplicity, reversibility.
- Make it clear that code review starts only after code exists.
- Add handoff/output fields for candidate-review verdicts when a reviewer requests a pivot.

## Optional tooling requirements

### Goal

Evaluate whether assistant-framework should add optional tooling around candidate search after the skill-only workflow proves useful. Phase 3 must remain optional, local-first, and policy-gated.

### Non-goals

- Do not make Hermes, BES, MCP, or any remote service a mandatory dependency.
- Do not add external model calls, telemetry, or code upload by default.
- Do not replace the skill/contracts workflow with a tool-only workflow.

### Candidate directions

#### Direction A: Local candidate archive helper

A small repo-native script could create/update `{agent_state_dir}/candidate-search.md` from a template and validate required sections.

Likely files:

- `skills/assistant-workflow/scripts/` or `tools/`
- `tests/` contract/smoke tests
- installer documentation if the helper is installed

Acceptance criteria:

- Works offline.
- Does not require external packages beyond the repo's existing stack unless explicitly approved.
- Validates goal tree, candidate list, rubric scores, selected candidate, and plan deviation fields.
- Fails closed with actionable messages.

#### Direction B: Optional MCP/local service

Only consider this if repeated manual use shows the archive/scoring workflow benefits from structured operations.

Possible operations:

- create search session
- add/update goal tree
- add candidate with lineage
- score candidate
- compare candidates
- export markdown archive

Acceptance criteria:

- Disabled unless explicitly installed/enabled.
- Runs locally.
- Stores data under configured local state.
- Has clear retention/redaction controls.
- Degrades to the Phase 1 markdown workflow when unavailable.

#### Direction C: Evaluation harness for search quality

Add offline fixtures that compare ordinary planning against candidate-search planning for ambiguous architecture/design prompts.

Acceptance criteria:

- Provider-neutral fixtures.
- Machine-checkable required/forbidden behavior.
- Tests verify candidate-search is triggered only for high-uncertainty/open-ended cases and not for trivial tasks.
- No external API calls required.


## Design guardrails

The original Phase 2 and Phase 3 requirements also retain these boundaries:

- Candidate search remains opt-in and triggered by uncertainty; it is not required for every task. Keep the pre-code candidate rubric separate from post-code quality review.
- External tools and durable memory writes are not requirements of candidate search.
- Optional tooling requires evidence of repeated friction in Phase 1/2 usage before it is justified. Preserve the Markdown fallback and provider-neutral skill contracts.
- Candidate archives may contain rejected proprietary designs. Establish redaction and retention controls before introducing structured persistence.
- Scores help compare trade-offs but do not prove correctness. Tests, review and user approval remain the basis for final correctness.

## Source owners

- [Workflow candidate search](../../skills/assistant-workflow/references/candidate-search.md)
- [Thinking](../../skills/assistant-thinking/SKILL.md), [ideation](../../skills/assistant-ideate/SKILL.md), and [review](../../skills/assistant-review/SKILL.md)

Before promoting an optional direction to implemented status, verify its owning source and actual checks. Development task sequences and run commands belong in local ignored task state.
