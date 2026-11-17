# End-to-end checks

Load when a complete user or system journey is the most direct way to observe the acceptance claim, including when the user or project explicitly prefers that scope.

## Claim and prerequisites

Name the user-visible start and success state, important negative path, environment, test account or controlled data, and real boundaries. Check that the app, service, browser, permissions, and required fixtures are available. Identify any substituted service or inaccessible platform before interpreting results.

## Procedure and oracle

Drive the journey through its supported interface and assert observable outcomes rather than implementation details. Use stable accessible names or identifiers, wait for a condition that represents completion, and capture diagnostics on failure. Isolate and clean up created data. A targeted smoke path may be enough for a narrow claim; broaden the journey only when additional user-visible boundaries matter.

## Traps and evidence

Avoid sleeps in place of state checks, brittle positional selectors, shared mutable accounts, happy-path-only coverage for consequential negative behavior, and repeated full journeys that add no evidence. A mocked external service proves only the substituted boundary. Record environment, inputs, final outcome, failures, substitutions, and cleanup.

Add lower-scope checks only for distinct logic, failure handling, or a binding obligation not reliably observed by the journey.
