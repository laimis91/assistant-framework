# Subagent Dispatch — Roles and Rules

Use specialized agents when the active tool policy and user authorization allow delegation. Each role has constrained access — a reviewer cannot edit files, a code writer doesn't run tests. When subagents are unavailable, denied, or policy-disallowed, keep the same role responsibilities as direct fallback evidence instead of pretending delegation happened.

For full role prompts, read `references/subagent-roles.md`.

## Delegation Policy State

Before spawning any subagent, resolve:

| Field | Values | Meaning |
|---|---|---|
| `subagent_policy_state` | `not_required`, `authorization_required`, `delegation_authorized`, `authorization_denied`, `subagents_unavailable`, `policy_disallowed` | Whether spawning subagents is allowed for this task and adapter |
| `subagent_execution_mode` | `delegated`, `direct_fallback`, `not_applicable` | Whether work is executed by subagents, by direct fallback with equivalent evidence, or without any subagent role |
| `subagent_authorization_scope` | list of roles/phases/actions | What the user explicitly authorized, when authorization was required |

If the active tool policy requires explicit user authorization before spawning subagents, ask once for the required scope before the first spawn. If the user declines, no subagent tool exists, or policy disallows spawning, use `direct_fallback` and preserve the same phase gates, role separation, verification evidence, and review evidence.

## Roles

| Role | Claude (agent name) | Codex (agent name) | Access | Phase |
|---|---|---|---|---|
| **Code Mapper** | `code-mapper` | `code-mapper` | Read-only | Discover |
| **Explorer** | `explorer` | `explorer` | Read-only | Discover |
| **Architect** | `architect` | `architect` | Read-only | Decompose, Plan, Design |
| **Code Writer** | `code-writer` | `code-writer` | Write | Build |
| **Builder/Tester** | `builder-tester` | `builder-tester` | Write | Build |
| **Reviewer** | `reviewer` | `reviewer` | Read-only | Review |

## What each role does

- **Code Mapper** — Lightweight structural map: file paths, entry points, interfaces, conventions. Output is compact enough to paste into other agents' prompts. Runs first on medium+ tasks.
- **Explorer** — Deep analysis: traces execution paths, analyzes design decisions, finds hidden dependencies and coupling. Understands WHY, not just WHERE.
- **Architect** — Designs implementation blueprints: files to create/modify, interfaces, data flows, build sequence, test plan. Does not write code.
- **Code Writer** — Implements code following the plan. Does not run builds or tests. Does not review. Focuses purely on clean, convention-matching implementation.
- **Builder/Tester** — Builds the project, writes tests, runs tests, absorbs noisy output. Returns concise results ("build passed, 2 tests failed: X, Y") not full logs.
- **Reviewer** — Independent code review with confidence-based filtering. Finds bugs, security issues, architecture violations. Does not edit files.

## Phase-to-subagent requirements

Every phase has a declared role responsibility. Phases without a subagent role are handled directly by the Orchestrator with explicit justification. Phases with a subagent role dispatch only when `subagent_execution_mode=delegated`; otherwise the Orchestrator records direct fallback evidence for the same role responsibility.

| Phase | Subagent(s) | Condition | Justification |
|---|---|---|---|
| **TRIAGE** | — (Orchestrator direct) | All sizes | Too lightweight for dispatch — single classification decision |
| **DISCOVER** | Code Mapper | Medium+ | Produces context map for downstream agents |
| **DISCOVER** | Explorer | Large+ | Traces execution paths and hidden dependencies |
| **DECOMPOSE** | Architect | Medium+ | Analyzes problem boundaries and proposes strict slice manifest |
| **PLAN** | Architect | Large+ | Designs full implementation blueprint from slice manifest |
| **DESIGN** | Architect | UI tasks | Proposes design direction; Orchestrator creates mockup |
| **BUILD** | Code Writer | All sizes | Implements code following the plan |
| **BUILD** | Builder/Tester | All sizes | Builds, runs tests, returns concise results |
| **REVIEW** | Reviewer | All sizes | Independent review via `assistant-review` skill |
| **DOCUMENT** | — (Orchestrator direct) | All sizes | Documentation generation is orchestrator's synthesis work |

**Rule:** If `subagent_execution_mode=delegated` and a phase's subagent column shows a dispatch, you MUST dispatch that role. If `subagent_execution_mode=direct_fallback`, you MUST NOT spawn subagents; instead record which role responsibility was handled directly and what equivalent evidence proves it.

## Dispatch rules by task size

| Size | Agents used | Flow |
|---|---|---|
| **Small** | Code Writer → Builder/Tester → Reviewer | Sequential, minimal (no Decompose) |
| **Medium** | Code Mapper → Architect (decompose) → Code Writer → Builder/Tester → Reviewer | Mapper feeds Architect, slices feed Writer |
| **Large** | Code Mapper → Explorer → Architect (decompose + plan) → Code Writer → Builder/Tester → Reviewer | Full pipeline with slice verification |
| **Mega** | All roles, parallel Code Writers per slice | Mapper → Explorer → Architect → parallel Writers → Builder/Tester and Reviewer at integration |

## Dispatch guidelines

- **Every task gets at minimum**: Code Writer → Builder/Tester → Reviewer responsibilities. In delegated mode these are subagents; in direct fallback they are explicitly recorded role-equivalent steps. No code ships without build + test + review evidence.
- **Every medium+ task gets Architect decomposition responsibility**: In delegated mode the Architect proposes smallest iterable slice boundaries; in direct fallback the same criteria and evidence are recorded directly.
- **Launch in parallel** when agents are independent (e.g., Code Mapper + Explorer on different modules)
- **Code Mapper runs first** on medium+ tasks — its output feeds into Architect and Code Writer
- **Reviewer gets a fresh dispatch each round** during the quality review loop when delegated mode is authorized; direct fallback must reset review context and record how stale-context risk was controlled
- **Main session stays Orchestrator**: owns user communication, final integration, handoffs
- **Do not dispatch agents for small inline tasks** within a larger workflow (e.g., a one-line fix during review doesn't need a Code Writer agent)
