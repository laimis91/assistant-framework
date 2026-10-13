# Integration checks

Load when a claim crosses a real boundary between collaborating components, such as serialization, configuration, dependency injection, storage, or a service adapter.

## Claim and prerequisites

Name the participating components and the contract between them. Decide which dependencies must be real to observe the claim and which unrelated services can be controlled. Use isolated data, namespaces, ports, or temporary resources with explicit cleanup; preserve production-relevant configuration where it is part of the risk.

## Procedure and oracle

Drive the changed contract through its owning boundary and inspect the other side's observable result. Include a representative failure path when error translation, persistence, cancellation, or cleanup changed. Use a contract double only for an external boundary that cannot be controlled, and label what the double does not establish.

## Traps and evidence

A mocked collaborator can prove local request formation, not the real serialization, storage, wiring, or service behavior it replaces. Avoid broad environment setup when a focused component boundary observes the claim. Capture identities, relevant configuration, result, and cleanup; redact sensitive values.

Further end-to-end or external-service evidence is warranted only for an uncovered material user journey or real boundary. Do not add unit tests merely because integration testing was selected.
