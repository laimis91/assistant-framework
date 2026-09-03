# Research

Tiered information gathering — scale effort to the question's importance.

## Methods

- **source_research** — default source-first workflow for factual questions, comparisons, and investigations.
- **five_lens_briefing** — STORM-inspired decision briefing. Read `five-lens-briefing.md` when the topic needs practitioner, academic/technical expert, skeptic, incentives, and historical lenses before synthesis.

## Modes

| Mode | Evidence budget | When to use |
|---|---|---|
| **Quick** | 1 authoritative source or 2 weak sources | Simple lookup, known answer exists somewhere |
| **Standard** | 3 differentiated research angles | Most research needs, need cross-validation |
| **Extensive** | 3+ angles with 2+ credible sources per major claim | Deep multi-domain, need comprehensive coverage |
| **Deep** | Iterative until sources stop changing the answer | Market mapping, threat landscapes, novel domains |

## Quick Research
Use the narrowest query likely to find an authoritative answer. Verify any URLs found (see `url-verify.md`).

## Standard Research
Cover 3 differentiated research angles:
1. **Direct evidence** — search for the most authoritative source
2. **Alternative perspective** — search from a different angle or keyword set
3. **Counter-evidence** — search for reasons the obvious answer might be wrong

Synthesize: What agrees? What's unique? What conflicts?

## Extensive Research
Generate 3+ research angles via structured thinking. For decision-grade questions, prefer the `five_lens_briefing` method: practitioner, academic/technical expert, skeptic, economist/incentives analyst, and historian/pattern matcher.
For each major claim, seek at least 2 credible sources or mark the claim LOW confidence. Synthesize by theme and cross-validate claims across angles.

## Five-Lens Briefing
Use `five-lens-briefing.md` when the question is not just "what is true?" but "how should I understand this and what should I do?" The method requires a perspective scan, contradiction map, synthesis, and peer review. It is compatible with standard, extensive, or deep tiers depending on risk and evidence needs.

If the user explicitly requests `quick` with `five_lens_briefing`, normalize the
tier to `standard`, preserve the selected five-lens method, and disclose the
tier normalization. `quick` remains valid for ordinary `source_research`.

## Deep Investigation
Iterative progressive research:
1. Broad landscape scan across differentiated source classes
2. Score entities/findings by importance
3. Deep-dive the highest-value findings
4. Repeat until coverage is sufficient

## Delegation by method

`source_research` is direct-capable: research angles are required, while
`subagent_policy_state=not_required` and
`subagent_execution_mode=not_applicable`. Never reduce source diversity because
delegation is unavailable.

`five_lens_briefing` is a Process method. Freeze one sibling-blind assignment
packet for each required LensKind before the first dispatch, then send one
independent LensResearcher per lens through the selected handoff. Capacity may
require waves, but later waves cannot consume earlier results. The root
Orchestrator alone synthesizes validated results; a separate
ResearchPeerReviewer critiques that initial synthesis.

Freeze an ordered five-entry packet manifest: each entry has `packet_id`, its
exact LensKind, and a `content_digest`. A ContentDigest is `sha256:` plus 64
lowercase hex SHA-256 over the exact UTF-8 bytes produced by RFC 8785 JSON
Canonicalization Scheme (JCS), with no trailing newline. Packet preimages include every
packet field except `content_digest`; packet-set preimage is its ordered
`packet_id`, `lens_kind`, `content_digest` manifest. Every delegated
dispatch or fallback root pass repeats the matching packet content digest; any
mismatch invalidates the complete lens stage.

After validating a usable return, recompute `lens_result_digest` over the RFC
8785 JCS bytes of `lens_result` only. Carry its LensKind, assignment ID, and digest unchanged into
an authoritative five-entry `accepted_lens_results` ledger that exactly equals
the peer-review input. Carry the same identity into the process record,
perspective scan, and question trace;
the presented fields must be exact projections of that accepted result. Preserve
valid empty source arrays for inference-only or unresolved results rather than
inventing a source marker.

This skill instruction sets `subagent_policy_state=delegation_triggered` and
`subagent_execution_mode=delegated` without a separate permission question.
Record a non-empty trigger scope. An opt-out, actual spawn failure or supported
configuration proof sets sequential fallback evidence; an exact policy block
also records its blocking source and no-exception basis.

Use sequential fallback only for explicit opt-out, real dispatch failure or
unavailability, supported configuration proof, or an exact policy block. Run
five frozen-packet root passes, record reduced independence, and retain peer
critique as a separate fresh pass. After one same-assignment schema-correction
retry, rerun the complete lens stage through evidenced fallback or block; do
not mix partial delegated and root-authored lenses while claiming independence.

For five-lens work, carry a numeric bounded search resource budget through the
root process and every frozen packet. Standard allows at most 3 queries, 4
sources, and 10 minutes per lens (15/20/50 overall); extensive allows 5/6/15
(25/30/75 overall); deep allows 8/10/25 (40/50/125 overall). Deep stops at
saturation or its hard ceiling. When a limit is exhausted, record gaps and
downgrade confidence instead of extending the search. These five-lens ceilings
do not change proportional direct `source_research` behavior.
Record SearchResourceUsage for every lens and the root: actual queries/sources,
elapsed minutes, termination state, exhausted dimensions, and downgrade
evidence. Summed query/source uses must match root totals, while root elapsed is
observed wall-clock. It is at least the sum of sequential fallback pass times,
or the sum of each delegated wave's maximum member time. Usable output cannot exceed a ceiling; reaching one records
an explicit gap and LOW lens confidence, while an over-ceiling run blocks.

## Candidate mechanisms

When the question asks why/how something happens, what caused a pattern, or
which improvement mechanisms to try, produce candidate mechanisms. Treat them
as hypotheses to validate, not proven causes. Each candidate mechanism needs
supporting evidence, confidence, counterevidence/conflicts, gaps, and a
validation method.

## Mandatory: URL Verification
**Every URL presented to the user MUST be verified.** See `url-verify.md`.
AI agents hallucinate plausible-looking URLs routinely. Never present an unverified URL.
Evidence that is verifiable only through a repository, authenticated source, or
offline authoritative source remains valid without a URL. Record its method and
a stable repository-relative locator, opaque connector/record identifier, or
bibliographic citation. A public URL must be globally routable and successfully
checked; reserved domains and private, loopback, link-local, or alternate-encoded
addresses are not public evidence. Never expose credentials, tokens, PII,
parent traversal, or absolute host paths in that reference.

## Mandatory: Confidence Scoring
Every research finding gets a confidence level:

| Level | Criteria |
|---|---|
| **HIGH** | 3+ independent sources agree, primary/official source found |
| **MEDIUM** | 2 sources agree, or 1 authoritative source |
| **LOW** | Single source, or sources conflict |

Always show confidence level with findings. Flag LOW-confidence findings explicitly.

## Output format

```
RESEARCH: [question]
Mode: [quick/standard/extensive/deep]
Evidence budget: [source/angle target and whether it was met]

FINDINGS
1. [finding] — confidence: HIGH
   Sources: [source 1], [source 2]
2. [finding] — confidence: MEDIUM
   Source: [source]
3. [finding] — confidence: LOW (single source, unverified)
   Source: [source]

CANDIDATE MECHANISMS (when requested by why/how/causal/improvement questions)
1. [mechanism] — confidence: MEDIUM — status: candidate
   Evidence: [source-backed evidence or inference notes]
   Counterevidence/conflicts: [conflicting evidence or none found]
   Gaps: [missing evidence or uncertainty]
   Validation method: [test, metric, comparison, experiment, or next check]

CONFLICTS
- [source A] says X, [source B] says Y — [assessment of which is more likely correct]

GAPS
- [what we couldn't find or verify]
```
