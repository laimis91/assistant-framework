---
name: assistant-clarify
description: "Clarify ambiguous or multi-intent requests. Use when the user asks to untangle, structure, or restate what they mean."
---

# Clarification Workflow

Use this when the user's message is hard to execute safely because it is fragmented, multi-intent, or underspecified.

Do not tell the user their prompt is "chaotic." Treat it as a normal collaboration problem: extract signal, reduce ambiguity, and keep momentum.

## Available Tools

| Tool | File | When to use |
|---|---|---|
| **Chaotic Prompts** | `chaotic-prompts.md` | User intent is compressed, mixed, or partially implicit. |
| **Research Notes** | `research-notes.md` | Need the psychology rationale behind the workflow. |

## Contracts

Read and follow these contracts before running the clarification workflow.

| Contract | File | Purpose |
|---|---|---|
| **Input** | `contracts/input.yaml` | Required context to resolve before clarifying a request. |
| **Output** | `contracts/output.yaml` | Required artifacts to produce before proceeding with execution. |

This is a Utility skill. It has no phase gates or sub-agent handoffs.

## Goal

Turn ambiguous, multi-intent, or underspecified prompts into a concise execution brief without shaming the user or stalling clear work. Preserve momentum with evidence-backed defaults when ambiguity does not materially change the next action. Reversibility alone, convention, or a plausible preference does not establish user intent.

## Success Criteria

- The likely goal, deliverables, constraints, and unknowns are separated.
- Clarifying questions cover every material, non-discoverable decision that lacks a safe default; they are grouped by topic and are not numerically capped.
- Each question includes a recommended default when a safe default exists.
- The next execution target is explicit once ambiguity is reduced.
- If evidence-backed safe defaults are enough, status is `ready_to_execute` and execution may proceed without asking ritual questions.
- A proposed product choice requires a question and an explicit user answer before dependent work proceeds; a recommendation is not an answer.

## Constraints

- Ask only when guessing would materially change correctness, scope, priority, safety, or user-visible output.
- Do not ask ritual questions when the prompt already contains enough signal to proceed.
- Preserve the user's wording and intent; do not reframe into a different task.
- Preserve evidence-backed existing behavior and justified technical defaults, but do not infer product intent from reversibility, convention, or plausibility alone.
- For proposed product choices, ask and wait for an explicit user answer before dependent work; do not treat a recommended default as consent.
- Prefer a single decision, bounded choices, and a recommended default over open-ended interrogation. Keep each interaction concise and goal/file-oriented, but do not suppress material questions to meet an arbitrary count.
- Treat company/security constraints as real blockers: do not ask for secrets or request unapproved external sharing as a clarification shortcut.

## Decision Rule: Ask or Act

Before asking, classify the ambiguity:

- **Safe default**: the interpretation is supported by the user's stated intent, conversation context, applicable policy, or relevant existing behavior, and it does not decide a material product question. A justified technical default may fill implementation details. Reversibility alone, convention, or a plausible preference does not establish user intent.
- **Bounded choice**: plausible paths would materially change the outcome. Ask concise, grouped questions for all currently material decisions. For proposed product choices, wait for the user's explicit answer before dependent work; a recommendation is not consent.
- **Material blocker**: action could be wrong, unsafe, destructive, policy-violating, or expensive. Stop and ask.

Default to action for low-risk discovery steps such as reading local files, inspecting existing project docs, or drafting a provisional brief.

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
3. **Clarifying questions** - every material question, grouped by topic; each states why it matters, risk if guessed, and a default or `none`. Use an empty list when ready to execute.
4. **Execution target** - the confirmed next action once ambiguity is reduced, or the blocker if it is not.
5. **Status** - ready to execute, needs clarification, or blocked.

## Stop Rules

- Stop and ask only when the next action would be meaningfully different depending on the answer.
- Stop after presenting clarification questions only when status is `needs_clarification` or `blocked`.
- If the request becomes clear during analysis, proceed with the execution target instead of continuing to clarify.
