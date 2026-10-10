# TDD Enforcement — Red-Green-Refactor

> **Fallback prompt pack.** If the `assistant-tdd` skill is installed, use it instead — it is more complete (includes bug fix pattern, review cycle integration, and additional rationalizations).

Load this only when the canonical `verification_decision.tdd_choice.mode` is true. User or project requirements must be resolved into that decision before applying this cycle.

## The Iron Law

For each selected TDD behavior, production changes require valid, meaningful RED first. If production code was written early, preserve it and record the ordering violation; do not delete work to manufacture a cycle.

## Red-Green-Refactor Cycle

For each selected TDD behavior:

### RED — Write a failing test

1. Add or extend one behavior assertion from authoritative expected behavior; name a plausible wrong outcome it distinguishes
2. Run it — it MUST fail
3. Verify it fails for the RIGHT reason (not a syntax error or missing import)
4. If it passes: the behaviour already exists or the test is wrong. Investigate.

### GREEN — Make it pass

1. Write the SIMPLEST code that makes the test pass
2. Do not write more code than needed — no "while I'm here" additions
3. Run the test — it must pass
4. Run selected regressions and binding project suites; do not substitute an unselected full suite.

### REFACTOR — Clean up

1. Remove duplication introduced in the GREEN step
2. Improve naming, extract methods, simplify
3. Run selected checks and binding regressions after refactoring — they must stay green
4. Do not add new behaviour during refactoring

## Verification at each transition

```
RED:      test written → test runs → test FAILS → failure reason is correct
GREEN:    code written → selected failing check passes → selected regressions and binding suites pass
REFACTOR: code cleaned → selected checks remain green → no new behaviour added
```

## When to apply

Verification scope and TDD are separate decisions. These task categories do not activate TDD by themselves. Follow the verifier's TDD choice; an active binding requirement must be resolved before work continues.

## Common rationalizations (rejected)

| Excuse | Why it's wrong |
|---|---|
| "The planned test passes before implementation" | Inspect whether behavior already exists or the test is wrong; characterize current behavior rather than fabricate RED |
| "The failure is an import, environment, or flaky error" | It is not valid RED; diagnose or record a blocker |
| "A broader suite is always safer" | Run selected checks and binding regressions; retain exclusions and gaps |

## Task journal integration

When TDD is active, the task journal Progress section should show the cycle:

```markdown
- [x] Step 1: User registration endpoint
  - RED: test_register_valid_user — fails (no endpoint)
  - GREEN: POST /api/users returns 201 — test passes
  - REFACTOR: extracted validation to UserValidator — all tests pass
```

## Activation

Carry the verifier's decision into the plan or task journal; do not add a local activation flag that conflicts with it.
```
- TDD: active (Red-Green-Refactor enforced)
```

When active, Review checks meaningful RED/GREEN/REFACTOR evidence for selected TDD behaviors. It does not require one test per function or infer activation from task type.
