# BES Candidate Search Phase 3 Plan

## Goal

Evaluate whether assistant-framework should add optional tooling around candidate search after the skill-only workflow proves useful. Phase 3 must remain optional, local-first, and policy-gated.

## Non-goals

- Do not make Hermes, BES, MCP, or any remote service a mandatory dependency.
- Do not add external model calls, telemetry, or code upload by default.
- Do not replace the skill/contracts workflow with a tool-only workflow.

## Candidate directions

### Direction A: Local candidate archive helper

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

### Direction B: Optional MCP/local service

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

### Direction C: Evaluation harness for search quality

Add offline fixtures that compare ordinary planning against candidate-search planning for ambiguous architecture/design prompts.

Acceptance criteria:

- Provider-neutral fixtures.
- Machine-checkable required/forbidden behavior.
- Tests verify candidate-search is triggered only for high-uncertainty/open-ended cases and not for trivial tasks.
- No external API calls required.

## Implementation sequence

1. Review usage evidence from Phases 1 and 2.
2. Decide whether a helper is justified or whether markdown/contracts are enough.
3. If justified, spike a local-only validator/exporter first.
4. Add tests before implementation.
5. Keep tool use optional and document fallback to `references/candidate-search.md`.
6. Run isolated install/smoke checks for Claude, Codex, and Gemini targets if installer behavior changes.

## Verification

Run the normal framework validation plus any new helper tests:

```bash
tools/skills/validate-skills.sh
git diff --check
bash ./tests/p0-p4/workflow-basics-contracts.sh
bash ./tests/p0-p4/eval-contracts.sh
bash ./tests/p0-p4/skill-eval-contracts.sh
bash ./tests/p0-p4/plugin-manifest-contracts.sh
```

If installer or agent-home behavior changes, also run isolated temp-home install smoke tests for supported agents.

## Risks and guardrails

- Tool creep: do not build a tool unless Phase 1/2 usage shows repeated friction.
- Runtime lock-in: preserve markdown fallback and provider-neutral skill contracts.
- Data leakage: candidate archives can contain rejected proprietary designs; add redaction and retention controls before structured persistence.
- False precision: scoring helps compare trade-offs but does not prove correctness; final correctness still comes from tests, review, and user approval.
