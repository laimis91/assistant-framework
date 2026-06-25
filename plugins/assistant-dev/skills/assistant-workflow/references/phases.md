# Workflow Phases — Detailed Instructions

Loaded on demand by the orchestrator during each phase. Read only the phase you're executing.

## Phase: Discover

Print: `--- PHASE: DISCOVER ---`

**Goal:** Zero untracked unknowns. No planning or coding until ambiguity is resolved.

For medium+ tasks or large review/research inputs, load `references/context-budget-and-pattern-retrieval.md` before mapping. Record what stays exact, what is summarized, what is omitted/deferred, and whether the work must be split/delegated instead of stuffed into one context. Resolve `subagent_policy_state`, `subagent_execution_mode`, and `subagent_authorization_scope` before spawning any subagent. For medium+ tasks, produce a **Code Mapper** context map (see `references/context-map-template.md`) by dispatching Code Mapper only when `subagent_execution_mode=delegated`; otherwise produce the same map directly in fallback mode. The Code Mapper returns context map markdown; if local state artifacts are configured and policy-allowed, the orchestrator persists that markdown to `{agent_state_dir}/context-map.md`. Otherwise, carry the context map forward in the plan/task packet. Code Writer and Architect use the map instead of re-exploring the codebase. For large/mega tasks, also trace execution paths with Explorer in delegated mode or direct fallback in non-delegated mode.

For any task that needs clarification, create or update `{agent_state_dir}/task.md` during Discover only when local state artifacts are configured and policy-allowed. Otherwise, include the same state in the response before printing clarification questions or any clarification wait. Persist:
- `Clarification status: ready | needs_clarification`
- `Clarification defaults applied: true | false`
- `Clarification confidence: low | medium | high`
- `Clarification questions asked: N`
- `Clarification question cap: N` where the cap is a maximum, never a quota
- `Clarification admissibility: satisfied | needs_clarification | not_applicable`
- `Unresolved clarification topics:` as a markdown list
- `Search mode: none | lightweight | candidate_search`
- `Candidate archive: {agent_state_dir}/candidate-search.md | inline | N/A`

For medium+ tasks, keep the task journal or equivalent carried-forward state for the full task lifecycle even when Discover resolves without a clarification wait.

Workflow state artifacts (`{agent_state_dir}/task.md`, `{agent_state_dir}/context-map.md`, `{agent_state_dir}/session.md`, and `{agent_state_dir}/working-buffer.md`) are framework-owned, ignored state when an agent state directory is configured and policy allows local state files. The orchestrator may create and update them directly. If state files are unavailable, carry the equivalent state in the response/plan packet. This exception never applies to project source, docs, tests, config, or generated app artifacts.

Discover does not complete while `Clarification status: needs_clarification`. Clarification waiting is a Discover substate, not a separate workflow phase.

Print: `>> Dispatching Code Mapper → context map` (when `subagent_execution_mode=delegated`)
Print: `>> Direct fallback Code Mapper responsibility → context map` (when `subagent_execution_mode=direct_fallback`)
Print: `>> Dispatching Explorer` (when `subagent_execution_mode=delegated`)
Print: `>> Direct fallback Explorer responsibility` (when `subagent_execution_mode=direct_fallback`)

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
7. Confirm or revise `Task type`, `Risk tier`, `Required gates`, `Required agents`, `subagent_policy_state`, and `subagent_execution_mode` from the saved Triage metadata after reading code/context. If discovery changes any of them, print `>> Re-triage required` and update the task journal before continuing.
8. For `task_type: bugfix`, classify `debugging_mode`: if root cause is unknown or the reproduction path is unclear, load and follow `assistant-debugging` before planning a fix. Carry forward its reproduction status, hypotheses, root cause/confidence, and residual risks. If `assistant-debugging` is unavailable or policy-disallowed, do direct hypothesis-driven debugging with the same evidence requirements and record the fallback path.

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
- For any task entering clarification wait, if no task journal/state packet exists yet, create one when local state artifacts are configured and policy-allowed; otherwise include the same state in the response before printing clarification questions or the clarification wait message.
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

**Goal:** Break the problem into the smallest iterable slices that can each be built, tested, reviewed against acceptance criteria, and verified before moving to the next slice.

A slice is not a layer, folder, module, broad feature bucket, setup step, or broad architectural component. It is the smallest deliverable increment that produces observable behavior, artifact output, contract surface, docs, eval coverage, config, migration, or refactor evidence.

**Skip condition:** Small tasks skip this phase entirely — they ARE the atomic unit.

**Entry rule:** Medium+ tasks do not enter Decompose until Discover has persisted `Clarification status: ready` and `Clarification defaults applied: true | false` is explicitly recorded.

For medium+ tasks, produce Architect-level slice boundaries based on the context map, requirements, risk tier, required gate packs, and the Context Budget note. Dispatch **Architect** only when `subagent_execution_mode=delegated`; otherwise perform direct fallback with equivalent criteria and evidence. When editing framework skills/contracts/evals/hooks, retrieve similar local patterns first and record the canonical pattern path plus any counterexample/edge case checked.

Print: `>> Dispatching Architect → strict slice decomposition` (when `subagent_execution_mode=delegated`)
Print: `>> Direct fallback Architect responsibility → strict slice decomposition` (when `subagent_execution_mode=direct_fallback`)

### Decomposition rules

1. **One or more valid slices** — use exactly one slice when that is the smallest iterable increment and record the single-slice rationale.
2. **Reject broad splits** — layer-only, module-only, folder-only, feature-only, setup-only, contract-only, and broad component-style decomposition is invalid as live Decompose output unless the slice is a verified deliverable artifact.
3. **No setup-only slices** — contract-only, config-only, migration-only, docs-only, eval-only, or refactor-only work is valid only when it is the deliverable artifact slice and has acceptance criteria plus verification evidence.
4. **Each slice must be independently verifiable** — if you cannot write a binary pass/fail check and expected success signal for it, it is not a slice.
5. **Order by dependency** — independent slices first, dependent slices after every `depends_on` prerequisite.
6. **No circular dependencies** — if two slices require each other to become observable, merge them into the smallest single iterable slice.
7. **Gate packs become criteria** — every required task-category gate must appear in at least one slice or in the plan-level verification criteria.

### Slice manifest format

```
## Slice Manifest

### Slice [slice_id]: [name]
- **Observable increment:** [behavior, artifact, contract, docs, eval, config, migration, or refactor output this slice makes visible]
- **Deliverable type:** behavior | artifact | contract | docs | eval | config | migration | refactor
- **Acceptance criteria:**
  - [ ] [Binary pass/fail statement]
  - [ ] [Binary pass/fail statement]
- **Files to create:** [exact paths or "none"]
- **Files to modify:** [exact paths or "none"]
- **Files to test:** [exact test paths or verification targets]
- **Enabling changes included:** [setup, contracts, wiring, or "none"]
- **Depends on:** [slice ids, or "none"]
- **Verification command:** [exact command or inspection method]
- **Expected success signal:** [specific passing output, file, or review signal]
- **Evidence to record:** [ledger/eval/test/review artifacts]
- **Deviation rollback rule:** [what to do if scope/files/behavior differ]

Single-slice rationale: [required when the manifest has exactly one slice]
```

### Verification criteria rules

Each criterion must be:
- **Binary** — pass or fail, no "partially done"
- **Observable** — can be checked by running a test, a build, or inspecting output
- **Specific** — "endpoint returns 200 for valid input" not "endpoint works"

Good: `[ ] GET /api/items returns 200 with JSON array`
Bad: `[ ] API works correctly`

### Decomposition Plan Review

Before leaving Decompose for medium+ work, load `references/decomposition-plan-review.md` and review the slice/subagent plan. Record the Decomposition Plan Review packet: Broad-split rejection, scope understanding, slice/subagent count sanity, step/cost budget, dependency order, output-plan match, fallback path, and decision (`proceed`, `revise_decomposition`, or `return_to_discover`). Broad-split rejection must explicitly prove broad layer/module/folder/feature/setup/contract/component splits were rejected unless they are verified deliverable artifact slices. If the decision is not `proceed`, repair decomposition or return to Discover before Plan.

### Plan handoff

Persist the slice manifest and Decomposition Plan Review packet, then carry both into Plan. Do not wait for separate
slice approval in Decompose; the Plan approval gate covers the slice
manifest, decomposition review, implementation packets, file scope, verification criteria, and risks
together. If decomposition exposes ambiguity, scope expansion, or competing
valid approaches, return to Discover for clarification before planning.

Print: `--- PHASE: DECOMPOSE COMPLETE ---`

## Phase: Plan

Print: `--- PHASE: PLAN ---`

**Goal:** Concrete, reviewable implementation plan.

For large tasks, produce an Architect-level implementation blueprint from existing patterns and Code Mapper/Explorer output. Dispatch **Architect** only when `subagent_execution_mode=delegated`; otherwise produce the same blueprint directly in fallback mode.

Print: `>> Dispatching Architect` (when `subagent_execution_mode=delegated`)
Print: `>> Direct fallback Architect responsibility` (when `subagent_execution_mode=direct_fallback`)

**Entry rule:** Do not enter Plan while the saved clarification state is pending. Resume Plan only after Discover records `Clarification status: ready` and all implementation-shaping fields are explicit or explicitly defaulted.

Before writing the plan, load `references/artifact-first-output-contract.md` and define the Artifact Contract: artifact type, required files/deliverables, output format/schema, acceptance criteria, verification command or method, expected success signal, owner/consumer, and non-goals. Then read `references/plan-template.md` and use the correct tier:
- Small: inline plan (goal, files, risks, tests). Do not wait for approval unless risk, ambiguity, user instruction, or a scope-changing decision makes approval necessary.
- Medium: standard plan (drop Security/Operability unless the task touches auth, PII, payments, or infra)
- Large/Mega: full plan (all sections including Security and Operability)

1. Research codebase: modules, patterns, entrypoints
2. Evaluate architecture (see `playbooks/*.md` for project-type rules)
3. Analyze 1-3 options with tradeoffs, pick one
4. Identify risks and edge cases
5. Put the Artifact Contract before task packets and map every medium+ task packet to at least one required artifact or acceptance criterion
6. For medium+ tasks: consume the Decompose slice manifest directly in the plan and align each task packet to exactly one slice_id without rediscovering boundaries
6. Write ordered implementation steps with file paths
7. For large/mega: fill in Security and Operability sections. For medium: only if the task touches auth, PII, payments, or infra (promote to Full tier per plan-template.md)
8. Carry `Task type`, `Risk tier`, `Required gates`, `Required agents`, `subagent_policy_state`, `subagent_execution_mode`, `subagent_authorization_scope`, and `Search mode` into the plan. Each required gate must map to task packet criteria or explicit N/A rationale.
9. If `search_mode: candidate_search`, load `references/candidate-search.md`, create the goal tree from acceptance/slice criteria, score candidates, record the archive location, and treat post-approval pivots as plan deviations requiring re-approval when scope/files/behavior/risk change.
10. Load prompt packs only when applicable:
   - Refactors: `references/prompts/refactor-safety.md`
   - Migrations/rewrites: `references/prompts/refactor-safety.md` plus any applicable migration or parity checklist
   - New code: `references/prompts/test-strategy.md`
   - DB changes: `references/prompts/migration.md`
   - Unknown-cause bugfix: use `assistant-debugging` first; only transition into TDD when reproduction/root-cause evidence can define a meaningful regression test.
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

For medium+ tasks, create a task journal using `references/task-journal-template.md` during Discover when local state artifacts are configured and policy-allowed, and keep updating it through Build. If local state files are unavailable, keep the same state in the plan/response packet. This state survives handoffs — it's the single source of truth for the current task. For cross-session handoffs when no task journal exists, use `references/context-handoff-templates.md` and its context engineering contract: preserve pinned context exactly, summarize compressible logs/reasoning, prune stale or unsafe residue, and end with the exact next action.

Capture **constraints** from Discovery/Plan (e.g. "don't touch ProjectA", "stay on .NET 8"). Check constraints before each step.

### Orchestrator delegation rule

**Delegated mode (`subagent_execution_mode=delegated`):** the orchestrator does not edit project source files or write implementation/test code directly. Framework-owned state artifacts (`{agent_state_dir}/task.md`, `{agent_state_dir}/context-map.md`, `{agent_state_dir}/session.md`, and `{agent_state_dir}/working-buffer.md`) are the exception only when configured and policy-allowed, and may be updated directly. If local state files are unavailable, carry equivalent state in the plan/response packet. Project source changes go through sub-agents, and the Agent Dispatch Log must record dispatch and result evidence for every required role before completion:
- **Code Writer** (`code-writer`): implements code following the plan
- **Builder/Tester** (`builder-tester`): builds, writes tests, runs tests
- **Reviewer** (`reviewer` or assistant-review delegated review): independent review evidence for Review

Any source-changing Build task must infer `required_agents` with at least Code Writer, Builder/Tester, and Reviewer. `not_applicable` is invalid once project source, tests, docs, config, hooks, contracts, or generated project artifacts will change. For medium+ delegated work, also record per-slice dispatch evidence before a slice is marked `VERIFIED`.

**Direct fallback mode (`subagent_execution_mode=direct_fallback`):** when authorization is denied, subagents are unavailable, or policy disallows spawning, the active agent may implement, test, and review directly, but must preserve the same phases, contracts, evidence requirements, and review/security gates. Do not pretend delegation happened; record `subagent_policy_state`, `subagent_execution_mode`, the explicit `Direct fallback reason: authorization_denied | subagents_unavailable | policy_disallowed`, and the direct-execution evidence.

**Strict subagent evidence gate:** any development/code-work task that changes project source, tests, docs, config, hooks, contracts, or generated artifacts must keep Code Writer, Builder/Tester, and Reviewer in `Required agents`; `subagent_execution_mode=not_applicable` is invalid for Build. Before leaving Build/Review, the task journal Agent Dispatch Log (or equivalent carried-forward state) must record `Code Writer dispatch` + `Code Writer result`, `Builder/Tester dispatch` + `Builder/Tester result`, and `Reviewer dispatch` + `Reviewer result` in delegated mode. Direct fallback must instead record `Code Writer direct evidence`, `Builder/Tester direct evidence`, and `Reviewer direct evidence` plus the explicit fallback reason. Silent fallback is invalid; Silent fallback cannot complete.

For each non-TDD step: dispatch Code Writer with the plan step + context map only in delegated mode, or execute directly in fallback mode and record Code Writer direct evidence → verify via Builder/Tester only in delegated mode, or run verification directly in fallback mode and record Builder/Tester direct evidence → check results → proceed or fix. For TDD-active steps, use the TDD sandwich in the Build loop.

### Build loop

**For medium+ tasks with slices:** execute one slice at a time. Each slice is the unit of implementation and verification.

Small tasks stay lightweight: use the plan-step loop below, record the normal build/test evidence, and do not create a slice ledger unless the task was decomposed into slices.

Print: `>> Slice [S]/[total]: [slice_id] [name]`

Before starting each medium+ slice:

1. Load the approved task packet for the slice, including slice_id, observable increment, deliverable type, files, acceptance criteria, verification command, expected success signal, evidence to record, and deviation/rollback rule
2. Confirm prior slice status is `VERIFIED` before advancing; do not start the next slice while the current slice is unverified
3. Check constraints from the task journal against the slice files and criteria

For the current slice task packet:

Print: `>> Step [N]/[total]: [description]`
Print: `>> Dispatching Code Writer → [step description]` (non-TDD, delegated mode)
Print: `>> Direct fallback Code Writer responsibility → [step description]` (non-TDD, direct fallback mode)
Print: `>> Dispatching Builder/Tester → RED evidence` (TDD active) when delegated mode is active
Print: `>> Direct fallback Builder/Tester responsibility → RED evidence` (TDD active) when direct fallback mode is active

1. Bugfix with unknown cause: complete `assistant-debugging` first, or record a concrete blocked/inconclusive debugging result. Do not patch until reproduction/root-cause evidence identifies a fix target or mitigation.
2. Non-TDD: in delegated mode, dispatch Code Writer for one plan step at a time, then Builder/Tester for build + test; in direct fallback, perform the same role responsibilities directly and update the task journal with role-equivalent evidence
3. TDD active: run the TDD sandwich for the step, with Builder/Tester RED before Code Writer GREEN and Builder/Tester VERIFY/REFACTOR-SAFETY afterward. In direct fallback, preserve those role boundaries in the evidence even though one agent performs the work. For bugfixes, the RED test must trace to the original reproduction/debugging evidence.
4. If implementation or verification fails and the cause is unclear: return to `assistant-debugging` before another patch attempt; otherwise dispatch Code Writer in delegated mode or perform the Code Writer responsibility directly in fallback mode before the next step
4. Tests alongside code, not after
5. **SOLID check** after each step: load `references/prompts/solid-principles.md` and evaluate the graduated checklist (SRP for small, SRP+OCP+DIP for medium, full SOLID for large/mega). Fix violations before moving to the next step.
6. **TDD mode** (when active): use the TDD sandwich per step:
   - Builder/Tester RED: write one failing behaviour test, run it, verify right failure reason, and return RED evidence.
   - Code Writer GREEN: implement minimal production code only after RED evidence is present.
   - Builder/Tester VERIFY/REFACTOR-SAFETY: run the targeted test, relevant suite, and regression checks; request Code Writer fixes for production failures.

Print: `>> Step [N]/[total]: DONE` (after each step passes build + test)

### Per-slice verification (medium+ tasks)

Per-slice verification is a Build-phase gate. It does not replace the full Review phase after Build completes.

After implementation for a slice is done, verify the slice against its criteria from the DECOMPOSE phase before moving on:

1. Dispatch Builder/Tester in delegated mode, or perform the Builder/Tester responsibility directly in fallback mode, to run the slice's verification command and any relevant build/test checks from the task packet
2. Check each acceptance criterion from the slice manifest independently — mark pass/fail with the command/result or inspection evidence used
3. Record verification evidence in the task journal slice verification ledger, including RED status when TDD was active, implementation status, command/result, criteria checked, and final status
4. Run a small self-check/local sanity check: compare changed files and behavior against the task packet, constraints, and deviation rule; record the result in the ledger
5. If any criterion, command, or self-check fails: fix before moving to the next slice
6. Mark the slice `VERIFIED` only after all criteria pass and evidence is recorded

Print: `>> Slice [S]/[total]: [slice_id] [name] — VERIFIED ([X]/[Y] criteria passed)`

Only proceed to the next slice after the current one is fully verified.

After all slices are verified:

Run integration tests across slice boundaries.

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

Load and follow `references/prompts/spec-review.md`. Compare implementation against the approved plan, approved task packets, and approved slices and produce a structured spec compliance result before Stage 2. For bugfixes, include the `assistant-debugging` reproduction/root-cause evidence in the review material and check that the regression test or validation path actually covers the isolated failure mechanism.

Quality review cannot satisfy spec review. Spec review checks scope and acceptance compliance; quality review checks correctness, maintainability, architecture, security, and coverage after spec compliance is clear.

1. Walk through each approved plan step, task packet, or slice against `git diff`.
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

**Load and follow `assistant-review` SKILL.md and its contracts.** This runs the autonomous review-fix loop (max 5 rounds) with visible progress. Do NOT implement the review loop inline when `subagent_execution_mode=delegated` and a delegated review agent is authorized — use the skill instructions so the loop is applied consistently.

The `assistant-review` skill will:
- Dispatch Reviewer subagents in delegated mode, or preserve fresh-review evidence in direct fallback mode
- Fix must-fix and should-fix items
- Re-review automatically
- Return a final clean/remaining summary

For small tasks: quick spec check + single review round is acceptable if clean.
For medium+ tasks: full two-stage review with autonomous quality loop via `assistant-review`.

### Status gate

When local hooks are configured and policy-allowed, use them to enforce the review cycle structurally. Example: a configured stop hook can block completion while the task journal/status packet is BUILDING or REVIEWING and the Review Log is missing entries or a Final Result.

When hooks are unavailable, enforce the same gate manually before presenting results:
- Review Log or equivalent review result must exist.
- Final Result must be recorded.
- The agent must complete the full review cycle before presenting results to the user.
- Do not claim the hook ran unless it actually exists and executed.

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
5. If local memory tools are approved and available, capture durable learnings in the configured local memory store; otherwise skip memory updates and report durable insights in the final response
6. **Task completion metrics**: Append a JSONL entry when local metrics are configured and policy allows it (see format below)
7. **Post-task reflection**: If `assistant-reflexion` is available, load and follow it to capture what worked, what didn't, and extract lessons for future tasks. This is where the compounding happens.

### Metrics entry format (all sizes)

Append one JSONL line to the agent's configured local workflow metrics location when metrics are enabled and policy-allowed (for example `~/{agent_state_dir}/memory/metrics/workflow-metrics.jsonl`, or another configured local path):
```json
{"date":"YYYY-MM-DD","project":"[name]","task":"[description]","size":"[small/medium/large/mega]","retriage":false,"review_rounds":N,"plan_deviations":N,"build_failures":N,"criteria_defined":N,"criteria_skipped":[],"agent_readiness_score":null,"slices_count":null,"slices_verified":null}
```
`agent_readiness_score` is null for small tasks (readiness check is skipped). This is how we measure whether workflow changes improve outcomes over time.

Print: `--- PHASE: DOCUMENT COMPLETE ---`
Print: `--- WORKFLOW COMPLETE ---`


## Verified Skill Distillation

When a completed workflow or review lesson should become durable framework knowledge, load `references/verified-skill-distillation.md`. Do not create or update skill files until the distillation packet has verifier_result `approved`. Prefer updating contracts, checklists, or evals over creating a new skill when the lesson is narrow.
