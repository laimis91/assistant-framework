# Context Map: Workflow Triage And Clarification Gates

## Project Type
- Assistant Framework repo: markdown/YAML skill contracts, bash lifecycle hooks, and JSON eval fixtures.

## Current Behavior
- `skills/assistant-workflow/SKILL.md` owns workflow frontmatter triggers and main triage guidance.
- `hooks/scripts/skill-router.sh` reads `triggers:` from installed `SKILL.md` files, matches every skill whose regex applies, and appends required input fields from `contracts/input.yaml`.
- `hooks/scripts/workflow-enforcer.sh` injects active task state from task journals on every prompt.
- `hooks/scripts/workflow-phase-gates.sh` provides shared plan/review/metrics helpers used by enforcer, stop review, and harness gate.
- Current clarification enforcement exists, but it does not define question caps as maximums, question admissibility, or triage risk/category gate packs.

## Key Files
- `skills/assistant-workflow/SKILL.md`
- `skills/assistant-workflow/contracts/input.yaml`
- `skills/assistant-workflow/contracts/phase-gates.yaml`
- `skills/assistant-workflow/contracts/output.yaml`
- `skills/assistant-workflow/contracts/handoffs.yaml`
- `skills/assistant-workflow/references/phases.md`
- `skills/assistant-workflow/references/task-journal-template.md`
- `skills/assistant-workflow/references/plan-template.md`
- `hooks/scripts/workflow-enforcer.sh`
- `hooks/scripts/workflow-phase-gates.sh`
- `tests/test-hooks.sh`
- `tests/p0-p4/runtime-phase-gate-contracts.sh`
- `tests/p0-p4/workflow-basics-contracts.sh`
- `tests/p0-p4/skill-eval-contracts.sh`
- `skills/assistant-workflow/evals/cases.json`
- `docs/evals/framework-instruction-cases.json`

## Test Locations
- `tests/test-hooks.sh`: skill-router and workflow-enforcer behavior.
- `tests/p0-p4/runtime-phase-gate-contracts.sh`: source/runtime wording and hook wiring guards.
- `tests/p0-p4/workflow-basics-contracts.sh`: workflow instruction/source contract guards.
- `tests/p0-p4/skill-eval-contracts.sh`: workflow eval inventory and case listing.
- `tools/skills/validate-skills.sh --skill assistant-workflow`: contract/frontmatter validation.
- `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-workflow`: workflow eval fixture validation.

## Implementation Risks
- Raw `code` in triggers causes false positives for explanation, review, and docs prompts because the router collects all matching skills.
- Adding required contract fields changes skill-router reminder output immediately.
- Hook parsing is label-based, so task journal field names must match templates and enforcer readers.
- Source skills use `.claude` paths; installer substitutes `.codex` paths for Codex installs.
- Existing plugin-local workflow copies are scaffolds; root `skills/assistant-workflow` remains the install source for default/profile installs.
