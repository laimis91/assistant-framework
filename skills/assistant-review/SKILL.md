---
name: assistant-review
description: "Review code, fix actionable findings, and run one fresh re-review. Use for explicit code review or the workflow Review phase; QA runs only when required."
---

# Autonomous Review And QA Evaluation

## Contracts

Read `contracts/index.yaml` first; do not load every contract. For `entry`, load `contracts/input.yaml` review-entry fields selected by `review-entry-fields` in `contracts/index.yaml`.
- Triggered `change_impact` and `architecture_pack_input`: resolve before planning or dispatch;
load the active round from `contracts/phase-gates.yaml` at each transition, and compact
`contracts/handoffs.yaml` pointer before Reviewer/QAEvaluator dispatch. Resolve
`reviewer_context` at pass start, `return_validation` after results, and
`contracts/output.yaml` before exit; keep change-impact guidance out of
Reviewer bundles.

Migration note: assistant-review contracts are v8.0. Persisted 6.0/7.0/7.1/7.2 batch packets are invalidated and rebuilt from a fresh 8.0 snapshot before CLEAN.
Preserve recoverable selected design, rationale, and viable alternatives/dispositions.
Workflow-composed `no_build_scope` is allowed only when no fix is required or
occurred and no due selected/binding build or test check exists; after a fix,
current passed evidence is mandatory. Standalone review-fix still requires
successful build and tests.
Apply `subagent_trigger_scope`; opt-out, unavailability, or policy blocks use
direct fallback. Reviewer returns and final summaries require non-empty
`reviewed_scope` so workflow consumers can use the producer packet.

Selectors resolve canonical fields; entry loads no review guidance. For a
missing/invalid selector, use `load_full_authoritative_file`, validate the full
canonical file, and record recovery.

## Goal

Find and fix authorized evidence-backed defects, regressions, and test gaps; report calibrated findings.

## Success Criteria

- Resolve scope, mode, and material before the loop; rank findings by severity, evidence, and confidence.
- Each frozen-snapshot batch plans and attempts at least two independent passes.
  All expected passes reach terminal accounting before aggregation, fix, or exit.
  `CLEAN`/`ISSUES_FIXED` require complete coverage. Audit exits after one started
  batch with non-empty `reviewed_scope`; failed, timed-out, blocked, or otherwise
  incomplete coverage returns `HAS_REMAINING_ITEMS`.
- Apply SOLID, KISS, DRY, YAGNI, and readability from
  `references/review-principles.md`; validate every applicable Pack, including
  invalid ones, with its Review Checklist.
- Review-fix resolves or explicitly defers must-fix/should-fix findings, validates, then re-reviews. Required QA returns evidence-backed score progression and final acceptance.
- Select `qa_evaluation_mode` from `contracts/input.yaml`. QA required positive triggers: explicit QA/acceptance evaluation request, accepted Done Contract, harness-capable acceptance scope, domain-scored scope, or scoped UI/visual/product/UX/docs/DX acceptance.
  QA non-triggers: template labels/placeholders, generic acceptance criteria labels, optional/not_required reasons, delegation/source-changing work alone, and ordinary medium+ code-review-only/source-changing work.
- Load `references/domain-rubrics.md` only when acceptance criteria, Done
  Contract, `domain_context`, or explicit `rubric_refs` scope domain quality;
  return selected_domain_rubrics/domain_quality_scores when scoped.

## Constraints

- Infer edit authority: report-only is audit; clear source authorization is
  review-fix; carried approval permits bounded in-scope fixes. If audit versus
  editing is materially unresolved, ask exactly: "Should I only report findings,
  or also implement and verify fixes?" Do not review/mutate until answered.
- Frame refactor findings as concrete risk using clean-code evidence lenses.
- Keep QA evaluation separate from code review: QA owns acceptance, Done
  Contract, verification, scoped quality, progression, and final result.
  Code Reviewer continues to own code defects, security, architecture, and test-coverage review. Code Reviewer still owns code defects.

## Entry

Review explicit material, then uncommitted changes, journal/packet, or current
files; ask only if material is unavailable.

A standalone `review this` runs Spec Review on user scope. Review-fix repairs
authorized mismatches and repeats to PASS before Reviewer dispatch; audit retains the Spec Review mismatch as an aggregate finding and continues a frozen read-only multi-pass batch. The task journal is optional. A workflow-composed review consumes carried Spec Review PASS and current passed verification for every due selected CheckSpec and resolved binding check. After any source fix, each subsequent Reviewer dispatch requires fresh current passed selected/binding evidence; applicable builds/tests must pass and not_applicable admission is forbidden.

## Review Modes

Select applicable spec, regression, test, maintainability, bugfix-evidence,
semantic/behavioral contract, agentic-loop safety, and security modes. Three
entry flags enable contract/loop modes; route security to Code Reviewer with
the assistant-security checklist/perspective.
`risk_selected_specialist` uses Code Reviewer with the selected specialist's
checklist/perspective and the canonical Reviewer schema.

Ownership and environment inform material, never edit authority. Return out-of-scope findings to workflow. Report severity (`must-fix`, `should-fix`, `nit`), file/line evidence, impact, smallest useful fix, and calibrated confidence; speculation is a non-blocking Observation.

QA evaluation runs after code-review/build evidence. Load `references/qa-evaluation-loop.md` when `qa_evaluation_mode=required`.

## Company-Safe Review Rules

Use local diffs/repo-native checks; external scans/reviews or installs need approval. Redact secrets/proprietary data; offer local/manual alternatives if blocked.

## Mandatory Review Checklists

The fresh Reviewer context bundle points to `references/review-checklists.md`;
applicable sections yield findings or an explicit "no concrete risk found"
check. Agentic loop flag -> Agentic Loop Safety Checklist -> `agentic_loop_safety_checks`;
map Behavioral Contract Review Checklist/`behavioral_contract_checks`;
Semantic Contract Review Checklist/`semantic_contract_checks`;
Architecture Decision Pack Review Checklist/`architecture_decision_pack_checks`.

## Refactor-Related Findings

Allowed risk categories: correctness/security, unsafe surface,
branching/responsibility growth, hidden dependency/ownership, brittle tests,
extension seams, and readability/maintainability. Every refactor-related finding MUST state its risk category, affected surface, evidence, and smallest durable fix.
Use concrete risk framing instead of generic convention, style,
cleanliness, or improvement language.
Request broad cleanup only when a smaller durable fix cannot remove the risk.

## Architecture Decision Pack Review

Review each applicable Pack or equivalent ADR, even if invalid; validate and
report it. Match its mode to canonical
`architecture_design_mode`; require independent challenge evidence for
`review_intensive`. Apply the full Architecture Decision Pack Review Checklist
in `references/review-checklists.md` and report gaps.

## Principle and Readability Lens

For medium+ reviews, run the **Design Coherence Pass** and return
evidence-bound `principle_checks.design_coherence`; findings name surface, risk,
and smallest fix.

## Review Loop Routing

After entry, load `references/review-loop.md` before the first REVIEW step. It
owns batches, transitions, barriers, and pivots. Fresh pass bundles carry
principles/checklists/rubrics. `worker_return_schema_selector` resolves only
recursive required/triggered shapes, types, enums, and cardinality; exclude
sibling/batch state. Impact projection preserves canonical closure and cannot
make audit/review-fix clean.

For a carried `approved_feature_preparation_qa_acceptance_obligation`, verify its scope,
prerequisite, source binding, and exact result/successful-pair conditions with
evidence from `contracts/handoffs.yaml` and `contracts/phase-gates.yaml`; return
rejected/`HAS_REMAINING_ITEMS` or blocked/`BLOCKED` when unmet.

## Exit: Present Final Result

For no findings, say: "No material findings within the reviewed scope and available evidence"; `CLEAN` is an enum, not proof.

## Rules

- Keep round results internal in fresh sibling-blind bundles; incomplete
  coverage returns `HAS_REMAINING_ITEMS`. Verify closure of prior fixes.

## Output

Return reviewed scope, rounds/result, evidence-backed findings/fixes, verification, applicable bugfix/agentic/behavioral/semantic checks, required QA, and residual risk per `contracts/output.yaml`.

## Stop Rules

- Audit mode stops after one review batch. Report terminal findings without edits.
- The normal review-fix path (max 10 rounds) is an initial review batch, fixes and validation, then one fresh re-review batch; mutation requires a new snapshot and complete coverage.
- Before round 3+, require `additional_round_reason` backed by changed files,
  unresolved finding, validation failure, regression/drift, or changed
  hypothesis; score alone is insufficient. round 10 is terminal; never start 11.
- Block and stop for unavailable/empty required review material.

### Drift detection (medium+ scope)

Compare rounds with `references/score-tracking.md`. Drift, regression,
stagnation, or pivot evidence returns `pivot_restart_signal`; the orchestrator records `pivot_restart_decision` before another pass.


## Review Finding Rule Distillation

For each blocker/must-fix, load
`references/review-finding-permanent-rule.md`; classify `one_off_fix`,
`permanent_rule_candidate`, or `no_action`. Promote only recurring process/eval
gaps, missing contracts/checklists, or high-impact repeat failures.
