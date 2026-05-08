# Context Map: Complete First-Class Skill Eval Coverage

## Current Eval Surface
- `tools/evals/run-skill-evals.sh` is the public runner for validation, listing, prompt emission, and local response grading.
- Fixture files live at `skills/<skill>/evals/cases.json`.
- Default inventory discovers first-class `skills/assistant-*` fixtures and excludes local-only `unity-*` fixtures unless `--include-local` is passed.
- Default first-class coverage is complete for all 15 tracked assistant skills:
  - `assistant-clarify`, `assistant-diagrams`, `assistant-docs`, `assistant-ideate`, `assistant-memory`, `assistant-onboard`, `assistant-reflexion`, `assistant-research`, `assistant-review`, `assistant-security`, `assistant-skill-creator`, `assistant-tdd`, `assistant-telos`, `assistant-thinking`, `assistant-workflow`.

## Newly Covered First-Class Skills
- `assistant-diagrams`: code-derived Mermaid/PlantUML diagram generation with `diagram_type`, `scope`, `source_files`, `diagram_code`, evidence, placement, and gaps.
- `assistant-docs`: code-derived docs with `doc_type`, `scope`, `source_files`, `files_updated`, `doc_coverage`, and `review_needed`.
- `assistant-ideate`: UNDERSTAND -> DIVERGE -> CONVERGE -> REFINE -> DECIDE pipeline; requires 8+ ideas, full scoring, refined candidates, and user decision.
- `assistant-reflexion`: reflect/recall/stats/consolidate actions; reflect extracts lessons with confidence and records via memory; recall returns relevant lessons with confidence, date, and project.
- `assistant-telos`: create/update/review Telos Context Files; create/update require TCF sections, review requires section findings, confirmation always required.

## Tests And Docs
- `tests/p0-p4/skill-eval-contracts.sh` asserts all 15 covered fixtures, representative rows for the newly covered skills, prompt emission, local-only exclusion, and docs wording.
- README and `docs/evals/README.md` describe complete first-class coverage and keep local-only Unity skills opt-in.
- `docs/skill-contract-design-guide.md` and the bundled `skills/assistant-skill-creator/references/skill-contract-design-guide.md` describe complete first-class per-skill eval fixtures.

## Constraints
- Keep the runner local and provider-neutral; no model/provider SDK/network behavior.
- Add only skill-local fixture JSON, P0/P4 assertions, and coverage docs.
- Match machine expectations to stable skill contract labels and exact casing.
- Check coverage facts separately from wrapped Markdown prose.
