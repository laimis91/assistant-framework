# Spec Compliance Review (Stage 1)

Use this before quality review. This review answers one question: did the actual change implement the approved task packet/component, and only that packet/component?

Quality review cannot satisfy this review. Code style, architecture, and maintainability feedback belongs in Stage 2.

## Inputs

- Approved plan or task packet/component manifest
- Changed files list and `git diff`
- Build/test/verification evidence recorded during Build
- Task journal component verification ledger for medium+ tasks

## Protocol

1. Check each approved task packet/component against the actual changes.
2. Confirm every acceptance criterion is implemented or explicitly deferred with approval.
3. Confirm changed files match the approved file list, or each mismatch has an approved deviation.
4. Confirm verification evidence matches the required command, expected success signal, and criteria checked.
5. Flag extra scope separately from quality issues.
6. If any item fails, return `FAIL` with required fixes. Fix, re-test, and re-run this review before Stage 2.

## Output

```markdown
### Spec Review #[N]: [task name]
- Result: PASS | FAIL
- Scope reviewed: [plan step(s), task packet(s), or component(s)]
- Missing acceptance criteria: [none, or list]
- Extra scope: [none, or list with file paths and disposition]
- Changed files mismatch: [none, or expected vs actual]
- Verification evidence mismatch: [none, or expected vs actual]
- Required fixes: [none, or ordered fix list]
```

`PASS` means all approved scope is present, no unapproved extra scope remains, changed files match or have approved deviations, and verification evidence matches the task packet.
