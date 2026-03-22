# Release Notes Generator

Load this during Phase 5 (Document) to produce user-facing release notes from the plan and implementation. The output is a draft for human review — never publish without a person reading it.

## When to use

Use for any task that produces user-facing changes:
- New features or capabilities
- Bug fixes that users would notice
- Performance improvements
- Breaking changes or deprecations
- Configuration or setup changes

Skip for: internal refactors with no user-visible impact (those get CHANGELOG entries like "Internal: refactored X", not full release notes).

## Process

### 1. Gather sources

Collect these before writing:

- **The plan:** What was the goal? What approach was chosen?
- **Git diff:** `git diff main...HEAD --stat` for changed files, `git log main...HEAD --oneline` for commit messages
- **Test results:** What new tests were added? What do they verify?
- **Migration notes:** Any schema changes, config changes, or setup steps?

### 2. Classify changes

Sort every change into exactly one category:

| Category | What goes here |
|---|---|
| **Features** | New capabilities, new endpoints, new UI elements |
| **Improvements** | Better performance, better UX, better error messages |
| **Fixes** | Bug corrections, crash fixes, data integrity fixes |
| **Breaking changes** | API changes, removed features, config format changes, minimum version bumps |
| **Deprecations** | Features still working but scheduled for removal |

**Rules:**
- A single task can produce changes in multiple categories
- Every item must be actionable or informative for the reader
- Don't include internal implementation details the user doesn't care about
- If there are breaking changes, they go first — users need to see these immediately

### 3. Write in user language

Translate technical changes into language your users understand.

**Bad:** "Refactored OrderService to use CQRS pattern with MediatR handlers"
**Good:** "Order processing is now faster and more reliable under high load"

**Bad:** "Added null check on line 47 of PaymentController"
**Good:** "Fixed a crash that could occur when submitting a payment with missing billing address"

**Bad:** "Migrated from Newtonsoft.Json to System.Text.Json"
**Good:** "API responses are now faster due to an updated serialization library. Response format is unchanged."

### 4. Include migration instructions

If the update requires any user action, include clear steps:

- Database migrations to run
- Configuration changes needed
- New environment variables
- Package updates or dependency changes
- Breaking API changes with before/after examples

### 5. Verify against actual changes

Cross-check the draft against the git diff:

- [ ] Every user-visible change in the diff is mentioned in the notes
- [ ] No claims in the notes that aren't backed by actual code changes
- [ ] Breaking changes accurately describe what breaks and how to fix it
- [ ] Migration steps actually work (run them, don't just list them)

## Output format

```markdown
# Release Notes — [version or task name]

**Date:** [YYYY-MM-DD]
**Scope:** [one-line summary of what this release covers]

## Breaking Changes

> **Action required:** [summary of what users need to do]

- **[change name]:** [what changed, what breaks, how to update]
  - Before: `[old usage]`
  - After: `[new usage]`

## Features

- **[feature name]:** [what it does, why it matters]
- ...

## Improvements

- **[improvement]:** [what's better and how]
- ...

## Fixes

- **[fix]:** [what was broken, what's fixed]
- ...

## Deprecations

- **[feature]:** Deprecated, will be removed in [version/date]. Use [alternative] instead.

## Migration Guide

[Only include if there are breaking changes or setup steps]

### Steps

1. [Step with exact command or action]
2. ...

### Configuration changes

| Setting | Old value | New value | Required? |
|---|---|---|---|
| [key] | [old] | [new] | [yes/no] |
```

## After generating

Present the draft to the user with:

```
Draft release notes ready for review.

Sources used:
- Plan: [task name]
- Commits: [count] commits, [files changed] files
- Tests: [count] new tests added
- Migration: [yes/no]

Please review for:
- Accuracy: does it match what actually shipped?
- Tone: is the language right for your audience?
- Completeness: anything missing or anything that should be removed?
```
