# Slice Review Topology

Use this reference only for multi-slice work with `promotion_mode: review_gated`.
It defines a portable evidence boundary; it does not perform remote operations.

## Topology

```text
target_branch: <target-branch>
target_base_sha: <immutable target commit>
└── task_branch: feature/<task>
    ├── slice_branch: slice/<task>/<slice-id>
    └── slice_branch: slice/<task>/<slice-id>
```

`<slice-id>` is a stable descriptive outcome or deliverable slug; sequence numbers belong to manifest order and display labels, not branch identity.

Every new strict slice packet carries all five fields together:

- `target_branch`: the repository-specific umbrella task target ref; it is not a `main` invariant.
- `target_base_sha`: the canonical 40- or 64-character lowercase commit SHA snapshot used to create the task branch. It remains immutable if the target branch advances and must stay an ancestor of both the target and task branches.
- `task_branch`: `feature/<task>`, the review and promotion base.
- `slice_branch`: `slice/<task>/<slice-id>`, the reviewed head.
- `promotion_mode`: `local` or `review_gated`.

`local` uses the runner's existing immutable verification and local promotion.
`review_gated` keeps immutable verification but emits review evidence instead of
locally promoting. Legacy briefs have none of these fields, retain their legacy
branch layout, and are local-only; never mix them with new topology briefs.

## State and evidence

The core state flow is:

```text
local verification -> REVIEW_PENDING -> REVIEW_APPROVED | REVIEW_REJECTED | REVIEW_STALE -> VERIFIED
```

`REVIEW_PENDING` is not `VERIFIED` and does not unlock dependent slices. A
pending record contains the exact `review_base_ref`, `review_head_ref`,
`verified_base_sha`, `verified_head_sha`, and `verification_evidence_ref` from
the local verifier. A changed ref or SHA is `REVIEW_STALE` and requires fresh
verification; it cannot reuse earlier evidence.

The core writes a bounded `<brief>.review-evidence.txt` `REVIEW_PENDING`
record atomically after local verification. An adapter writes the separate
`<brief>.review-approval.txt` outcome record; it must preserve the pending
topology, reviewed SHA pair, and verification evidence exactly. Approval
requires `provider_gate_state: passed` plus unchanged reviewed SHAs.
Final `VERIFIED` additionally requires the exact reviewed head to be an
ancestor of `task_branch` and fresh host verification after integration.

`run-agents.sh` reads these paired records from its log directory. For a
separate readiness check, pass `--review-evidence-dir DIR`; otherwise
`check-integration.sh --task-branch ... --briefs ...` uses `briefs/logs`.

## Adapter boundary

The framework core emits local evidence only. A configured adapter owns remote
push, review-request creation, gate evaluation, and merge execution. Its
provider-neutral outcome records opaque `review_request_ref`,
`provider_gate_state` (`not_evaluated`, `passed`, or `failed`), and
`provider_gate_evidence_ref`. The core never interprets provider identity or
implements provider commands, credentials, pipeline syntax, or repository
policy configuration.

## Review evidence schema

The pending record uses `--- SLICE REVIEW EVIDENCE ---` markers and omits
adapter-only outcome fields. The approval record uses
`--- SLICE REVIEW APPROVAL ---` markers and adds nonblank opaque
`review_request_ref` and `provider_gate_evidence_ref` values.

```text
schema_version: 1
slice_id: <slice id>
state: REVIEW_PENDING | REVIEW_APPROVED | REVIEW_REJECTED | REVIEW_STALE
promotion_mode: review_gated
target_branch: <target ref>
target_base_sha: <immutable target commit SHA>
task_branch: <task ref>
slice_branch: <slice ref>
review_base_ref: <task ref>
review_head_ref: <slice ref>
verified_base_sha: <exact task SHA>
verified_head_sha: <exact slice SHA>
verification_evidence_ref: <local verifier evidence>
review_request_ref: <opaque adapter reference>
provider_gate_state: not_evaluated | passed | failed
provider_gate_evidence_ref: <opaque adapter evidence>
```
