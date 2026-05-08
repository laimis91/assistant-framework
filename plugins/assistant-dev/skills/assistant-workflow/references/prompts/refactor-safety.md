# Refactor Safety Prompt

Load this during Phase 3 (Plan) when the task is a refactor — restructuring code without changing its external behaviour. Produces a "refactor safety contract" that defines what must not change and how to verify it.

## When to use

Use when the task is any of:
- Moving code between files, folders, or layers
- Renaming classes, methods, or namespaces
- Extracting interfaces, services, or components
- Changing internal data structures while keeping external APIs the same
- Replacing a library or pattern with an equivalent
- Consolidating duplicate code

Skip for: tasks that intentionally change behaviour (those are features or fixes, not refactors).

## Before: Capture current behaviour

Before touching any code, document what the system does today. This becomes the baseline to verify against after the refactor.

### Public API surface

List everything external consumers depend on:

| API | Signature / shape | Notes |
|---|---|---|
| [endpoint / method / event / config] | [return type, params, status codes] | [any contract callers depend on] |

### Existing test outputs

Run the full test suite and record the results:

```bash
# Record baseline
dotnet test --logger "trx" --results-directory ./refactor-baseline/
# or: npm test 2>&1 | tee refactor-baseline.log
# or: pio test 2>&1 | tee refactor-baseline.log
```

- Total tests: [N]
- Passing: [N]
- Failing: [N] — (if any already fail, note them as pre-existing)
- Skipped: [N]

### Observable behaviour snapshot

For areas not covered by tests, capture current behaviour manually:

- API responses: `curl` key endpoints and save responses
- UI states: screenshot critical screens
- CLI output: run key commands and save output
- Database state: note current schema version and row counts for affected tables

## Invariants: define what must not change

Explicitly list what the refactor must preserve:

### Hard invariants (breaking any of these means the refactor failed)

- [ ] Public API signatures unchanged (method names, parameters, return types)
- [ ] Database schema unchanged (tables, columns, types, constraints)
- [ ] Configuration format unchanged (appsettings keys, env var names)
- [ ] External service contracts unchanged (HTTP endpoints, message formats)
- [ ] Build output unchanged (assembly names, entry points, published artifacts)
- [ ] All existing tests continue to pass without modification

### Soft invariants (acceptable to change with justification)

- Internal method signatures (callers are within the refactored scope)
- File and folder structure (if the move is the point of the refactor)
- Internal naming (if the rename is the point of the refactor)
- Test helper utilities (if tests need to adapt to new internal structure)

### Things explicitly allowed to change

- [List what the refactor is intentionally restructuring]
- [e.g., "class locations move from Services/ to Application/Services/"]

## After: verification plan

After the refactor is complete, verify every invariant:

### Automated verification

```bash
# 1. Build must pass
dotnet build  # or npm run build / pio run

# 2. All tests must pass with same results as baseline
dotnet test

# 3. Compare test counts (no tests accidentally lost)
# Baseline: [N] total, [N] passing
# After: [N] total, [N] passing — must match

# 4. If applicable: API contract check
# Compare OpenAPI spec before/after (no schema drift)
```

### Manual verification

- [ ] Confirm public API responses match baseline snapshots
- [ ] Confirm UI behaviour matches baseline screenshots
- [ ] Confirm config/env vars still load correctly
- [ ] Confirm DI container resolves all services (app starts without runtime errors)

## Regression tests

Specific tests that would catch accidental behaviour changes:

| What could break | Test to verify | Command |
|---|---|---|
| [public method moved] | [existing unit test still calls it] | `dotnet test --filter "ClassName"` |
| [DI registration changed] | [integration test that resolves the service] | `dotnet test --filter "Category=Integration"` |
| [namespace renamed] | [build passes, no unresolved references] | `dotnet build` |
| [config key moved] | [app starts and reads config correctly] | [manual or integration test] |

## Output format

Add this block to the plan as the "Refactor Safety Contract" section:

```markdown
### Refactor Safety Contract

**What's changing:** [one-line description of the restructuring]
**What must not change:** [one-line description of preserved behaviour]

**Baseline:**
- Tests: [N] passing, [N] total
- API surface: [count] public endpoints/methods — signatures locked
- Schema: [version or "no DB changes"]
- Config: [count] keys — names and structure locked

**Hard invariants:**
- [ ] [list each]

**Verification commands:**
1. `dotnet build` — compiles without errors
2. `dotnet test` — all [N] tests pass
3. [additional verification steps]

**Rollback:** If invariants break and can't be quickly fixed, `git checkout` the pre-refactor state. The refactor is atomic — partial completion is not acceptable.
```
