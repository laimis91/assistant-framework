# Creative (Verbalized Sampling)

Generate diverse, non-obvious options by explicitly sampling low-probability ideas before selecting the best.

## When to use
- Naming things (projects, APIs, variables, products)
- Generating novel approaches when obvious solutions feel stale
- Brainstorming where diversity of ideas matters more than speed
- Any creative task where the first idea is rarely the best

## Why this works
LLMs tend toward mode-collapse — returning the most probable (common, generic) response. By explicitly generating multiple low-probability options first, then selecting, you get 1.6-2.1x more diverse output with ~25% higher quality (Zhang et al., 2024).

## Process

### Step 1: Generate 5 diverse options internally
In your thinking, generate 5 options. Each must:
- Have < 10% individual probability (avoid the obvious first answer)
- Span different conceptual directions
- Include at least one that feels surprising or unconventional

### Step 2: Evaluate against criteria
For each option, score against the user's stated or implied criteria.

### Step 3: Present the best 1-3
Show only the top options with brief rationale. User doesn't need to see all 5.

## Output format

```
CREATIVE OPTIONS for: [what we're generating]

Option A: [name/idea]
  Why: [rationale, what makes this good]

Option B: [name/idea]
  Why: [rationale, different angle]

Option C: [name/idea] (if warranted)
  Why: [rationale, the surprising one]

Recommendation: [which and why]
```

## Tips
- The "surprising" option often has the most value — it breaks you out of conventional thinking
- If all 5 internal options feel similar, you're not being diverse enough. Try inverting assumptions.
- Works best combined with constraints: "Name this API endpoint, must be < 20 chars, verb-first"
