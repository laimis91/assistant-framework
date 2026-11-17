# Change-impact during debugging

Load when the reported symptom, diagnosis, proposed fix, or cosmetic decision can affect another
consumer. Keep an audit-only diagnosis honest: discovery can identify missing
or material unknown boundaries, but it cannot claim future execution, review,
or a clean result.

Shared, materially unresolved, or explicitly carried expanded impact uses
assistant-review's
[expanded-work checklist](../../assistant-review/references/change-impact.md#expanded-work-checklist);
no script or runtime is needed, and assistant-workflow need not be installed. An
evidenced local repair stays on its ordinary regression-verification path with a
local self-check plus fresh independent review.

Every proposed behavior repair records impact scope, an applicability reason,
and causal evidence for a local decision. Before any source/test mutation,
including a regression-test write, or Fixer dispatch, shared, unresolved, or
explicitly expanded impact records a passing `pre_build` checklist result against
the referenced capture, independent expected context, and assessment, resolved
against the fix packet; a status or `checklist_result_ref` alone is insufficient.
Preserve the same artifact identity through expanded verification. An expanded
fix completion needs a passing `completion` checklist result, actual current
verification, and assistant-review's projection of its existing canonical
manifest, ledger, snapshot, and concern bindings; that projection never replaces
assistant-review's own terminal coverage/result. The fresh independent reviewer
checks the checklist result against the diff.

Debugging 4.0 replaced the former checker script's receipt (`validator_result_ref`) with
`checklist_result_ref`. An older packet that carries `validator_result_ref` stays
readable as a record of a past checker run, but it is not a current checklist
result: record the checklist before a new mutation or completion.
