# Optional review preflight

The orchestrator may use these two recipes before a review batch. They are optional
and cheap. They are never a required step, gate or extra pass, and skipping them
changes nothing else in the review.

## What a preflight hit is

A preflight hit is a lead, not a finding. Inspect it. It becomes a finding only after
the normal findings bar in `SKILL.md`: a real situation, file and line, impact, and
calibrated confidence. A lead never reaches discovery passes as a finding or a list:
discovery contexts already exclude orchestrator-held findings (`pre_batch_findings`
in `contracts/handoffs.yaml`), and this recipe adds no other channel. Sibling and
discovery blindness is unchanged.

## Recipe 1: scan only the added lines

Inspect only the `+` lines of the review diff, for example from
`git diff -U0 <base>...HEAD` or the frozen snapshot diff. Look for:

- error suppression that can turn a failure into success, such as
  `2>/dev/null || true`, an empty or swallowed catch, or an ignored exit status;
- skipped, focused or disabled tests (`skip`, `only`, `xit`, `@Ignore` and similar);
- debug leftovers: print or console logging, commented-out code;
- weakened assertions: a removed `assert`, a loosened comparison, an expected value
  copied from the output;
- new test-only exports, flags or hooks with no production caller.

A suppressed error can be intentional. Confirm what the line does before recording
anything, for example that an invalid input now ends in success. Then record the
finding with file:line and impact.

## Recipe 2: baseline versus new failures

When checks fail on the change, compare each failure by identity and cause: check
ID, failure signature (exception type, message, failing assertion or exit status)
and the reason it fails. Never compare counts alone; "3 failures before, 3 after"
says nothing about which failures they are.

- A failure absent at baseline is new.
- The same check failing at baseline for the same cause persists. Keep it visible in
  the report; a baseline failure may still be a product defect and is not
  automatically irrelevant.
- The same check failing for a different cause is new. Report both causes.

Get the baseline without touching the user's work. Export the base revision to
scratch space with `git archive <base> | tar -x -C <scratch>` and run the checks
there. Use `git worktree add --detach <scratch> <base>` only when the build needs
repository metadata; it writes under `.git/worktrees`, so remove it afterwards. Never
stash, reset or check out over the user's checkout, index, branches or dirty work.

Execution follows the existing review authority. Audit runs nothing: it uses
existing results and static inspection only ([script-execution.md](script-execution.md)).
Standalone review-fix and workflow-composed review run checks as
[review-loop.md](review-loop.md) already allows, and running a changed script still
follows [script-execution.md](script-execution.md).
