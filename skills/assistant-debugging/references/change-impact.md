# Change-impact during debugging

Load when the reported symptom, diagnosis, or proposed fix can affect another
consumer. Keep an audit-only diagnosis honest: discovery can identify missing
or material unknown boundaries, but it cannot claim future execution, review,
or a clean result.

From the directory containing the actively loaded `SKILL.md`, resolve the common
checker as `../../tools/change-impact/validate-change-impact.cjs` and invoke it
with quoted explicit paths under Node 22+ only for shared, materially
unresolved, or explicitly carried expanded impact. Do not use the process cwd
or assume assistant-workflow is installed. A missing checker/runtime blocks that
expanded deterministic gate; an evidenced local repair remains on its ordinary
regression-verification and self-review path.

Every proposed behavior repair records impact scope, an applicability reason,
and causal evidence for a local decision. Before a source fix, shared or
unresolved impact needs the common pre-build assessment, including bounded
base/candidate consumers and distinct material transitions. Preserve the same
artifact identity through expanded verification. An expanded fix completion
needs actual current verification and assistant-review's projection of its
existing canonical manifest, ledger, snapshot, and concern bindings; that
projection never replaces assistant-review's own terminal coverage/result.
