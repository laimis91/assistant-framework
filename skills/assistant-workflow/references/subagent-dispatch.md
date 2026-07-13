# Subagent Dispatch — Roles and Rules

Use specialized agents when the active tool policy and user authorization allow delegation. Each role has constrained access: code-reviewer, qa-evaluator, and reviewer cannot edit files. Code Writer may act as a bounded edit/test executor when that lane is selected. When subagents are unavailable, denied, or policy-disallowed, keep the same selected-lane responsibilities as direct fallback evidence instead of pretending delegation happened.

For full role prompts, read `references/subagent-roles.md`.

## Delegation Policy State

Before spawning any subagent, resolve:

| Field | Values | Meaning |
|---|---|---|
| `subagent_policy_state` | `not_required`, `authorization_required`, `delegation_authorized`, `authorization_denied`, `subagents_unavailable`, `policy_disallowed` | Whether spawning subagents is allowed for this task and adapter |
| `subagent_execution_mode` | `delegated`, `direct_fallback`, `not_applicable` | Whether work is executed by subagents, by direct fallback with equivalent evidence, or without any subagent role |
| `subagent_authorization_scope` | list of roles/phases/actions | What the user explicitly authorized, when authorization was required |

Light small low-risk localized work uses `subagent_policy_state=not_required`
and `subagent_execution_mode=not_applicable`; it does not ask for delegation and
instead records direct implementation, relevant automated validation/tests, and
a fresh self-review. For standard/strict development/code-work roles, Assistant
Framework policy requires explicit user authorization before spawning subagents.
Ask once for the required scope before the first spawn unless the current
user prompt already explicitly authorizes subagents for this task. If authorization
is granted, set `subagent_policy_state=delegation_authorized`, set
`subagent_execution_mode=delegated`, and spawn the configured role agents. If
authorization has not been granted or denied yet, keep
`subagent_policy_state=authorization_required`, ask the authorization question,
and wait; do not continue through phases that require subagents. For Codex,
current CLI/app releases support native subagent workflows by default; custom
agents live in `~/.codex/agents/` or project `.codex/agents/` and are spawned by
explicitly asking Codex to spawn an agent by name. Do not mark
`subagents_unavailable` merely because the visible tool list lacks a tool named
`Task`, `delegate`, or `subagent`; only use `subagents_unavailable` after a real
spawn attempt fails or the adapter documentation/configuration proves no subagent
mechanism exists. If the user declines or policy disallows spawning for
standard/strict work, use `direct_fallback` and preserve the same phase gates,
role separation, verification evidence, and review evidence.

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

- **Code Mapper** — Lightweight structural map: file paths, entry points, interfaces, conventions. Output is compact enough to paste into other agents' prompts. Runs first on medium+ tasks.
- **Explorer** — Deep analysis: traces execution paths, analyzes design decisions, finds hidden dependencies and coupling. Understands WHY, not just WHERE.
- **Architect** — Designs implementation blueprints: files to create/modify, interfaces, data flows, build sequence, test plan. Does not write code.
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
| **DISCOVER** | Code Mapper | Medium+ | Produces context map for downstream agents |
| **DISCOVER** | Explorer | Large+ | Traces execution paths and hidden dependencies |
| **DECOMPOSE** | Architect | Medium+ | Analyzes problem boundaries and proposes strict slice manifest |
| **PLAN** | Architect | Large+ | Designs full implementation blueprint from slice manifest |
| **DESIGN** | Architect | UI tasks | Proposes design direction; Orchestrator creates mockup |
| **BUILD** | Code Writer / bounded executor | Standard/strict | Owns implementation; also focused RED/GREEN/verification in bounded lane |
| **BUILD** | Builder/Tester | `build_execution_lane=separated_workers` | Independent RED/build/test verification for triggered split work |
| **REVIEW** | Code Reviewer, or Reviewer compatibility | Standard/strict | Independent code review via `assistant-review` skill |
| **REVIEW** | QA Evaluator | `qa_evaluation_mode=required` only | Independent acceptance QA via `assistant-review` QA loop |
| **DOCUMENT** | — (Orchestrator direct) | All sizes | Documentation generation is orchestrator's synthesis work |

**Rule:** If `subagent_execution_mode=delegated` and a phase's subagent column shows a dispatch, you MUST dispatch that role. If `subagent_execution_mode=direct_fallback`, you MUST NOT spawn subagents; instead record which role responsibility was handled directly and what equivalent evidence proves it.

## Dispatch rules by task size

| Size | Agents used | Flow |
|---|---|---|
| **Small light** | None | Direct implementation, relevant automated validation/tests, and fresh self-review; promote out of light when risk/harness/QA criteria apply |
| **Small standard/strict** | Bounded executor → Code Reviewer, or separated workers when triggered | Sequential, minimal (no Decompose); QA only when required |
| **Medium** | Code Mapper → Architect (decompose) → bounded executor → Code Reviewer → QA Evaluator when required | Ordinary default; add Builder/Tester only when separated_workers triggers |
| **Large** | Code Mapper → Explorer → Architect (decompose + plan) → Code Writer → Builder/Tester → Code Reviewer → QA Evaluator when required | Full pipeline with slice verification; Reviewer may be used only as compatibility |
| **Mega** | All roles, parallel Code Writers per slice | Mapper → Explorer → Architect → parallel Writers → Builder/Tester, Code Reviewer, and QA Evaluator when required at integration |

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
  allowed only for explicit `authorization_denied`,
  `subagents_unavailable`, or `policy_disallowed` reasons, and must record
  equivalent role, phase, verification, and review evidence; silent fallback
  fails the completion gates.
- **QA evidence gate**: when QA is required, delegated mode is not complete until the task journal Agent Dispatch Log records QA Evaluator dispatch/result evidence after Builder/Tester and Code Reviewer evidence. Direct fallback must record fresh QA Evaluator direct evidence separately from Code Reviewer direct evidence. QA required positive triggers: explicit QA/acceptance evaluation request, accepted Done Contract, harness-capable acceptance scope, domain-scored scope, or scoped UI/visual/product/UX/docs/DX acceptance. QA non-triggers: template labels/placeholders, generic acceptance criteria labels, optional/not_required reasons, delegation/source-changing work alone, and ordinary medium+ code-review-only/source-changing work.
- **Every medium+ task gets Architect decomposition responsibility**: In delegated mode the Architect proposes smallest iterable slice boundaries; in direct fallback the same criteria and evidence are recorded directly.
- **Launch in parallel** when agents are independent (e.g., Code Mapper + Explorer on different modules)
- **Code Mapper runs first** on medium+ tasks — its output feeds into Architect and Code Writer
- **Code Reviewer gets a fresh dispatch each round** during the quality review loop when delegated mode is authorized; `reviewer` is the compatibility route for older handoffs. Direct fallback must reset review context and record how stale-context risk was controlled.
- **QA Evaluator gets a fresh dispatch each QA round** when QA is required and delegated mode is authorized. Direct fallback must reset acceptance-evaluation context and record how stale-context risk was controlled.
- **Main session stays Orchestrator**: owns user communication, final integration, handoffs
- **Do not dispatch agents for small inline tasks** within a larger workflow (e.g., a one-line fix during review doesn't need a Code Writer agent)
