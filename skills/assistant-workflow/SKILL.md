---
name: assistant-workflow
description: "Prepare, plan, build, or resume repository task state: feature/epic/story technical preparation, implementation, fixes, migrations, refactors, artifacts, backlog items, and intended-change ideas."
requires:
  - assistant-review
  - assistant-verification
  - assistant-tdd
---

# Development Workflow

Implementation requests and intended-change ideas enter Discover requirements check.

## Goal

Verify outcomes.

## Success Criteria

- Before resume, reconcile the newest user request and repository evidence. For stale, superseded, or completed state, update `{agent_state_dir}/task.md` before acting; record classification, reason, task identity, and exact next action.
- Run Decompose, Design, and durable state only when triggered. `prepare_only` runs Discover -> Preparation Completion; readiness planning is optional, implementation gates do not apply, and no execution is claimed.
- `plan_mode`: bounded small uses no-wait `inline`; for `execution_intent != prepare_only`, `approval_required` applies to medium+, risk, destructive, and scope changes. In `prepare_only`, use `inline` only for explicitly requested readiness planning; otherwise `none`.
- Ordinary medium+ work stays standard, non-harness, and non-QA unless controller criteria apply. Harness-capable work carries required artifacts; preparation records harness/QA requests as typed future obligations with capability inactive.
- Candidate Search needs alternatives, design/optimization uncertainty, repeated failures, unclear/flaky bugs or reviewer-requested pivots.
- Triggered Architecture Decision Packs use fresh source evidence. Preparation retains Discover-only context through Preparation Completion; implementation binds the Pack through Plan, packets, Build, handoff, and Review.
- Existing-system preparation inspects sources, code, and tests. Carry the exact typed approved result into `implement_only` with existing-system evidence or a typed `not_applicable` basis and inactive future obligations. Product questions need evidence.
- Behavior-bearing work records compact change-impact applicability. Shared, materially unresolved, or carried expanded impact uses the common pre-Build/completion checker; carry its identity through planning, Build, and assistant-review. Resolve it from the active installation, never repository cwd.
- Review, QA, and security apply when triggered; assistant-review owns Reviewer/QAEvaluator handoffs. Medium+ completion binds canonical review/QA state and exact snapshot; remaining work, incomplete coverage, or rejected/blocked QA prevents completion. Medium+ uses `references/final-handoff.md`; `prepare_only` returns readiness and next state.

## Constraints

Honor user/repository schemas: preserve paths, keys, types, ids and literals. Apply source-backed defaults; ask material product
questions. Plan approval cannot settle intent. assistant-clarify owns prompt-level ambiguity; workflow owns evidence-backed questions. Skip Plan only when eligible.

Progressive Discover: no-execution boundary. Mutating prerequisites need a separate approved workflow and returned evidence. Scope changes require correctness,
security, safety or verification grounds. Installs, uploads, external calls and
third-party proprietary sharing need explicit approval. Prefer repo-native tools;
load `references/ai-usage-policy.md` for external services, installs or sensitive data.


## Contracts

Read `contracts/index.yaml`; load progressively by current selector; enforce canonical gates. Reuse sections only with matching source/task identity/context; reload after identity change, compaction or unresolved selectors.


- `entry`: load entry fields declared by `contracts/index.yaml` from `contracts/input.yaml`; `references/triage-rubric.md` is its only entry reference.
- `architecture_design`: load `references/architecture-decision-pack.md` when `architecture_design_mode != not_applicable`; use the typed Pack before Decompose/Plan and retain its reference through Review.
- `feature_preparation`: load `references/feature-preparation-evidence.md` for repository-grounded preparation, existing behavior, every `implement_only`, or carried harness/QA obligations (including `feature_preparation_scope=not_applicable`). Before Decompose, Plan, or Build, retain `approved_feature_preparation_result` unchanged plus its evidence ref or typed `not_applicable` source binding. Carried QA uses only the existing post-Build, post-Code-Reviewer QA Evaluator lane.
- `change_impact`: load `references/change-impact.md` when behavior, cosmetic, or local/shared/unresolved impact affects verification. Record compact applicability; shared, materially unresolved, or explicitly carried expanded work requires common pre-Build/completion.
- `progressive_discovery`: load `references/progressive-discovery.md` when `uncertainty_shape=progressive`, route-clear state is `pending`/`consumed`, sequence readiness is `active`/`closed`, or retention is `terminally_archived`. Durable markers still require validation with missing/invalid retention or `not_applicable`/retained state; fail closed. Retained artifacts remain active after bounded shape. Terminal archival needs a typed `progressive_terminal_archival` tombstone and final evidence; completed alone is insufficient and archive cannot revert. Fully specified `not_applicable` tasks stay bounded; size alone is no trigger.
- `delegation`: load role/trigger fields and `references/subagent-dispatch.md` before dispatch.
- `verification`: run `assistant-verification` before Plan fixes checks or no-plan Build. Show unchanged `verification_decision` before Build and at completion alongside `evidence_assessment`, including light. Preserve decision/task-wide `tdd_mode`, due `selected_check_ids` and exact binding tuples through packets/lanes. Derive `tdd_applies` from selected IDs intersecting unchanged `tdd_choice.applicable_check_ids`; assess actual evidence before review/completion. TDD is scope/method-independent: require meaningful RED only when active; never fabricate it.
- `packet_admission`: Python 3.9+ required. Load selector before canonical Plan/resume/dispatch/verification/completion. Run pure helper using independent authority; block missing/unsupported runtime, follow selector recovery. Native adoption/benefit gated.
- `current_phase`: load active `contracts/phase-gates.yaml` at transition. Before dispatch and return, load `contracts/handoffs.yaml` through `build_handoff` only for CodeWriter/BuilderTester; other roles use `selected_handoff`. `completion`: load `contracts/output.yaml` before final exit.

Resolve selectors by unique id, canonical path, section, key and explicit names; `name_from` uses declared `allowed_names` only. Missing/invalid selectors require `load_full_authoritative_file`, full-contract validation and recorded recovery.

Migration v12 -> v13: Refresh active separated TDD through `references/build-worker-protocol.md` and current handoff stage/selection contracts. Earlier verifier-authored RED stays historical: never relabel it or infer current authorization.

Migration: v14.0 requires assistant-verification and preserves assistant-review. Load packet_admission for verified v12/v13 slices; released13 and unreleased canonical13 are not interchangeable. Before Build, older packets need a current verification decision and matching TDD projection; never infer historical checks or RED. Pack `selected_alternative_id` stays stable; verified `quality_scenario_id` resolves verification identity; `review_result` retains canonical refs. Plan binds task/review refs as `downstream_bound` before Build (inline at pre-Build if `plan_mode=none`); material invalidation clears refs through refresh, re-plan and reapproval.

## Visible Checkpoints

Use exact markers only for `controller_intensity=strict`, explicit policy, or user request; otherwise follow all gates with concise updates.

When required, use this exact format:
```
--- PHASE: [name] ---
>> [step description]
--- PHASE: [name] COMPLETE ---
```

## Refactor Guidance

- Justify it with a concrete risk only: correctness, security, unsafe change surface, ownership, brittle testing, or extension seam.
- Tie incidental or scope-expanding refactors to concrete risk.
- Choose the smallest useful, durable fix; keep cleanup scoped.

## Triage

Start Triage: update; strict uses `--- PHASE: TRIAGE ---`. Load triage rubric; scan Candidate scope read-only and assess type/risk/size/gates/agents/intensity/plan/subagent state/search. Ideas need binary criteria.

Prepare-only: Discover -> [readiness] -> Preparation Completion; no implementation. Small: Discover quick -> [Plan] -> Build -> Review -> Document; `plan_mode=none` only for trivial safe work. Medium: Discover -> [Decompose] -> Plan -> [Design] -> Build -> Review -> Document. Large/Mega: Discover -> [Decompose] -> Plan -> Design -> Build -> Review -> Document. Decompose refines canonical packets only for concrete execution purpose; size forces neither additional packets nor Architect.

[Design] is UI only. Print `>> Triaged as: [SIZE] — phases: [list]` and `>> Triage metadata: type=[TASK_TYPE] | risk=[RISK_TIER] | intensity=[controller_intensity] | architecture=[architecture_design_mode] | plan=[plan_mode] | gates=[count] | agents=[count] | search=[search_mode] | scope_confidence=[low|medium|high]`. If scope expands, stop and re-triage. Load `references/candidate-search.md` only when `search_mode: candidate_search`.

## Phase Routing

Load generated `references/phases/<current-phase>.md` (lowercase; Preparation Completion is `preparation-completion`). Missing or unknown view: load authoritative `references/phases.md`. Load `references/workflow-controller.md` only when resolving shared routing/default, movement, harness, review, QA, or subagent-separation decisions. `references/workflow-controller.md` is the canonical source for controller intensity, workflow state, manual verification, harness/QA routing, and review-role separation. For large material/patterns load `references/context-budget-and-pattern-retrieval.md`; before Plan use `references/artifact-first-output-contract.md` only outside `prepare_only`. Ordinary Plan review: `references/decomposition-plan-review.md` questions; no standalone artifact. Plan loads `references/plans/<size>.md` (`mega` uses `large`, `prepare_only` uses `prepare-only`); missing or unknown view loads authoritative `references/plan-template.md`. Nonstandard continuation loads `references/context-handoff-templates.md`. Optional `prepare_only` readiness Plans omit Artifact Contracts and executable packets.

| Phase | When | Key action |
|---|---|---|
| Discover | All | Inspect request/repo/unknowns; map only unresolved file boundaries; unknown-cause bugs load assistant-debugging. |
| Decompose | Concrete execution purpose only | Refine canonical packet boundaries; no second manifest. |
| Plan | `plan_mode != none`; optional readiness | Route inline/approval. |
| Design | UI only; not `prepare_only` | Direction, checklist, approval. |
| Build | Not `prepare_only` | Run approved checks; active TDD adds meaningful RED/GREEN/REFACTOR. Separate only high-risk or broad/noisy/environment-heavy verification; retain results and exclusions. |
| Review | Not `prepare_only` | Light self-review; expanded impact uses assistant-review; standard/strict uses independent assistant-review; QA when required. |
| Document | Not `prepare_only` | Apply state/manual-verification modes; metrics are optional and non-blocking. |
| Preparation Completion | `prepare_only` | Return readiness; approval is next. |

Before dispatch, load `references/subagent-dispatch.md` and resolve `subagent_policy_state`, `subagent_execution_mode`, `subagent_trigger_scope`, and conditional `policy_blocking_source`. Light small low-risk work uses `not_required`/`not_applicable`. For standard/strict work, a direct user request or applicable `AGENTS.md` or active-skill instruction triggers `delegation_triggered`: infer scope and dispatch the configured role agents without a separate permission question. Direct fallback needs explicit opt-out, exact active policy block, or real unavailability; do not infer unavailability merely because no visible tool is named `Task`, `delegate`, or `subagent`. Delegation retains parent sandbox, tool/action approvals, external-write, install, destructive-operation, and secrets safeguards.

Load `references/harness-controller.md` only for non-`prepare_only` work with `harness_capable=true`. Load `assistant-security` when touching auth, user input, secrets, persistence, network/shell calls, dependency/config changes, or external integrations.

## Output

Return status, changed files/purpose, verification/skipped-check reasons, applicable review/spec/quality/QA/security, residual risks and next step; qualify claims with evidence.

## Stop Rules

Stop for missing material intent/authority, unapproved Build, missing required output evidence (completed selected and binding checks and applicable review), or unapproved scope, files, behavior, risk, verification, or acceptance changes. Active TDD requires meaningful RED, GREEN, and REFACTOR evidence. Record the blocker and obtain approval before continuing.
