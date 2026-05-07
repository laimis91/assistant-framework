---
name: assistant-clarify
description: "Clarification workflow for messy, ambiguous, or multi-intent prompts. Use when the user writes in fragments, compresses several asks together, leaves key goals or constraints implicit, or signals uncertainty about what they actually want. Triggers on: 'chaotic prompt', 'messy prompt', 'unclear prompt', 'figure out what I mean', 'help me structure this', 'not sure how to ask this', 'can you make sense of this'."
effort: medium
triggers:
  - pattern: "chaotic prompt|messy prompt|unclear prompt|figure out what i mean|help me structure this|turn this into a structured prompt|clarify my request|not sure how to ask this|can you make sense of this|i'm not sure what i'm asking|not sure what i need|help me untangle this|sort this out with me|i have a few things mixed together|this might be two separate asks|i'm deciding between|should i do x or y"
    priority: 75
    min_words: 4
    reminder: "This request matches assistant-clarify. Invoke it to restate the likely goal, ask 1-3 high-yield clarification questions, and convert the input into a structured brief before proceeding."
---

# Clarification Workflow

Use this when the user's message is hard to execute safely because it is fragmented, multi-intent, or underspecified.

Do not tell the user their prompt is "chaotic." Treat it as a normal collaboration problem: extract signal, reduce ambiguity, and keep momentum.

## Available Tools

| Tool | File | When to use |
|---|---|---|
| **Chaotic Prompts** | `chaotic-prompts.md` | User intent is compressed, mixed, or partially implicit. |
| **Research Notes** | `research-notes.md` | Need the psychology rationale behind the workflow. |

## Usage

Read `chaotic-prompts.md` when any of these are true:
- Multiple asks are mixed together without priorities
- Goals, deliverables, or constraints are implied rather than stated
- The message jumps between symptoms, solutions, and decisions
- References like "it", "that", or "the thing" do not resolve cleanly
- The safest next step is a short Q&A instead of guessing

## Output

Return:
1. **Interpretation** - the user's likely goal in one or two sentences.
2. **Structured brief** - knowns, unknowns, assumptions, constraints, and likely deliverables.
3. **Clarifying questions** - one to three high-yield questions with defaults or recommendations.
4. **Execution target** - the confirmed next action once ambiguity is reduced, or the blocker if it is not.
5. **Status** - ready to execute, needs clarification, or blocked.
