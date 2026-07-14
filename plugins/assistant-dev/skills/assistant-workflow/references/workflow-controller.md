# Workflow Controller

Internal reference for `assistant-workflow` routing and default decisions. This
file centralizes decision boundaries that cut across phase details while
`assistant-workflow` remains the public compatibility entrypoint.

## Controller Role and Non-Goals

- Keep `assistant-workflow` as the only public workflow skill entrypoint.
- Decide the workflow control shape: intensity, harness routing, QA routing,
  movement, and role separation.
- Organize decisions by boundary, not by phase name: routing/defaults,
  movement, harness boundary, subagent/review/QA lanes, and validation.
- Do not redefine phase execution steps, skill contracts, or task packet
  schemas; those stay in `references/phases.md` and `contracts/`.
- Do not create a public `skills/*workflow-controller*` directory or add a new
  triggerable workflow-controller skill.
- Do not replace `references/harness-controller.md`; that file remains
  harness-only.

## Invocation and Loading Rules

- Load this reference from `assistant-workflow` when a task needs shared
  workflow routing or default decisions.
- Use it before phase-specific detail when selecting `controller_intensity`,
  `plan_mode`, `workflow_state_mode`, `manual_verification_mode`, `learning_capture_mode`,
  `harness_capable`, `qa_evaluation_mode`, movement direction, or review/QA
  ownership.
- Keep the root `SKILL.md` outcome-shaped. Keep phase mechanics in
  `references/phases.md`.
- Do not load `references/harness-controller.md` from this reference unless the
  routing decision has already set `harness_capable=true`.

## Routing Defaults

- `plan_mode=none`: only trivial, localized, reversible, low-risk work with one
  obvious implementation path, known files and verification, no material
  ambiguity, and no public contract, data, security, destructive, or policy
  concern. Discover carries the goal, scope, constraints, and verification
  directly into Build; there is no plan artifact.
- `plan_mode=inline`: bounded small work with more than one useful step but no
  approval trigger. Record the compact plan and continue without waiting.
- `plan_mode=approval_required`: all medium+ work and any task with high/critical
  risk, destructive effects, public contract/data/security changes, material
  architecture or scope choices, repository approval policy, or an explicit
  user request. Wait for approval before Build.

- `light`: small, low-risk, local work with no public behavior, data, security,
  harness, or QA acceptance risk. It may run inline/direct with relevant
  automated validation and a fresh self-review. Use
  `workflow_state_mode=inline`, `subagent_policy_state=not_required`, and
  `subagent_execution_mode=not_applicable`; do not require Code Writer,
  Builder/Tester, or independent Reviewer dispatch evidence. It does not require
  a journal, metrics, reflexion, memory, or manual verification unless separately
  triggered.
- `standard`: ordinary medium+ source-changing work defaults to
  `controller_intensity=standard`, `harness_capable=false`, and
  `qa_evaluation_mode=not_required`. It uses
  `build_execution_lane=bounded_executor`: one edit/test owner during Build.
  Review then independently dispatches Code Reviewer or records the allowed
  fresh direct-fallback result. It requires an approved plan, Build
  verification, and independent review, but no harness, split-worker, or QA
  ceremony by size.
- `strict`: select only for high/critical risk,
  `harness_capable=true`, `qa_evaluation_mode=required`, trace/replay criteria,
  explicit harness/QA criteria, or explicit strict control.
- Do not infer `strict`, `harness_capable=true`, or required QA from
  size=medium+ or delegation alone.
- Treat `harness_capable` as false unless the task is long-running,
  trace/replay-ready, high-risk harness work, domain-scored,
  UI/visual/product/UX/docs/DX-facing, explicitly requested as harness/QA work,
  or already has an accepted Done Contract/Harness Recipe.
- Treat `qa_evaluation_mode=not_required` unless explicit QA/acceptance
  evaluation, accepted Done Contract, harness-capable acceptance scope,
  domain-scored scope, or scoped UI/visual/product/UX/docs/DX acceptance applies.

## Progress Update Policy

Phase checkpoints are required only for `controller_intensity=strict`, explicit
project policy, or a user request. Light and standard work use concise natural
progress updates while still following the same applicable phases and
gates.

## State, Verification, and Learning Defaults

- During Discover, apply deterministic safe defaults immediately and record
  topic, value, source, and rationale with
  `clarification_defaults_applied=true`; never ask for confirmation of a safe
  default. Ask only when no safe default exists. A `defaults` reply remains
  compatibility shorthand for accepting displayed recommendations on questions
  that actually required a response; it is not automatic-default evidence.

- Before using persisted state, load `references/task-state-reconciliation.md`.
  Compare the newest user request and current repository identity/evidence,
  classify the state as `active`, `stale`, `superseded`, or `completed`, and
  use the recorded next action only when the state is reconciled active.
- Use `workflow_state_mode=inline` unless state must survive clarification,
  delegation, compaction/cross-session continuation, explicit persistence, or
  strict/harness/required-QA execution. Medium+ size alone does not force a task
  journal; `journal` owns durable state when one of those triggers applies.
- Use `manual_verification_mode=required` only for an explicit request,
  subjective or UI acceptance, external effects, destructive/migration work,
  or inadequate automated verification. Optional steps do not create a wait,
  and user confirmation is not a ritual completion gate.
- Use `learning_capture_mode=auto` normally. The Learning Controller becomes
  required only for explicit `required` mode or concrete review findings,
  build/test failures, user corrections, or memory trend signals. Metrics,
  reflexion, and memory remain optional and non-blocking.

## Move Forward, Step Back, or Replan

- After clarification, create the stable Requirement Acceptance Map for
  medium+, or small work promoted by ambiguity, risk, or multiple material
  requirements. Otherwise keep compact `acceptance_criteria`. Decomposition,
  task packets, review, and completion consume ids only when the map applies.
- Move forward when required inputs are resolved, the current phase gate is
  satisfied, approval-required plans are approved before Build, and the
  next action stays inside approved scope.
- Step back to Discover when an implementation-shaping unknown appears that
  affects correctness, scope, behavior, data, public contract, security,
  migration safety, or verification and cannot be safely inferred locally.
- Step back to Decompose when the slice boundary is broad, not independently
  verifiable, ordered incorrectly, or no longer maps to the artifact contract.
- Step back to Plan when files, behavior, risk, verification, acceptance
  criteria, harness routing, QA routing, or role requirements differ from the
  approved plan.
- Replan when the approved packet is stale, a plan deviation changes scope, a
  Code Writer blocker requires `missing_contract` or `stale_plan` recovery, or
  a pivot/restart decision selects replan.
- Ordinary non-harness Build repair is same-scope and bounded. Persist
  `build_repair_state` with `max_attempts=3`, `no_progress_limit=2`, normalized
  failure signatures, progress evidence, plan version,
  `cumulative_attempt_count`, and terminal `terminal_route`. Redispatch,
  compaction, or continuation never resets the cumulative same-scope count.
  Reaching either bound terminates in pivot/replan/debugging or blocked.

## Harness Boundary

- This controller only decides whether harness routing applies.
- `references/harness-controller.md` is loaded only after
  `harness_capable=true` is established.
- Do not load `references/harness-controller.md` for ordinary medium work,
  source-changing work alone, delegation alone, generic acceptance labels, or
  optional/not_required QA reasons.
- When harness routing applies, `references/harness-controller.md` owns Done
  Contract, Harness Recipe, and the harness entry gate.
- `references/harness-runtime-artifacts.md` owns Harness Run State, Trace
  Ledger, Replay Packet, Artifact Reference Ledger, pivot/restart details, and
  runtime corrective actions.

## Subagent, Review, and QA Separation

- For ordinary medium standard work, Code Mapper maps context, one bounded
  executor owns focused RED/GREEN/edit/test work in Build. After Build, Review
  owns independent Code Reviewer dispatch/result evidence. Code Reviewer
  reviews code quality, defects, security, architecture, and test coverage.
- Use separated Code Writer and Builder/Tester only for high/critical risk,
  broad/noisy/environment-heavy verification, explicit independent TDD
  evidence, or explicit separation.
- Light work implements directly, runs relevant automated validation/tests, and
  performs a fresh self-review without worker or independent-review dispatch
  evidence. Any security, high-risk, harness, or QA trigger promotes the work out
  of this lane.
- Code Reviewer and QA Evaluator responsibilities stay separate.
- QA Evaluator runs only when `qa_evaluation_mode=required`, after build/test
  and Code Reviewer evidence exist.
- QA Evaluator owns acceptance, Done Contract readiness, verification evidence,
  final readiness, and scoped domain quality.
- `reviewer` remains a compatibility route for code review handoffs; it does
  not satisfy required QA Evaluator evidence.

## Validation Expectations

- Contract and eval checks must prove this file exists and is linked from
  `SKILL.md` and `references/phases.md`.
- Contract checks must prove no public `skills/*workflow-controller*` skill
  directory exists.
- Contract checks must prove this reference is decision-boundary oriented, not
  fragmented by phase-name sections.
- Ordinary medium checks must preserve `controller_intensity=standard`,
  `harness_capable=false`, and `qa_evaluation_mode=not_required`.
- Harness checks must prove `references/harness-controller.md` stays
  harness-only.
- Generated plugin mirrors must come from
  `tools/plugins/sync-plugin-skills.sh --apply`; do not hand-edit plugin skill
  copies.
