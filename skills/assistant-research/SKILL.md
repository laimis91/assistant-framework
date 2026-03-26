---
name: assistant-research
description: "Research and investigation tools for information gathering. Use when you need to research a topic, investigate an entity, look into a technology, or verify URLs. Triggers on: 'research', 'investigate', 'look into', 'find out about', 'what is', 'compare options for'."
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

Research produces confidence-scored findings. Present results with:
- Confidence level (high/medium/low) per finding
- Source attribution
- Verified URLs only
