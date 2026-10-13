# Test Strategy Prompt

Load this during Plan only when `assistant-verification` selected automated tests. Use authoritative requirements and accepted behavior as the oracle; verification selection decides whether tests, another method, or both are appropriate.

## When to use

Use when the selected verification decision includes automated tests for:
- Business logic or domain rules
- API endpoints or request handling
- Data access or query logic
- User-facing workflows
- Integration points with external services
- State machines or conditional flows

Do not activate tests from this prompt alone. If tests are not selected, record the selected method and its concrete procedure in the plan.

## Step 1: Identify behaviours, not code

List the behaviours this change introduces. Think from the user's or caller's perspective, not from the implementation.

**Format:**

```
When [precondition], and [action], then [expected outcome].
```

**Examples:**
- When a valid order is submitted, then the order is saved and a confirmation email is queued.
- When an unauthenticated user hits /api/orders, then they receive a 401 response.
- When the payment gateway times out, then the order is marked as pending and a retry is scheduled.

List only material behaviors and boundaries in the approved scope. For each selected test, name a plausible wrong outcome it must distinguish; do not create phrase-matching assertions or expand scope.

## Step 2: Record selected test scopes

For each selected automated check, retain its CheckSpec `test_scope`. Use this table to describe that boundary, not to select a different scope:

| Size | Characteristics | When to use |
|---|---|---|
| **Unit** | Fast (<100ms), no IO, no DB, no network. Mock external dependencies. | Pure logic, calculations, validations, domain rules, mapping |
| **Integration** | Uses real DB, real file system, or real service. Slower but higher confidence. | Data access, DI wiring, API request/response pipeline, config loading |
| **E2E** | Full stack running. Tests the complete user flow. | The selected user journey, including its selected positive or negative paths. |

Preserve the selected check's claim, boundary and oracle. Return a material gap or policy conflict to `assistant-verification`; do not reselect scope or add layers here.

### Assignment table

| # | Behaviour | Size | Why |
|---|---|---|---|
| 1 | [behaviour description] | Unit / Integration / E2E | [brief justification] |
| 2 | ... | ... | ... |

## Step 3: Decide what to mock

Implement the carried CheckSpec's prerequisites and exclusions. The guidance below applies only where it preserves the selected observation; a substitute cannot prove a real boundary it does not exercise.

| Dependency | Mock or Real | Reason |
|---|---|---|
| Database | Mock for unit, real for integration | Unit tests shouldn't need DB setup |
| HTTP clients | Substitute only when the CheckSpec permits it; retain a selected real-service boundary | Recorded or mocked responses do not establish real-service integration |
| File system | Mock for unit, real for integration | Avoid test pollution across runs |
| Time / clock | Mock always | Deterministic tests, no flakiness |
| Random / GUIDs | Mock when output matters | Deterministic assertions |
| Logging | Real (verify log calls if critical) | Logging rarely needs mocking |
| DI container | Real for integration | Tests should verify real wiring |

**Mocking philosophy:** Mock at boundaries, not at implementation details. If you're mocking a class you own and it's in the same layer, you're probably testing implementation, not behaviour.

## Step 4: Edge cases from risks

Pull edge cases directly from the plan's "Risks / edge cases" section:

| Risk from plan | Test to cover it | Size |
|---|---|---|
| [risk description] | [test that would catch it] | [unit/integration] |

Use the method selected for the risk. Add a test only when selected; otherwise record the concrete non-test procedure and evidence needed. A targeted mutation is appropriate only to resolve a specific oracle concern, not as a blanket requirement.

## Step 5: Flake prevention rules

Apply these isolation rules without changing the selected claim or boundary:

- **No time-dependence:** Don't assert on `DateTime.Now` or elapsed time. Inject a clock and control it.
- **No order-dependence:** Tests must pass in any order. No test should depend on another test running first.
- **No shared mutable state:** Each test sets up its own data. Use fresh DB contexts, not shared fixtures that accumulate state.
- **External network boundaries:** Use mocks or recorded responses only where the CheckSpec permits substitutes. Exercise a selected real service within approved access and isolated data. If it is prohibited or unavailable, record the gap and return it to the existing owner; do not silently replace the boundary.
- **No hardcoded ports or paths:** Use dynamic port allocation and temp directories.
- **No `Thread.Sleep` or `Task.Delay` for synchronization:** Use proper async waits, polling with timeout, or event-based synchronization.
- **Deterministic data:** Use fixed seeds for random data, fixed dates for time-based logic.

## Output format

When tests are selected, include their test plan within the verification plan. The plan must preserve the canonical decision and may use this format:

```markdown
### Selected Verification Plan

**Decision:** [canonical verification decision reference]
**Selected checks:** [check id, claim, method, and evidence required]
**Omitted checks:** [decision rationale; none invented]
**Automated tests:** [only the selected test checks, or none]

| # | Behaviour | Size | Mocking | Notes |
|---|---|---|---|---|
| 1 | [When X, then Y] | Unit | [what's mocked] | |
| 2 | [When X, then Y] | Integration | Real DB | |
| 3 | [When X, then Y] | E2E | None | Critical path |

**Risk-driven checks:**
| Risk or claim | Selected method | Evidence |
|---|---|---|
| [from plan] | [test description] | [size] |

**Commands or procedures:**
- Command-based checks record exact argv and cwd.
- Non-command checks record the concrete steps and observed result.

**Oracle:** [authoritative expected behavior and plausible wrong outcome each selected test distinguishes]
**Focused mutation, if needed:** [specific oracle concern and targeted mutation; otherwise none]
```
