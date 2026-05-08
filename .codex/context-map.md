# Context Map: Expanded Level 4 Per-Skill Eval Coverage

## Eval Runner Surface
- `tools/evals/run-skill-evals.sh` is the command entrypoint.
- `tools/evals/lib/skill-eval-inventory.sh` discovers default first-class `skills/assistant-*` fixtures and excludes local-only `unity-*` fixtures unless `--include-local` is used.
- `tools/evals/lib/skill-eval-fixtures.sh` validates fixture schema, skill identity, safe case ids, duplicate ids, and non-empty machine expectation arrays.
- `tools/evals/lib/skill-eval-render.sh` emits prompt packets under `<output>/<skill>/<case-id>.md`.
- `tools/evals/lib/skill-eval-grade.sh` locally grades response files against required and forbidden substrings.

## Existing Coverage
- Current fixtures exist for ten first-class skills:
  - `skills/assistant-clarify/evals/cases.json`
  - `skills/assistant-memory/evals/cases.json`
  - `skills/assistant-onboard/evals/cases.json`
  - `skills/assistant-research/evals/cases.json`
  - `skills/assistant-thinking/evals/cases.json`
  - `skills/assistant-workflow/evals/cases.json`
  - `skills/assistant-review/evals/cases.json`
  - `skills/assistant-tdd/evals/cases.json`
  - `skills/assistant-security/evals/cases.json`
  - `skills/assistant-skill-creator/evals/cases.json`
- The repo has 15 first-class `assistant-*` skills, so current default fixture coverage is 10/15.

## Target Skill Surfaces
- `skills/assistant-skill-creator/SKILL.md` plus contracts define CAPTURE, DESIGN, BUILD, VALIDATE gates, required contract fields, output artifacts, and validation summary expectations.
- `skills/assistant-memory/SKILL.md` plus contracts define memory actions, entity types, query/content requirements, confirmation output, and secret/PII safety rules.
- `skills/assistant-research/SKILL.md` plus contracts define tier/tool selection, search/synthesize/verify pipeline, confidence levels, verified URLs, conflicts, gaps, and structured output.
- `skills/assistant-onboard/SKILL.md` plus contracts define surface scan, architecture map, pattern recognition, knowledge gaps, project orientation, key files, conventions, memory_updated, and specific questions.

## Contract Test Surface
- `tests/p0-p4/skill-eval-contracts.sh` is the current P0/P4 suite for per-skill eval contracts.
- It already validates default inventory, targeted selection by name/dir/SKILL.md, listing, prompt emission, response grading, malformed fixtures, duplicate ids, local-only exclusion/inclusion, and docs coverage wording.
- The current docs assertion names ten-skill coverage and guards the incomplete-coverage statement.

## Documentation Surface
- `README.md` has the public quick-start section for per-skill eval fixtures.
- `docs/evals/README.md` has the detailed runner usage and current tracked fixture list.
- `docs/skill-contract-design-guide.md` describes Level 4 conformance and currently states ten-skill expanded coverage with five remaining first-class skills as future work.
