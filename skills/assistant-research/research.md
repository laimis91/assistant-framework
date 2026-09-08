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

`quick` remains valid for ordinary `source_research`.

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
Apply the same safe reference and public-URL rules to both sides of every
conflict record.

## Mandatory: Confidence Scoring
Every research finding gets a confidence level:

| Level | Criteria |
|---|---|
| **HIGH** | `source_provenance` proves both 3+ unique independence keys and at least one primary/official source |
| **MEDIUM** | 2 sources agree, or 1 authoritative source |
| **LOW** | Single source, or sources conflict |

Keep public `sources` as strings. Optional `source_provenance` has exact
`source`, `independence_key`, and `authority` (`primary`, `official`, or
`secondary`) rows whose unique source set equals `sources`; HIGH requires it,
3+ independent agreeing sources, and primary/official evidence.
Always show confidence and flag LOW explicitly.

## Output format

```
RESEARCH: [question]
Mode: [quick/standard/extensive/deep]
Evidence budget: [source/angle target and whether it was met]

FINDINGS
1. [finding] — confidence: HIGH
   Sources: [source 1], [source 2]
   Source provenance: [{source, independence_key, authority}, ...]
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
