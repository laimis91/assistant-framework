# Lifecycle verification

docs/lifecycle-verification.md is canonical. Generate the three skill-local
copies with `tools/skills/sync-lifecycle-verification.sh --apply`; `--check`
rejects missing or drifted copies. Local copies support standalone installation.

## Select affected observations

Load only for changed behavior or symptoms involving acquisition/readiness,
active work, cancellation, collection/finalization, shutdown, owned resources,
cleanup or retry. Synchronous calculations, labels and formatting alone do not
qualify; neither does an async keyword. Shared-work and publication cases apply
only when those semantics exist.

Use existing CheckSpecs, debugging evidence or review scope/findings for expected
observations, ownership and limits. Reuse adequate assertions. These scenarios
are selection aids, never a universal matrix or test-per-row requirement. They
add no output schema, default TDD, architecture/QA gate or review round.

| Affected boundary | Material observation |
| --- | --- |
| Startup/readiness | Distinguish admission, ready, active, exited and released. |
| Cancellation during collection/final cleanup | Reach that exact boundary; retain outcome, observations, relevant abort reason and settlement. Active-work cancellation does not cover it. |
| Work then cleanup failure | Preserve completed result or primary diagnostic and report unresolved owners/recovery; cleanup failure must not replace the primary outcome or imply full release. |
| Mixed child outcomes | Keep per-child success, failure and unresolved ownership; another success or missing health cannot erase a failure. |
| Cleanup retry | Retry unresolved owned resources only; retain successful cleanup. Connection ownership grants no right to terminate foreign/attached targets. |
| Disconnect/leader exit | Observe descendants, streams and handles separately; transport loss or leader exit alone does not prove release. |
| Atomic publication | Identify the commit/cancellation cutoff, retain a committed-output receipt and do not invent rollback after commit. |
| Shared startup/work | Separate caller cancellation from owner shutdown while other callers still need work. |

## Boundary evidence

Use a marker, barrier or controlled production seam to establish interleaving;
a timed sleep alone cannot show that finalization was reached. Prefer public
boundaries when practical without requiring end-to-end tests for every claim.
Label source-only, mocked and unavailable observations honestly.

For example, pause at a finalization marker after collecting a result, cancel,
then release the barrier. Observe the retained result/primary failure, abort
reason and settled operation. A matched successful run must retain its result
and release its owned resources. Reuse an adequate control; active-work-only
cancellation is insufficient for this changed boundary.

In a coupled recovery case, child A fails work and cleanup, child B cleans up,
and C is attached. Retain A's primary diagnostic and unresolved handle, B's
success and C's foreign ownership. Retry only A's unresolved owned handle;
verify settlement/release separately from a disconnected transport or exited
leader. Unknown release remains unresolved, including surviving descendants.

Source basis: REA testing/tool-design guidance and cleanup-cancellation regression
at `5927937179476c66aa8621658faca42f9578b42a` (see the preparation source
manifest). These are original provider-neutral examples; upstream tests were
not executed. Guidance and structural/offline checks prove no native adherence,
provider correctness, defect reduction or efficiency benefit.
