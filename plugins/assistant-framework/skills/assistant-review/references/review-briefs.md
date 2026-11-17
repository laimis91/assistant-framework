# Discovery perspective briefs

Each brief says which questions a discovery pass asks first. It changes emphasis
only: it adds no perspective, pass, round schedule or reviewer count, and batch
topology stays with [review-batch.md](review-batch.md). Passes with different
leads find different defects; identical briefs tend to repeat the same findings.

Every brief keeps the same baseline. The pass still receives the original request,
spec or acceptance criteria. It still inspects connected callers, contracts, tests
and configuration beyond the diff, including outside-diff consumers. It keeps its
assigned scope and coverage obligations, applies every loaded principle and
triggered checklist, and stays sibling-blind. The lead is where to start, not where
to stop.

## `contract_and_test_oracle`

Lead with the contract. Re-read the request, spec or acceptance criteria before the
implementation narrative, and list what each criterion requires the change to do.
Then check the tests against it: could a fake or incomplete implementation still
pass? Report a missing or weakened assertion, a criterion with no observable proof,
or behaviour the change adds outside the criteria. Then continue with the remaining
questions, beyond the diff where callers or tests live elsewhere.

## `runtime_lifecycle_and_failure_paths`

Lead with execution. Trace what happens when an input is invalid, a dependency
fails, a call times out or a step runs twice, and follow one ordinary path as a
control. Look for error handling that turns a failure into success, wrong
conditionals, missing cleanup, and state left behind after a partial failure. The
acceptance criteria and existing behaviour still decide which failures matter.
Follow the path beyond the diff when the failing step is in an unchanged callee.

## `integration_compatibility_and_consumers`

Lead with consumers. For each changed name, key, schema, output, default or
behaviour, search for its consumers beyond the diff: callers, configuration,
scripts, generated clients, docs, and sibling implementations of the same operation.
A renamed configuration key whose only reader is outside the diff is the typical
miss. Check that each consumer still works, or that the change updates it, and that
sibling implementations agree. A consumer broken by the change is a defect whether or
not the acceptance criteria name it.

## `architecture_maintainability_and_reuse`

Lead with ownership and reuse. Search for an existing helper, rule or owner that
the change re-implements, and compare their semantics. Ask whether a special case
or wrapper dodges a fix that belongs in the shared path. State the actual cost and
rule out an intentional boundary as the Reporting Rule in
[review-principles.md](review-principles.md) requires. Search beyond the diff; the
acceptance criteria still bound what must change now.

## `light_contract_and_runtime`

One light pass covers both leads. Start from the request, spec or acceptance
criteria and ask whether the tests would catch a fake implementation. Then trace one
failure path and one ordinary path through the change. Inspect beyond the diff where
a changed name or behaviour has callers. The light pass keeps every other baseline
question; it is smaller, not narrower.
