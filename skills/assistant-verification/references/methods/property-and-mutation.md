# Property and mutation techniques

Load when a broad input space or state invariant needs stronger coverage, or when a specific assertion's ability to reject wrong behavior is uncertain. Neither technique is globally mandatory.

## Property checks

State an independent invariant and constrain the generated input to the supported domain. Useful properties include round-trip behavior, ordering or conservation rules, idempotence, and metamorphic relations. Make randomness reproducible; retain a failing seed and shrink the example to a minimal counterexample. For stateful behavior, define legal transitions and the invariant after each transition.

## Mutation probes

Use a small, relevant mutation only to challenge a concrete oracle concern: identify the plausible wrong behavior, alter it reversibly in an isolated experiment, and verify that the assertion fails for that reason. Review survivors and equivalent mutants rather than treating a mutation score as proof.

## Traps and evidence

Unconstrained generators can produce invalid inputs and misleading failures. A property that restates the implementation or a mutation unrelated to the claim adds little evidence. Bound the domain, runtime, and mutation set; save only reproducible counterexamples and observed results.

Add these techniques only when they close a material input-space or oracle gap that examples and existing checks do not already cover.
