---
name: assistant-research
description: "This skill provides research and investigation tools for information gathering. Use when the user says 'research', 'investigate', 'look into', 'find out about', 'what is', 'compare options for'. Also activates during the workflow's Discovery phase when external information gathering is needed."
triggers:
  - pattern: "research|investigate|look into|find out about|what is|compare options for"
    priority: 65
    min_words: 4
    reminder: "This request matches assistant-research. Consider whether the Skill tool should be invoked with skill='assistant-research' for research and investigation."
---

# Research Tools

## Contracts

| Contract | File | Purpose |
|---|---|---|
| **Input** | `contracts/input.yaml` | Question, tier, tool selection |
| **Output** | `contracts/output.yaml` | Findings with confidence scores, conflicts, gaps |
| **Phase Gates** | `contracts/phase-gates.yaml` | Search → Synthesize → Verify pipeline gates |

**Rules:**
- Every finding must have a confidence level (HIGH/MEDIUM/LOW) based on source count
- Every URL must be verified before presenting to user
- Conflicts and gaps must be explicitly checked and reported (even if empty)

On-demand investigation capabilities with tiered depth and URL verification.

## Goal

Answer research questions with evidence-weighted findings, verified URLs, explicit conflicts, and clear gaps.

## Success Criteria

- Research depth matches the decision risk and evidence available.
- Findings include confidence levels based on source quality and agreement.
- URLs are verified before presentation or explicitly omitted/flagged.
- Conflicts and gaps are reported even when the answer is otherwise clear.

## Constraints

- Ask only when the missing scope materially changes source selection, depth, jurisdiction/domain, or decision criteria and cannot be inferred.
- Do not present single-source claims as high confidence unless the source is primary/official and the claim is directly supported.
- Do not hardcode subagent counts as mandatory behavior; use evidence budgets and research angles that fit the active adapter.

## Available Tools

| Tool | File | When to use |
|---|---|---|
| **Research** | `research.md` | Information gathering at 4 tiers: quick / standard / extensive / deep |
| **Investigate** | `investigate.md` | Deep entity/domain investigation with ethical framework |
| **Verify URLs** | `url-verify.md` | Validate any URLs before presenting to user |

## Usage

Read the relevant tool file when the situation calls for it.

**Choosing the right tier (Research tool):**
- **Quick**: Single-source lookup, factual questions
- **Standard**: Multi-source comparison, technology evaluation
- **Extensive**: Comprehensive analysis, decision support with multiple perspectives
- **Deep**: Full investigation with primary sources, expert synthesis

**When to use Investigate vs Research:**
- Research: "What caching libraries exist for .NET?" (broad exploration)
- Investigate: "How does Redis Cluster handle failover?" (deep dive on specific entity)

**URL Verification:**
Always verify URLs before presenting them to the user. Dead links erode trust.

## Output

Return:
- **Status** - completion state and confidence for the research result.
- **Answer** - concise synthesis of the research result.
- **Findings** - confidence-scored findings with source attribution.
- **Sources** - verified URLs only, with enough context to understand relevance.
- **Conflicts** - conflicting evidence or interpretations, or "none found".
- **Gaps** - unanswered questions, weak evidence, stale sources, or recommended next checks.

## Stop Rules

- Stop and ask one focused question only when scope or decision criteria would materially change source selection or interpretation.
- Stop and report a gap when required sources are inaccessible, stale, conflicting, or too weak for the requested confidence.
- Do not finalize with unverified URLs.
