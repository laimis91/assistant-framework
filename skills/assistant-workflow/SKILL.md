---
name: assistant-workflow
description: "Run proportional development phases and resume persisted task state. Use to plan, build, implement, fix, migrate, refactor, or continue project artifacts."
effort: high
triggers:
  - pattern: "rewrite|implement|fix|migrate|refactor|continue|resume|recover|build feature|build the|build a|build an|create feature|add feature|(create|make) (a |an |the |new )*(rest |api )?(endpoint|dashboard|screen|page|component|service|tool|app|feature)|idea into (an |a )?(implementation plan|implementation|plan|code|feature)|how should i approach|break this down|start working on|let.s (build|create|implement|add|make|fix|migrate|refactor|rewrite)|phase [0-9]|code (this|that|it|the|a|an|up)"
    priority: 40
    min_words: 2
    reminder: "This matches assistant-workflow. Read this SKILL.md and contracts/index.yaml first, then load the selector. Triage task size and include tests in Build; do not skip phases."
---

# Development Workflow

Public routing contract; detailed mechanics live in references and contracts.

## Goal

Move work to verified outcome through right-sized phases, gates, tests, review, and safe execution.

## Success Criteria

- Scale phases to risk; Decompose, Design, and durable state run only when triggered.
- Before resume, reconcile the newest user request and repository evidence.
- If resume reconciliation classifies persisted state as stale, superseded, or completed, update the framework-owned `{agent_state_dir}/task.md` before acting or returning; record the classification and reason, current task identity, and repaired exact next action.
- `plan_mode` keeps planning proportional: trivial safe work may use `none`, bounded small work may use `inline`, and medium+, risky, destructive, or scope-shaping work uses `approval_required`. When `plan_mode=inline`, small work has an inline plan and proceeds without ceremony unless risk requires approval.
- `references/workflow-controller.md` is the canonical source for controller intensity, workflow state, manual verification, harness/QA routing, and review-role separation.
- Ordinary medium+ workflow tasks stay standard, non-harness, and non-QA unless explicit controller criteria apply.
- Harness-capable work carries the Done Contract, Harness Recipe, and trace/replay artifacts required by the controller.
- Candidate Search is reserved for explicit alternatives, open-ended architecture/design, optimization, high uncertainty, repeated failures, unclear/flaky bugs, or reviewer-requested pivots.
- Behavior changes default tests-first or carry explicit validation in the same Build step.
- Review, QA, and security routing apply when triggered.
- Medium+ final output follows `references/final-handoff.md`; small output gives changed files, evidence, review status, risks, and next steps.

## Constraints

- Explicit user or repository artifact schemas override workflow-internal shapes; preserve exact paths, keys, types, ids, and supplied literals.
- Do not skip applicable phases; Plan is inapplicable only when the explicit `plan_mode=none` eligibility gate passes.
- Do not ask ritual questions when code/context makes the next safe action clear.
- Ask bounded clarification before planning only when an undiscoverable implementation-shaping unknown lacks a safe default and affects correctness, scope, behavior, data, public contract, security, migration safety, or verification.
- assistant-clarify owns prompt-level ambiguity when its routing matches; clear prompts do not invoke it. Existing workflow clarification owns precise, answerable questions and safe defaults.
- Load `references/progressive-discovery.md` when `uncertainty_shape=progressive`, `progressive_route_clear_consumption_state in [pending, consumed]`, `progressive_sequence_readiness_state in [active, closed]`, or `progressive_artifact_retention_state=terminally_archived`. The durable markers load validation regardless of whether progressive_artifact_retention_state is missing, not_applicable, or retained, so invalid carried state fails closed instead of releasing artifacts. Retained state keeps active/resumable progressive artifacts available after `uncertainty_shape=bounded`. `terminally_archived` is allowed only after explicit final archival/termination evidence proves continuation and reference resolution are impossible; `Task state: completed` does not qualify by itself, and terminally archived state cannot revert. Fully specified tasks with `not_applicable` markers stay bounded, and size alone is not a trigger.
- Progressive Discover is a no-execution boundary; any mutating prerequisite uses a separate approved workflow that returns evidence before normal workflow gates continue.
- Keep scope changes explicit and tied to correctness, security, safety, or verification.
- Do not install tools, upload code, call external services, or paste proprietary content into third-party systems unless the user explicitly approved that path.
- Prefer repo-native commands over new tooling.
- When external services, installs, or sensitive-data handling are in scope, load `references/ai-usage-policy.md` for company-safe detail. It is not an entry dependency.

## Contracts

Canonical contracts are authoritative. Read `contracts/index.yaml` first, validate at enforcement, and load only the contract selector applicable to the current boundary:

- `entry`: load the exact entry fields declared by `contracts/index.yaml` from `contracts/input.yaml`; `references/triage-rubric.md` is the only declared entry reference.
- `progressive_discovery`: load `references/progressive-discovery.md` when `uncertainty_shape=progressive`, either durable marker is pending/consumed or active/closed, or `progressive_artifact_retention_state=terminally_archived`; durable markers route even when the retention state is missing or invalid. `terminally_archived` releases the durable artifacts only with explicit final archival/termination evidence, never merely `Task state: completed`, and cannot revert.
- `delegation`: load role and trigger fields when roles may be required and before any subagent dispatch.
- `current_phase`: active `contracts/phase-gates.yaml` at transition.
- `selected_handoff`: `contracts/handoffs.yaml` before dispatch and return validation.
- `completion`: `contracts/output.yaml` at completion before final exit.

Selectors resolve by unique id plus canonical path, exact section, key, and explicit names. Runtime selectors resolve `name_from` only through their declared `allowed_names`.

Missing or invalid selector: `load_full_authoritative_file`; validate the full named canonical file and record recovery.

Migration note: assistant-workflow contracts are v4. Direct-user, applicable
`AGENTS.md`, or active-skill instructions trigger delegation; record the
`subagent_trigger_scope` and dispatch without a
separate permission question. Explicit opt-out, real unavailability, or an
exact policy block uses evidenced fallback. `verification_command` is non-empty
argv `string[]`; assistant-review v3 owns Reviewer/QAEvaluator handoffs and
returns `final_summary` / `qa_evaluation_result`; the `reviewed_scope` is non-empty.

## Visible Checkpoints

Phase markers are required only for `controller_intensity=strict`, explicit
project policy, or a user request. Light and standard work still follows every
logical phase and gate, but reports progress with concise natural updates
without exact marker ceremony.

When exact markers are required, use this instruction: `Use this exact format:`

```
--- PHASE: [name] ---
```

For steps within a phase:

```
>> [step description]
```

For completion:

```
--- PHASE: [name] COMPLETE ---
```

## Refactor Guidance

- Justify it with a concrete risk only: correctness, security, unsafe change surface, ownership, brittle testing, or poor extension seam.
- Tie incidental or scope-expanding refactors to concrete risk instead of vague framing such as generic convention language, style, cleanliness, or generic improvement.
- Choose the smallest useful, durable fix that removes the identified risk. Keep cleanup scoped unless the user explicitly requested cleanup, reorganization, or refactor work.

## Triage

Start Triage with a concise update; strict markers use `--- PHASE: TRIAGE ---`.

Load `references/triage-rubric.md`, perform a quick read-only Candidate scope
scan, then assess task type, risk, size, gates, agents, controller intensity,
plan mode, subagent state, and search mode. Ideas need binary criteria.

| Size | Phases |
|---|---|
| **Small** | Discover quick -> [Plan] -> Build -> Review -> Document; `plan_mode=none` only for trivial safe work, otherwise inline or approval-required |
| **Medium** | Discover -> Decompose -> Plan -> [Design] -> Build -> Review -> Document |
| **Large** | Discover -> Decompose -> Plan -> Design -> Build -> Review -> Document |
| **Mega** | Discover -> Decompose -> Plan -> Design -> Build -> Review -> Document |

[Design] = UI only.

Print: `>> Triaged as: [SIZE] — phases: [list]`
Print: `>> Triage metadata: type=[TASK_TYPE] | risk=[RISK_TIER] | intensity=[controller_intensity] | plan=[plan_mode] | gates=[count] | agents=[count] | search=[search_mode] | scope_confidence=[low|medium|high]`

If scope exceeds initial triage during any phase, stop and re-triage. Use `references/candidate-search.md` only when `search_mode: candidate_search` is selected.

## Phase Routing

Load `references/phases.md` for the current phase. Load `references/workflow-controller.md` only when resolving shared routing/default, movement, harness, review, QA, or subagent-separation decisions. Use `references/context-budget-and-pattern-retrieval.md` for large material or framework patterns, `references/artifact-first-output-contract.md` before Plan, `references/decomposition-plan-review.md` before medium+ Decompose exits, `references/plan-template.md` during Plan, and `references/context-handoff-templates.md` for non-standard continuations.

| Phase | When | Key Actions |
|---|---|---|
| Discover | All | Inspect request/repo and unknowns; medium+: Code Mapper; unknown-cause bugfixes: load `assistant-debugging`. |
| Decompose | Medium+ | Smallest slices with acceptance and verification. |
| Plan | `plan_mode != none` | Inline stays concise; approval-required waits for approved scope, packets, files, checks, and risks. |
| Design | UI only | Direction, checklist, approval. |
| Build | All | Light direct; ordinary medium one edit/test executor; separation only for high-risk or broad/noisy/environment-heavy verification. Tests/validation travel with code. |
| Review | All | Light fresh self-review; standard/strict Spec Review then independent `assistant-review`; QA only when required. |
| Document | All | Apply state/manual-verification modes; metrics optional and non-blocking. |

For subagent rules, load `references/subagent-dispatch.md` and resolve
`subagent_policy_state`, `subagent_execution_mode`, `subagent_trigger_scope`,
and conditional `policy_blocking_source` before spawning. Light small low-risk
work uses `not_required` and `not_applicable`. For standard/strict work, a
direct user request or applicable `AGENTS.md` or active-skill instruction triggers `delegation_triggered`: infer scope and dispatch the configured role agents without a separate permission question. Direct fallback needs explicit
opt-out, an exact active policy block, or real unavailability; do not infer unavailability merely because no visible tool is named `Task`, `delegate`, or `subagent`. Delegation retains parent sandbox, tool/action approvals,
external-write, install, destructive-operation, and secrets safeguards.

Load `references/harness-controller.md` only after `references/workflow-controller.md` or carried-forward phase state establishes `harness_capable=true`.
Load `assistant-security` when touching auth, user input, secrets, persistence, network calls, shell commands, dependency/config changes, or external integrations.
For review-gated multi-slice work, load `references/slice-review-topology.md` before emitting or consuming slice review evidence.

## Output

Return:
- Status: complete, partially complete, blocked, or plan ready.
- Changed files: paths and purpose.
- Verification: commands, pass/fail, skipped checks with reasons.
- Review result: spec, quality, QA, and security when applicable.
- Residual risk: blockers, assumptions, policy constraints, or follow-up.
- Next step: one practical recommendation.

Do not use phrases like "should work", "probably fixed", or "looks good" unless immediately qualified with evidence or uncertainty.

## Stop Rules

- Stop and ask when an implementation-shaping field is material, undiscoverable, and has no safe default.
- Stop before Build when `plan_mode=approval_required` until plan approval.
- Stop before final response if build, tests, required review, or output contract evidence is missing.
- Stop when a plan deviation changes approved scope, files, behavior, risk, verification, or acceptance criteria; record the deviation and get approval before continuing.
