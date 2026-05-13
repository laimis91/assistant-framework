# Research

Tiered information gathering — scale effort to the question's importance.

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
Generate 3+ research angles via structured thinking. For each major claim, seek at least 2 credible sources or mark the claim LOW confidence.
Synthesize by theme and cross-validate claims across angles.

## Deep Investigation
Iterative progressive research:
1. Broad landscape scan across differentiated source classes
2. Score entities/findings by importance
3. Deep-dive the highest-value findings
4. Repeat until coverage is sufficient

Use `memory_add_insight` to record notable findings in the knowledge graph for future sessions.

## Adapter-Aware Delegation

Research angles are required; subagent dispatch is optional. If the active adapter and user/tool policy permit parallel agents, each angle can be delegated independently. If not, run the angles sequentially in the main session and record that delegation was unavailable. Never reduce source diversity just because delegation is unavailable.

## Mandatory: URL Verification
**Every URL presented to the user MUST be verified.** See `url-verify.md`.
AI agents hallucinate plausible-looking URLs routinely. Never present an unverified URL.

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

CONFLICTS
- [source A] says X, [source B] says Y — [assessment of which is more likely correct]

GAPS
- [what we couldn't find or verify]
```
