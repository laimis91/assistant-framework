# Task Journal Template

Write to `.claude/task.md` in the project root. This file is the single source of truth for the current task — it survives context compression and session continuations.

## When to create
- At plan approval (Phase 2 gate passed)
- Small tasks: optional (only if multi-step)
- Medium+: always

## When to update
- After each Build step completes (update Progress, Artifact Registry, and check off Milestones)
- When key decisions are made
- When constraints are added by the user
- After each review cycle pass (append to Review Log — never overwrite)
- At verification summary (all steps done)
- During user review feedback

## Template

```markdown
## Task: [1-sentence description]
Status: BUILDING [step N/M] | VERIFYING | REVIEWING | DONE

## Constraints
- [user-stated boundaries, e.g. "Do not modify ProjectA"]
- [technical constraints, e.g. "Must stay on .NET 8"]
- [scope limits, e.g. "Backend only, no UI changes"]

## Plan
[paste approved plan verbatim — steps with file paths]

## Key Decisions
- [decision]: [why] (Step N)

## Artifact Registry
[track every file created or modified — survives compression, prevents file-tracking loss]
| File | Purpose | Last Step |
|------|---------|-----------|
| [path] | [what and why] | Step N |

## Milestones
[compression-safe boundaries — each marks a point where context can be safely truncated]
- [ ] M1: [milestone description] (after Step N)
- [ ] M2: [milestone description] (after Step N)

## Progress
- [x] Step 1: [what was done, files changed]
- [x] Step 2: [what was done, files changed]
- [ ] Step 3: [next]

## Test Coverage
- Unit: [what's covered]
- Integration: [what's covered, or "N/A"]
- E2E: [what's covered, or "N/A"]

## Verification Summary
[filled after all build steps complete]

### What changed
- [file]: [what and why]

### What's tested
- [test]: [what it verifies]

### Manual test instructions
1. [step-by-step for the user to verify]

### Known limitations
- [anything not covered or deferred]

## Review Log
[append an entry each time a review stage runs — never overwrite previous entries]

### Spec Review #1
- Plan alignment: matches | minor drift | significant drift
- Missing items: [none, or list]
- Scope creep: [none, or list with disposition]

### Quality Review #1
- Round: 1 of 5
- Previously fixed: 0 items from prior rounds
- Found this round: [count] must-fix, [count] should-fix, [count] nits (all fixed below)
- Complexity: [ran / skipped (not C#) / tool unavailable]
  - [method (line N): score X — refactored to Y, or "within threshold"]
- Must-fix:
  - [x] [file:line] — [issue] → [fix applied]
- Should-fix:
  - [x] [file:line] — [issue] → [fix applied or "deferred"]
- Re-test: PASS

### Quality Review #2 (autonomous re-review)
- Round: 2 of 5
- Previously fixed: [count] items from prior rounds
- Found this round: [count] must-fix, [count] should-fix, [count] nits (all fixed below)
- Must-fix:
  - [x] [file:line] — [issue] → [fix applied]
- Should-fix:
  - [x] [file:line] — [issue] → [fix applied or "deferred"]
- Re-test: PASS

[...repeat until clean or max rounds reached...]
[Note: On test failure, skip this entry — write only "- Result: HAS REMAINING ITEMS" to Final result]

### Final result
- Result: CLEAN | ISSUES FIXED | HAS REMAINING ITEMS
- Review rounds: [count]
- Total must-fix resolved: [count across all rounds]
- Total should-fix resolved: [count across all rounds]
- Should-fix deferred: [list any remaining]
- Nits noted: [count, not fixed]

## Review Notes
[filled during user review / handoff]
- [ ] [issue or change request]
- [ ] [issue or change request]
```

## Lifecycle

1. **Created** at plan approval — Status: BUILDING [1/N]
2. **Build** each step — update Progress, Artifact Registry, Key Decisions, Status after each step. Check off Milestones when reached.
3. **Review cycle** when all steps done — Spec Review first (plan alignment), then Quality Review (pr-review.md checklist), fix must-fix → re-test → re-review until clean, fill Final Result
4. **Verification** after review cycle passes — fill Verification Summary, Status: VERIFYING
5. **Handoff** to user — they test manually and add Review Notes
6. **Review fixes** — fix issues, re-test, re-review, update Progress
7. **Done** — Status: DONE, promote insights to memory, delete file

## Rules

- Keep entries concise — this is a log, not documentation
- Constraints are checked before each Build step
- On context continuation: read `.claude/task.md` FIRST, before any other action
- Never delete constraints unless the user explicitly removes them
- The Verification Summary replaces the need for context-handoff templates during active work
