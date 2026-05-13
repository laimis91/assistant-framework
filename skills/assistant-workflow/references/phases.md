# Workflow Phases — Detailed Instructions

Loaded on demand by the orchestrator during each phase. Read only the phase you're executing.

## Phase: Discover

Print: `--- PHASE: DISCOVER ---`

**Goal:** Zero untracked unknowns. No planning or coding until ambiguity is resolved.

For medium+ tasks, dispatch a **Code Mapper** to produce a context map (see `references/context-map-template.md`). The context map is stored at `.claude/context-map.md` and used by Code Writer and Architect instead of re-exploring the codebase. For large/mega tasks, also dispatch an **Explorer** to trace execution paths and understand behavior.

For any task that needs clarification, create or update `.claude/task.md` during Discover before printing clarification questions or any clarification wait. Persist:
- `Clarification status: ready | needs_clarification`
- `Clarification defaults applied: true | false`
- `Clarification confidence: low | medium | high`
- `Clarification questions asked: N`
- `Clarification question cap: N` where the cap is a maximum, never a quota
- `Clarification admissibility: satisfied | needs_clarification | not_applicable`
- `Unresolved clarification topics:` as a markdown list

For medium+ tasks, keep `.claude/task.md` for the full task lifecycle even when Discover resolves without a clarification wait.

Discover does not complete while `Clarification status: needs_clarification`. Clarification waiting is a Discover substate, not a separate workflow phase.

Print: `>> Dispatching Code Mapper → context map` (when applicable)
Print: `>> Dispatching Explorer` (when applicable)

1. Read repo: README, CLAUDE.md, AGENTS.md, key files. Batch independent file reads/searches when the active tool policy supports parallel calls; use sequential reads otherwise.
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
5. Ask structured clarification Q&A with recommendations for any unresolved implementation-shaping field only when the question is admissible. Admissible means the answer affects correctness, scope, behavior, data, public contract, security, migration safety, or verification; cannot be discovered from code/context; has no safe default; and includes the risk if guessed.
6. Restate requirements in 1-3 sentences after clarification is resolved
7. Confirm or revise `Task type`, `Risk tier`, `Required gates`, and `Required agents` from the saved Triage metadata after reading code/context. If discovery changes any of them, print `>> Re-triage required` and update the task journal before continuing.

**Clarification format:**
```
Need to know
1. [Question]?
   Why needed: [correctness/scope/behavior/security/verification impact]
   Risk if guessed: [what could break]
   Safe default: [default, or "none"]
   a) [Option]  b) [Option]  c) [Option]
   --> Recommendation: b because [reason]

Reply with: "1b 2a" or "defaults".
```

**Clarification state rules:**
- For any task entering clarification wait, if `.claude/task.md` does not exist yet, create it before printing clarification questions or the clarification wait message.
- Question caps are maximums, not quotas. Small tasks usually ask 0-1 questions; medium tasks may ask 0-4; large/mega tasks may ask more only when each question is admissible. A well-specified medium+ task can and should record `Clarification questions asked: 0`.
- Before printing questions, keep the workflow `Status` in Discover, update the task journal to `Clarification status: needs_clarification`, `Clarification defaults applied: false`, `Clarification confidence: low | medium`, `Clarification questions asked: N`, `Clarification question cap: N`, `Clarification admissibility: needs_clarification`, and list each unresolved implementation-shaping topic.
- Print: `>> WAITING: Clarification answers required`
- Stop after the wait message. Do not continue into Decompose or Plan while clarification is pending.
- On resume, accept only:
  - explicit question/option answers covering the open question ids (example: `1b 2a`)
  - explicit `defaults`
- Do not infer answers from free-form continuation text.
- Every implementation-shaping field that is still unresolved must appear in `Unresolved clarification topics` until it is answered or explicitly defaulted.
- Treat clarification as pending whenever unresolved clarification topics are non-empty, even if `Clarification status` was previously recorded as `ready`.
- If the reply is `defaults`, print the defaults being applied, set `Clarification defaults applied: true`, clear the unresolved topics list, and set `Clarification status: ready`.
- If the reply is explicit answers, record the chosen options, set `Clarification defaults applied: false`, clear the unresolved topics list, and set `Clarification status: ready`.
- If no questions are needed, record `Clarification status: ready`, `Clarification confidence: high`, `Clarification questions asked: 0`, `Clarification admissibility: not_applicable`, and explain briefly what code/context made the task clear.

**Rules:**
- No commands, edits, or plans that depend on unknowns
- Read-only discovery (search, git log, browsing) is allowed
- Small tasks: 0-1 questions. Mega: full Q&A.

Print: `--- PHASE: DISCOVER COMPLETE ---`

## Phase: Decompose

Print: `--- PHASE: DECOMPOSE ---`

**Goal:** Break the problem into small, independently verifiable components. Each component is a unit of work that can be built, tested, and verified in isolation before moving to the next.

Think of components like LEGO bricks — each one is self-contained and testable, and together they form the solution.

**Skip condition:** Small tasks skip this phase entirely — they ARE the atomic unit.

**Entry rule:** Medium+ tasks do not enter Decompose until Discover has persisted `Clarification status: ready` and `Clarification defaults applied: true | false` is explicitly recorded.

For medium+ tasks, dispatch an **Architect** to analyze the problem and propose component boundaries based on the context map, requirements, risk tier, and required gate packs.

Print: `>> Dispatching Architect → component decomposition`

### Decomposition rules

1. **2-7 components** for medium tasks, **3-7 for large**, mega uses sub-task decomposition (see Mega section)
2. **Each component must be independently verifiable** — if you can't write a binary pass/fail check for it, it's not a component
3. **Order by dependency** — independent components first, dependent ones after their prerequisites
4. **No circular dependencies** — if A needs B and B needs A, merge them into one component
5. **Shared contracts first** — if multiple components share interfaces/DTOs, extract those as component #1
6. **Gate packs become criteria** — every required task-category gate must appear in at least one component or in the plan-level verification criteria.

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

### Plan handoff

Persist the component manifest and carry it into Plan. Do not wait for separate
component approval in Decompose; the Plan approval gate covers the component
manifest, implementation packets, file scope, verification criteria, and risks
together. If decomposition exposes ambiguity, scope expansion, or competing
valid approaches, return to Discover for clarification before planning.

Print: `--- PHASE: DECOMPOSE COMPLETE ---`

## Phase: Plan

Print: `--- PHASE: PLAN ---`

**Goal:** Concrete, reviewable implementation plan.

For large tasks, dispatch an **Architect** — it analyzes existing patterns (using Code Mapper/Explorer output) and returns a structured implementation blueprint.

Print: `>> Dispatching Architect` (when applicable)

**Entry rule:** Do not enter Plan while the saved clarification state is pending. Resume Plan only after Discover records `Clarification status: ready` and all implementation-shaping fields are explicit or explicitly defaulted.

Read `references/plan-template.md` and use the correct tier:
- Small: inline plan (goal, files, risks, tests). Do not wait for approval unless risk, ambiguity, user instruction, or a scope-changing decision makes approval necessary.
- Medium: standard plan (drop Security/Operability unless the task touches auth, PII, payments, or infra)
- Large/Mega: full plan (all sections including Security and Operability)

1. Research codebase: modules, patterns, entrypoints
2. Evaluate architecture (see `playbooks/*.md` for project-type rules)
3. Analyze 1-3 options with tradeoffs, pick one
4. Identify risks and edge cases
5. For medium+ tasks: include the Decompose component manifest in the plan and align each task packet to a component
6. Write ordered implementation steps with file paths
7. For large/mega: fill in Security and Operability sections. For medium: only if the task touches auth, PII, payments, or infra (promote to Full tier per plan-template.md)
8. Carry `Task type`, `Risk tier`, `Required gates`, and `Required agents` into the plan. Each required gate must map to task packet criteria or explicit N/A rationale.
9. Load prompt packs only when applicable:
   - Refactors: `references/prompts/refactor-safety.md`
   - Migrations/rewrites: `references/prompts/refactor-safety.md` plus any applicable migration or parity checklist
   - New code: `references/prompts/test-strategy.md`
   - DB changes: `references/prompts/migration.md`
   - TDD mode: use `assistant-tdd` skill (or `references/prompts/tdd-enforcement.md` if skill not installed)
   - **SOLID (plan phase):** Review `references/prompts/solid-principles.md` graduated enforcement table to fill SOLID design notes in the plan template's Architecture section (medium+ tasks).

### Approval gate

For small tasks, print the inline plan and continue directly to Build unless the task has unresolved ambiguity, user-requested approval, destructive operations, or scope-changing choices.

For medium+ tasks, print: `>> WAITING: Plan approval required`

Present the plan and WAIT:
```
Review the plan:
- "approved" -- I'll start implementation
- "approved with changes: [list]" -- I'll update first
- Questions -- I'll address before proceeding
```

Print: `--- PHASE: PLAN COMPLETE (approved) ---` for approved medium+ plans, or `--- PHASE: PLAN COMPLETE ---` for no-wait small plans.

## Phase: Design (UI/UX only, skip for backend)

Print: `--- PHASE: DESIGN ---`

1. Define design direction (tone, palette, typography)
2. Propose design system (CSS variables, components)
3. Create visual mockup (HTML artifact)
4. Production checklist: states, responsive, accessibility

Print: `>> WAITING: Design approval required`

Show mockup and WAIT for approval.

Print: `--- PHASE: DESIGN COMPLETE (approved) ---`

## Phase: Build

Print: `--- PHASE: BUILD ---`

### Task journal

For medium+ tasks, create `.claude/task.md` using `references/task-journal-template.md` during Discover and keep updating it through Build. This file survives context compression — it's the single source of truth for the current task. For cross-session handoffs when no task journal exists, use `references/context-handoff-templates.md`.

Capture **constraints** from Discovery/Plan (e.g. "don't touch ProjectA", "stay on .NET 8"). Check constraints before each step.

### Orchestrator delegation rule

**The orchestrator NEVER edits files or writes code directly.** All file changes go through sub-agents:
- **Code Writer** (`code-writer`): implements code following the plan
- **Builder/Tester** (`builder-tester`): builds, writes tests, runs tests

Think of it like a general who directs the battle but never picks up a rifle. The orchestrator dispatches, monitors, and course-corrects — but the agents do the actual work.

For each non-TDD step: dispatch Code Writer with the plan step + context map → when done, dispatch Builder/Tester to verify → check results → proceed or fix. For TDD-active steps, use the TDD sandwich in the Build loop.

### Build loop

**For medium+ tasks with components:** execute one component at a time. Each component may contain multiple plan steps, but the component is the unit of verification.

Small tasks stay lightweight: use the plan-step loop below, record the normal build/test evidence, and do not create a component ledger unless the task was decomposed into components.

Print: `>> Component [C]/[total]: [name]`

Before starting each medium+ component:

1. Load the approved task packet for the component, including files, criteria, verification command, expected success signal, and deviation/rollback rule
2. Confirm prior component status is `VERIFIED` before advancing; do not start the next component while the current component is unverified
3. Check constraints from the task journal against the component files and criteria

For each plan step within the component:

Print: `>> Step [N]/[total]: [description]`
Print: `>> Dispatching Code Writer → [step description]` (non-TDD)
Print: `>> Dispatching Builder/Tester → RED evidence` (TDD active)

1. Non-TDD: dispatch Code Writer for one plan step at a time, then dispatch Builder/Tester for build + test and update the task journal
2. TDD active: run the TDD sandwich for the step, with Builder/Tester RED before Code Writer GREEN and Builder/Tester VERIFY/REFACTOR-SAFETY afterward
3. If implementation or verification fails: dispatch Code Writer to fix before the next step
4. Tests alongside code, not after
5. **SOLID check** after each step: load `references/prompts/solid-principles.md` and evaluate the graduated checklist (SRP for small, SRP+OCP+DIP for medium, full SOLID for large/mega). Fix violations before moving to the next step.
6. **TDD mode** (when active): use the TDD sandwich per step:
   - Builder/Tester RED: write one failing behaviour test, run it, verify right failure reason, and return RED evidence.
   - Code Writer GREEN: implement minimal production code only after RED evidence is present.
   - Builder/Tester VERIFY/REFACTOR-SAFETY: run the targeted test, relevant suite, and regression checks; request Code Writer fixes for production failures.

Print: `>> Step [N]/[total]: DONE` (after each step passes build + test)

### Per-component verification (medium+ tasks)

Per-component verification is a Build-phase gate. It does not replace the full Review phase after Build completes.

After all steps for a component are done, verify the component against its criteria from the DECOMPOSE phase before moving on:

1. Dispatch Builder/Tester to run the component's verification command and any relevant build/test checks from the task packet
2. Check each verification criterion from the component manifest independently — mark pass/fail with the command/result or inspection evidence used
3. Record verification evidence in the task journal component verification ledger, including RED status when TDD was active, implementation status, command/result, criteria checked, and final status
4. Run a small self-check/local sanity check: compare changed files and behavior against the task packet, constraints, and deviation rule; record the result in the ledger
5. If any criterion, command, or self-check fails: fix before moving to next component
6. Mark the component `VERIFIED` only after all criteria pass and evidence is recorded

Print: `>> Component [C]/[total]: [name] — VERIFIED ([X]/[Y] criteria passed)`

Only proceed to the next component after the current one is fully verified.

After all components are verified:

Run integration tests across component boundaries.

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

## Phase: Review

Print: `--- PHASE: REVIEW ---`

### Stage 1 — Spec Review

Print: `>> Stage 1: Spec Review`

Load and follow `references/prompts/spec-review.md`. Compare implementation against the approved plan or approved task packets/components and produce a structured spec compliance result before Stage 2.

Quality review cannot satisfy spec review. Spec review checks scope and acceptance compliance; quality review checks correctness, maintainability, architecture, security, and coverage after spec compliance is clear.

1. Walk through each approved plan step, task packet, or component against `git diff`.
2. Check for missing acceptance criteria: any required behavior not reflected in code or evidence.
3. Check for extra scope: any code change not in the approved scope, unless explicitly approved as a deviation.
4. Check changed files mismatch: expected files versus actual changed files.
5. Check verification evidence mismatch: required command, expected success signal, and criteria checked versus recorded evidence.
6. **Append** a `### Spec Review #N` entry to the task journal's Review Log using the prompt's structured output:
   - Result: PASS | FAIL
   - Missing acceptance criteria
   - Extra scope
   - Changed files mismatch
   - Verification evidence mismatch
   - Required fixes
7. **Spec review FAIL:** fix required items, re-test, and re-run spec review before Stage 2.
8. **Spec review PASS:** proceed to Stage 2.

Print: `>> Spec Review: [PASS / FAIL — found N required fixes]`

### Stage 2 — Quality Review

Print: `>> Stage 2: Quality Review — loading assistant-review SKILL.md`

**Load and follow `assistant-review` SKILL.md and its contracts.** This runs the autonomous review-fix loop (max 5 rounds) with visible progress. Do NOT implement the review loop inline when a delegated review agent is available — use the skill instructions so the loop is applied consistently.

The `assistant-review` skill will:
- Dispatch Reviewer subagents
- Fix must-fix and should-fix items
- Re-review automatically
- Return a final clean/remaining summary

For small tasks: quick spec check + single review round is acceptable if clean.
For medium+ tasks: full two-stage review with autonomous quality loop via `assistant-review`.

### Status gate

The stop hook (`~/.claude/hooks/assistant/stop-review.sh`) enforces the review cycle structurally:
- If the task journal status is BUILDING or REVIEWING **and** the Review Log is missing entries or a Final Result, the agent is **blocked from stopping**.
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
2. Fix each issue (re-enter Build → Review for those steps only; tests remain part of Build)
3. Update verification summary
4. Present again for approval

Do NOT proceed to Document until the user confirms.

## Phase: Document

Print: `--- PHASE: DOCUMENT ---`

### Small tasks — lightweight path

For small tasks, skip documentation updates and go straight to metrics:

1. **Task completion metrics**: Append a JSONL entry (see format below)
2. **Post-task reflection** (optional): Load and follow `assistant-reflexion` if the task produced a non-obvious lesson

Then print completion markers and exit.

### Medium+ tasks — full path

1. Update README, CHANGELOG, architecture docs as needed
2. Code comments where "why" isn't obvious
3. Complete `references/release-readiness-checklist.md`
4. If user-facing changes: generate release notes using `references/prompts/release-notes.md`
5. Use `memory_add_insight` to capture learnings in the knowledge graph
6. **Task completion metrics**: Append a JSONL entry (see format below)
7. **Post-task reflection**: If `assistant-reflexion` is available, load and follow it to capture what worked, what didn't, and extract lessons for future tasks. This is where the compounding happens.

### Metrics entry format (all sizes)

Append one JSONL line to the agent's workflow metrics location (for example `~/.claude/memory/metrics/workflow-metrics.jsonl`, `~/.codex/memory/metrics/workflow-metrics.jsonl`, or `~/.gemini/memory/metrics/workflow-metrics.jsonl`):
```json
{"date":"YYYY-MM-DD","project":"[name]","task":"[description]","size":"[small/medium/large/mega]","retriage":false,"review_rounds":N,"plan_deviations":N,"build_failures":N,"criteria_defined":N,"criteria_skipped":[],"agent_readiness_score":null,"components_count":null,"components_verified":null}
```
`agent_readiness_score` is null for small tasks (readiness check is skipped). This is how we measure whether workflow changes improve outcomes over time.

Print: `--- PHASE: DOCUMENT COMPLETE ---`
Print: `--- WORKFLOW COMPLETE ---`
