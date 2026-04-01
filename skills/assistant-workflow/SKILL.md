---
name: assistant-workflow
description: "This skill provides a structured development workflow with phases: triage, discover, plan, build, test, review, document. Use when the user says 'build', 'implement', 'fix', 'refactor', 'plan', 'create', 'add feature', 'idea', 'how should I approach', 'break this down', 'start working on'. Also activates for any non-trivial development task requiring discovery and planning before coding."
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

## Phase Execution

Load `references/phases.md` and execute the phase matching your current stage. Each phase has:
- Entry checkpoint: `--- PHASE: [name] ---`
- Exit checkpoint: `--- PHASE: [name] COMPLETE ---`
- Approval gates where indicated (WAIT for user)

| Phase | When | Key Actions |
|---|---|---|
| **Discover** | All sizes | Read repo, resolve unknowns, restate requirements. Medium+: dispatch Code Mapper. |
| **Decompose** | Medium+ | Break into 2-7 components with verification criteria. Approval gate. |
| **Plan** | All sizes | Implementation steps with file paths. Load `references/plan-template.md`. Approval gate. |
| **Design** | UI tasks only | Design direction, mockup, production checklist. Approval gate. |
| **Build & Test** | All sizes | One step at a time. Code Writer -> Builder/Tester. Tests alongside code. |
| **Review** | All sizes | Stage 1: Spec Review. Stage 2: invoke `assistant-review` skill. |
| **Document** | All sizes | Small: metrics only. Medium+: docs + metrics + reflection. |

For subagent roles and dispatch rules, load `references/subagent-dispatch.md`.
For mega tasks and anti-patterns, load `references/mega-and-patterns.md`.

## Context Management

- **On continuation**: read `.claude/task.md` FIRST — it has the full task state
- Small: read only target files. Medium: read touched files + plan template.
- Large: read interfaces/contracts + plan template + playbook.
- Mega: each sub-task gets its own brief and context.
- Files >500 lines: search first, read sections as needed.
- After 3+ build/fix iterations: summarize and drop stale context.
