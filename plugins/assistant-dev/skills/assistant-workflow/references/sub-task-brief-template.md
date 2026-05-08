# Sub-Task Brief Template

Use this template when decomposing mega tasks. Each sub-task gets its own brief that can be pasted into a new conversation.

## Decomposition rules

- Aim for 3–7 sub-tasks
- Sub-task #1 is ALWAYS shared contracts (interfaces, DTOs, entities, message schemas)
- All other sub-tasks branch from the integration branch after #1 is merged
- UI sub-tasks include a Design step, backend sub-tasks skip it
- Sub-tasks add code comments but do NOT update README, CHANGELOG, or architecture docs

## Git branching strategy

```
main
 └── feature/[mega-task-name]           ← integration branch
      ├── feature/[mega-task]/contracts  ← shared contracts (merge first)
      ├── feature/[mega-task]/sub-task-2
      ├── feature/[mega-task]/sub-task-3
      └── feature/[mega-task]/sub-task-4
```

Workflow:
1. Create integration branch from main
2. Build contracts on feature/[mega-task]/contracts, merge into integration branch
3. Each sub-task branches from integration branch (which now has contracts)
4. Sub-tasks work independently on their branches
5. Integration: merge all into integration branch, resolve conflicts
6. Final merge: integration branch → main

## Brief template

````markdown
## Sub-Task Brief: [name]

### Agent
Agent: [code-writer | architect | reviewer | explorer | builder-tester | code-mapper]
Role: [Implementer | Architect | Reviewer | Explorer]

### Context
Project: [name]
Parent task: [one-sentence description of the mega task]
This is sub-task [N] of [total]. Other sub-tasks are handling: [list].

### Goal
[What this sub-task delivers]

### Scope
- Files/modules to touch: [list]
- Layer: [Domain / Application / Infrastructure / UI / etc.]

### Shared contracts (already defined)
[Paste the interfaces, DTOs, schemas this sub-task must implement or consume.
Include the actual code/signatures, not just names.]

### Constraints
- Must not modify: [files owned by other sub-tasks]
- Must implement: [interface/contract from shared contracts]
- Architecture: [rules from the parent plan]
- Naming conventions: [from project]
- Git branch: [branch name to work on]

### Acceptance criteria
- [ ] [Criterion 1]
- [ ] [Criterion 2]
- [ ] Tests pass: [specific test command]

### What to do
Read `.claude/memory.md` for project context before starting.
Run: Plan → [Design →] Build.
Follow project conventions.
Add code comments where intent isn't obvious.
Do NOT update README, CHANGELOG, or architecture docs —
that happens in the final Document phase after integration.

### Completion status

When the sub-task is complete, report status using one of these values:

| Status | Meaning | What happens next |
|---|---|---|
| `DONE` | All acceptance criteria met, tests pass, no concerns | Proceed to integration |
| `DONE_WITH_CONCERNS` | Criteria met but there are trade-offs or risks worth noting | Orchestrator reviews concerns before integration |
| `NEEDS_CONTEXT` | Blocked by missing information not in the brief | Orchestrator provides context or adjusts the brief |
| `BLOCKED` | Cannot proceed — dependency issue, tooling failure, or design conflict | Orchestrator investigates and unblocks |

**Report format:**
```text
## Sub-Task Status: [DONE | DONE_WITH_CONCERNS | NEEDS_CONTEXT | BLOCKED]

### Summary
[1-3 sentences: what was accomplished]

### Concerns (if DONE_WITH_CONCERNS)
- [trade-off or risk worth noting]

### Blocker (if NEEDS_CONTEXT or BLOCKED)
- What's needed: [specific missing information or resolution]

### Changes made
- [file]: [what changed]

### Tests
- [test command]: [result]
```
````

## Execution strategies

**Parallel sessions (multiple conversations):**
Best when sub-tasks have no dependencies after contracts. Start each with its brief.

**Sequential sessions:**
Best when sub-tasks depend on each other. Complete one, carry output to next.

**Multi-agent (Claude Code, Codex CLI):**
Each agent gets a brief as its prompt. Requires well-defined contracts and an integration step.

```bash
codex exec "$(cat briefs/sub-task-1-api.md)" --cwd .
codex exec "$(cat briefs/sub-task-2-frontend.md)" --cwd .
```

## Decomposition patterns

**By architectural layer:** Domain → Application → Infrastructure → UI. Build contracts first, then parallel.

**By feature / vertical slice:** Each sub-task delivers one feature end-to-end. Watch for shared model conflicts.

**By bounded context / module:** Each sub-task owns a module or service. Define inter-service contracts first.

**Contracts-first (recommended default):** Sub-task #1 is always shared contracts. Everything else runs parallel against them.

## Integration phase prompt

```
All sub-tasks are done. Now integrate:
1. Merge all sub-task branches into integration branch
2. Resolve merge conflicts
3. Verify all shared contracts are implemented correctly
4. Wire components together (DI, routes, configs)
5. Run integration tests across boundaries
6. Run full test suite
7. Fix contract mismatches

Sub-tasks completed:
- [name]: [what was built, branch]
- [name]: [what was built, branch]

Shared contracts: [list]
```

## When decomposition goes wrong

| Problem | Sign | Fix |
|---|---|---|
| Too coupled | Every sub-task needs every other | Redraw boundaries |
| Contracts too vague | Lots of integration mismatches | Define as actual code signatures |
| Too small | Brief overhead exceeds the work | Merge sub-tasks |
| Too many (8+) | Coordination overhead kills gains | Merge, aim for 3–7 |
| Missing sub-task | Integration reveals unowned gap | Add sub-task or assign to integration |
| Context lost | New session misses conventions | Add project rules to each brief |
| Merge conflicts | Overlapping file modifications | Tighten scope, contracts-first |
