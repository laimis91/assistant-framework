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

## Workflow

### 1. Scope and source plan

State the topic, user role/goal if known, decision being informed, and evidence budget. Ask only if a missing answer materially changes source selection or interpretation and cannot be inferred.

### 2. Perspective scan

Analyze the topic through five lenses. Use real sources where available; when a lens is reasoned from general domain knowledge rather than sourced evidence, label it LOW confidence until verified.

1. **Practitioner** — works with this daily. What practical realities are usually ignored? What would they warn about?
2. **Academic / technical expert** — studies the evidence. What does the best evidence say? Where does evidence contradict popular belief?
3. **Skeptic** — challenges the mainstream view. What is the strongest counterargument? What evidence do proponents ignore?
4. **Economist / incentives analyst** — follows incentives. Who profits? What financial, organizational, or status incentives shape the narrative?
5. **Historian / pattern matcher** — compares earlier cycles. What historical parallels exist? How did similar situations play out?

For each lens produce:

- core position in 2-3 sentences
- strongest evidence or source class
- likely blind spot
- one unique insight no other lens supplied
- confidence level and source notes

### 3. Contradiction map

Find where the lenses disagree. The disagreements are usually the highest-value part of the briefing.

Include:

- direct conflicts between lenses, with the clashing claims named
- which lens has strongest evidence and why
- which lens has weakest evidence and why
- what every lens agrees on
- the biggest unresolved question
- what none of the lenses addressed

### 4. Synthesis briefing

Combine the scan and contradiction map into a decision-ready briefing:

- one-paragraph executive summary with nuance
- 5 key findings ranked by reliability
- for each finding, which lenses support and challenge it
- hidden connection visible only after combining lenses
- practical implication for the user's role/goal
- recommended action: do / wait / avoid / investigate further
- frontier question that would most change the conclusion

### 5. Peer review

Self-critique before presenting:

- confidence score for each major claim
- weakest claim and how to verify it
- source bias or lens dominance
- missing sixth perspective that could change the conclusion
- evidence that would falsify the recommendation
- revision to the recommendation if the critique changes it

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

CONTRADICTION MAP
- Direct conflicts: ...
- Strongest evidence: ...
- Weakest evidence: ...
- Consensus: ...
- Biggest unresolved question: ...
- Missing angle/gap: ...

SYNTHESIS
- Executive summary: ...
- Key findings ranked by reliability: ...
- Hidden connection: ...
- Actionable implication for [role/goal]: ...
- Recommendation: do / wait / avoid / investigate further
- Frontier question: ...

PEER REVIEW
- Confidence scores: ...
- Weakest claim: ...
- Bias check: ...
- Missing sixth perspective: ...
- Falsification test: ...
- Revised recommendation if needed: ...

SOURCES / VERIFIED URLS
- ...

GAPS
- ...
```
