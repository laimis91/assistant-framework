# Change-impact validator

`validate-change-impact.cjs` is a Node 22-or-newer standard-library-only CLI. It checks
that an assessment closes against a separately supplied capture authority. It
does not execute commands in its JSON files, access the network, mutate the
repository, or claim to discover every runtime dependency.

Use one explicit file for each input. The expected-context file is the current
independent authority: its `capture_id`, snapshot IDs, and every required edge
must exactly match the capture. A response cannot make itself current merely by
choosing matching strings in its assessment. The caller must obtain this
authority independently; the tool validates consistency, not that discovery was
complete.

When recapturing, calculate `universe_id` from the current bounded discovery
universe (roots plus relevant source, registration, configuration, event and
state files), including files newly added since the prior capture. Give the
fresh inventory and resulting ID to the independent expected-context authority
before completion. A reused old universe ID is stale once that authority has a
new ID; the checker then rejects the capture and assessment.

```sh
node tools/change-impact/validate-change-impact.cjs --phase discovery \
  --capture capture.json --expected expected-context.json
node tools/change-impact/validate-change-impact.cjs --phase pre_build \
  --capture capture.json --expected expected-context.json --assessment assessment.json
node tools/change-impact/validate-change-impact.cjs --phase completion \
  --capture capture.json --expected expected-context.json --assessment assessment.json \
  --review review.json
```

The command writes one JSON result with stable reason codes and exits zero only
when the requested phase is valid. Completion also requires actual verification
and one exact review binding per captured requirement obligation. Missing Node 22 or a
missing installed checker is a blocker for a triggered deterministic gate; do
not replace it with a manual pass.

Discovery can record material unknown boundaries. Pre-build and completion
reject them until their impact is resolved. A waiver records residual risk only
when an existing policy or authorization is cited by its `rationale_ref`; it
does not create authorization and cannot pass completion.

## Document model

All documents are JSON and have a fixed `schema_version`. See
`protocol.v1.json`, `example.completion.v1.json`, and the tests for complete
valid examples.

* Capture: `change-impact-capture/v1` records roots, the union of base and
  candidate edges, `base_id`/`candidate_id`/`universe_id`, and material unknown
  boundaries. A shared assessment or material unknown boundary requires at least
  one recorded discovery root; compact cosmetic/local controls may have none. An edge has a stable ID, consumer ID, contract ID, dependency kind
  (`call`, `wrapper`, `config`, `registration`, `event`, `state`, or `public`),
  presence (`base`, `candidate`, or `both`), and source identity. Its required
  contract/state-transition records are distinct from edges: one consumer edge
  can require navigation success, dirty-cancel, and stale-completion coverage.
* Expected context: `change-impact-expected-context/v1` independently records
  the required impact scope, current capture ID, snapshot, required edges,
  required contract/state transitions, and current verification source
  identities. It catches an unsupported local claim, a known omitted consumer
  or state transition, or an added/removed edge even when the assessment is
  internally consistent.
* Assessment: `change-impact-assessment/v1` creates exactly one canonical
  obligation per captured contract/state-transition requirement. `preserve` and `change` require planned verification;
  `unaffected` needs a rationale and cannot carry verification; `waived` and
  `blocked` remain unverified residual risk and cannot pass completion.
  `change` and `waived` also require an opaque `authorization_ref` to existing
  authority; the checker does not interpret it or create new authorization.
  Verification plans bind contract, state transition, oracle, manual/command
  steps reference, and source identity. Equivalent obligations may reuse a plan
  only through a named group with two or more same-contract members and a
  justification.
* Review: `change-impact-review/v1` is a projection of the existing
  assistant-review scope manifest and coverage ledger. It carries their source
  IDs and review snapshot identity, then maps each assessment obligation and
  edge to the original scope-item and coverage-concern IDs. The independently
  supplied expected context records the required source and mappings, so a new
  assessment-authored review list or wrong/stale review source fails.

`review_context` may be `null` for discovery and pre-build, because review
artifacts do not yet exist. Completion requires its current source identities
and exact mappings. This is not a workflow-only dependency: standalone
debugging and review can supply the same explicit documents.

Input documents are limited to 256 KiB, depth 16, 200 array items and 60 object
keys. Diagnostics contain reason codes only, never arbitrary input values.
