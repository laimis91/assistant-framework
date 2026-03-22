# TDD Enforcement — Red-Green-Refactor

> **Fallback prompt pack.** If the `assistant-tdd` skill is installed, use it instead — it is more complete (includes bug fix pattern, review cycle integration, and additional rationalizations).

Load this when the plan calls for TDD, the user requests it, or the project conventions require tests-first.

## The Iron Law

No production code without a failing test first. If you write code before its test, **delete the code** and start with the test. This is not negotiable — code written before tests has unknown coverage and cannot be trusted.

## Red-Green-Refactor Cycle

For each behaviour in the test plan:

### RED — Write a failing test

1. Write ONE test that describes the desired behaviour
2. Run it — it MUST fail
3. Verify it fails for the RIGHT reason (not a syntax error or missing import)
4. If it passes: the behaviour already exists or the test is wrong. Investigate.

### GREEN — Make it pass

1. Write the SIMPLEST code that makes the test pass
2. Do not write more code than needed — no "while I'm here" additions
3. Run the test — it must pass
4. Run ALL tests — nothing else should break

### REFACTOR — Clean up

1. Remove duplication introduced in the GREEN step
2. Improve naming, extract methods, simplify
3. Run ALL tests after each refactoring — they must stay green
4. Do not add new behaviour during refactoring

## Verification at each transition

```
RED:      test written → test runs → test FAILS → failure reason is correct
GREEN:    code written → failing test PASSES → all other tests still pass
REFACTOR: code cleaned → all tests still pass → no new behaviour added
```

## When to apply

**Always use TDD for:**
- New features with defined acceptance criteria
- Bug fixes (write the failing test that reproduces the bug first)
- Refactors that change interfaces (characterization tests first)

**Exceptions (require explicit user approval to skip):**
- Throwaway prototypes / spikes
- Generated code (scaffolding, migrations)
- Configuration-only changes
- UI layout / styling with no logic

## Common rationalizations (rejected)

| Excuse | Why it's wrong |
|---|---|
| "Tests after achieve the same thing" | Tests-first discover requirements; tests-after verify remembered cases |
| "I already tested it manually" | Manual testing is unrepeatable and incomplete |
| "Deleting working code is wasteful" | Unverified code is technical debt, not an asset |
| "TDD slows me down" | TDD is faster than production debugging |
| "This is too simple to need a test" | Simple code becomes complex code. The test documents intent. |

## Task journal integration

When TDD is active, the task journal Progress section should show the cycle:

```markdown
- [x] Step 1: User registration endpoint
  - RED: test_register_valid_user — fails (no endpoint)
  - GREEN: POST /api/users returns 201 — test passes
  - REFACTOR: extracted validation to UserValidator — all tests pass
```

## Activation

Add to the plan or task journal constraints:
```
- TDD: active (Red-Green-Refactor enforced)
```

When active, the review cycle checks that every new function has a corresponding test that was written BEFORE the implementation.
