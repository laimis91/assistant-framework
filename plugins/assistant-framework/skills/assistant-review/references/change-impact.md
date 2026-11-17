# Change-impact review projection

Load for a review that covers a behavior or cosmetic change, carries a change-impact
artifact, or has a locality/shared/unresolved decision. Record compact
applicability evidence for every behavior change. Keep this outside the fresh
reviewer context bundle: the reviewer-context load set remains unchanged.

Evidenced local work keeps ordinary review and verification. Shared, materially
unresolved, or explicitly carried expanded work uses the checklist below;
no script or runtime is needed. This works for selective installs and custom
homes; do not require assistant-workflow.

## Expanded-work checklist

Record a checklist result for the current phase: each item below with `pass`,
`fail` or `not_applicable` (only where the item names its phase) and an evidence
ref. Any `fail` blocks the phase. The result's pointer is `checklist_result_ref`.

1. **Universe recorded.** The bounded base/candidate universe is recorded: the
   discovery roots plus the relevant source, registration, configuration, event
   and state files, including files added since the last capture, with
   `base_id`, `candidate_id` and `universe_id`.
2. **Consumer classes covered.** Each consumer class (direct call, configuration,
   registration, event, state, public interface, wrapper, added consumer,
   removed consumer) is covered by cited evidence, or recorded as not applicable
   with a reason.
3. **One disposition per requirement.** Each captured contract or state-transition
   requirement has exactly one disposition. `preserve` and `change` carry planned
   verification; `unaffected` carries a rationale and no verification; `waived`
   and `blocked` stay unverified residual risk. `change` and `waived` cite existing
   authorization; the checklist never creates authorization.
4. **Independent expected context.** The expected context (required scope, edges
   and requirements) comes from the capture or another source the assessment
   author did not write, and every required edge and requirement maps to the
   assessment. An internally consistent assessment that omits a known consumer
   fails.
5. **No material unknown.** At `pre_build` and `completion`, no material unknown
   boundary remains. Discovery may record unknowns as gaps.
6. **Same artifact identity.** `artifact_identity` is unchanged from discovery to
   completion. When source changed after capture, the universe and expected
   context were captured again and the new identities are recorded.
7. **Verification bound** (`completion` only). Actual verification ran against
   the current `base_id`/`candidate_id`/`universe_id` and is recorded with its
   verification identity; at least one `preserve` or `change` obligation is
   verified. `waived` or `blocked` obligations block completion.
8. **Review bound** (`completion` only). The review projection maps each
   obligation once to the original `scope_manifest` item and `coverage_ledger`
   concern of the current review snapshot.

The fresh independent reviewer checks the checklist result against the diff:
every changed consumer appears in the checklist, and every consumer the checklist
lists as changed appears in the diff. That review replaces the former
deterministic receipt.

## Review projection

Use the existing canonical `scope_manifest`, `coverage_ledger`, current review
snapshot, and concern IDs to create the completion projection. Map each captured
requirement once; do not create an impact-specific coverage ledger. Read-only
audit can identify absent/stale mappings and report the gap. Review fix must
refresh its frozen snapshot after mutation and record a fresh checklist result.
A passing checklist never replaces `final_summary.coverage_complete`, required
terminal passes, or the CLEAN/ISSUES_FIXED decision.

## Older packets

Review 11.0 replaced the former checker script and its receipt (`validator_result_ref`)
with this checklist and `checklist_result_ref`. A packet from producer 10.0 that
carries `validator_result_ref` stays readable as a record of a past checker run,
but it is not a current checklist result: record the checklist before relying on
that evidence at a new phase.
