---
name: assistant-review
description: "Review code, fix actionable findings, and run one fresh re-review. Use for explicit code review or the workflow Review phase; QA runs only when required."
---

# Review

## Shared operating guidance

Load [the common outcome guidance and shared stagnation policy](../../tools/progress/operating-guidance.md) for this activity. Keep specialist methods, authority and completion evidence below; single-pass work needs no progress artifact.


Find concrete defects and regressions within scope. Read the diff and connected
callers, contracts, tests and configuration, including affected consumers outside
the diff. Findings require real input/situation, file/line evidence, impact,
calibrated confidence and the smallest useful fix. Style taste/speculation stays
non-blocking. Preserve carried reduced-testing boundary/source through criteria,
verification evidence and material snapshot refs. Additional tests require a
distinct important uncovered failure and inadequate-existing-evidence rationale;
scores/generic coverage advice cannot expand scope. Return material expansion
to selection/approval.

## Authority and scope

Resolve reviewed material from explicit scope, then uncommitted changes, carried
packet/journal, or current files. Block if required material is unavailable or
empty. A report-only request is audit; clear edit authorization permits review-fix
within its approved scope. If edit authority is materially unresolved, ask whether
to report only or implement and verify fixes; do not review or mutate while unresolved.
Ownership or access alone never grants edit authority.
Standalone `review this` does not require a task journal.

Use local company-safe diffs/checks; external scans, reviews, and installs retain
explicit approval. Redact secrets and private data. Preserve dirty work and return
out-of-scope findings to the composing workflow.

## Review process

Load `contracts/index.yaml` at the structured review boundary, then entry and
applicable architecture inputs. For behavior or cosmetic changes, a carried
change-impact artifact, or a locality/shared/unresolved decision, load
`change_impact` and [change-impact.md](references/change-impact.md) before planning
or dispatch. Keep this guidance outside Reviewer bundles.

Load [review-loop.md](references/review-loop.md) before the first batch; it owns
transitions, frozen snapshot identity, response
barriers, aggregation, and pivots. The current v9 protocol remains authoritative:

- Each frozen batch plans and attempts at least two independent, sibling-blind
  passes. Resolve `reviewer_context` for each pass, the selected handoff before
  dispatch/return, and `return_validation` before aggregation. Account for every
  expected pass; incomplete coverage returns `HAS_REMAINING_ITEMS`.
- Standalone review checks the user's specification. Audit retains mismatches
  as findings and finishes one read-only batch. Review-fix repairs authorized
  mismatches and requires Spec PASS before quality review. Workflow-composed
  review consumes carried Spec PASS and current due-check evidence.
- Review only relevant spec, regression, testing, maintainability, bugfix,
  semantic/behavioral contract, loop-safety, and security concerns. Fresh bundles
  use applicable sections of [review-checklists.md](references/review-checklists.md)
  and [review-principles.md](references/review-principles.md); do not fill every
  checklist for unrelated work. Medium+ retains its Design Coherence Pass.
- Review applicable Architecture Decision Packs, including invalid ones, for
  freshness, ownership/lifecycle, design pressures, types/primitive exceptions,
  quality evidence, compatibility, and handoff. Preserve independent challenge
  when `review_intensive` applies.
- Before workflow-composed mutation, preserve or refresh the canonical verification
  selection under `F_REVIEW_VERIFICATION_SELECTION`. An active TDD finding goes
  back to the Build owner with its identities, oracle, scope, IDs, and bindings;
  the review fixer cannot bypass RED. Standalone review-fix retains build/tests.
- After a fix, verify due selected/binding checks against the new source, freeze
  a fresh snapshot, and run a fresh complete review batch. No-build admission
  applies only when no fix is required/occurred and no due selected or executable
  binding check exists. A source fix forbids it.

The change-impact projection does not replace canonical snapshot/coverage closure. Missing/invalid
selectors load the full named contract. Load
[legacy-compatibility.md](references/legacy-compatibility.md) only for persisted
pre-v9 results; do not reinterpret historical evidence as a current clean batch.

## QA and stopping

QA stays separate from code review and runs after Build and Code Reviewer evidence
only when explicit QA/acceptance, accepted Done Contract, harness acceptance,
domain-scored scope, or scoped UI/visual/product/UX/docs/DX acceptance requires it.
Size, delegation, source changes, and generic acceptance labels do not trigger QA.
Load [qa-evaluation-loop.md](references/qa-evaluation-loop.md) when required and
[domain-rubrics.md](references/domain-rubrics.md) only for scoped domain quality.
Carry approved preparation QA obligations and exact result/source bindings.

Audit stops after its first started batch, without fixes. Review-fix runs round 1,
authorized fixes and validation, then fresh round 2. Round 3+ requires changed
files, unresolved findings, validation failure, regression/drift, or changed
hypothesis; score alone is insufficient. Productive rounds can continue beyond 10 under the same shared guard.
Medium+ score diagnostics use [score-tracking.md](references/score-tracking.md).
Require a recorded pivot/restart decision before another pass only for evidenced
shared semantic guard stagnation or an applicable material change. Score labels
alone do not require a decision, reset the evaluator, or pause productive work.

## Result

Report findings/fixes, scope, verification and material limits. No findings means
"No material findings within the reviewed scope and available evidence";
`CLEAN` is an enum, not proof. Consumers retain
`contracts/output.yaml`, canonical reviewed scope, batch/round evidence, required
checks and QA. `CLEAN`/`ISSUES_FIXED` require complete current coverage and no
remaining must-fix/should-fix items. Failed or blocked passes cannot claim clean.
Omit empty checklist and internal protocol sections from the human summary.

Load [review-finding-permanent-rule.md](references/review-finding-permanent-rule.md)
only for evidence of recurring process gaps or high-impact repeatable failures.
A finding does not automatically require a permanent rule or new framework.
Existing mapped all-ID distillation fixtures retain their consumed classification
envelope; that compatibility requirement does not govern ordinary human summaries.
