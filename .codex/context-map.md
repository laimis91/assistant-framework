# Context Map
Generated: 2026-05-08 | Task: Per-skill eval fixture slice

Note: Code Mapper was dispatched as Lorentz for this medium task but did not return before timeout/interruption. This map is a recovery map from direct Discover evidence and should be treated as compact, task-scoped context.

## Entry Points

- `tools/evals/run-framework-instruction-evals.sh` - existing provider-neutral offline runner for framework-level instruction eval fixtures.
- `docs/evals/framework-instruction-cases.json` - existing framework-level eval fixture with schema metadata, cases, setup context, expected behavior, pass criteria, fail signals, and machine expectations.
- `tests/p0-p4/eval-contracts.sh` - P0/P4 contracts for the framework eval fixture and runner.
- `tests/test-p0-p4-contracts.sh` - aggregate P0/P4 runner; sources `tests/p0-p4/eval-contracts.sh`.
- `tools/skills/validate-skills.sh` - first-class skill source validator added in the previous slice.
- `tools/skills/lib/validate-inventory.sh` - selected skill inventory logic: default first-class `skills/assistant-*`; `--include-local` includes all `skills/*`.

## Current Eval Flow

`docs/evals/framework-instruction-cases.json`
-> `tools/evals/run-framework-instruction-evals.sh --validate-fixture`
-> `--list` / `--emit-prompts DIR`
-> local captured responses saved as `<case-id>.txt|.md`
-> `--responses DIR` deterministic substring grading.

The runner is shell plus `jq`. It does not call provider APIs, provider SDKs, or network services.

## Relevant Existing Behavior

- Framework eval fixture validates top-level suite metadata and non-empty case arrays.
- Each case has `id`, `title`, `category`, `purpose`, `prompt`, `setup_context`, `expected_behavior`, `pass_criteria`, `fail_signals`, and `machine_expectations`.
- `machine_expectations.required_substrings` and `forbidden_substrings` are non-empty arrays used for local grading.
- Prompt emission writes one Markdown packet per case.
- Response grading fails for missing files, empty files, exact fail-signal hits, missing required substrings, and forbidden substring hits.

## Skill Inventory

- First-class release skills are `skills/assistant-*/SKILL.md`.
- `skills/unity-*` directories are local-only and must stay excluded from default release/eval requirements.
- No existing `skills/*/evals/*` files were found during Discover.

## Candidate Slice Boundaries

- Create a reusable per-skill eval runner rather than extending the framework runner in place.
- Add fixture support under individual first-class skills, starting with a small pilot set.
- Keep per-skill eval fixtures provider-neutral and offline, matching framework eval semantics.
- Add P0/P4 contracts that validate fixture shape, prompt emission, response grading, default inventory behavior, and local-only Unity exclusion.
- Update docs to explain how per-skill evals complement the source validator.

## Test Locations

| Area | Test File | Type |
|---|---|---|
| Framework eval runner | `tests/p0-p4/eval-contracts.sh` | Shell contract tests |
| Aggregate P0/P4 suite | `tests/test-p0-p4-contracts.sh` | Shell aggregate |
| Skill source validator | `tests/p0-p4/skill-validator-contracts.sh` | Shell contract tests |
| Eval docs | `docs/evals/README.md` | Documentation |
| Skill contract direction | `docs/skill-contract-design-guide.md` | Documentation |

## Verification Commands

- `tools/evals/run-framework-instruction-evals.sh --validate-fixture`
- `bash tests/p0-p4/eval-contracts.sh`
- `bash tests/test-p0-p4-contracts.sh`
- `tools/skills/validate-skills.sh`
- `git diff --check`

## Risks

- Duplicating runner logic could create drift between framework-level and per-skill grading.
- Requiring eval fixtures for all first-class skills in one slice would create a large authoring burden and noisy review.
- Inferring eval inventory from local-only skills would violate the framework rule for Unity skills.
- Heuristic substring grading must be presented as local proxy checks, not natural-language judgment.
