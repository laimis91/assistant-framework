# Subagent Dispatch — Roles and Rules

Dispatch specialized agents instead of doing everything sequentially. Each has constrained access — a reviewer cannot edit files, a code writer doesn't run tests.

For full role prompts, read `references/subagent-roles.md`.

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

Every phase has a declared agent responsibility. Phases without subagent dispatch are handled directly by the Orchestrator with explicit justification.

| Phase | Subagent(s) | Condition | Justification |
|---|---|---|---|
| **TRIAGE** | — (Orchestrator direct) | All sizes | Too lightweight for dispatch — single classification decision |
| **DISCOVER** | Code Mapper | Medium+ | Produces context map for downstream agents |
| **DISCOVER** | Explorer | Large+ | Traces execution paths and hidden dependencies |
| **DECOMPOSE** | Architect | Medium+ | Analyzes problem boundaries and proposes component manifest |
| **PLAN** | Architect | Large+ | Designs full implementation blueprint from component manifest |
| **DESIGN** | Architect | UI tasks | Proposes design direction; Orchestrator creates mockup |
| **BUILD** | Code Writer | All sizes | Implements code following the plan |
| **BUILD** | Builder/Tester | All sizes | Builds, runs tests, returns concise results |
| **REVIEW** | Reviewer | All sizes | Independent review via `assistant-review` skill |
| **DOCUMENT** | — (Orchestrator direct) | All sizes | Documentation generation is orchestrator's synthesis work |

**Rule:** If a phase's subagent column shows a dispatch, you MUST dispatch it. The Orchestrator should not absorb subagent work — separation of concerns keeps each agent focused.

## Dispatch rules by task size

| Size | Agents used | Flow |
|---|---|---|
| **Small** | Code Writer → Builder/Tester → Reviewer | Sequential, minimal (no Decompose) |
| **Medium** | Code Mapper → Architect (decompose) → Code Writer → Builder/Tester → Reviewer | Mapper feeds Architect, components feed Writer |
| **Large** | Code Mapper → Explorer → Architect (decompose + plan) → Code Writer → Builder/Tester → Reviewer | Full pipeline with component verification |
| **Mega** | All roles, parallel Code Writers per sub-task | Mapper → Explorer → Architect → parallel Writers → Builder/Tester and Reviewer at integration |

## Dispatch guidelines

- **Every task gets at minimum**: Code Writer → Builder/Tester → Reviewer. No code ships without build + test + review.
- **Every medium+ task gets Architect for decomposition**: The Architect proposes component boundaries — the Orchestrator doesn't decompose alone.
- **Launch in parallel** when agents are independent (e.g., Code Mapper + Explorer on different modules)
- **Code Mapper runs first** on medium+ tasks — its output feeds into Architect and Code Writer
- **Reviewer gets a fresh dispatch each round** during the quality review loop — stale context weakens reviews
- **Main session stays Orchestrator**: owns user communication, final integration, handoffs
- **Do not dispatch agents for small inline tasks** within a larger workflow (e.g., a one-line fix during review doesn't need a Code Writer agent)
