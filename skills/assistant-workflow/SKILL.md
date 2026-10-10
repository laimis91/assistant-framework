---
name: assistant-workflow
description: "Prepare, plan, build, or resume repository task state: feature/epic/story technical preparation, implementation, fixes, migrations, refactors, project artifacts, backlog items, and intended-change ideas."
requires:
  - assistant-review
  - assistant-verification
---

# Development Workflow

Clear implementation requests, backlog items, and ideas with an intended change enter Discover requirements check.

## Goal

Move repository work from request to a verified outcome through the applicable workflow phases.

## Success Criteria

- Before resume, reconcile the newest user request and repository evidence. For stale, superseded, or completed state, update `{agent_state_dir}/task.md` before acting; record classification, reason, task identity, and exact next action.
- Run Decompose, Design, and durable state only when triggered. `prepare_only` runs Discover -> Preparation Completion; readiness planning is optional, implementation gates do not apply, and no execution is claimed.
- `plan_mode`: bounded small uses no-wait `inline`; for `execution_intent != prepare_only`, `approval_required` applies to medium+, risk, destructive, and scope changes. In `prepare_only`, use `inline` only for explicitly requested readiness planning; otherwise `none`.
- Ordinary medium+ work stays standard, non-harness, and non-QA unless controller criteria apply. Harness-capable work carries required artifacts; preparation records harness/QA requests as typed future obligations with capability inactive.
- Use Candidate Search only for explicit alternatives, open-ended design, optimization, high uncertainty, repeated failures, unclear/flaky bugs, or a reviewer-requested pivot.
- Triggered Architecture Decision Packs use fresh source evidence. Preparation retains Discover-only context through Preparation Completion; implementation binds the Pack through Plan, packets, Build, handoff, and Review.
- Use `assistant-verification` before Plan fixes checks or no-plan Build; carry decision/TDD unchanged and assess actual results before review/completion. TDD is independent of scope/method; active TDD requires meaningful RED, otherwise never fabricate RED.
- Existing-system preparation inspects sources, code, and tests. Carry the exact typed approved result into `implement_only` with existing-system evidence or a typed `not_applicable` basis and inactive future obligations. Product questions need evidence.
- Behavior-bearing work records compact change-impact applicability. Shared, materially unresolved, or carried expanded impact uses the common pre-Build/completion checker; carry its identity through planning, Build, and assistant-review. Resolve it from the active installation, never repository cwd.
- Review, QA, and security apply when triggered; assistant-review owns Reviewer/QAEvaluator handoffs. Medium+ completion binds canonical review/QA state and exact snapshot; remaining work, incomplete coverage, or rejected/blocked QA prevents completion. Medium+ uses `references/final-handoff.md`; `prepare_only` returns readiness and next state.

## Constraints

Honor user/repository schemas exactly: preserve paths, keys, types, ids, and literals. Use source-backed defaults; ask about material product choices Plan approval cannot settle. assistant-clarify handles prompt ambiguity; workflow asks answerable, evidence-backed questions. Skip Plan only when eligible.

Progressive Discover does not execute; mutating prerequisites require a separate approved workflow and returned evidence before gates continue. Tie scope changes to correctness, security, safety, or verification. Installs, uploads, external calls, or sharing proprietary content with third parties need explicit approval. Prefer repo-native commands; for external services, installs, or sensitive data, load `references/ai-usage-policy.md`.

## Contracts

Read `contracts/index.yaml`; load the current selector and validate against canonical
content at enforcement. Reuse an already-loaded exact canonical selector section while
source/task identity and context remain faithful; recheck its gates and load only missing
or new selectors. Reread if source/task identity changes, context is missing/compacted,
or resolution is unresolved. The index never replaces canonical contracts.

- `entry`: load entry fields declared by `contracts/index.yaml` from `contracts/input.yaml`; `references/triage-rubric.md` is its only entry reference.
- `architecture_design`: load `references/architecture-decision-pack.md` when `architecture_design_mode != not_applicable`; use the typed Pack before Decompose/Plan and retain its reference through Review.
- `feature_preparation`: load `references/feature-preparation-evidence.md` for repository-grounded preparation, existing behavior, every `implement_only`, or carried harness/QA obligations (including `feature_preparation_scope=not_applicable`). Before Decompose, Plan, or Build, retain `approved_feature_preparation_result` unchanged plus its evidence ref or typed `not_applicable` source binding. Carried QA uses only the existing post-Build, post-Code-Reviewer QA Evaluator lane.
- `change_impact`: load `references/change-impact.md` when behavior, cosmetic, or local/shared/unresolved impact affects verification. Record compact applicability; shared, materially unresolved, or explicitly carried expanded work requires common pre-Build/completion.
- `progressive_discovery`: load `references/progressive-discovery.md` when `uncertainty_shape=progressive`, route-clear state is `pending`/`consumed`, sequence readiness is `active`/`closed`, or retention is `terminally_archived`. Durable markers still require validation with missing/invalid retention or `not_applicable`/retained state; fail closed. Retained artifacts remain active after bounded shape. Terminal archival needs a typed `progressive_terminal_archival` tombstone and final evidence; completed alone is insufficient and archive cannot revert. Fully specified `not_applicable` tasks stay bounded; size alone is no trigger.
- `delegation`: load role/trigger fields and `references/subagent-dispatch.md` before dispatch.
- `verification`: run `assistant-verification` before Plan fixes checks or no-plan Build.
  Show unchanged `verification_decision` before Build and both `verification_decision`
  and `evidence_assessment` at completion, including light. Carry the decision and
  `tdd_choice.mode` unchanged into packet/lane; assess actual evidence before
  review/completion.
- `current_phase`: load active `contracts/phase-gates.yaml` at transition. `selected_handoff`: load `contracts/handoffs.yaml` before dispatch and return. `completion`: load `contracts/output.yaml` before final exit.

Selectors resolve by unique id plus canonical path, section, key, and explicit names; runtime `name_from` resolves only declared `allowed_names`. Missing or invalid selectors use `load_full_authoritative_file`; validate the full named canonical contract and record recovery.

Migration note: assistant-workflow contracts are v12.0 and require assistant-verification while preserving assistant-review. Refresh older packets without a current verification decision and matching TDD projection before Build; never infer historical checks or RED. Pack alternatives bind stable `selected_alternative_id`; verified `quality_scenario_id` binds resolvable verification identity; Pack `review_result` retains canonical refs. Before Build, Plan binds task/review refs as `downstream_bound` (inline at pre-Build when `plan_mode=none`); material invalidation clears refs through refresh, re-plan, and reapproval.

## Visible Checkpoints

Use exact markers only for `controller_intensity=strict`, explicit policy, or user request; otherwise follow all gates with concise updates.

When required, use this exact format:
```
--- PHASE: [name] ---
>> [step description]
--- PHASE: [name] COMPLETE ---
```

## Refactor Guidance

Refactor only for concrete correctness, security, unsafe change-surface, ownership,
brittle-testing, or extension-seam risk. Tie scope expansion to that risk; avoid generic
style. Make the smallest durable fix; keep cleanup scoped unless requested.

## Triage

Start Triage with a concise update; strict uses `--- PHASE: TRIAGE ---`. Load the triage rubric; scan Candidate scope read-only and assess type/risk/size/gates/agents/intensity/plan/subagent state/search. Ideas need binary criteria.

Prepare-only: Discover -> [readiness] -> Preparation Completion; no implementation. Small: Discover quick -> [Plan] -> Build -> Review -> Document; `plan_mode=none` only for trivial safe work. Medium: Discover -> Decompose -> Plan -> [Design] -> Build -> Review -> Document. Large/Mega: Discover -> Decompose -> Plan -> Design -> Build -> Review -> Document.

[Design] is UI only. Print `>> Triaged as: [SIZE] — phases: [list]` and `>> Triage metadata: type=[TASK_TYPE] | risk=[RISK_TIER] | intensity=[controller_intensity] | architecture=[architecture_design_mode] | plan=[plan_mode] | gates=[count] | agents=[count] | search=[search_mode] | scope_confidence=[low|medium|high]`. If scope expands, stop and re-triage. Load `references/candidate-search.md` only when `search_mode: candidate_search`.

## Phase Routing

Load generated `references/phases/<current-phase>.md` (lowercase; Preparation Completion is `preparation-completion`). Missing or unknown view: load authoritative `references/phases.md`. Load `references/workflow-controller.md` only when resolving shared routing/default, movement, harness, review, QA, or subagent-separation decisions. `references/workflow-controller.md` is the canonical source for controller intensity, workflow state, manual verification, harness/QA routing, and review-role separation. Load `references/architecture-decision-pack.md` only when architecture mode applies. For large material/patterns use `references/context-budget-and-pattern-retrieval.md`; before Plan use `references/artifact-first-output-contract.md` only outside `prepare_only`; before medium+ Decompose exits use `references/decomposition-plan-review.md`. During Plan use `references/plans/<size>.md` (`mega` uses `large`, `prepare_only` uses `prepare-only`); missing or unknown view loads authoritative `references/plan-template.md`. Non-standard continuation uses `references/context-handoff-templates.md`. Optional `prepare_only` readiness Plans omit Artifact Contracts and executable slices.

| Phase | When | Key action |
|---|---|---|
| Discover | All | Inspect request/repo/unknowns; map only unresolved file boundaries; unknown-cause bugs load assistant-debugging. |
| Decompose | Medium+ implementation | Smallest slices with acceptance and verification. |
| Plan | `plan_mode != none`; optional readiness | Route inline/approval. |
| Design | UI only; not `prepare_only` | Direction, checklist, approval. |
| Build | Not `prepare_only` | Run approved checks; active TDD adds meaningful RED/GREEN/REFACTOR. Separate only high-risk or broad/noisy/environment-heavy verification; retain results and exclusions. |
| Review | Not `prepare_only` | Light self-review; expanded impact uses assistant-review; standard/strict uses independent assistant-review; QA when required. |
| Document | Not `prepare_only` | Apply state/manual-verification modes; metrics are optional and non-blocking. |
| Preparation Completion | `prepare_only` | Return readiness; approval is next. |

Before dispatch, load `references/subagent-dispatch.md` and resolve `subagent_policy_state`, `subagent_execution_mode`, `subagent_trigger_scope`, and conditional `policy_blocking_source`. Light small low-risk work uses `not_required`/`not_applicable`. For standard/strict work, a direct user request or applicable `AGENTS.md` or active-skill instruction triggers `delegation_triggered`: infer scope and dispatch the configured role agents without a separate permission question. Direct fallback needs explicit opt-out, exact active policy block, or real unavailability; do not infer unavailability merely because no visible tool is named `Task`, `delegate`, or `subagent`. Delegation retains parent sandbox, tool/action approvals, external-write, install, destructive-operation, and secrets safeguards.

Load `references/harness-controller.md` only for non-`prepare_only` work with `harness_capable=true`. Load `assistant-security` when touching auth, user input, secrets, persistence, network/shell calls, dependency/config changes, or external integrations.

## Output

Return status, changed files/purpose, verification and skipped-check reasons, applicable review/spec/quality/QA/security, residual risks, and next step; qualify claims with evidence.

## Stop Rules

Stop for missing material intent/authority, unapproved Build, missing required output evidence (completed selected and binding checks and applicable review), or unapproved scope, files, behavior, risk, verification, or acceptance changes. Active TDD requires meaningful RED, GREEN, and REFACTOR evidence. Record the blocker and obtain approval before continuing.
