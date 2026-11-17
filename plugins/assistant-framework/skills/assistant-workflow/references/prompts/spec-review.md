# Acceptance Spec Obligations

Spec-obligation checklist of the final fresh acceptance review (`assistant-review`, `review_subject=acceptance`). It answers one question: did the actual change implement the approved task packet/slice, and only that task packet/slice?

There is no separate Spec reviewer. A newly created fresh-context reviewer (Codex `fork_turns=none`) of the final review batch owns these obligations from its self-contained handoff, for example the contract_and_test_oracle pass; light trivial/small work covers them in its one compact fresh review. The author or a Build actor cannot. Unavailable isolation leaves Review incomplete. Historical Stage 1 `### Spec Review #N` records stay readable under their original labels.

## Inputs

- Original user request and accepted requirement IDs
- Approved plan or task packet/canonical packet collection
- Changed files list and `git diff`
- Build/test/verification evidence recorded during Build
- Task journal canonical packet execution evidence for medium+ tasks

## Obligations

1. Reconcile the original request, requirement IDs, and approved plan against delivered results; record each unfinished or omitted item once in the review's `request_plan_reconciliation`.
2. Check each approved task packet/slice against the actual changes.
3. Confirm every acceptance criterion is implemented or explicitly deferred with approval.
4. Confirm changed files match the approved file list, or each mismatch has an approved deviation.
5. Confirm verification evidence matches the required command, expected success signal, and criteria checked.
6. Flag extra scope separately from quality issues.
7. If any item fails, return `FAIL` with required fixes. In review-fix mode, fix, re-test, and run a fresh complete acceptance review on the changed snapshot; audit mode reports without source changes.

## Output

Record `spec_review_result`; journal this entry only when a task journal exists.

```markdown
### Spec Review #[N]: [task name]
- Result: PASS | FAIL
- Acceptance review: [final_review_snapshot_id]
- Scope reviewed: [plan step(s), task packet(s), or slice(s)]
- Request/plan reconciliation: [ref to that review's request_plan_reconciliation, which owns unfinished or omitted items]
- Missing acceptance criteria: [none, or list]
- Extra scope: [none, or list with file paths and disposition]
- Changed files mismatch: [none, or expected vs actual]
- Verification evidence mismatch: [none, or expected vs actual]
- Required fixes: [none, or ordered fix list]
```

`PASS` means no requested or planned item is unfinished or omitted without approved exclusion, all approved scope is present, no unapproved extra scope remains, changed files match or have approved deviations, and verification evidence matches the task packet.
