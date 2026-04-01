---
name: assistant-tdd
description: "This skill enforces Test-Driven Development with Red-Green-Refactor cycle and strict verification gates. Use when the user says 'tests first', 'test-driven', 'TDD', 'write the test first', 'red green refactor'. Also activates when project conventions require tests-first development."
effort: high
triggers:
  - pattern: "tdd|tests? first|test.driven|red green refactor|write the test first"
    priority: 85
    reminder: "This request matches assistant-tdd. You MUST invoke the Skill tool with skill='assistant-tdd' BEFORE writing any production code."
---

# Test-Driven Development

## Contracts

This skill enforces strict gate assertions at every RED → GREEN → REFACTOR transition.

| Contract | File | Purpose |
|---|---|---|
| **Input** | `contracts/input.yaml` | Behaviors to implement, test framework, exceptions |
| **Output** | `contracts/output.yaml` | Cycle log with verified pass/fail at each phase |
| **Phase Gates** | `contracts/phase-gates.yaml` | RED/GREEN/REFACTOR transition assertions + invariants |
| **Handoffs** | `contracts/handoffs.yaml` | Subagent dispatch contracts (currently none; workflow owns TDD handoffs) |

**Rules:**
- Check phase gate assertions at every transition (RED→GREEN, GREEN→REFACTOR, REFACTOR→next RED)
- Every cycle must have verified test execution results (not assumed)
- No production code without a preceding failing test — this is structurally enforced, not advisory

Enforces the Red-Green-Refactor cycle. When active, no production code is written without a failing test first.

## The Iron Law

No production code without a failing test first. If you write code before its test, **delete the code** and start with the test. This is not negotiable — code written before tests has unknown coverage and cannot be trusted.

## Activation

This skill activates when:
- The user explicitly requests TDD ("use TDD", "tests first", "red green refactor")
- The plan includes `TDD: active` in constraints
- The project's CLAUDE.md or conventions require tests-first

When active, add to the task journal constraints:
```
- TDD: active (Red-Green-Refactor enforced)
```

## The Cycle

For each behaviour or plan step:

### RED — Write a failing test

1. Write ONE test that describes the desired behaviour
2. Run it — it **MUST** fail
3. Verify it fails for the **RIGHT reason** (not a syntax error or missing import)
4. If it passes: the behaviour already exists or the test is wrong. Investigate.

### GREEN — Make it pass

1. Write the **SIMPLEST** code that makes the test pass
2. Do not write more code than needed — no "while I'm here" additions
3. Run the test — it must pass
4. Run **ALL** tests — nothing else should break

### REFACTOR — Clean up

1. Remove duplication introduced in the GREEN step
2. Improve naming, extract methods, simplify
3. Run ALL tests after each refactoring — they must stay green
4. Do not add new behaviour during refactoring

## Verification gates

Each transition has a gate that must pass before proceeding:

```
RED:      test written → test runs → test FAILS → failure reason is correct
GREEN:    code written → failing test PASSES → all other tests still pass
REFACTOR: code cleaned → all tests still pass → no new behaviour added
```

**Never skip a gate.** If the test doesn't fail in RED, stop. If other tests break in GREEN, stop. If tests fail after REFACTOR, undo and try again.

## When to apply

**Always use TDD for:**
- New features with defined acceptance criteria
- Bug fixes (write the failing test that reproduces the bug first)
- Refactors that change interfaces (characterization tests first)
- Any behaviour in the test plan from `assistant-workflow`

**Exceptions (require explicit user approval to skip):**
- Throwaway prototypes / spikes
- Generated code (scaffolding, migrations)
- Configuration-only changes
- UI layout / styling with no logic

## Bug fix pattern

Bug fixes get their own TDD variant:

1. **Reproduce**: write a test that demonstrates the bug (RED — test fails showing the bug exists)
2. **Fix**: make the minimal change to fix the bug (GREEN — test passes)
3. **Protect**: verify no regressions, refactor if needed (REFACTOR — all tests green)

This ensures the bug can never silently return.

## Common rationalizations (rejected)

These excuses are not valid reasons to skip TDD:

| Excuse | Why it's wrong |
|---|---|
| "Tests after achieve the same thing" | Tests-first discover requirements; tests-after verify remembered cases |
| "I already tested it manually" | Manual testing is unrepeatable and incomplete |
| "Deleting working code is wasteful" | Unverified code is technical debt, not an asset |
| "TDD slows me down" | TDD is faster than production debugging |
| "This is too simple to need a test" | Simple code becomes complex code. The test documents intent. |
| "I'll add the test right after" | "After" becomes "never." Write it now. |

## Task journal integration

When TDD is active, the task journal Progress section must show the cycle for each step:

```markdown
- [x] Step 1: User registration endpoint
  - RED: test_register_valid_user — fails (no endpoint exists)
  - GREEN: POST /api/users returns 201 — test passes
  - REFACTOR: extracted validation to UserValidator — all tests pass
- [x] Step 2: Duplicate email rejection
  - RED: test_register_duplicate_email — fails (no uniqueness check)
  - GREEN: returns 409 on duplicate — test passes
  - REFACTOR: moved email check to domain service — all tests pass
```

## Review cycle integration

When TDD is active, the Spec Review (Stage 1) adds an extra check:
- Every new public method/endpoint has a corresponding test
- Tests were written BEFORE implementation (verify via commit history or task journal RED entries)
- No production code exists without a matching test

## Pairing with assistant-workflow

This skill enhances the Build loop in `assistant-workflow`:
- Step 6 in the Build loop activates Red-Green-Refactor per plan step
- The test plan from `references/prompts/test-strategy.md` defines the behaviours to TDD
- The review cycle verifies TDD discipline was maintained

## Quick reference

```
1. Pick next behaviour from test plan
2. RED:      write test → run → must FAIL → right reason?
3. GREEN:    write code → run → must PASS → all tests pass?
4. REFACTOR: clean up → run → still PASS → no new behaviour?
5. Log RED/GREEN/REFACTOR in task journal
6. Repeat from 1
```
