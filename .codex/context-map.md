# Context Map: High-Control Per-Skill Eval Coverage

## Eval Runner Surface
- `tools/evals/run-skill-evals.sh` is the command entrypoint.
- `tools/evals/lib/skill-eval-inventory.sh` discovers default first-class `skills/assistant-*` fixtures and excludes local-only `unity-*` fixtures unless `--include-local` is used.
- `tools/evals/lib/skill-eval-fixtures.sh` validates fixture schema, safe case ids, non-empty expectation arrays, and skill identity.
- `tools/evals/lib/skill-eval-render.sh` emits prompt packets under `<output>/<skill>/<case-id>.md`.
- `tools/evals/lib/skill-eval-grade.sh` locally grades response files against required and forbidden substrings.

## Existing Fixture Pattern
- `skills/assistant-clarify/evals/cases.json` contains two cases with suite metadata, provider-neutral flags, setup context, expected behavior, pass criteria, fail signals, and machine expectations.
- `skills/assistant-thinking/evals/cases.json` follows the same schema and uses deterministic substrings as offline proxies for skill-contract adherence.

## Target Skill Surfaces
- `skills/assistant-workflow/SKILL.md` and `contracts/phase-gates.yaml` define visible workflow checkpoints, Discover/Decompose/Plan approval gates, Build tests, Review, and output artifacts.
- `skills/assistant-review/SKILL.md` and `contracts/phase-gates.yaml` define scope resolution, review-fix/audit modes, confidence thresholds, autonomous rounds, rubric requirements, and final summary shape.
- `skills/assistant-tdd/SKILL.md` and `contracts/phase-gates.yaml` define RED/GREEN/REFACTOR ordering, RED evidence, no production code before failing tests, and all-tests verification.
- `skills/assistant-security/SKILL.md`, `contracts/phase-gates.yaml`, and `contracts/output.yaml` define scoped security analysis, methodology use, severity, evidence, impact, remediation, risk summary, and action items.

## Contract Test Surface
- `tests/p0-p4/skill-eval-contracts.sh` is the current P0/P4 suite for per-skill eval contracts.
- It already validates default inventory, targeted selection by name/dir/SKILL.md, listing, prompt emission, response grading, malformed fixtures, duplicate ids, and local-only fixture exclusion/inclusion.
- The expected default inventory is dynamic for counts but still names only the original pilot fixtures in several assertions.

## Documentation Surface
- `README.md` has the public quick-start section for per-skill eval fixtures.
- `docs/evals/README.md` has the detailed runner usage and current coverage statement.
- `docs/skill-contract-design-guide.md` describes Level 4 conformance and currently calls wider per-skill coverage future work.
