---
name: assistant-workflow
description: "This skill provides a structured development workflow with phases: triage, discover, decompose when needed, plan, design when needed, build, review, document. Tests are part of Build; Review is the post-build verification loop. Use when the user says 'build', 'implement', 'fix', 'refactor', 'plan', 'create', 'add feature', 'idea', 'how should I approach', 'break this down', 'start working on'. Also activates for any non-trivial development task requiring discovery and planning before coding."
effort: high
requires:
  - assistant-memory
triggers:
  - pattern: "rewrite|implement|fix|migrate|refactor|build feature|build the|build a|build an|create feature|add feature|how should i approach|break this down|start working on|let.s (build|create|implement|add|make|fix|migrate|refactor|rewrite)|phase [0-9]|code (this|that|it|the|a|an|up)"
    priority: 40
    min_words: 2
    reminder: "This request matches assistant-workflow. You MUST load and follow this SKILL.md and its contracts before acting. At minimum: triage the task size, then build with tests included in the Build phase. Skipping workflow for speed is explicitly prohibited."
---

# Development Workflow

Core principles: **verify before deciding**, **right-sized ceremony**, **every idea becomes testable criteria**.

## Goal

Move non-trivial development work from request to verified outcome through right-sized phases, explicit gates, tests, and review.

## Success Criteria

- Triage, discovery, planning, build, review, and document phases run at the smallest useful depth.
- Medium+ work has an approved plan before implementation; small work has an inline plan and proceeds without ceremony unless risk requires approval.
- Tests or validation run with the implementation step they protect.
- Final output reports changed files, verification evidence, residual risks, and next steps.

## Constraints

- Do not skip phases; scale them down for small work instead.
- Do not ask ritual clarification or approval questions when code/context makes the next safe action clear.
- Keep scope changes explicit and tied to correctness, security, safety, or verification risk.

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

## Refactor Guidance

When a task includes incidental or scope-expanding refactor work:
- Justify it with a concrete risk only: correctness, security, unsafe change surface, branching/responsibility growth, hidden dependency/ownership, brittle testing, or poor extension seam.
- Tie incidental or scope-expanding refactors to concrete risk instead of vague framing such as generic convention language, style, cleanliness, or generic improvement.
- Choose the smallest useful, durable fix that removes the identified risk. Keep cleanup scoped unless the user explicitly requested cleanup, reorganization, or refactor work.

## Triage

Print: `--- PHASE: TRIAGE ---`

Load `references/triage-rubric.md`. Assess task type, risk tier, size, required gates, and required agents. Size determines which phases run, but risk and task type determine the gate packs.

| Size | Phases |
|---|---|
| **Small** (bugfix, typo, config, one-file) | Discover (quick) -> Plan (inline, no wait unless risk/ambiguity requires it) -> Build -> Review -> Document |
| **Medium** (feature, refactor, endpoint) | Discover -> Decompose -> Plan -> [Design] -> Build -> Review -> Document |
| **Large** (new project, multi-module) | Discover -> Decompose -> Plan -> Design -> Build -> Review -> Document |
| **Mega** (rewrite, 10+ files across layers) | Discover -> Decompose -> Plan -> Design -> Build -> Review -> Document |

[Design] = include if task has UI work, skip for backend-only.

Print: `>> Triaged as: [SIZE] — phases: [list]`
Print: `>> Triage metadata: type=[TASK_TYPE] | risk=[RISK_TIER] | gates=[count] | agents=[count]`

If scope exceeds initial triage during any phase, stop and re-triage.

## Phase Execution

Load `references/phases.md` and execute the phase matching your current stage. Each phase has:
- Entry checkpoint: `--- PHASE: [name] ---`
- Exit checkpoint: `--- PHASE: [name] COMPLETE ---`
- Approval gates where indicated (WAIT for user)

| Phase | When | Key Actions |
|---|---|---|
| **Discover** | All sizes | Read repo, resolve unknowns, restate requirements. Medium+: dispatch Code Mapper. |
| **Decompose** | Medium+ | Break into 2-7 components with verification criteria. Feed the manifest into Plan. |
| **Plan** | All sizes | Implementation steps with file paths. Load `references/plan-template.md`. Small tasks use inline no-wait plans unless risk/ambiguity requires approval; medium+ tasks use the single approval gate for scope, components, and build plan. |
| **Design** | UI tasks only | Design direction, mockup, production checklist. Approval gate. |
| **Build** | All sizes | One step at a time. Code Writer -> Builder/Tester. Tests alongside code. |
| **Review** | All sizes | Stage 1: Spec Review. Stage 2: load and follow `assistant-review` SKILL.md and contracts. |
| **Document** | All sizes | Small: metrics only. Medium+: docs + metrics + reflection. |

For subagent roles and dispatch rules, load `references/subagent-dispatch.md`.
For mega tasks and anti-patterns, load `references/mega-and-patterns.md`.

## Context Management

- **On continuation**: read the active project task journal FIRST; it has the full task state
- Small: read only target files. Medium: read touched files + plan template.
- Large: read interfaces/contracts + plan template + playbook.
- Mega: each sub-task gets its own brief and context.
- Files >500 lines: search first, read sections as needed.
- After 3+ build/fix iterations: summarize and drop stale context.

## Output

Return:
- **Status** - final workflow state and whether review completed cleanly.
- **Changed files** - paths and purpose for each change.
- **Verification** - commands run, pass/fail results, and skipped checks with reasons.
- **Review result** - spec and quality review outcome.
- **Residual risk** - blockers, assumptions, or follow-up work.

## Stop Rules

- Stop and ask when an implementation-shaping field is material, undiscoverable, and has no safe default.
- Stop before medium+ Build until the plan is approved.
- Stop before final response if build, tests, required review, or output contract evidence is missing.
