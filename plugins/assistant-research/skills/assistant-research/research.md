# Research

Tiered information gathering — scale effort to the question's importance.

## Modes

| Mode | Agents | When to use |
|---|---|---|
| **Quick** | 1 (WebSearch) | Simple lookup, known answer exists somewhere |
| **Standard** | 3 parallel | Most research needs, need cross-validation |
| **Extensive** | 6-12 parallel | Deep multi-domain, need comprehensive coverage |
| **Deep** | Iterative | Market mapping, threat landscapes, novel domains |

## Quick Research
Single WebSearch query. Verify any URLs found (see `url-verify.md`).

## Standard Research
Launch 3 agents in parallel, each with a different angle on the same question:
1. **Agent 1**: Direct answer — search for the most authoritative source
2. **Agent 2**: Alternative perspective — search from a different angle or keyword set
3. **Agent 3**: Counter-evidence — search for reasons the obvious answer might be wrong

Synthesize: What agrees? What's unique? What conflicts?

## Extensive Research
Generate 3 research angles via deep thinking. Launch 2-4 agents per angle.
Synthesize by theme, cross-validate claims across agents.

## Deep Investigation
Iterative progressive research:
1. Broad landscape scan (6-12 agents)
2. Score entities/findings by importance
3. Deep-dive the highest-value findings
4. Repeat until coverage is sufficient

Use `memory_add_insight` to record notable findings in the knowledge graph for future sessions.

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
