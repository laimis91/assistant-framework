# Assess evidence quality

Load when evidence is ambiguous, reused, partial, or used to support a completion or comparison claim.

## Check the observation

Resolve each evidence reference and compare its actual assertion with the claim. Prefer an independent observable oracle that fails for a plausible wrong outcome. A test that merely runs the changed code may provide incidental coverage; a phrase match, schema pass, command-start event, or file-existence check does not prove useful behavior.

Classify evidence using the existing result state and freshness rules. A prior pass is reusable only when its source/config/toolchain identity, relevant conditions, acceptance coverage, and exclusions still match. Inspection of a test establishes what it covers, not that it ran. A retry-only pass after a failed or flaky attempt is not reliable passing evidence. Failed, skipped, partial, stale, unknown, and unavailable results remain gaps for any claim they do not establish.

## Bound each claim

When relevant, distinguish structural validity, native activation, task behavior, and comparative value. Do not require all kinds for every task. A valid contract does not show that a host routes to it; activation does not show the skill performs the requested action. An artifact's existence or parseability does not establish correct, current, complete, or accessible content. Observing an attempt does not establish successful completion at the real boundary.

Treat substitutes, mocks, seeded data, selected environment, and inaccessible dependencies as explicit exclusions. Claim only the boundary actually observed. Missing latency, token, cost, or platform telemetry limits a claim that depends on that measurement; it does not invalidate unrelated functional evidence.

## Wrong-outcome control

Before trusting a material assertion, describe a specific wrong output or action it must reject. If structural and phrase checks would accept an empty, stale, or incorrect artifact, inspect the actual content or successful operation and tighten the observation. Qualitative judgments need a task-specific rubric and reasoned inspection; do not turn subjective quality into an unsupported numeric score.

Mark sufficient only when current, resolved refs support every material claim and binding check within the named scope, with no material gap. Otherwise use insufficient, or blocked when an unavailable capability or unresolved material dependency prevents adequate verification. Keep exclusions visible; sufficient is not proof of every possible fault, independent review, or delivery approval.
