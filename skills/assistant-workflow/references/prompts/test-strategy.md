# Test Strategy Prompt

Load this during Phase 2 (Plan) for any task that introduces new code paths. Think about what to test before writing code — this produces a test plan that becomes part of the implementation plan.

## When to use

Use for any task that adds or changes:
- Business logic or domain rules
- API endpoints or request handling
- Data access or query logic
- User-facing workflows
- Integration points with external services
- State machines or conditional flows

Skip for: documentation-only changes, config tweaks with no logic, pure CSS/styling.

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

List every behaviour — including error cases, edge cases, and the "nothing should happen" scenarios.

## Step 2: Classify test sizes

For each behaviour, decide the appropriate test size:

| Size | Characteristics | When to use |
|---|---|---|
| **Unit** | Fast (<100ms), no IO, no DB, no network. Mock external dependencies. | Pure logic, calculations, validations, domain rules, mapping |
| **Integration** | Uses real DB, real file system, or real service. Slower but higher confidence. | Data access, DI wiring, API request/response pipeline, config loading |
| **E2E** | Full stack running. Tests the complete user flow. Slowest, most brittle. | Critical user journeys only. Keep few. |

**Rule of thumb:** Unit by default. Promote to integration only when the behaviour depends on infrastructure. Promote to E2E only for critical happy-path flows.

### Assignment table

| # | Behaviour | Size | Why |
|---|---|---|---|
| 1 | [behaviour description] | Unit / Integration / E2E | [brief justification] |
| 2 | ... | ... | ... |

## Step 3: Decide what to mock

| Dependency | Mock or Real | Reason |
|---|---|---|
| Database | Mock for unit, real for integration | Unit tests shouldn't need DB setup |
| HTTP clients | Mock always (unless testing the integration itself) | External services are unreliable and slow |
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

If a risk has no test, either add one or document why it's accepted without test coverage.

## Step 5: Flake prevention rules

Every test must follow these rules:

- **No time-dependence:** Don't assert on `DateTime.Now` or elapsed time. Inject a clock and control it.
- **No order-dependence:** Tests must pass in any order. No test should depend on another test running first.
- **No shared mutable state:** Each test sets up its own data. Use fresh DB contexts, not shared fixtures that accumulate state.
- **No external network calls:** Mock or use recorded responses (WireMock, HttpMessageHandler fakes).
- **No hardcoded ports or paths:** Use dynamic port allocation and temp directories.
- **No `Thread.Sleep` or `Task.Delay` for synchronization:** Use proper async waits, polling with timeout, or event-based synchronization.
- **Deterministic data:** Use fixed seeds for random data, fixed dates for time-based logic.

## Output format

Add this block to the implementation plan:

```markdown
### Test Plan

**Behaviours to test:** [total count]
**Breakdown:** [N] unit, [N] integration, [N] E2E

| # | Behaviour | Size | Mocking | Notes |
|---|---|---|---|---|
| 1 | [When X, then Y] | Unit | [what's mocked] | |
| 2 | [When X, then Y] | Integration | Real DB | |
| 3 | [When X, then Y] | E2E | None | Critical path |

**Risk-driven tests:**
| Risk | Test | Size |
|---|---|---|
| [from plan] | [test description] | [size] |

**Test commands:**
- Unit: `dotnet test --filter "Category=Unit"` (or equivalent)
- Integration: `dotnet test --filter "Category=Integration"`
- E2E: [project-specific command]

**Flake prevention:** Clock injected via [mechanism], no shared state, no external calls.
```
