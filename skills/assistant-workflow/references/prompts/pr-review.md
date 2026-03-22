# Quality Review Checklist (Stage 2)

Load this during Stage 2 of the review cycle. This is the quality gate — it runs after the Spec Review confirms the implementation matches the plan.

## When to use

Run this review as part of the autonomous review-fix loop: after all build steps complete and tests pass. The loop runs up to 5 rounds, fixing must-fix and should-fix items each round until clean. You do NOT need to wait for user input between rounds.

For small tasks, do a quick pass through the "must-check" items only. For medium+ tasks, work through the full checklist.

## Multi-round context (for autonomous loop)

When dispatching the Reviewer subagent for round N > 1, prepend this context to the prompt:

```
## Previously Fixed (Round N of 5)

This is review round [N]. The following [count] items were already found
and fixed in prior rounds — do NOT re-report them:

[list each previously fixed item: "- [file:line] — [issue] (round N)"]

Focus ONLY on NEW high-confidence findings not in the above list.
Raise your confidence threshold each round:
- Round 1-2: report findings at 80%+ confidence
- Round 3-4: report findings at 85%+ confidence
- Round 5: report findings at 90%+ confidence

If you find no new issues above your confidence threshold, say "No new findings."
```

## Review process

1. Re-read the approved plan (or lightweight plan for small tasks)
2. Diff the changes: `git diff main...HEAD` (or appropriate base branch)
3. Walk through each checklist section below
4. Produce the output: issues grouped by severity

## Checklist

### Correctness (must-check)

- Does the code do what the plan says? Compare each plan step to its implementation.
- Are there plan steps that weren't implemented? (missing functionality)
- Are there code changes not in the plan? (scope creep — flag for approval)
- Do all conditional paths have tests or explicit justification for skipping?
- Edge cases from the plan's risk section — are they handled in code?

### Architecture (must-check)

- Does the change respect project layer boundaries?
  - Domain: no dependencies on Infrastructure, UI, or framework types
  - Application: depends on Domain, not on Infrastructure
  - Infrastructure: implements Application interfaces
  - UI/Presentation: depends on Application, never on Infrastructure directly
- Are new files in the correct folders per project conventions?
- Does the change follow existing patterns? (e.g., if other services use constructor DI, don't use service locator)
- Any new cross-layer dependencies introduced? (flag for review)

### Error handling

- Are failure modes handled, not just the happy path?
- Do errors return structured responses? (not raw exceptions to callers)
- Are external calls (HTTP, DB, file IO) wrapped in appropriate error handling?
- Is there retry logic where appropriate? (idempotent operations only)
- Are errors logged with enough context to diagnose? (but no PII in logs)

### Security

- No secrets, API keys, or credentials in code (including test code)
- No SQL string concatenation — parameterized queries or ORM only
- User inputs validated before use
- No PII in logs or error messages
- Auth checks present on new endpoints/actions
- No `[Authorize]` missing on controllers/actions that need it (or equivalent for your framework)

### Tests

- Do tests verify behaviour, not implementation details?
  - Good: "returns 404 when item not found"
  - Bad: "calls _repository.GetById exactly once"
- Can the tests actually fail? (mentally break the code — would the test catch it?)
- Are test names descriptive enough to understand the scenario without reading the test body?
- No hardcoded paths, ports, or timestamps that will break in CI
- No test interdependencies (order-dependent or shared mutable state)
- Missing tests: any code paths with no test coverage that should have it?

### Readability

- Clear naming: methods say what they do, variables say what they hold
- No magic numbers or strings — use named constants or enums
- Comments explain "why," not "what" (code should explain "what")
- No dead code, commented-out code, or leftover debug statements
- Consistent formatting with the rest of the codebase

### Cognitive Complexity (C# projects — auto-run)

For C# projects, run the cognitive complexity tool against changed files:

```bash
bash "<framework-tools>/cognitive-complexity/run-complexity.sh" --changed --verbose
```

Where `<framework-tools>` is the installed tools directory (typically `~/.claude/tools`, `~/.codex/tools`, or `~/.gemini/tools`).

- **Threshold: 15** (SonarSource default). Methods above this are flagged.
- Flagged methods are **must-fix** — refactor to reduce complexity before merge.
- Common fixes: extract helper methods, use early returns/guard clauses, simplify boolean expressions, replace nested conditionals with pattern matching.
- If the tool is not built/available, note it and continue with manual readability review.

**Interpreting results:**
- Score 0-5: simple, no action needed
- Score 6-15: moderate, acceptable
- Score 16-25: high — refactor recommended (must-fix in review)
- Score 26+: very high — refactor required, likely multiple concerns in one method

### Performance (medium+ tasks)

- No N+1 queries (loading related data in a loop instead of batch/join)
- No unbounded collections (missing pagination, limits, or caps)
- No blocking calls in async paths (`Task.Result`, `.Wait()`, `Thread.Sleep` in async)
- No unnecessary allocations in hot paths
- Any new database queries have appropriate indexes?
- Caching: is it needed? If used, what's the invalidation strategy?

## Output format

```markdown
### Quality Review #[N]: [task name]

**Overall:** [ready to merge / needs fixes / needs rework]

#### Must-fix (blocks merge)
1. [file:line] — [issue description]
2. ...

#### Should-fix (merge but follow up)
1. [file:line] — [issue description]
2. ...

#### Nits (optional improvements)
1. [file:line] — [suggestion]
2. ...

#### Positive notes
- [things done well worth calling out]
```

## After review (autonomous loop behavior)

- **Must-fix items:** fix immediately, then re-review (next loop round)
- **Should-fix items:** fix immediately alongside must-fix items (don't defer — our experience shows these are real issues worth fixing)
- **Nits:** do NOT fix — note them but exit the loop. Nits don't justify another round.
- **No findings:** exit loop, write Final Result: CLEAN
- **Max rounds reached with remaining must-fix:** exit loop, write Final Result: HAS REMAINING ITEMS, escalate to user
- If significant drift from plan: stop and flag for re-approval before continuing

## Review discipline — receiving feedback

When implementing fixes from the review (including self-review findings):

### Do
- **Fix silently.** The code itself shows you heard the feedback. No commentary needed.
- **Verify before implementing.** Re-read the finding against the actual codebase — is it correct for this specific project?
- **Address blocking issues first**, then simple fixes, then complex ones. Test each individually.
- **Push back with technical reasoning** when a finding is wrong — e.g., violates YAGNI, conflicts with prior decisions, or misunderstands context.
- **One fix at a time.** Apply, test, confirm, next.

### Don't
- **No performative language.** Never write "Great catch!", "You're absolutely right!", "Excellent point!" — these are noise. Just fix it.
- **No partial implementation.** If a finding is unclear, investigate fully before acting. Items may be related — partial understanding leads to wrong fixes.
- **No assumptions about intent.** If review feedback is ambiguous, clarify first (or re-read the plan).
- **No defensive responses.** If you disagree, state the technical reason and move on.

### When external review feedback arrives (from the user)

1. Read all feedback completely before acting
2. Restate the requirement in your own words (in the task journal)
3. Check each item against actual codebase state
4. Assess technical soundness for this specific project and stack
5. Implement one item at a time with testing after each
6. If feedback contradicts the plan, flag it — don't silently deviate
