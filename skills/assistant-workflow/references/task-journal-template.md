# Task Journal Template

Write to `.claude/task.md` in the project root. This file is the single source of truth for the current task — it survives context compression and session continuations.

## When to create
- Any task that enters clarification wait: during Discover, before printing clarification questions or the wait message
- Medium+: during Discover, before leaving Discover even when no clarification wait is needed
- Small tasks without clarification wait: optional unless the task is multi-step

## When to update
- When clarification questions are asked, answered, or resolved via explicit `defaults`
- After each Build step completes (update Progress, Artifact Registry, and check off Milestones)
- When key decisions are made
- When constraints are added by the user
- After each review cycle pass (append to Review Log — never overwrite)
- At verification summary (all steps done)
- During user review feedback

## Template

```markdown
## Task: [1-sentence description]
Status: DISCOVERING | DECOMPOSING | PLANNING | BUILDING [step N/M] | REVIEWING | DOCUMENTING | DONE
Triaged as: [small | medium | large | mega]
Task type: [feature | bugfix | refactor | migration | rewrite | config | infra | security | docs | spike]
Risk tier: [low | moderate | high | critical]
Clarification status: [ready | needs_clarification]
Clarification defaults applied: [true | false]
Clarification confidence: [low | medium | high]
Clarification questions asked: [0+]
Clarification question cap: [0+; maximum, not quota]
Clarification admissibility: [satisfied | needs_clarification | not_applicable]
Unresolved clarification topics:
- [none, or one short topic per line]
Required gates:
- [common gate or task-category gate from references/triage-rubric.md]
Required agents:
- [workflow role or skill required by size/risk/type]
Plan approval: [yes/no + date]

## Constraints
- [user-stated boundaries, e.g. "Do not modify ProjectA"]
- [technical constraints, e.g. "Must stay on .NET 8"]
- [scope limits, e.g. "Backend only, no UI changes"]

## Plan
[paste approved plan verbatim — include component manifest for medium+ tasks, plus steps with file paths]

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

## Component Verification Ledger
[required for medium+ tasks; update after each component before starting the next]
| Component | Task Packet | RED Status | Implementation Status | Verification Command/Result | Criteria Checked | Self-Check Result | Final Status |
|-----------|-------------|------------|-----------------------|-----------------------------|------------------|-------------------|--------------|
| C1: [name] | [packet id] | [pass/fail/N/A] | [done/blocked] | `[command]` → [pass/fail + signal] | [X/Y passed] | [pass/fail + note] | [VERIFIED/BLOCKED] |

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
- Result: PASS | FAIL
- Scope reviewed: [plan step(s), task packet(s), or component(s)]
- Missing acceptance criteria: [none, or list]
- Extra scope: [none, or list with file paths and disposition]
- Changed files mismatch: [none, or expected vs actual]
- Verification evidence mismatch: [none, or expected vs actual]
- Required fixes: [none, or ordered fix list]

### Quality Review #1
- Round: 1 of 5
- Previously fixed: 0 items from prior rounds
- Found this round: [count] must-fix, [count] should-fix, [count] nits (all fixed below)
- Rubric: correctness=[score] quality=[score] architecture=[score] security=[score] coverage=[score]
- Weighted: [score]
- Delta from previous: — (first round)
- Drift check: — (first round)
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
- Rubric: correctness=[score] quality=[score] architecture=[score] security=[score] coverage=[score]
- Weighted: [score]
- Delta from previous: [+/- amount]
- Drift check: [GENUINE / SUSPICIOUS / DRIFT / REGRESSION / STAGNATION / NEUTRAL]
- Must-fix:
  - [x] [file:line] — [issue] → [fix applied]
- Should-fix:
  - [x] [file:line] — [issue] → [fix applied or "deferred"]
- Re-test: PASS

[...repeat until clean or max rounds reached...]
[Note: On test failure, skip this entry — write only "- Result: HAS_REMAINING_ITEMS" to Final result]

### Final result
- Result: CLEAN | ISSUES_FIXED | HAS_REMAINING_ITEMS
- Review rounds: [count]
- Final rubric score: [weighted score] ([PASS/REFINE/PIVOT])
- Score progression: [round1→round2→...roundN] (e.g., 3.50→3.85→4.10)
- Drift incidents: [count, or "none"]
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

1. **Created** during Discover when clarification state must be tracked. Any task that enters clarification wait creates it before the wait; medium+ tasks also create it before leaving Discover even when no clarification wait is needed.
2. **Triage metadata** — record `Task type`, `Risk tier`, `Required gates`, and `Required agents` before leaving Triage. Discovery may re-triage these fields when code/context evidence changes the risk or required gates.
3. **Clarification** updates — question caps are maximums, not quotas. Clear medium+ tasks may record `Clarification questions asked: 0` with `Clarification confidence: high`. While waiting, keep `Status: DISCOVERING`, set `Clarification status: needs_clarification`, set `Clarification defaults applied: false`, set confidence/cap/admissibility fields, and list every unresolved implementation-shaping topic. On explicit answers, clear unresolved topics, keep `Clarification defaults applied: false`, and set `Clarification status: ready`. On explicit `defaults`, print the applied defaults, clear unresolved topics, set `Clarification defaults applied: true`, and set `Clarification status: ready`.
4. **Decompose** — medium+ tasks set `Status: DECOMPOSING` after Discover is ready, then persist the component manifest before moving on to planning. Small tasks skip this state.
5. **Plan approval** — once ready to plan, set `Status: PLANNING`, include the component manifest in the plan for medium+ tasks, capture the approved plan, and update `Plan approval`.
6. **Build** each step — update Progress, Artifact Registry, Key Decisions, Status after each step. For medium+ tasks, update the Component Verification Ledger after each component and do not start the next component until the current one is `VERIFIED`. Check off Milestones when reached.
7. **Review cycle** when all steps done — Spec Review first (structured PASS/FAIL from `references/prompts/spec-review.md`), then Quality Review (assistant-review quality loop), fix must-fix → re-test → re-review until clean, fill Final Result
8. **Document** after review cycle passes — fill Verification Summary, Status: DOCUMENTING
9. **Handoff** to user — they test manually and add Review Notes
10. **Review fixes** — fix issues, re-test, re-review, update Progress
11. **Done** — Status: DONE, promote insights to memory, delete file

## Rules

- Keep entries concise — this is a log, not documentation
- Resume from clarification waits only on explicit numbered answers or explicit `defaults`
- Constraints are checked before each Build step
- On context continuation: read `.claude/task.md` FIRST, before any other action
- Never delete constraints unless the user explicitly removes them
- The Verification Summary replaces the need for context-handoff templates during active work
