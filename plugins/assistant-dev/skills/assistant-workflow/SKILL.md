---
name: assistant-workflow
description: "This skill provides a structured development workflow with phases: triage, discover, decompose when needed, plan, design when needed, build, review, document. Tests are part of Build; Review is the post-build verification loop. Use when the user says 'build', 'implement', 'fix', 'refactor', 'plan', 'create', 'add feature', 'idea', 'how should I approach', 'break this down', 'start working on'. Also activates for any non-trivial development task requiring discovery and planning before coding."
effort: high
triggers:
  - pattern: "rewrite|implement|fix|migrate|refactor|build feature|build the|build a|build an|create feature|add feature|how should i approach|break this down|start working on|let.s (build|create|implement|add|make|fix|migrate|refactor|rewrite)|phase [0-9]|code (this|that|it|the|a|an|up)"
    priority: 40
    min_words: 2
    reminder: "This request matches assistant-workflow. You MUST load and follow this SKILL.md and its contracts before acting. At minimum: triage the task size, then build with tests included in the Build phase. Skipping workflow for speed is explicitly prohibited."
---

# Development Workflow

Core principles: **verify before deciding**, **right-sized ceremony**, **every idea becomes testable criteria**, **tests travel with the implementation**, and **final answers need evidence**.

## Goal

Move non-trivial development work from request to verified outcome through right-sized phases, explicit gates, tests, review, and company-safe execution.

This skill is intentionally agent-agnostic: it must work in restricted company environments where third-party tools, remote AI services, unapproved package installs, and external code sharing may be prohibited. Use the repo's native tools first, document assumptions, and never require framework-specific infrastructure to produce good development results.

## Success Criteria

- Triage, discovery, planning, build, review, and document phases run at the smallest useful depth.
- Medium+ work has an approved plan before implementation; small work has an inline plan and proceeds without ceremony unless risk requires approval.
- Behavior changes have tests or explicit validation attached to the implementation step they protect.
- Final output reports changed files, verification evidence, residual risks, and next steps.
- Candidate Search is used for explicit alternatives, open-ended architecture/design, optimization, high uncertainty, repeated failed attempts, unclear/flaky bugs, or reviewer-requested pivots — not as default ceremony.
- Company-safe constraints are respected: no unapproved external installs, no code/secrets exfiltration, and no hidden dependency on third-party agent tooling.

## Constraints

- Do not skip phases; scale them down for small work instead.
- Do not ask ritual clarification or approval questions when code/context makes the next safe action clear.
- Do ask bounded clarification questions during Discover/preparation before planning when an implementation-shaping unknown would change correctness, scope, behavior, data, public contract, security, migration safety, or verification, cannot be discovered locally, and has no safe default.
- Do not enter Plan by silently assuming answers to unresolved implementation-shaping unknowns; either ask and wait, explicitly apply safe defaults, or record why local context made the path clear.
- Keep scope changes explicit and tied to correctness, security, safety, or verification risk.
- Do not install tools, upload code, call external services, or paste proprietary content into third-party systems unless the user explicitly approved that path.
- Prefer local, repo-native commands (`npm test`, `dotnet test`, `pytest`, project scripts, existing linters) over introducing new tooling.

## Company-Safe Mode

Assume company repositories may have strict policy until proven otherwise.

Default behavior:
- Read local files and run local project commands only.
- Do not add dependencies, CLIs, services, browser extensions, MCP servers, or agent-specific integrations without explicit approval.
- Do not send source code, logs with secrets, stack traces containing customer data, credentials, or private URLs to external services.
- Do not store secrets, tokens, internal endpoints, or temporary task progress in long-term memory.
- If a requested action conflicts with policy, propose a local/manual alternative and state the trade-off.

Allowed without extra approval when already available in the repo/environment:
- Existing test/build/lint/typecheck commands.
- Existing package manager commands that do not install new dependencies.
- Reading documentation, configs, source files, and tests in the checked-out repo.

Ask before:
- Installing or upgrading dependencies.
- Enabling external integrations.
- Running destructive commands or migrations.
- Sharing code or artifacts outside the local environment.

## Contracts

This skill enforces strict input/output contracts and phase gate assertions. Read the contract files in `contracts/` before executing the workflow. All contracts are **mandatory** and enforced.

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
- If any contract check fails: resolve it before proceeding and record the recovery

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

These are mandatory. Visible checkpoints are the proof that the workflow is being followed.

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

When the user has an idea, question, or vague goal - not a concrete task - decompose it before triaging:

1. **Reverse engineer**: What do they explicitly want? What constraints or exclusions did they state? What's implied?
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

## Acceptance Criteria Quality Bar

Criteria must be useful to implementers and reviewers.

Good criteria are:
- **Atomic**: one independently verifiable behavior per bullet.
- **Binary**: pass/fail is clear.
- **Observable**: test, command, UI behavior, API response, or documented artifact can prove it.
- **Scoped**: avoids vague words like "complete", "robust", "clean", or "better" unless decomposed.

If a criterion contains `and`, `with`, `all`, `every`, `complete`, or multiple failure modes, split it before planning.

## Refactor Guidance

When a task includes incidental or scope-expanding refactor work:
- Justify it with a concrete risk only: correctness, security, unsafe change surface, branching/responsibility growth, hidden dependency/ownership, brittle testing, or poor extension seam.
- Tie incidental or scope-expanding refactors to concrete risk instead of vague framing such as generic convention language, style, cleanliness, or generic improvement.
- Choose the smallest useful, durable fix that removes the identified risk. Keep cleanup scoped unless the user explicitly requested cleanup, reorganization, or refactor work.

## Triage

Print: `--- PHASE: TRIAGE ---`

Load `references/triage-rubric.md`. Assess task type, risk tier, size, required gates, required agents, and `search_mode`. Size determines which phases run, but risk and task type determine the gate packs.

| Size | Phases |
|---|---|
| **Small** (bugfix, typo, config, one-file) | Discover (quick) -> Plan (inline, no wait unless risk/ambiguity requires it) -> Build -> Review -> Document |
| **Medium** (feature, refactor, endpoint) | Discover -> Decompose -> Plan -> [Design] -> Build -> Review -> Document |
| **Large** (new project, multi-module) | Discover -> Decompose -> Plan -> Design -> Build -> Review -> Document |
| **Mega** (rewrite, 10+ files across layers) | Discover -> Decompose -> Plan -> Design -> Build -> Review -> Document |

[Design] = include if task has UI work, skip for backend-only.

Print: `>> Triaged as: [SIZE] — phases: [list]`
Print: `>> Triage metadata: type=[TASK_TYPE] | risk=[RISK_TIER] | gates=[count] | agents=[count] | search=[search_mode]`

If scope exceeds initial triage during any phase, stop and re-triage.

### Risk tiers

Use the contract/rubric values exactly: `low`, `moderate`, `high`, or `critical`.

- **low**: local, reversible, tested, no public behavior or data impact.
- **moderate**: multiple files, shared helpers, unclear edge cases, or moderate verification work.
- **high**: public contracts, data shape, migration, behavior parity, security-sensitive paths, weak tests, or multi-layer coupling.
- **critical**: irreversible data loss risk, auth bypass, secret exposure, payment/security boundary, or production outage risk.

High and critical work require an explicit risk note in the plan and a review/security gate before finalizing. Critical work also requires an approval gate before Build.

## Phase Execution

Load `references/phases.md` and execute the phase matching your current stage. Use `references/context-budget-and-pattern-retrieval.md` when material is large or when editing framework patterns. Use `references/artifact-first-output-contract.md` before Plan so implementation starts from concrete deliverables and verification signals. Use `references/decomposition-plan-review.md` before medium+ work leaves Decompose. Use `references/context-handoff-templates.md` for context engineering and continuation packets when no task journal/equivalent state exists, or when an explicit non-standard handoff is requested. Each phase has:
- Entry checkpoint: `--- PHASE: [name] ---`
- Exit checkpoint: `--- PHASE: [name] COMPLETE ---`
- Approval gates where indicated (WAIT for user)

| Phase | When | Key Actions |
|---|---|---|
| **Discover** | All sizes | Read repo, resolve unknowns, restate requirements. Medium+: produce Code Mapper context map via delegated mode or direct fallback. Unknown-cause bugfixes: load and follow `assistant-debugging` before planning a fix. |
| **Decompose** | Medium+ | Produce one or more smallest iterable slices with strict acceptance and verification fields. Feed the slice manifest into Plan. |
| **Plan** | All sizes | Implementation steps with file paths. Load `references/plan-template.md`. Small tasks use inline no-wait plans unless risk/ambiguity requires approval; medium+ tasks use the single approval gate for scope, slices, and build plan. |
| **Design** | UI tasks only | Design direction, mockup, production checklist. Approval gate. |
| **Build** | All sizes | One step at a time. Code Writer -> Builder/Tester. Tests alongside code. |
| **Review** | All sizes | Stage 1: Spec Review. Stage 2: load and follow `assistant-review` SKILL.md and contracts. |
| **Document** | All sizes | Small: metrics only. Medium+: docs + metrics + reflection. |

For subagent roles and dispatch rules, load `references/subagent-dispatch.md` and resolve `subagent_policy_state`, `subagent_execution_mode`, and `subagent_authorization_scope` before any subagent spawn. If the active tool policy requires explicit user authorization, ask once for the needed delegation scope. A sufficient prompt is: `This workflow expects Code Writer, Builder/Tester, and Reviewer subagents for [scope]. May I use subagents for this task?` After authorization, use `delegated` mode and spawn the configured role agents. Use `direct_fallback` only when authorization is denied, policy disallows spawning, or a real spawn attempt fails because subagents/custom agents are unavailable; do not infer unavailability merely because no visible tool is named `Task`, `delegate`, or `subagent`.
For BES-style option exploration, load `references/candidate-search.md` only when `search_mode: candidate_search` is selected.
For mega tasks and anti-patterns, load `references/mega-and-patterns.md`.

## Planning Checklist

Medium+ plans must include:
- **Goal**: one sentence.
- **Non-goals**: what will not be changed.
- **Acceptance criteria**: atomic checklist.
- **Likely files**: exact paths when known; otherwise directories and discovery tasks.
- **Implementation steps**: ordered, small enough to verify independently.
- **Test strategy**: failing tests, focused tests, regression checks, or explicit validation when tests are not feasible.
- **Risk/security notes**: especially for high-risk surfaces.
- **Rollback/mitigation**: only when deployment/data/config risk exists.

Small tasks still need an inline plan, but it may be 2-5 bullets.

## Build Rules

- For behavior changes, use tests-first by default: reproduce/RED, implement/GREEN, refactor only after green.
- If tests-first is not feasible, state the exception and run the smallest reliable validation command.
- For bug fixes, reproduce the bug with a failing test or minimal command before fixing whenever feasible.
- When a bugfix starts with unknown cause, load and follow `assistant-debugging` during Discover/Build before entering `assistant-tdd`; capture reproduction, hypotheses, disconfirming evidence, root cause status, confidence, and residual risks.
- Once the failure mechanism is understood, transition into `assistant-tdd` with a regression test based on the original reproduction path.
- Never claim a fix works from code inspection alone when a command, test, or local reproduction is available.
- If verification fails and the next fix is obvious, fix and rerun. If the cause is unclear, switch back to `assistant-debugging` instead of random patching.

## Review and Security Gates

Before final output for medium+ or high-risk work:
- Run the relevant build/test/lint/typecheck commands available in the repo.
- Review the diff against the acceptance criteria.
- For bugfixes, verify the review material includes reproduction/root-cause evidence from `assistant-debugging` or a clear reason it was not applicable.
- Use `assistant-review` for quality/spec review when the change is non-trivial.
- Use `assistant-security` when touching auth, user input, secrets, persistence, network calls, shell commands, dependency/config changes, or external integrations.

Review findings must cite evidence and concrete risk. Avoid generic style feedback unless it affects correctness, security, maintainability, or test reliability.

## Context Management

- **On continuation**: read the active project task journal FIRST; it has the full task state
- Small: read only target files. Medium: read touched files + plan template.
- Large: read interfaces/contracts + plan template + playbook.
- Mega: each slice gets its own strict slice brief and context.
- Files >500 lines: search first, read sections as needed.
- After 3+ build/fix iterations: summarize and drop stale context.

## Output

Return:
- **Status** - complete, partially complete, blocked, or plan ready.
- **Changed files** - paths and purpose for each change.
- **Verification** - commands run, pass/fail results, and skipped checks with reasons.
- **Review result** - spec, quality, and security review outcome when applicable.
- **Residual risk** - blockers, assumptions, policy constraints, or follow-up work.
- **Next step** - one practical recommendation.

Do not use phrases like "should work", "probably fixed", or "looks good" unless immediately qualified with evidence or uncertainty.

## Stop Rules

- Stop and ask when an implementation-shaping field is material, undiscoverable, and has no safe default.
- Stop before medium+ Build until the plan is approved.
- Stop before final response if build, tests, required review, or output contract evidence is missing.


## Verified Skill Distillation

Use `references/verified-skill-distillation.md` before promoting successful workflows or review lessons into skills, constraints, or evals.
