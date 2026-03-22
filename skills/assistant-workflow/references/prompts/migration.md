# Migration Prompt

Load this during Phase 2 (Plan) when the task involves database schema changes, data transformations, or data store migrations. Produces a migration section for the plan with explicit rollback steps.

## When to use

Use when the task involves any of:
- Adding, removing, or altering database tables or columns
- Changing indexes, constraints, or relationships
- Migrating data between stores (e.g., SQL to NoSQL, local to cloud)
- Backfilling or transforming existing data
- Changing ORM mappings or entity configurations
- Renaming database objects

Skip for: code-only refactors with no schema or data changes.

## Section 1: Forward migration

Document exactly what changes:

### Schema changes

| Change | Object | Details | Nullable? | Default? |
|---|---|---|---|---|
| Add column | [table.column] | [type, e.g., nvarchar(256)] | [yes/no] | [value or none] |
| Add table | [table] | [column list] | — | — |
| Alter column | [table.column] | [old type → new type] | [change?] | [change?] |
| Add index | [table.index] | [columns, unique?] | — | — |
| Drop column | [table.column] | [type being removed] | — | — |
| Add FK | [table.column → parent] | [cascade rule] | — | — |

### Migration code

```bash
# EF Core
dotnet ef migrations add [MigrationName] --project [Infrastructure project]
dotnet ef database update

# Or raw SQL
# Provide the exact SQL statements for both forward and rollback
```

### Data changes

If existing data needs transformation alongside schema changes:
- What data is affected? (row count estimate, which records)
- Transformation logic: [description]
- Is it idempotent? (can you run it twice safely?)
- Batch size: [N rows per batch, or all-at-once]

## Section 2: Backward compatibility

**Key question:** Can the old version of the code run against the new schema during rollout?

This matters for:
- Rolling deployments (old and new code run simultaneously)
- Quick rollback (revert code but keep the new schema)
- Feature flags (new code path is behind a flag, old path still active)

### Compatibility checklist

- [ ] New columns are nullable or have defaults (old code won't insert them)
- [ ] No columns removed that old code reads from
- [ ] No columns renamed that old code references
- [ ] No constraints added that old data violates
- [ ] No type changes that break old code's assumptions
- [ ] Foreign keys allow existing data patterns

**If backward-incompatible:** You need a multi-phase migration:

```
Phase 1: Add new columns/tables (both code versions work)
Phase 2: Deploy new code (writes to both old and new)
Phase 3: Backfill data to new columns
Phase 4: Remove old columns (only after all code uses new)
```

## Section 3: Rollback migration

**Key question:** Can you reverse this migration without data loss?

| Change | Reversible? | Data loss? | Rollback step |
|---|---|---|---|
| Add column | Yes | No | Drop column |
| Add table | Yes | Loses new data | Drop table |
| Drop column | No* | Yes | Restore from backup |
| Alter column (widen) | Yes | No | Alter back |
| Alter column (narrow) | Maybe | Maybe (truncation) | Alter back, check data fits |
| Data backfill | Depends | Depends | Reverse transformation or restore |

*For destructive changes: keep a backup column or table for a defined retention period.

### Rollback commands

```bash
# EF Core
dotnet ef database update [PreviousMigrationName]

# Or raw SQL rollback
# Provide exact SQL for rollback
```

### Rollback verification

After rolling back, confirm:
- [ ] Schema matches pre-migration state
- [ ] Application starts and connects successfully
- [ ] Existing data is intact and accessible
- [ ] All tests pass against rolled-back schema

## Section 4: Data backfill strategy

If existing rows need updating (e.g., populating a new column from existing data):

### Backfill plan

- **Source:** Where does the data come from? (another column, computed, external source)
- **Target:** [table.column]
- **Row count:** [estimate]
- **Batch size:** [N] rows per batch (avoid locking entire tables)
- **Idempotent:** [yes/no] — can you re-run safely if interrupted?
- **Timing:** Run during migration, after deployment, or as background job?

### Backfill script

```sql
-- Example: batch update with progress
DECLARE @BatchSize INT = 1000;
DECLARE @RowsAffected INT = 1;

WHILE @RowsAffected > 0
BEGIN
    UPDATE TOP (@BatchSize) [table]
    SET [new_column] = [computed_value]
    WHERE [new_column] IS NULL;

    SET @RowsAffected = @@ROWCOUNT;
    -- Log progress
END
```

Or for EF Core:
```csharp
// In a migration or seed script, batch process
var batch = context.Items.Where(x => x.NewColumn == null).Take(1000);
```

## Section 5: Zero-downtime assessment

**Key question:** Can this migration run while the application is serving traffic?

| Factor | Status | Notes |
|---|---|---|
| Schema change locks tables? | [yes/no] | [ALTER on large tables can lock — check DB engine] |
| Backfill locks rows? | [yes/no] | [batch updates to minimize lock duration] |
| Application tolerates schema mid-change? | [yes/no] | [backward compatibility from Section 2] |
| Migration duration estimate | [seconds/minutes/hours] | [based on data volume] |

**If zero-downtime isn't possible:** Document the maintenance window requirement and notify stakeholders.

## Output format

Add this block to the plan:

```markdown
### Migration Plan

**Type:** [schema only / schema + data / data only]
**Backward compatible:** [yes / no — if no, multi-phase plan required]
**Rollback safe:** [yes / partial / no — explain]
**Zero-downtime:** [yes / no — if no, maintenance window needed]

**Forward migration:**
- [list of schema changes]
- [data backfill if applicable]
- Command: `dotnet ef database update` (or equivalent)

**Rollback:**
- Command: `dotnet ef database update [PreviousMigration]` (or equivalent)
- Data loss: [none / acceptable / requires backup restore]
- Verified: [ ] schema matches pre-migration, [ ] app starts, [ ] tests pass

**Backfill:** [description or "N/A"]
- Rows: [estimate], Batch size: [N], Idempotent: [yes/no]

**Risks:**
- [risk]: [mitigation]
```
