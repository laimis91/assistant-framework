# Five-Lens Research Briefing

Decision-grade research using a STORM-inspired multi-perspective workflow: perspective scan → contradiction map → synthesis → peer review.

Use this when the user needs understanding that is broader than a normal source lookup: investment/trading research, business decisions, technology choices, architecture options, vendor/tool evaluation, unfamiliar domains, negotiations, presentations, or any topic where incentives and blind spots matter.

## When to choose this method

Prefer `five_lens_briefing` when any of these are true:

- The user asks for deep research, due diligence, decision support, or "what should I do?".
- The topic has incentives, controversy, trade-offs, hype, or expert disagreement.
- A single summary would likely reproduce the majority framing and miss practitioner reality.
- The output will inform money, architecture, strategy, career, negotiation, or public communication.

Do not use this as ceremony for simple factual lookups. Use quick or standard `source_research` instead.

## High-stakes constraint

For finance/trading, legal, medical, safety-critical, or similarly high-impact decisions:

- frame the output as educational due diligence and decision support, not professional advice or an instruction to act
- state user-context and risk caveats before any recommendation
- verify decision-critical claims with real sources before strengthening a recommendation
- default the recommendation to `investigate_further` unless verified evidence, explicit user context, and the peer review all support a stronger `do`, `wait`, or `avoid` recommendation
- never recommend executing a trade, legal action, medical action, or other irreversible high-stakes action without qualified professional/user approval

## Workflow

### 1. Scope and source plan

State the topic, user role/goal if known, decision being informed, and evidence budget. Ask only if a missing answer materially changes source selection or interpretation and cannot be inferred.

An explicit `quick` request for this method normalizes to `standard` while
preserving `five_lens_briefing`; disclose that tier normalization. The valid
five-lens tiers are `standard`, `extensive`, and `deep`.

Use the frozen numeric search resource budget: standard is at most 3 queries,
4 sources, and 10 minutes per lens (15/20/50 overall); extensive is 5/6/15
(25/30/75 overall); deep is 8/10/25 (40/50/125 overall). Deep stops at
saturation or its hard ceiling. Record budget exhaustion as gaps and LOW
confidence; do not continue searching indefinitely.

### 2. Freeze, dispatch, and validate the perspective scan

Before the first dispatch, freeze exactly five sibling-blind assignment packets
as one immutable packet set with a set ID, digest, and pre-dispatch timestamp:
one for each named lens below. A packet contains shared scope, evidence budget,
and its LensKind only; it excludes sibling results, prior waves, contradiction
mapping, synthesis, recommendation, and peer review. Dispatch one independent
`LensResearcher` identity per packet. Capacity-bounded waves are allowed when
their coverage is exact, disjoint, and exhaustive; later waves cannot consume earlier results.
Each frozen packet also carries an explicit source_policy and isolation_policy.
Independent dispatch means distinct native dispatch or agent identities, not
distinct model identities: one model may serve multiple isolated assignments.

The packet set includes an ordered five-entry manifest. Each entry binds
`packet_id`, its exact LensKind, and a `content_digest` over the canonical
complete frozen packet. ContentDigest is `sha256:` plus 64 lowercase hex
SHA-256 over the exact UTF-8 bytes produced by RFC 8785 JSON Canonicalization
Scheme (JCS), with no trailing newline; packet preimage excludes `content_digest` and
`packet_set_digest` applies the same construction to the ordered manifest array
whose entries contain exactly `packet_id`, `lens_kind`, and `content_digest`.
Every delegated dispatch or fallback root pass repeats the matching packet
content digest. A changed packet body or digest mismatch invalidates the entire
lens stage.

Validate each return against its frozen assignment before accepting it. One
same-assignment schema-correction retry is allowed. If the lens stage still
fails, rerun the complete lens stage through evidenced sequential fallback or
block—never present a partial delegated/root mixture as independent research.
For every usable return, recompute `lens_result_digest` over the RFC 8785 JCS
bytes of `lens_result` only. Retain the five authoritative bodies in
`accepted_lens_results`, exactly equal to the peer input. The process record,
perspective scan, and question trace must repeat the matching LensKind, assignment ID, and digest,
and their presented lens fields must exactly project that accepted result,
including an empty source array when inference-only or unresolved evidence has
a recorded gap.

Record actual query/source uses, elapsed minutes, termination state, exhausted
dimensions, and downgrade evidence for every lens plus overall query/source
totals and observed wall-clock elapsed. A usable record never exceeds a
configured ceiling. Sequential fallback wall-clock is at least the sum of pass
times; delegated wall-clock is at least the sum of each wave's maximum member
time. Ceiling exhaustion requires an explicit gap and LOW lens
confidence; an over-ceiling run blocks.

Sequential fallback is only for explicit opt-out, real failed/unavailable
mechanism, supported configuration proof, or exact policy block. It still runs
five frozen-packet root passes, records reduced independence, omits invented
references, and retains peer critique as a separate fresh pass.

Every delegated dispatch or fallback root pass binds both its packet ID and
packet-set ID. Record the first lens execution timestamp after the set freeze;
this ordering proves later waves did not alter the frozen assignments.

Set `subagent_policy_state=delegation_triggered` and
`subagent_execution_mode=delegated` for this skill-instruction-triggered
method without a separate permission question. For fallback, record concrete
`sequential_fallback_evidence`; an exact policy block also records
`policy_blocking_source` and its no-exception basis.

### 3. Perspective scan results

Analyze the topic through five lenses. Use real sources where available; when a lens is reasoned from general domain knowledge rather than sourced evidence, label it LOW confidence until verified.

1. **Practitioner** — works with this daily. What practical realities are usually ignored? What would they warn about?
2. **Academic / technical expert** — studies the evidence. What does the best evidence say? Where does evidence contradict popular belief?
3. **Skeptic** — challenges the mainstream view. What is the strongest counterargument? What evidence do proponents ignore?
4. **Economist / incentives analyst** — follows incentives. Who profits? What financial, organizational, or status incentives shape the narrative?
5. **Historian / pattern matcher** — compares earlier cycles. What historical parallels exist? How did similar situations play out?

For each lens produce:

- core position in 2-3 sentences
- exact sources or verified URLs from the accepted lens result; preserve an
  empty array for inference-only or unresolved evidence with a recorded gap
- likely blind spot
- one unique insight no other lens supplied
- confidence level and source notes

### 4. Question trace / evidence ledger

STORM is not just fixed perspectives; it is perspective-guided question asking with retrieval-backed answers and follow-up questions before synthesis. Before building the contradiction map, create a lightweight question trace:

For each lens:

- ask at least one lens-specific research question that lens would naturally ask
- answer it with source-grounded evidence when tools/sources are available
- record sources or verified URLs used for the answer
- retain every material follow-up prompted by the first answer, contradiction, or gap; do not impose a numeric cap
- for each follow-up, record its question, answer or gap, sources/verified URLs, and evidence status; when no material follow-up exists, record one typed `none_needed` decision
- label whether each answer is source-backed, inference-only, or unresolved

Decision-critical evidence may use a verified public URL, repository-relative
locator, opaque authenticated connector/record identifier, or offline
bibliographic citation. Non-URL methods do not fabricate a URL. Public URLs are
successfully checked and globally routable, never reserved-domain, private,
loopback, link-local, or alternate-encoded addresses. Keep every reference free
of credentials, tokens, PII, parent traversal, and absolute host paths.

Do not synthesize from a lens until its key question and at least one answer/gap entry are recorded. If source access is unavailable, keep the question trace and mark answers as inference-only or unresolved rather than pretending they are source-backed.

### 5. Root-owned contradiction map

After all five results validate, the root Orchestrator alone builds the
contradiction map. The disagreements are usually the highest-value part of the
briefing.

Include:

- direct conflicts between lenses, with the clashing claims named
- which lens has strongest evidence and why
- which lens has weakest evidence and why
- what every lens agrees on
- the biggest unresolved question
- what none of the lenses addressed

### 6. Root-owned synthesis briefing

Combine the scan and contradiction map into a decision-ready briefing:

- one-paragraph executive summary with nuance
- 5 key findings ranked by reliability
- for each finding, which lenses support and challenge it
- hidden connection visible only after combining lenses
- practical implication for the user's role/goal
- recommended action: do / wait / avoid / investigate further, with high-stakes caveats when applicable
- frontier question that would most change the conclusion

### 7. Independent peer review

Dispatch a distinct `ResearchPeerReviewer` after the root initial synthesis.
The reviewer critiques rather than rewrites root-owned synthesis; it must be a
separate identity from every LensResearcher. If only peer review fails, retain
validated lens results and use a separately recorded reviewer fallback.
The Orchestrator creates `peer_review_assignment_id`, the worker echoes it, and
the Orchestrator—not the worker—records native peer reviewer identity metadata.
When no decision-critical source can be verified, pass an empty verified-source
ledger with verification gaps; peer review must downgrade or block unsupported
claims rather than inventing evidence or refusing the review.

The peer review must assess:

- confidence score for each major claim
- weakest claim and how to verify it
- source bias or lens dominance
- missing sixth perspective that could change the conclusion
- evidence that would falsify the recommendation
- revision to the recommendation if the critique changes it

When verdict is `revise`, the root Orchestrator records a revision disposition
for every required revision exactly once: `applied` or `claim_downgraded`, with
closure evidence. The peer worker does not self-attest those changes. An
unresolved revision blocks presentation. The Orchestrator records
`revision_disposition_id` in peer review and repeats that exact value as
`peer_review_revision_disposition_id` in process evidence.

For `accepted` and `accepted_with_concerns`, `required_revisions` is empty. A
`revise` verdict has one or more required revisions and complete orchestrator-
owned dispositions for each. Unusable or blocked peer results cannot present.

## Verification rule

The five-lens method produces hypotheses and structure; it does not replace source verification. Before finalizing:

- verify the top 3-5 decision-critical claims with real sources when tools are available
- keep URLs only if verified per `url-verify.md`
- downgrade or mark as gaps any claim that could not be verified
- separate "lens inference" from "source-backed finding"

## Output format

```text
RESEARCH: [topic]
Method: five_lens_briefing
Tier: [standard/extensive/deep]
Evidence budget: [source/angle target and whether met]

PERSPECTIVE SCAN
1. Practitioner — confidence: [HIGH/MEDIUM/LOW]
   Core position: ...
   Evidence/source notes: ...
   Blind spot: ...
   Unique insight: ...
2. Academic / technical expert — ...
3. Skeptic — ...
4. Economist / incentives analyst — ...
5. Historian / pattern matcher — ...

QUESTION TRACE / EVIDENCE LEDGER
1. Practitioner
   Question: ...
   Source-grounded answer: ...
   Sources / verified URLs: ...
   Follow-ups:
   - decision: follow_up
     Question: [first material follow-up]
     Answer or open gap: ...
     Sources / verified URLs: ...
     Evidence status: source-backed / inference-only / unresolved
   - decision: follow_up
     Question: [second material follow-up]
     Answer or open gap: ...
     Sources / verified URLs: ...
     Evidence status: source-backed / inference-only / unresolved
   Evidence status: source-backed / inference-only / unresolved
2. Academic / technical expert — ...
3. Skeptic — Follow-ups: [{decision: none_needed, answer_or_gap: no material follow-up, sources_or_verified_urls: [verified source], evidence_status: source-backed}]
4. Economist / incentives analyst — ...
5. Historian / pattern matcher — ...

CONTRADICTION MAP
- Direct conflicts: ...
- Strongest evidence: ...
- Weakest evidence: ...
- Consensus: ...
- Biggest unresolved question: ...
- Missing angle/gap: ...

FINDINGS
1. [source-backed factual claim or decision insight] — confidence: [HIGH/MEDIUM/LOW]
   Sources: [source names]
   Verified URLs: [verified URLs, if any]
2. ...

CONFLICTS
- [source or lens A] says X; [source or lens B] says Y — [assessment]
- none found, if conflicts were explicitly checked and none were found

SYNTHESIS
- Executive summary: ...
- Key findings ranked by reliability: ...
- Hidden connection: ...
- Actionable implication for [role/goal]: ...
- Recommendation: do / wait / avoid / investigate further
- High-stakes caveat/context, if applicable: ...
- Frontier question: ...

PEER REVIEW
- Confidence scores: ...
- Weakest claim: ...
- Bias check: ...
- Missing sixth perspective: ...
- Falsification test: ...
- Revised recommendation if needed: ...

FIVE-LENS PROCESS EVIDENCE
- Frozen packet-set ID/digest, ordered packet manifest/content digests, pre-dispatch record ID, and first-execution evidence: ...
- Lens mode and exact five dispatches/root passes with assignment/packet-set/content-digest bindings and return_validated: ...
- Peer assignment, native identity or fresh fallback pass, and mode: ...
- Reduced independence and admissible fallback evidence, if applicable: ...
- Search resource budget and exhaustion gaps, if any: ...
- Revision disposition ID matching peer review and applied/downgraded closure, when verdict=revise: ...

SOURCES / VERIFIED URLS
- ...

GAPS
- ...
```
