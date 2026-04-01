# Workflow Phases — Detailed Instructions

Loaded on demand by the orchestrator during each phase. Read only the phase you're executing.

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
