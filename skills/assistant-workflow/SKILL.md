---
name: assistant-workflow
description: "Structured development workflow for any task: triage, discover, plan, build, test, verify, document. Use for any development task: build, implement, fix, refactor, plan, create, add feature. Also triggers on: 'idea', 'how should I approach', 'break this down', 'start working on'."
effort: high
requires:
  - assistant-memory
triggers:
  - pattern: "implement feature|implement the|implementing|fix bug|fix the|build feature|build the|build a|build an|refactor the|create feature|add feature|how should i approach|break this down|start working on|let.s (build|create|implement|add|make)|phase [0-9]"
    priority: 40
    min_words: 4
    reminder: "This request matches assistant-workflow. You MUST invoke the Skill tool with skill='assistant-workflow' BEFORE writing any code. At minimum: triage the task size, then build with tests. Skipping workflow for speed is explicitly prohibited — see CLAUDE.md."
---

# Development Workflow

Core principles: **never guess**, **right-sized ceremony**, **every idea becomes testable criteria**.

## Contracts

This skill enforces strict input/output contracts and phase gate assertions. Read the contract files in `contracts/` before executing the workflow. All contracts are **mandatory** — not advisory.

| Contract | File | Purpose |
|---|---|---|
| **Input** | `contracts/input.yaml` | Required fields to resolve before Triage |
| **Output** | `contracts/output.yaml` | Artifacts that must exist before `--- WORKFLOW COMPLETE ---` |
| **Phase Gates** | `contracts/phase-gates.yaml` | Assertions checked at every phase transition |
| **Handoffs** | `contracts/handoffs.yaml` | Data shapes between subagent dispatch and return |

**Rules:**
- Resolve all input contract fields before printing `--- PHASE: TRIAGE ---`
- Check phase gate assertions before printing any `--- PHASE: {name} COMPLETE ---`
- Include all required handoff context fields when dispatching subagents
- Validate all required handoff return fields when subagents complete
- Verify all output contract artifacts before printing `--- WORKFLOW COMPLETE ---`
- If any contract check fails: resolve it before proceeding, never skip silently

## Visible Checkpoints

You MUST print checkpoint messages at every phase transition and key step so the user can see workflow progress. Use this exact format:

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

These are mandatory. If the user never sees these messages, the workflow is not being followed.

## Idea-to-Action Pipeline

Before any workflow, classify the input:

```
Input arrives
    |
Is this an idea/question (not a concrete task)?
    YES --> Decompose into testable criteria (see below), then Triage
    NO  --> Triage directly
```

### Decomposing ideas into criteria

When the user has an idea, question, or vague goal — not a concrete task — decompose it before triaging:

1. **Reverse engineer**: What do they explicitly want? What do they NOT want? What's implied?
2. **Extract criteria**: Write 4-12 atomic, binary, testable statements (8-12 words each)
3. **Apply splitting test**: If a criterion joins two verifiable things (AND/WITH) -> split. If parts can fail independently -> split. If it says "all/every/complete" -> enumerate.
4. **Present for confirmation**: Show criteria, get approval, then triage as a task.

**Example:**
```
Idea: "I want to add caching to our API"

Criteria:
- [ ] GET endpoints return cached responses for repeated calls
- [ ] Cache TTL is configurable per endpoint
- [ ] Cache invalidates on POST/PUT/DELETE to same resource
- [ ] Cache-Control headers are set on cached responses
- [ ] Cache miss falls through to normal handler transparently
- [ ] Cache can be disabled per-request via header
- [ ] Cache storage is abstracted behind an interface

Approve these criteria? Then I'll triage and plan.
```

## Triage

Print: `--- PHASE: TRIAGE ---`

Assess task size. This determines which phases run.

| Size | Phases |
|---|---|
| **Small** (bugfix, typo, config, one-file) | Discover (quick) -> Plan (lightweight) -> Build & Test -> Review -> Document |
| **Medium** (feature, refactor, endpoint) | Discover -> Decompose -> Plan -> [Design] -> Build & Test -> Review -> Document |
| **Large** (new project, multi-module) | Discover -> Decompose -> Plan -> Design -> Build & Test -> Review -> Document |
| **Mega** (rewrite, 10+ files across layers) | Discover -> Decompose -> sub-tasks -> Integrate -> Review -> Document |

[Design] = include if task has UI work, skip for backend-only.

Print: `>> Triaged as: [SIZE] — phases: [list]`

If scope exceeds initial triage during any phase, stop and re-triage.

## Subagent Dispatch

Dispatch specialized agents instead of doing everything sequentially. Each has constrained access — a reviewer cannot edit files, a code writer doesn't run tests.

For full role prompts, read `references/subagent-roles.md`.

### Roles

| Role | Claude (agent name) | Codex (agent name) | Access | Phase |
|---|---|---|---|---|
| **Code Mapper** | `code-mapper` | `code-mapper` | Read-only | Discover |
| **Explorer** | `explorer` | `explorer` | Read-only | Discover |
| **Architect** | `architect` | `architect` | Read-only | Decompose, Plan, Design |
| **Code Writer** | `code-writer` | `code-writer` | Write | Build |
| **Builder/Tester** | `builder-tester` | `builder-tester` | Write | Build |
| **Reviewer** | `reviewer` | `reviewer` | Read-only | Review |

### What each role does

- **Code Mapper** — Lightweight structural map: file paths, entry points, interfaces, conventions. Output is compact enough to paste into other agents' prompts. Runs first on medium+ tasks.
- **Explorer** — Deep analysis: traces execution paths, analyzes design decisions, finds hidden dependencies and coupling. Understands WHY, not just WHERE.
- **Architect** — Designs implementation blueprints: files to create/modify, interfaces, data flows, build sequence, test plan. Does not write code.
- **Code Writer** — Implements code following the plan. Does not run builds or tests. Does not review. Focuses purely on clean, convention-matching implementation.
- **Builder/Tester** — Builds the project, writes tests, runs tests, absorbs noisy output. Returns concise results ("build passed, 2 tests failed: X, Y") not full logs.
- **Reviewer** — Independent code review with confidence-based filtering. Finds bugs, security issues, architecture violations. Does not edit files.

### Phase-to-subagent requirements

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

### Dispatch rules by task size

| Size | Agents used | Flow |
|---|---|---|
| **Small** | Code Writer → Builder/Tester → Reviewer | Sequential, minimal (no Decompose) |
| **Medium** | Code Mapper → Architect (decompose) → Code Writer → Builder/Tester → Reviewer | Mapper feeds Architect, components feed Writer |
| **Large** | Code Mapper → Explorer → Architect (decompose + plan) → Code Writer → Builder/Tester → Reviewer | Full pipeline with component verification |
| **Mega** | All roles, parallel Code Writers per sub-task | Mapper → Explorer → Architect → parallel Writers → Builder/Tester and Reviewer at integration |

### Dispatch guidelines

- **Every task gets at minimum**: Code Writer → Builder/Tester → Reviewer. No code ships without build + test + review.
- **Every medium+ task gets Architect for decomposition**: The Architect proposes component boundaries — the Orchestrator doesn't decompose alone.
- **Launch in parallel** when agents are independent (e.g., Code Mapper + Explorer on different modules)
- **Code Mapper runs first** on medium+ tasks — its output feeds into Architect and Code Writer
- **Reviewer gets a fresh dispatch each round** during the quality review loop — stale context weakens reviews
- **Main session stays Orchestrator**: owns user communication, final integration, handoffs
- **Do not dispatch agents for small inline tasks** within a larger workflow (e.g., a one-line fix during review doesn't need a Code Writer agent)

## Phase 1: Discover

Print: `--- PHASE: DISCOVER ---`

**Goal:** Zero untracked unknowns. No planning or coding until ambiguity is resolved.

For medium+ tasks, dispatch a **Code Mapper** to produce a context map (see `references/context-map-template.md`). The context map is stored at `.claude/context-map.md` and used by Code Writer and Architect instead of re-exploring the codebase. For large/mega tasks, also dispatch an **Explorer** to trace execution paths and understand behavior.

Print: `>> Dispatching Code Mapper → context map` (when applicable)
Print: `>> Dispatching Explorer` (when applicable)

1. Read repo: README, CLAUDE.md, AGENTS.md, key files
2. Compare current state against request
3. **Recall lessons**: If `assistant-reflexion` is available, check past lessons for this project type and task type. Incorporate high-confidence lessons into constraints.
   Print: `>> Found [N] relevant lessons from past tasks` (or skip silently if none)
4. **Agent readiness check** (medium+ tasks): Quick scan of the project environment. Score 0-5:
   - Linter config present? (eslint, .editorconfig, analyzers, etc.)
   - Build scripted/documented? (CI, Makefile, documented `dotnet build` command, etc.)
   - Test suite exists? (any test project or test files)
   - `CLAUDE.md` or `AGENTS.md` exists? (agent can orient itself)
   - Observability in place? (logging, telemetry, health checks)
   Print: `>> Agent readiness: [N]/5` followed by any gaps found.
   If score ≤ 2: recommend fixing environment gaps before feature work. The agent isn't broken — the environment is.
5. Ask structured Q&A with recommendations when ambiguous
6. Restate requirements in 1-3 sentences

**Q&A format:**
```
Need to know
1. [Question]?
   a) [Option]  b) [Option]  c) [Option]
   --> Recommendation: (b) because [reason]

Reply with: "1b 2a" or "defaults".
```

**Rules:**
- No commands, edits, or plans that depend on unknowns
- Read-only discovery (search, git log, browsing) is allowed
- Small tasks: 0-1 questions. Mega: full Q&A.

Print: `--- PHASE: DISCOVER COMPLETE ---`

## Phase 2: Decompose

Print: `--- PHASE: DECOMPOSE ---`

**Goal:** Break the problem into small, independently verifiable components. Each component is a unit of work that can be built, tested, and verified in isolation before moving to the next.

Think of components like LEGO bricks — each one is self-contained and testable, and together they form the solution.

**Skip condition:** Small tasks skip this phase entirely — they ARE the atomic unit.

For medium+ tasks, dispatch an **Architect** to analyze the problem and propose component boundaries based on the context map and requirements.

Print: `>> Dispatching Architect → component decomposition`

### Decomposition rules

1. **2-7 components** for medium tasks, **3-7 for large**, mega uses sub-task decomposition (see Mega section)
2. **Each component must be independently verifiable** — if you can't write a binary pass/fail check for it, it's not a component
3. **Order by dependency** — independent components first, dependent ones after their prerequisites
4. **No circular dependencies** — if A needs B and B needs A, merge them into one component
5. **Shared contracts first** — if multiple components share interfaces/DTOs, extract those as component #1

### Component manifest format

```
## Components

### Component 1: [name]
- **What:** [1-2 sentence description]
- **Files:** [files to create or modify]
- **Depends on:** [other component names, or "none"]
- **Verification criteria:**
  - [ ] [Binary pass/fail statement]
  - [ ] [Binary pass/fail statement]

### Component 2: [name]
...
```

### Verification criteria rules

Each criterion must be:
- **Binary** — pass or fail, no "partially done"
- **Observable** — can be checked by running a test, a build, or inspecting output
- **Specific** — "endpoint returns 200 for valid input" not "endpoint works"

Good: `[ ] GET /api/items returns 200 with JSON array`
Bad: `[ ] API works correctly`

### Approval gate

Print: `>> WAITING: Component decomposition approval required`

Present the component manifest and WAIT:
```
Review the decomposition:
- "approved" -- I'll plan each component
- "merge [X] and [Y]" -- I'll combine and re-present
- "split [X]" -- I'll break it down further
- Questions -- I'll address before proceeding
```

Print: `--- PHASE: DECOMPOSE COMPLETE (approved) ---`

## Phase 3: Plan

Print: `--- PHASE: PLAN ---`

**Goal:** Concrete, reviewable implementation plan.

For large tasks, dispatch an **Architect** — it analyzes existing patterns (using Code Mapper/Explorer output) and returns a structured implementation blueprint.

Print: `>> Dispatching Architect` (when applicable)

Read `references/plan-template.md` and use the correct tier:
- Small: inline plan (goal, files, risks, tests)
- Medium: standard plan (drop Security/Operability unless the task touches auth, PII, payments, or infra)
- Large/Mega: full plan (all sections including Security and Operability)

1. Research codebase: modules, patterns, entrypoints
2. Evaluate architecture (see `playbooks/*.md` for project-type rules)
3. Analyze 1-3 options with tradeoffs, pick one
4. Identify risks and edge cases
5. Write ordered implementation steps with file paths
6. For large/mega: fill in Security and Operability sections. For medium: only if the task touches auth, PII, payments, or infra (promote to Full tier per plan-template.md)
7. Load prompt packs only when applicable:
   - Refactors: `references/prompts/refactor-safety.md`
   - New code: `references/prompts/test-strategy.md`
   - DB changes: `references/prompts/migration.md`
   - TDD mode: use `assistant-tdd` skill (or `references/prompts/tdd-enforcement.md` if skill not installed)
   - **SOLID (plan phase):** Review `references/prompts/solid-principles.md` graduated enforcement table to fill SOLID design notes in the plan template's Architecture section (medium+ tasks).

### Approval gate

Print: `>> WAITING: Plan approval required`

Present the plan and WAIT:
```
Review the plan:
- "approved" -- I'll start implementation
- "approved with changes: [list]" -- I'll update first
- Questions -- I'll address before proceeding
```

Print: `--- PHASE: PLAN COMPLETE (approved) ---`

## Phase 4: Design (UI/UX only, skip for backend)

Print: `--- PHASE: DESIGN ---`

1. Define design direction (tone, palette, typography)
2. Propose design system (CSS variables, components)
3. Create visual mockup (HTML artifact)
4. Production checklist: states, responsive, accessibility

Print: `>> WAITING: Design approval required`

Show mockup and WAIT for approval.

Print: `--- PHASE: DESIGN COMPLETE (approved) ---`

## Phase 5: Build & Test

Print: `--- PHASE: BUILD ---`

### Task journal

For medium+ tasks, create `.claude/task.md` using `references/task-journal-template.md`. Update after each step. This file survives context compression — it's the single source of truth for the current task. For cross-session handoffs when no task journal exists, use `references/context-handoff-templates.md`.

Capture **constraints** from Discovery/Plan (e.g. "don't touch ProjectA", "stay on .NET 8"). Check constraints before each step.

### Orchestrator delegation rule

**The orchestrator NEVER edits files or writes code directly.** All file changes go through sub-agents:
- **Code Writer** (`code-writer`): implements code following the plan
- **Builder/Tester** (`builder-tester`): builds, writes tests, runs tests

Think of it like a general who directs the battle but never picks up a rifle. The orchestrator dispatches, monitors, and course-corrects — but the agents do the actual work.

For each step: dispatch Code Writer with the plan step + context map → when done, dispatch Builder/Tester to verify → check results → proceed or fix.

### Build loop

**For medium+ tasks with components:** execute one component at a time. Each component may contain multiple plan steps, but the component is the unit of verification.

Print: `>> Component [C]/[total]: [name]`

For each plan step within the component:

Print: `>> Step [N]/[total]: [description]`
Print: `>> Dispatching Code Writer → [step description]`

1. Dispatch Code Writer for one plan step at a time
2. After each step: dispatch Builder/Tester for build + test, update task journal
3. If fails: dispatch Code Writer to fix before next step
4. Tests alongside code, not after
5. **SOLID check** after each step: load `references/prompts/solid-principles.md` and evaluate the graduated checklist (SRP for small, SRP+OCP+DIP for medium, full SOLID for large/mega). Fix violations before moving to the next step.
6. **TDD mode** (when active): follow Red-Green-Refactor per step. Write failing test → implement → refactor. Use `assistant-tdd` skill (or `references/prompts/tdd-enforcement.md` if skill not installed).

Print: `>> Step [N]/[total]: DONE` (after each step passes build + test)

### Per-component verification (medium+ tasks)

After all steps for a component are done, verify the component against its criteria from the DECOMPOSE phase:

1. Run build + all tests
2. Check each verification criterion from the component manifest — mark pass/fail
3. If any criterion fails: fix before moving to next component
4. Update task journal with component verification status

Print: `>> Component [C]/[total]: [name] — VERIFIED ([X]/[Y] criteria passed)`

Only proceed to the next component after the current one is fully verified.

After all components are verified:

7. Run integration tests across component boundaries

**Loop-back rule:** If implementation reveals a plan problem, STOP:
```
>> PLAN DEVIATION DETECTED
Plan assumed: [X]. Reality: [Y].
Options: a) Adjust step [N]  b) Rethink approach
```

Never silently deviate from the plan.

Print: `>> Build complete — all [N] steps implemented`
Print: `>> Running final build + tests`
Print: `>> Build: [passed/failed] | Tests: [N passed, M failed]`

Print: `--- PHASE: BUILD COMPLETE ---`

## Phase 6: Review

Print: `--- PHASE: REVIEW ---`

### Stage 1 — Spec Review

Print: `>> Stage 1: Spec Review`

Compare implementation against the approved plan:

1. Walk through each plan step — is it implemented? Compare the plan to `git diff`.
2. Check for **missing functionality**: any plan step not reflected in code
3. Check for **scope creep**: any code change not in the plan (flag for approval)
4. Verify edge cases from the plan's risk section are handled
5. Confirm acceptance criteria are met (if defined)
6. **Append** a `### Spec Review #N` entry to the task journal's Review Log:
   - Plan alignment: matches / minor drift / significant drift
   - Missing items (if any)
   - Scope creep (if any)
7. **Spec issues found:** fix them, re-test, re-run spec review
8. **Spec clear:** proceed to Stage 2

Print: `>> Spec Review: [CLEAN / found N issues, fixing]`

### Stage 2 — Quality Review

Print: `>> Stage 2: Quality Review — invoking assistant-review skill`

**Invoke the `assistant-review` skill.** This runs the autonomous review-fix loop (max 5 rounds) with visible progress. Do NOT implement the review loop inline — delegate to the skill so the loop instructions are loaded into context.

The `assistant-review` skill will:
- Dispatch Reviewer subagents
- Fix must-fix and should-fix items
- Re-review automatically
- Return a final clean/remaining summary

For small tasks: quick spec check + single review round is acceptable if clean.
For medium+ tasks: full two-stage review with autonomous quality loop via `assistant-review`.

### Status gate

The stop hook (`~/.claude/hooks/assistant/stop-review.sh`) enforces the review cycle structurally:
- If the task journal status is BUILDING or VERIFYING **and** the Review Log is missing entries or a Final Result, the agent is **blocked from stopping**.
- The agent must complete the full review cycle and write the Final Result before it can present results to the user.
- This is not advisory — the hook prevents the agent from finishing without review.

Print: `--- PHASE: REVIEW COMPLETE ---`

### Verification summary

After final review passes, write the Verification Summary in the task journal:
- What changed (files + why)
- What's tested (unit/integration/E2E coverage)
- Review result (clean / issues fixed / remaining should-fix items)
- Manual test instructions (step-by-step for the user)
- Known limitations

### Handoff

Print: `>> WAITING: User verification required`

Present the verification summary to the user:
```
All steps complete. Here's what to test:
[manual test instructions from journal]

After testing, let me know:
- "looks good" -- I'll finalize and document
- Issues: [describe] -- I'll fix and re-verify
- "add constraint: [X]" -- I'll note it and adjust
```

When the user reports issues:
1. Add to Review Notes in task journal
2. Fix each issue (re-enter Build → Test → Review for those steps only)
3. Update verification summary
4. Present again for approval

Do NOT proceed to Phase 7 until the user confirms.

## Phase 7: Document

Print: `--- PHASE: DOCUMENT ---`

### Small tasks — lightweight path

For small tasks, skip documentation updates and go straight to metrics:

1. **Task completion metrics**: Append a JSONL entry (see format below)
2. **Post-task reflection** (optional): Invoke `assistant-reflexion` if the task produced a non-obvious lesson

Then print completion markers and exit.

### Medium+ tasks — full path

1. Update README, CHANGELOG, architecture docs as needed
2. Code comments where "why" isn't obvious
3. Complete `references/release-readiness-checklist.md`
4. If user-facing changes: generate release notes using `references/prompts/release-notes.md`
5. Use `memory_add_insight` to capture learnings in the knowledge graph
6. **Task completion metrics**: Append a JSONL entry (see format below)
7. **Post-task reflection**: If `assistant-reflexion` is available, invoke it to capture what worked, what didn't, and extract lessons for future tasks. This is where the compounding happens.

### Metrics entry format (all sizes)

Append one JSONL line to `~/.claude/memory/metrics/workflow-metrics.jsonl`:
```json
{"date":"YYYY-MM-DD","project":"[name]","task":"[description]","size":"[small/medium/large/mega]","retriage":false,"review_rounds":N,"plan_deviations":N,"build_failures":N,"criteria_defined":N,"criteria_skipped":[],"agent_readiness_score":null,"components_count":null,"components_verified":null}
```
`agent_readiness_score` is null for small tasks (readiness check is skipped). This is how we measure whether workflow changes improve outcomes over time.

Print: `--- PHASE: DOCUMENT COMPLETE ---`
Print: `--- WORKFLOW COMPLETE ---`

## Mega Task Decomposition

Read `references/sub-task-brief-template.md` for brief format.

- 3-7 sub-tasks
- Sub-task #1: shared contracts (interfaces, DTOs, entities) -- build first
- Each sub-task: Plan --> [Design] --> Build & Test
- Git: integration branch + per-sub-task branches

Automation scripts in `scripts/` (bash):
- `decompose.sh` -- create branches, worktrees, briefs
- `run-agents.sh` -- launch parallel agents (reads `agent.conf` for CLI)
- `check-integration.sh` -- validate integration readiness
- `generate-agents-md.sh` -- capture project knowledge

## Agent Portability

Claude, Codex, and Gemini all use the same skill format (SKILL.md + directory).
Agent definitions are per-platform: Claude uses `.md` files in `agents/claude/`, Codex uses `.toml` files in `agents/codex/`.

## Related skills (invoke when applicable)

- **assistant-review**: Autonomous review loop — MUST be invoked for Stage 2 quality review
- **assistant-tdd**: Test-Driven Development enforcement — Red-Green-Refactor cycle (Build phase, when TDD is active)
- **assistant-thinking**: Structured reasoning for architecture decisions (Discovery, Plan phases)
- **assistant-research**: Information gathering during Discovery phase
- **assistant-security**: Security analysis during Plan/Build phases
- **assistant-memory**: Capture insights at task completion (Phase 7)
- **assistant-reflexion**: Lesson recall in Discovery phase; post-task reflection in Document phase
- **assistant-docs**: Documentation generation in Document phase or standalone
- **assistant-onboard**: Systematic project learning when entering a new codebase
- **assistant-ideate**: Brainstorming pipeline during idea-to-action decomposition
- **assistant-diagrams**: Visual documentation during Plan/Document phases

## Context Management

- **On continuation**: read `.claude/task.md` FIRST — it has the full task state, no guessing needed
- Small tasks: read only target files. Skip reference templates.
- Medium: read touched files. Load plan template only.
- Large: read interfaces/contracts. Load plan template + playbook.
- Mega: each sub-task gets its own brief and context.
- Files >500 lines: search first, read sections as needed.
- After 3+ build/fix iterations: summarize and drop stale context.

## Anti-Patterns

- **Guess:** Ask when ambiguous, state assumptions when clear
- **Skip Discovery:** Even small tasks get quick validation
- **Skip Decompose:** Medium+ tasks MUST decompose into components. "It's straightforward" is not an excuse — decomposition reveals hidden complexity.
- **Mega-step:** One plan step at a time
- **Silent drift:** Stop and flag plan deviations
- **Tests after:** Write tests alongside each step
- **Skip review:** NEVER skip review. Invoke `assistant-review` skill. If you don't see `--- PHASE: REVIEW ---` in the output, review was skipped.
- **Review once and done:** Review has two stages (spec + quality) and quality is an autonomous loop
- **No gate:** Always wait for approval before Build
- **No checkpoints:** Every phase MUST print `--- PHASE: [name] ---` messages. Missing checkpoints = workflow not followed.
- **Skip SOLID:** Evaluate the graduated SOLID checklist after each build step, not as a batch at the end
- **Context hoarding:** Every file read must serve a purpose
