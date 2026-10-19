# Review result compatibility

Load only for persisted pre-v8 review results. Current v8 field definitions and
migration validation remain authoritative in `contracts/input.yaml` and
`contracts/handoffs.yaml`.

Invalidate persisted 6.0/7.0/7.1/7.2 result, delegation, snapshot, Pack, QA, plan,
and coverage references. Rebuild a fresh rehashed v8 snapshot and complete review
before CLEAN/ISSUES_FIXED. Preserve raw history, recoverable selected design,
rationale, viable alternatives/dispositions, and complete closure identity tuples.
For partial tuples use the exact version-specific fill/ID/collision rules in the
input contract; never recompute supplied aggregate IDs or substitute old evidence
for a new batch. Historical failures do not permanently block a later complete
replacement batch, but every current expected pass needs terminal accounting.
