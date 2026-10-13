# Unit checks

Load when an isolated behavior, domain rule, or local boundary can be observed without proving collaboration with a real component.

## Claim and prerequisites

State the public behavior or invariant, allowed input domain, relevant boundary values, and failure condition. Use authoritative examples and requirements. Identify the smallest owning test suite and its setup; make time, randomness, and external state deterministic where they affect the oracle.

## Procedure and oracle

Exercise representative normal, boundary, and invalid cases only where they distinguish plausible outcomes. Assert externally meaningful values, state, errors, or side effects. Reuse or extend an existing test when it already owns the behavior. Keep collaborators real when practical; replace only unstable or unrelated edges and name the substitution.

## Traps and evidence

Avoid private call-order assertions, testing trivial getters, mirroring mutable filenames or content without a product invariant, and adding cases that repeat the same oracle. A passing unit test proves its isolated assertion under that setup; it does not prove service wiring, serialization, UI behavior, or an external integration. Record command/result identity, assertions covered, relevant exclusions, and failures.

Use integration or end-to-end evidence only when an additional material boundary is otherwise uncovered.
