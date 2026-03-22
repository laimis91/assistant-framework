# Migration Guide Generator

## Protocol

### Step 1: Identify Breaking Changes

Compare two versions or branches:
- API signature changes (parameters added/removed/retyped)
- Configuration changes (new required settings, renamed keys)
- Database schema changes (new columns, changed types, removed tables)
- Dependency version bumps with breaking changes
- Behavioral changes (same API, different results)

### Step 2: Assess Impact

For each breaking change:
- Who is affected? (API consumers, database admins, deployers, end users)
- How severe? (compile error, runtime error, silent behavior change)
- Is there a workaround?

### Step 3: Generate

```markdown
# Migration Guide: [from version] → [to version]

## Overview

[1-2 sentences: what changed and why]

## Breaking Changes

### [Change Title]

**Impact:** [who is affected]
**Severity:** [compile error / runtime error / behavior change]

**Before:**
```[language]
[old code/config]
```

**After:**
```[language]
[new code/config]
```

**Migration steps:**
1. [step]
2. [step]

## New Required Configuration

| Setting | Value | Where to set |
|---|---|---|
| [setting] | [example] | [location] |

## Database Migrations

[If applicable: migration commands, rollback instructions]

## Deprecations

| Deprecated | Replacement | Removal Target |
|---|---|---|
| [old] | [new] | [version] |

## Verification

After migration, verify:
- [ ] [check 1]
- [ ] [check 2]
```

### Rules

- Every breaking change must have a migration path
- Include both "before" and "after" code examples
- Database changes must include rollback instructions
- Test the migration steps if possible
