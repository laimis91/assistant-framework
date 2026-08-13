---
name: assistant-review
description: "Review code, fix actionable findings, and run one fresh re-review. Use for explicit code review or the workflow Review phase; QA runs only when required."
effort: high
triggers:
  - pattern: "fix (all |the |review |reported )?issues|fix (all |the )?findings|apply (all )?fixes"
    priority: 90
    reminder: "This request to fix review issues matches assistant-review. You MUST read this SKILL.md and contracts/index.yaml first, then load the applicable contract selector. The skill includes fix -> validation -> re-review steps that run before the final summary."
  - pattern: "review|fresh review|code review|review this|check the code|/review"
    priority: 80
    reminder: "This request matches assistant-review. You MUST read this SKILL.md and contracts/index.yaml first, then load the applicable contract selector. Run the autonomous review-fix loop to its exit condition before reporting."
---

# Autonomous Review And QA Evaluation

## Contracts

Canonical input, output, phase-gate, and handoff schemas remain authoritative at their enforcement points. Read `contracts/index.yaml` first; do not load every contract at entry.

- `entry`: load `contracts/input.yaml` review-entry fields selected by `review-entry-fields` in `contracts/index.yaml`.
- `current_round`: load the active round step from `contracts/phase-gates.yaml` at each transition.
- `selected_handoff`: select the compact dispatch pointer from `contracts/handoffs.yaml` before Reviewer or QAEvaluator dispatch.
- `reviewer_context`: resolve the fresh bounded Reviewer bundle only when a review pass begins.
- `return_validation`: select the canonical return pointer only after a worker/direct-fallback result exists.
- `completion`: load the applicable `contracts/output.yaml` artifacts at completion, before the final review exit.

Migration note: assistant-review contracts are v6. Pack projections require non-empty boundaries, exact five-concern design-pressure coverage, and a current authoritative `ref` that preserves recoverable selected design, rationale, and viable alternatives/dispositions; triggered Reviewer returns require `architecture_decision_pack_checks`. v4 Pack review carries canonical `architecture_design_mode`; its nested Pack mode must match and review-intensive review requires independent challenge evidence. Applicable direct-user,
`AGENTS.md`, and active-skill instructions trigger required Reviewer and QA
roles; record their provenance and covered work in `subagent_trigger_scope`
without a second permission question. Explicit opt-out, real unavailability,
and exact active policy blocks retain direct fallback. Every Reviewer return and
final summary requires a non-empty `reviewed_scope` string array so workflow
consumers can use the producer packet without deriving or guessing its boundary.

Selectors use unique id, canonical path, exact section/key, and explicit or allowed runtime names. Entry declares no immediate principles, checklist, or rubric references.

If a selector is missing or invalid, apply `load_full_authoritative_file`: load the full named canonical file, validate the applicable rules, and record any recovery before proceeding.

Run the bounded review policy, keep intermediate results inside the loop, and present one final evidence-calibrated result. Required QA follows build/test and code-review evidence.

## Goal

Find evidence-backed defects, regressions, and test gaps; fix them in review-fix mode; and return one policy-safe result without implying proof of correctness. Required QA independently evaluates acceptance, evidence, scoped quality, progression, and readiness.

## Success Criteria

- Scope, mode, and review material are resolved before the loop.
- Findings are severity-ranked with evidence and confidence.
- Every Reviewer return names the non-empty `reviewed_scope` actually inspected.
- Every review applies the SOLID, KISS, DRY, YAGNI, and readability lens from `references/review-principles.md`.
- When a carried Architecture Decision Pack applies, the review checks its freshness, ownership/dependency boundary, semantic type ledger, falsifiable quality scenarios, compatibility/extension seam, and verification handoff.
- In review-fix mode, must-fix and should-fix findings are addressed or explicitly deferred.
- Validation and a fresh review follow fixes.
- QA evaluation runs after code-review/build evidence when `qa_evaluation_mode=required`, returns score progression and a final acceptance verdict, and does not replace code-reviewer.
- QA required positive triggers: explicit QA/acceptance evaluation request, accepted Done Contract, harness-capable acceptance scope, domain-scored scope, or scoped UI/visual/product/UX/docs/DX acceptance.
- QA non-triggers: template labels/placeholders, generic acceptance criteria labels, optional/not_required reasons, delegation/source-changing work alone, and ordinary medium+ code-review-only/source-changing work.
- QA evaluation loads `references/domain-rubrics.md` only when `domain_context`, explicit `rubric_refs`, or subjective/UI/visual/product/UX/docs/DX/domain acceptance criteria require scoped domain-quality scoring.

## Constraints

- Default to audit mode when the user asks to provide, report, list, or summarize findings.
- Do not emit intermediate review summaries; present one final summary after loop exit.
- Use concrete risk categories for refactor-related findings.
- Treat clean-code principles as evidence lenses, not acronym-driven style rules.
- Keep QA evaluation separate from code review: QA focuses on acceptance criteria, Done Contract, verification evidence, UI/visual/product/UX/docs/DX/domain quality, score progression, and final result. Code Reviewer continues to own code defects, security, architecture, and test-coverage review.

## Entry

Prefer explicit files/content/diff, then uncommitted changes, then the active task journal or packet, then requested current-file audit. Ask only when no review material can be determined.

A standalone `review this` with no carried workflow evidence performs Spec Review against the user request and user scope, records a PASS evidence pointer before Reviewer dispatch, and blocks dispatch on FAIL until the scope mismatch is fixed and Spec Review passes. Standalone review does not require a task journal; `task_journal_path` remains optional.

A workflow-composed review consumes the carried Spec Review PASS pointer and carried current build/test evidence. After any source fix, every subsequent Reviewer dispatch requires real current passed build/test evidence; a not-applicable marker is invalid.

## Review Modes

Use the smallest applicable combination: spec, regression, test, maintainability, bugfix evidence, semantic contract, behavioral contract, agentic loop safety, and security. Contract and loop modes are enabled by the three entry flags; security-sensitive surfaces route to `assistant-security`.

Findings include severity (`must-fix`, `should-fix`, or `nit`), file/line evidence, concrete impact, smallest useful fix, and evidence-calibrated confidence. Speculative concerns remain non-blocking Observations.

QA evaluation runs after code-review/build evidence and only when `qa_evaluation_mode=required`. Load `references/qa-evaluation-loop.md` at that later boundary. Load `references/domain-rubrics.md` only when acceptance criteria, Done Contract, `domain_context`, or explicit `rubric_refs` scope domain quality; selected_domain_rubrics/domain_quality_scores when scoped. Code Reviewer still owns code defects, security, architecture, and test coverage.

## Company-Safe Review Rules

Prefer local diffs and repo-native checks. Do not require external scanners, remote review, or unapproved installs; redact secrets and proprietary data. Offer local/manual equivalents when policy blocks an external scan.

## Mandatory Review Checklists

The fresh Reviewer context bundle points to `references/review-checklists.md` and supplies only the applicable checklist sections. Checklist headings alone are not evidence; each selected area produces findings or an explicit "no concrete risk found" check.

- Agentic loop flag -> Agentic Loop Safety Checklist -> `agentic_loop_safety_checks`.
- Behavioral flag -> Behavioral Contract Review Checklist -> `behavioral_contract_checks`.
- Semantic flag -> Semantic Contract Review Checklist -> `semantic_contract_checks`.
- Architecture Decision Pack flag -> Architecture Decision Pack Review Checklist -> `architecture_decision_pack_checks`.

## Refactor-Related Findings

Use refactor-related findings only for concrete actionable risk. Allowed risk categories:
- correctness
- security
- unsafe change surface
- branching/responsibility growth
- hidden dependency/ownership
- brittle testing
- poor extension seam
- readability/maintainability drag

Every refactor-related finding MUST state the risk category, affected surface, evidence from the review material, and the smallest durable fix that addresses the risk within the normal finding text.

Use concrete risk framing instead of generic convention, style, cleanliness, or improvement language. Request broad cleanup only when a smaller durable fix cannot remove the risk.

## Architecture Decision Pack Review

Review a Pack only when workflow metadata or review material says one applies. Its nested mode must equal canonical `architecture_design_mode`; review-intensive review requires independent challenge evidence. It is a compact, durable decision record, not a permanent architect role or global memory. Require source/revision freshness and every material question that could invalidate the decision; group questions with why, risk if guessed, and a safe default where available. Check control/early-exit behavior, ownership/disposal, bounded resource envelope, extension registration, and the representative producer-consumer path before accepting an interface or engine. Treat generic `string`, numeric, collection, or callback interfaces as a finding when they erase domain/public/lifecycle semantics without an explicit local-boundary primitive exception and conversion/validation. Do not approve memory, performance, or extensibility claims without workload, budget, measurement method, and failure condition; mark absent evidence as unknown or a verification gap.

## Principle and Readability Lens

The fresh Reviewer bundle includes `references/review-principles.md` for clean-code checks. For medium+ scope, run its Design Coherence Pass and return `principle_checks.design_coherence`: evidence-backed risk or `no concrete risk found`, never a structural heuristic. Report findings only with concrete risk.

For each principle/readability finding, include the violated lens, affected surface, concrete evidence, risk category, and smallest durable fix. Do not report acronym-only findings such as "violates SOLID" without naming the observed behavior and the user-facing or maintainer risk.

## Review Loop Routing

After entry fields are resolved, load `references/review-loop.md` before the first REVIEW step. It is the only immediately mandatory first-review reference in orchestrator context and owns REVIEW -> EVALUATE -> FIX -> VALIDATE, fresh bundle construction, drift/pivot handling, and the max 10 rounds limit. Principles, applicable checklist sections, and rubric guidance belong to the fresh Reviewer worker bundle created only when a review pass begins; they are not assistant-review entry dependencies.

Run QA only when `qa_evaluation_mode=required`. The loop routes to `references/qa-evaluation-loop.md` after build/test and code-review evidence exist; QA evaluates acceptance and scoped quality, and does not replace code review.

## Exit: Present Final Result

Present one summary using `contracts/output.yaml`. For no findings, say: "No material findings within the reviewed scope and available evidence." `CLEAN` remains a machine enum, not proof of correctness.

## Rules

- Keep round results internal and present one final summary.
- Use a fresh Reviewer bundle each medium+ round; direct fallback uses the same isolated bundle without claiming a subagent dispatch.
- Previously fixed items are not re-reported; findings remain evidence-backed.

## Output

Return reviewed scope, rounds/result, evidence-backed findings and fixes, verification, applicable bugfix/agentic/behavioral/semantic checks, required QA result, and residual risk. `contracts/output.yaml` owns the exact schema.

## Stop Rules

- Audit mode stops after one review pass. Report findings without edits.
- The normal review-fix path is an initial review, fixes and validation, then one fresh re-review; stop after a no-finding pass unless new evidence justifies another round.
- Before round 3+, require `additional_round_reason` backed by changed files, an unresolved finding, validation failure, regression/drift, or a changed hypothesis. Score below threshold alone is insufficient.
- The hard max 10 rounds remains: round 10 is terminal and round 11 never starts.
- Stop and report a blocker if required review material is unavailable or empty.

### Drift detection (medium+ scope)

Compare medium+ rounds using `references/score-tracking.md`. Drift, regression,
stagnation, or pivot evidence returns `pivot_restart_signal`; the orchestrator records `pivot_restart_decision` and applies the round 3+ evidence gate before another pass.


## Review Finding Rule Distillation

At the end of review, load `references/review-finding-permanent-rule.md` for every blocker or must-fix finding. Classify each as `one_off_fix`, `permanent_rule_candidate`, or `no_action`. Promote only recurring process gaps, fake-pass eval gaps, missing contracts, missing checklists, or high-impact repeatable failure modes; do not promote style nits or one-off file-specific issues into broad rules.
