# Final Handoff

During Document, produce the sole `final_handoff` artifact for medium+ work or
any execution with `controller_intensity=strict` or required QA
after validation and review. Review provides its result/evidence but does not
create this artifact. Keep it concise, but include enough evidence for another
developer to understand the design and test the result without reading the full
session.

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
10. **Review completion** — exact projection of the canonical assistant-review
    `final_summary` ref, producer version, result, `coverage_complete`, eligible
    `evidence_bounded_claim`, exact `final_review_snapshot_id`, final identity,
    and applicable typed QA terminal/obligation state. The alias must equal the
    current final-batch `review_snapshot_id` and identify the same identity.
11. **Review claim** — use exactly `No material findings within the reviewed
    scope and available evidence` only when review completion is `complete`.
    Canonical `HAS_REMAINING_ITEMS`, incomplete coverage, rejected QA, QA
    `HAS_REMAINING_ITEMS`, blocked QA, or QA `BLOCKED` requires explicit
    remaining-item or blocker wording and the next action instead.

`completion_disposition=complete` requires canonical review result `CLEAN` or
`ISSUES_FIXED`, `coverage_complete=true`, and, when QA is required, an
`accepted` or `accepted_with_concerns` verdict with QA result `CLEAN` or
`ISSUES_FIXED`. A carried deferred-QA obligation additionally requires fulfilled
scope, met prerequisite, and exact source binding. Otherwise use
`remaining_items` or `blocked`. A non-complete
disposition forbids `--- WORKFLOW COMPLETE ---`.

When an Architecture Decision Pack applied, include its fresh reference in the
architecture-decision section. State the design-pressure outcome
(control/ownership/resource/extension/representative path), semantic type or
primitive-exception commitments, quality verification, and
compatibility/invalidation outcome instead of copying stale architecture prose.

When a straightforward task has no material architecture decision, rejected
alternative, or rollback action, use a concise `N/A — [concrete reason]`
instead of inventing filler.

Manual test scenarios are developer documentation. Providing them does not
imply that manual verification must be executed. Waiting for execution or user
observation is controlled only by `manual_verification_mode=required`.

Small handoffs may use concise values, but strict or required-QA execution
still includes every required `final_handoff` field and typed terminal result.
