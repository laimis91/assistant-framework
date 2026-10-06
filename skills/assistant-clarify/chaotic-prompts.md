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

### Step 3: Ask concise, grouped rounds

Ask all currently material questions that still change execution, grouped by decision topic. There is no numeric question quota; keep each round concise and avoid asking questions that context can resolve.

Rules:
- Prefer open or choice-based questions over yes/no
- Give options or recommendations when useful, while making clear that a recommendation is not the user's answer
- Ask about output shape, priority, and constraints before implementation details
- If one answer changes which other decisions matter, ask it first, then reassess before the next round
- After each response, reassess unresolved decisions and treat only explicitly answered choices as resolved; expose newly material questions in another concise round.
- For proposed product choices, wait for an explicit answer before dependent work; a recommendation is not consent.

Preferred format:

```text
Need to pin down
1. What's the primary output here?
   a) ...
   b) ...
   c) ...
   Recommendation: (a) because ...

Reply with the numbered choice or choices, such as "1a, 2c". You may answer only the decisions that are ready; I will reassess what remains open.
```

### Step 4: Summarize into a confirmed target

Once the user answers, reassess all unresolved decisions. Rewrite the request into a crisp execution brief only when the material product choices have explicit answers:

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
- Asking scattered small questions instead of concise, grouped decisive questions
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
1. [currently material decision question]?
   a) [option]
   b) [option]
   Recommendation: ([x]) because [reason]
2. [another currently material decision, if any]?
   ...

Reply with the numbered choice or choices. After each reply, I will reassess the remaining questions.
```
