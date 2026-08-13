# Subagent Dispatch — Roles and Rules

Use specialized agents when a direct user request or applicable `AGENTS.md` or active-skill instruction triggers delegation. Each role has constrained access: code-reviewer, qa-evaluator, and reviewer cannot edit files. Code Writer may act as a bounded edit/test executor when that lane is selected. When subagents are unavailable, explicitly opted out, or policy-disallowed, keep the same selected-lane responsibilities as direct fallback evidence instead of pretending delegation happened. Delegation never bypasses parent sandbox, action/tool approvals, external-write, install, destructive-operation, or secrets safeguards.

For full role prompts, read `references/subagent-roles.md`.

## Delegation Policy State

Before spawning any subagent, resolve:

| Field | Values | Meaning |
|---|---|---|
| `subagent_policy_state` | `not_required`, `delegation_triggered`, `delegation_opted_out`, `subagents_unavailable`, `policy_disallowed` | Whether an applicable instruction triggers delegation or requires evidenced fallback |
| `subagent_execution_mode` | `delegated`, `direct_fallback`, `not_applicable` | Whether work is executed by subagents, by direct fallback with equivalent evidence, or without any subagent role |
| `subagent_trigger_scope` | provenance plus roles/phases/actions | Direct user, applicable `AGENTS.md`, or active skill instruction that triggers delegation and its covered work |
| `policy_blocking_source` | exact active rule, conditional | Required only for `policy_disallowed`; names the rule and confirms no applicable user, AGENTS, or skill exception |

Light small low-risk localized work uses `subagent_policy_state=not_required`
and `subagent_execution_mode=not_applicable`; it does not ask for delegation and
instead records direct implementation, relevant automated validation/tests, and
a fresh self-review. For standard/strict development/code-work roles, Assistant
Framework policy treats a direct user request or applicable `AGENTS.md` or
active-skill instruction as a delegation trigger. Infer `subagent_trigger_scope`
with its provenance and covered roles/phases/actions, set
`subagent_policy_state=delegation_triggered`, set
`subagent_execution_mode=delegated`, and spawn the configured role agents
without a separate permission question. An explicit user opt-out sets
`subagent_policy_state=delegation_opted_out` and uses direct fallback. For Codex,
current CLI/app releases support native subagent workflows by default; custom
agents live in `~/.codex/agents/` or project `.codex/agents/` and are spawned by
explicitly asking Codex to spawn an agent by name. Do not mark
`subagents_unavailable` merely because the visible tool list lacks a tool named
`Task`, `delegate`, or `subagent`; only use `subagents_unavailable` after a real
spawn attempt fails or the adapter documentation/configuration proves no subagent
mechanism exists. If the user explicitly opts out or policy disallows spawning for
standard/strict work, use `direct_fallback` and preserve the same phase gates,
role separation, verification evidence, and review evidence.

`policy_disallowed` requires a non-empty `policy_blocking_source` that names the
exact active blocking rule and confirms no applicable direct-user, `AGENTS.md`,
or active-skill trigger exception. A conditional policy that says not to spawn
unless an applicable instruction asks does not make policy_disallowed when the
active skill requires subagents.

## Roles

| Role | Claude (agent name) | Codex (agent name) | Access | Phase |
|---|---|---|---|---|
| **Code Mapper** | `code-mapper` | `code-mapper` | Read-only | Discover |
| **Explorer** | `explorer` | `explorer` | Read-only | Discover |
| **Architect** | `architect` | `architect` | Read-only | Decompose, Plan, Design |
| **Code Writer** | `code-writer` | `code-writer` | Write | Build |
| **Builder/Tester** | `builder-tester` | `builder-tester` | Write | Build |
| **Code Reviewer** | `code-reviewer` | `code-reviewer` | Read-only | Review |
| **Reviewer** | `reviewer` | `reviewer` | Read-only | Review compatibility |
| **QA Evaluator** | `qa-evaluator` | `qa-evaluator` | Read-only | Review QA |

## What each role does

- **Code Mapper** — Lightweight structural map: file paths, entry points, interfaces, conventions. Use only when the current boundary cannot be resolved directly; output stays compact enough to paste into the current packet.
- **Explorer** — Deep analysis: traces execution paths, analyzes design decisions, finds hidden dependencies and coupling. Use only for an unresolved lifecycle, failure, coupling, or behavior question after a compact map.
- **Architect** — Conditional Architecture Decision Pack/implementation blueprint work for genuine boundary, public-contract, quality-driver, or viable-alternative uncertainty. Does not write code and is not a permanent role.
- **Code Writer / bounded executor** — Implements the packet. In `bounded_executor`, also writes focused tests and runs focused verification; never performs independent review.
- **Builder/Tester** — Conditional separated verifier for broad/noisy/environment-heavy or high-risk work. Builds, writes tests, runs suites, and absorbs noisy output without modifying production code.
- **Code Reviewer** — Canonical independent code review with confidence-based filtering. Finds bugs, security issues, architecture violations, test coverage gaps, and structural code issues. Does not edit files.
- **Reviewer** — Compatibility route for existing handoffs that still say `Reviewer`; use only when `code-reviewer` is unavailable or a legacy prompt/handoff requires the old name.
- **QA Evaluator** — Independent QA acceptance evaluation after build/test and code-review evidence. Checks acceptance criteria, Done Contract, verification evidence, scoped UI/visual/product/UX/docs/DX/domain quality, score progression, and final result. Does not replace Code Reviewer.

## Phase-to-subagent requirements

Standard/strict phases have declared role responsibilities. Phases without a
subagent role are handled directly by the Orchestrator with explicit
justification. Phases with a subagent role dispatch only when
`subagent_execution_mode=delegated`; otherwise standard/strict direct fallback
records equivalent evidence. The light lane is direct/not_applicable and uses
its compact validation plus fresh-review evidence instead.

| Phase | Subagent(s) | Condition | Justification |
|---|---|---|---|
| **TRIAGE** | — (Orchestrator direct) | All sizes | Too lightweight for dispatch — single classification decision |
| **DISCOVER** | Code Mapper | Current file/boundary cannot be resolved directly | Produces a compact context map only when it reduces uncertainty |
| **DISCOVER** | Explorer | Unresolved lifecycle/failure/coupling/behavior question after mapping | Traces only the needed execution path |
| **DECOMPOSE** | Architect | Pack or slice boundary has genuine uncertainty | Analyzes the current boundary and proposes the smallest usable slice manifest |
| **PLAN** | Architect | `architecture_design_mode` is `required`/`review_intensive` or an ordinary plan cannot resolve a concrete boundary | Produces a bounded blueprint from current evidence |
| **DESIGN** | Architect | UI tasks | Proposes design direction; Orchestrator creates mockup |
| **BUILD** | Code Writer / bounded executor | Standard/strict | Owns implementation; also focused RED/GREEN/verification in bounded lane |
| **BUILD** | Builder/Tester | `build_execution_lane=separated_workers` | Independent RED/build/test verification for triggered split work |
| **REVIEW** | Code Reviewer, or Reviewer compatibility | Standard/strict | Independent code review via `assistant-review` skill |
| **REVIEW** | QA Evaluator | `qa_evaluation_mode=required` only | Independent acceptance QA via `assistant-review` QA loop |
| **DOCUMENT** | — (Orchestrator direct) | All sizes | Documentation generation is orchestrator's synthesis work |

**Rule:** If `subagent_execution_mode=delegated` and a phase's subagent column shows a dispatch, you MUST dispatch that role. If `subagent_execution_mode=direct_fallback`, you MUST NOT spawn subagents; instead record which role responsibility was handled directly and what equivalent evidence proves it.

## Illustrative sizing patterns (not dispatch limits)

| Size | Agents used | Flow |
|---|---|---|
| **Small light** | None | Direct implementation, relevant automated validation/tests, and fresh self-review; promote out of light when risk/harness/QA criteria apply |
| **Small standard/strict** | Bounded executor → Code Reviewer, or separated workers when triggered | Sequential, minimal (no Decompose); QA only when required |
| **Medium** | Bounded executor → Code Reviewer, plus mapping/design roles only when their concrete trigger applies | Ordinary default; add Builder/Tester only when separated_workers triggers |
| **Large** | Current-boundary mapping/analysis/design roles as needed → Code Writer/Builder-Tester when selected → Code Reviewer → QA Evaluator when required | Full evidence path is selected by risk and uncertainty, not by role count |
| **Mega** | Parallel writers/role specialists only for independently executable slices and concrete triggers | Integration still requires current verification/review evidence; do not add roles as ceremony |

## Dispatch guidelines

- **Light lane**: small low-risk localized work may keep `required_agents`
  empty and use direct implementation, relevant automated validation/tests, and
  fresh self-review evidence. `subagent_execution_mode=not_applicable` is valid
  for this lane. Security, high-risk, harness-capable, required-QA, or otherwise
  promoted work cannot use this exception.
- **Standard ordinary-medium minimum**: bounded executor → Code Reviewer.
  **Separated-workers minimum**: Code Writer → Builder/Tester → Code Reviewer.
  `reviewer` remains valid compatibility routing for existing
  handoffs, but new dispatches should use `code-reviewer` for code defects,
  security, architecture, test coverage, and structural code issues. In
  delegated mode these are subagents; in direct fallback they are explicitly
  recorded role-equivalent steps. Size alone does not select separated workers;
  `not_applicable` is invalid for standard/strict Build tasks.
- **Evidence gate for standard/strict work**: delegated mode is not complete until the
  task journal records selected-lane dispatch/result/verification evidence and
  Code Reviewer dispatch/result evidence. Builder/Tester evidence is required
  only for `separated_workers`,
  or Reviewer dispatch/result evidence when compatibility routing is used.
  Medium+ delegated slice work also records per-slice dispatch evidence before
  each slice is marked verified. Delegated evidence must correspond to a real
  native dispatch/thread and result. Reference the agent id, task name, thread,
  or tool result when the runtime exposes one; task-journal claims without a
  matching native result do not satisfy delegated evidence. Direct fallback is
  allowed only for explicit `delegation_opted_out`,
  `subagents_unavailable`, or `policy_disallowed` reasons, and must record
  equivalent role, phase, verification, and review evidence; silent fallback
  fails the completion gates.
- **QA evidence gate**: when QA is required, delegated mode is not complete until the task journal Agent Dispatch Log records QA Evaluator dispatch/result evidence after Builder/Tester and Code Reviewer evidence. Direct fallback must record fresh QA Evaluator direct evidence separately from Code Reviewer direct evidence. QA required positive triggers: explicit QA/acceptance evaluation request, accepted Done Contract, harness-capable acceptance scope, domain-scored scope, or scoped UI/visual/product/UX/docs/DX acceptance. QA non-triggers: template labels/placeholders, generic acceptance criteria labels, optional/not_required reasons, delegation/source-changing work alone, and ordinary medium+ code-review-only/source-changing work.
- **Architect is conditional**: use it only when a Pack/slice boundary has genuine uncertainty; in direct work the same compact decision criteria and evidence are recorded without inventing an Architect dispatch.
- **Launch in parallel** when agents are independent (e.g., Code Mapper + Explorer on different modules)
- **Code Mapper runs only when needed** to resolve current files/boundaries; its compact output feeds the current plan/implementation packet without becoming durable global memory.
- **Code Reviewer gets a fresh dispatch each round** during the quality review loop when delegated mode is triggered; `reviewer` is the compatibility route for older handoffs. Direct fallback must reset review context and record how stale-context risk was controlled.
- **QA Evaluator gets a fresh dispatch each QA round** when QA is required and delegated mode is triggered. Direct fallback must reset acceptance-evaluation context and record how stale-context risk was controlled.
- **Main session stays Orchestrator**: owns user communication, final integration, handoffs
- **Do not dispatch agents for small inline tasks** within a larger workflow (e.g., a one-line fix during review doesn't need a Code Writer agent)
