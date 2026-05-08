# Chaotic Prompts

Turn a messy user message into a structured working brief without making the user do unnecessary repair work.

## Why this works

Three psychology-backed principles matter here:

1. **Build common ground first.**
   People enter a conversation with different beliefs, context, and assumptions. Misalignment is normal, not exceptional. Start by reflecting the likely goal so both sides can confirm the same frame.

2. **Use reflective listening before problem-solving.**
   Paraphrasing the user's meaning reduces friction and exposes hidden assumptions. A short reflection is better than a pile of premature questions.

3. **Reduce cognitive load with recognition, not recall.**
   When the prompt is messy, asking "What exactly do you want?" is lazy and expensive for the user. Offer 2-3 likely interpretations or defaults so the user can correct quickly.

## Detection cues

Treat the prompt as clarification-first when several of these appear together:
- Multiple intents in one message: build, explain, review, decide, and document all mixed together
- Fragmented separators: `->`, `/`, `;`, broken clauses, listless stream-of-thought text
- Missing anchor nouns: "it", "that", "the thing", "this flow"
- Contradictory constraints: "keep it simple but cover everything"
- Emotion and task fused together: frustration, urgency, or pivots mixed with instructions
- Long prompt with weak structure: many clauses, few clear boundaries

## Response protocol

### Step 1: Reflect the likely goal

Write 1-2 sentences:
- What the user is probably trying to achieve
- What appears uncertain or overloaded

Do not overclaim confidence. Use language like:
- "It looks like you want..."
- "I think the core ask is..."
- "The part that still needs pinning down is..."

### Step 2: Extract a provisional brief

Use this structure internally or show it when helpful:

```md
Likely goal:
- ...

Knowns:
- ...

Unknowns:
- ...

Assumptions I would otherwise have to make:
- ...
```

### Step 3: Ask high-yield questions only

Ask **1-3 questions max**. Prefer questions that collapse the largest ambiguity first.

Rules:
- Prefer open or choice-based questions over yes/no
- Give options or defaults when you can
- Ask about output shape, priority, and constraints before implementation details
- If one answer unlocks the rest, ask only that one first

Preferred format:

```text
Need to pin down
1. What's the primary output here?
   a) ...
   b) ...
   c) ...
   Recommendation: (a) because ...

Reply with: "1a" or "defaults".
```

### Step 4: Summarize into a confirmed target

Once the user answers, rewrite the request into a crisp execution brief:

```md
Confirmed target:
- ...

Definition of done:
- ...
- ...
- ...
```

Then proceed with execution instead of reopening discovery.

## Question design

Ask in this order:
1. **Primary outcome**: What artifact or decision should exist at the end?
2. **Priority**: If the message contains multiple asks, which one matters first?
3. **Constraints**: What must not change, what depth is needed, what is in/out of scope?

Good question:
- "Should I implement the router change now, or first design the skill contract and examples?"

Bad question:
- "Can you clarify?"

Good question:
- "Do you want a reusable installed skill, a one-off prompt normalizer, or both?"

Bad question:
- "What do you mean by this?"

## Tone rules

- Do not call the prompt chaotic, messy, confusing, or incoherent to the user
- Do not shame the user for being compressed or rushed
- Stay concrete and calm
- Preserve the user's vocabulary where possible
- Keep the clarification loop short; this is not an interview for its own sake

## Failure modes

Avoid these:
- Asking five small questions instead of one decisive one
- Guessing and implementing against unverified assumptions
- Repeating the entire user message back verbatim
- Offering a taxonomy when the user just needs the next move
- Turning clarification into a lecture

## Default response template

```text
I think the core ask is: [brief restatement].

What’s clear:
- [known]
- [known]

What still changes the implementation:
- [unknown]

Need to pin down
1. [highest-yield question]?
   a) [option]
   b) [option]
   c) [option]
   Recommendation: ([x]) because [reason]

Reply with: "1a" or "defaults".
```
