# Context Handoff Templates

Use these when continuing work across conversations. Ask the AI to generate the appropriate summary before ending a session.

**Note:** If a task journal (`.claude/task.md`) exists, it supersedes these templates during active work — the journal already contains the full task state. Use these templates only when no task journal exists or for non-standard handoff scenarios.

## Prompt to generate a handoff summary

```
Summarize our progress in a compact format I can paste into a new
conversation to continue without losing context. Use the appropriate
handoff template.
```

## Template 1: Continuing a session

When continuing work in a new conversation:

```
Continuing work on [project name].

Previous session summary:
- Requirements: [restated from Discovery]
- Key decisions: [from Q&A]
- Plan status: [which steps are done, which remain]
- Current phase: [where we left off]
- Known issues: [anything flagged during build]

[Include relevant file paths]

Continue from [specific step or phase].
```

## Template 2: Mid-Build handoff

When context is getting long during implementation:

```
Continuing Build on [project name].

Requirements: [1-3 sentence summary]
Architecture: [pattern in use]

Plan steps completed:
- Step 1: [done — what was built]
- Step 2: [done — what was built]
- Step 3: [in progress / next up]
- Step 4-N: [remaining]

Test results so far:
- [what passed]
- [what failed, if any]

Known issues:
- [any flagged problems]

Files changed so far:
- [file]: [brief description of change]
- [file]: [brief description of change]

[Include relevant file paths]

Continue from step [N].
```

## Template 3: Starting a sub-task session

When starting a decomposed sub-task:

```
[Paste the Sub-Task Brief from the decomposition phase]

The repo is attached. Run the standard workflow:
Plan → [Design if UI] → Build.

Follow project conventions. Do not modify files outside your scope.
Work on branch: [branch name].
```

## Template 4: Integration session

When all sub-tasks are done:

```
Integration phase for [project name].

Completed sub-tasks:
1. [name]: [what was built, key files changed, branch]
2. [name]: [what was built, key files changed, branch]
3. [name]: [what was built, key files changed, branch]

Shared contracts: [list interfaces/DTOs/schemas]

Integrate:
1. Merge all sub-task branches into integration branch
2. Resolve conflicts
3. Verify all contracts are correctly implemented
4. Wire components together (DI, routes, configs)
5. Run full integration test suite
6. Fix mismatches

[Include relevant file paths]
```

## Template 5: Discovery handoff

When Discovery Q&A spans sessions:

```
Continuing Discovery for [project name].

What we've clarified so far:
- [Q&A question]: [answer chosen]
- [Q&A question]: [answer chosen]

Still open:
- [unanswered question or area of ambiguity]

Key files found:
- [file path]: [what it contains / why it matters]

[Include relevant file paths]

Continue Discovery — ask remaining questions.
```
