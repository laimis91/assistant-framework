# Expert-method authoring and debugging pilot

Approved design recorded 2026-10-22. Authority: the user's `approve` of the
previously presented authoring-method and debugging pilot. Repository source:
`c920fd89ee232032aafd2541dd51c9c5bd9744f3`. Work is isolated in the writable clone
`/tmp/assistant-expert-method-pilot-V1`, branch `feature/expert-method-pilot`.
Unrelated work in the user's primary checkout is outside this scope.

The outcome is to introduce conditional expert-method authoring guidance,
reusing current success criteria and DESIGN gates, and test the resulting
debugging candidate against consequential diagnosis decisions. Creator guidance
is assessed by source/semantic review; this pilot does not isolate the causal
benefit of the authoring procedure or run creator-task behavioral comparisons. A debugging candidate is justified only by actual
development baseline evidence. The candidate may be an evidence-supported
no-change decision. No general expert-quality claim follows from this pilot.

First freeze four Python-stdlib diagnosis-only scenarios, prompts, rubric, source
snapshot and discriminating smoke evidence. One case is development; three are
sealed held-out cases. Subject workspaces contain ordinary source, configuration,
logs and reproduction commands, never scoring rubrics or ground truth. Root
distributes independent identical subject copies. No fixes are authorized in
subject runs. No model run is part of fixture preparation.

Compare target skill disabled, current target skill and candidate in separate
fresh contexts, matched for subject bytes, task, model/runtime, permissions and
available tools. Explicit supplied-skill observations are not native activation.
The hard allowance is at most 12 charged subject evaluations: four scenarios by
three conditions, including any partial or failed evaluation starts. Do not tune
on held-out outcomes, reuse them for development, replace failed runs, or increase
the cap. Freeze a candidate identity (or no-change disposition) after development
and before held-out execution. If no material candidate is justified, report that
fact rather than fabricate a difference. Development findings do not establish
held-out improvement.

Use the canonical verification decision in `selection.json`: existing focused
checks, source/guide validation, artifact inspection, controlled observation and
independent review. No new executable-test assertions are selected; TDD is false,
not_selected. Root owns aggregate selection after the actual source diff. This
stage writes fixtures and pilot documents only; skill-source edits and subject
evaluations await root's continuation.

The shared task guard is `expert-method-pilot`: retain one outcome, source-bound
window of three consecutive unproductive semantic cycles and shared history in
`journal.md`. Productive work has no cumulative attempt limit. Preserve authority,
access, the 12-run resource cap and acceptance boundaries. Stop for material scope,
risk, cost, access or acceptance changes; missing required evidence; exhausted
evaluation cap; or the shared stagnation threshold. Retain completed checkpoints.

Upstream limitation supplied by root: the read-only Anthropic skill-creator fetch
failed TLS certificate validation. TLS remains enabled and the registry remains
unchanged. The existing 2026-10-13 assessment is within its 30-day window; no
unavailable external fact currently blocks the local fixture design.
