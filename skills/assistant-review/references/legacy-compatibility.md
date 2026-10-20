# Review result compatibility

Load only for persisted pre-v9 review results. Current v9 field definitions and
migration validation remain authoritative in `contracts/input.yaml` and
`contracts/handoffs.yaml`.

Invalidate persisted 6.0/7.0/7.1/7.2 result, delegation, snapshot, Pack, QA, plan,
and coverage references. Rebuild a fresh rehashed v9 snapshot and complete review
before CLEAN/ISSUES_FIXED. Preserve raw history, recoverable selected design,
rationale, viable alternatives/dispositions, and complete closure identity tuples.
For partial tuples use the exact version-specific fill/ID/collision rules in the
input contract; never recompute supplied aggregate IDs or substitute old evidence
for a new batch. Historical failures do not permanently block a later complete
replacement batch, but every current expected pass needs terminal accounting.

Persisted v8 results remain v8 historical evidence. Rebuild current snapshot/coverage under v9 before a current clean claim, preserving closure identities and findings. Old cap exhaustion alone is no longer a blocker; missing progress history remains an explicit gap.
