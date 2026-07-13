# Final Handoff

For medium+ work, produce a reconstructable developer handoff after validation
and review. Keep it concise, but include enough evidence for another developer
to understand the design and test the result without reading the full session.

## Required sections

1. **Changed behavior and areas** — user-visible behavior plus important files
   or modules.
2. **Architecture decisions and rationale** — dependency/ownership decisions
   and why they fit the repository.
3. **Rejected alternatives and tradeoffs** — material alternatives considered,
   including the strongest downside of the chosen path.
4. **Requirement evidence** — `requirement_id -> acceptance criterion ->
   verification result/evidence` and approved exclusions, if any.
5. **Automated verification** — exact commands and concise pass/fail signals.
6. **Manual test scenarios** — setup, numbered actions, and expected outcomes,
   or `N/A — automated verification is sufficient` with a concrete reason.
7. **Compatibility and regression surfaces** — callers, consumers, data,
   configuration, generated mirrors, and platform paths considered.
8. **Known limitations and untested areas** — uncertainty must remain visible.
9. **Rollback or recovery** — how to disable, revert, or recover when relevant.
10. **Review claim** — evidence-bounded wording; never imply proof beyond the
    reviewed scope and available evidence.

When a straightforward task has no material architecture decision, rejected
alternative, or rollback action, use a concise `N/A — [concrete reason]`
instead of inventing filler.

Manual test scenarios are developer documentation. Providing them does not
imply that manual verification must be executed. Waiting for execution or user
observation is controlled only by `manual_verification_mode=required`.

Small tasks may use a compact subset, but must still state verification and
known limitations when material.
