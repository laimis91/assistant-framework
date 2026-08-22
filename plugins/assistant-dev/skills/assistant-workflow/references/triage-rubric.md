# Triage Rubric And Gate Packs

## Required Triage Output

Record `task_type`, `risk_tier`, `size`, `controller_intensity`, `plan_mode`,
`execution_intent`, `qa_evaluation_mode`, `harness_capable`,
`architecture_design_mode`, `architecture_design_trigger_reasons`,
`build_execution_lane`, `workflow_state_mode`, `manual_verification_mode`,
`required_gates`, `required_agents`, `subagent_policy_state`,
`subagent_execution_mode`, `subagent_trigger_scope`, `search_mode`, and
`candidate_scope_scan` evidence.

## Size Rules

| Size | Use when |
|---|---|
| `small` | Local low-risk tested. |
| `medium` | Multi-file feature/refactor/integration/contract. |
| `large` | Cross-module public/config/data/weak-tests/uncertainty. |
| `mega` | Rewrite/migration/legacy restructure/parity. |

Auth/PII/payment/destructive-public-data/API/legacy-migration: `large`
unless isolated/covered.

## Plan Mode Rules

| Mode | Use when |
|---|---|
| `none` | prepare_only at any size retains `none`, including high/critical risk, unless optional readiness planning is requested. |
| `inline` | Bounded small, no approval trigger. |
| `approval_required` | For execution_intent != prepare_only, medium+ work, high/critical, destructive/public/data/security, material architecture/scope, policy, or explicit approval. |

## Controller Intensity Rules

For `prepare_only`, set `qa_evaluation_mode=not_required` and retain explicit
QA/acceptance only in `feature_preparation_result.future_qa_acceptance_obligation`;
risk/project criteria may still select strict preparation. QA request alone never promotes strict and remains a future obligation; QA request alone never selects harness_capable=true during prepare_only without separate harness evidence.

| Intensity | Use when |
|---|---|
| `light` | Small low-risk localized work. |
| `standard` | Ordinary medium+ source-changing work when `harness_capable=false` and `qa_evaluation_mode=not_required`. |
| `strict` | High/critical, `harness_capable == true`, `qa_evaluation_mode == required`, explicit harness/QA acceptance, or trace/replay; QA only outside `prepare_only`. |

Never infer `strict` from size/delegation.

## Candidate Scope Scan

Scan paths/symbols/tests/docs/contracts/config/mirrors/runtime; evidence.

## Risk Tier Rules

| Risk tier | Use when |
|---|---|
| `low` | Local/reversible/tested. |
| `moderate` | Shared helper/unclear edge. |
| `high` | Public/data/migration/security/weak-test coupling. |
| `critical` | Loss, auth bypass, secret exposure, payment/security, outage. |


## Search Mode Rules

`none`: obvious path; `lightweight`: 1–3 options; `candidate_search`:
alternatives/design/optimization/uncertainty, repeated failure/flaky bug, or
pivot; loads `references/candidate-search.md`.

## Architecture Design Mode Rules

`architecture_design_mode` selects a pre-plan Architecture Decision Pack; size
alone is not a trigger.

- `not_applicable`: one evidenced path; reason.
- `lightweight`: one bounded ownership/dependency/type/verification decision.
- `required`: new/cross-boundary/public/persistent-lifecycle/material-quality-extensibility,
  extension seam, or viable design choice.
- `review_intensive`: independent high-risk/conflicting-driver challenge.

Non-`not_applicable` loads `references/architecture-decision-pack.md`; Pack owns
facts/questions/types/exceptions/verification/freshness/handoff.
An extension seam or material extensibility makes `not_applicable` invalid.

## Execution Gates

For execution: record requirements/scope/verification; run tests, build, review.

## Preparation Gates

For `prepare_only`, require exactly `feature-preparation evidence` and concrete
Discover/preparation roles; no execution/task-category gates.

## Task Category Gate Packs

### Bugfix
Capture reproduction/root cause; add regression assertion; keep scope tied.

### Feature
Make acceptance binary; test new behavior; check contract/config/telemetry/docs.

### Refactor / Migration / Rewrite
Inventory baseline; protect parity; list invariants; approve changes; map boundaries.

### Config / Infra
List runtime/rollback; never hardcode secrets/local state; dry-run/smoke.

### Security / Input
Consider abuse, validation, authorization, trust; never log sensitive data; load
security review for auth, PII, payments, external input.

### Docs-Only
Documentation-only work does not require code or test changes unless it changes runnable behavior.
Remove or reconcile outdated instructions with current behavior.

### Spike
Explore feasibility; no unsupported claims.

## Required Agents

Use `references/subagent-dispatch.md`; in `prepare_only`, QA is future only.
Security -> `assistant-security`; parity -> Explorer; docs-only skips non-runnable Build.
