# Code Explainer

## Protocol

### When to Use

- User says "explain this code" or "doc this"
- User is learning a new part of the codebase
- Complex logic that would benefit from documentation

### Step 1: Understand Context

Before explaining:
- What does this code do in the larger system?
- Who calls it? What calls it?
- What are the important design decisions?
- What's non-obvious or surprising?

### Step 2: Generate Explanation

Adapt depth to complexity:

**Simple code** (< 20 lines, clear logic):
```markdown
## [Function/Class Name]

[1-2 sentences: what it does and why]

Key points:
- [non-obvious detail 1]
- [non-obvious detail 2]
```

**Complex code** (algorithms, multi-step logic, patterns):
```markdown
## [Function/Class Name]

### Purpose
[What problem this solves]

### How it works
[Step-by-step walkthrough of the logic]

### Design decisions
- [Why this approach vs. alternatives]

### Edge cases
- [What happens in boundary conditions]

### Dependencies
- [What this relies on and why]
```

### Step 3: Decide Where to Put It

- **Inline comments**: for non-obvious lines within the code
- **XML doc comments**: for public API methods (.NET convention)
- **Separate doc**: for architectural explanations or complex algorithms
- **Just explain**: if user wants understanding, not permanent docs

### Rules

- Explain the **why**, not the **what** — code already says what
- Don't over-explain obvious patterns
- Use the project's terminology, not generic terms
- If the code is confusing because it's badly written, say so and offer to refactor
- Tailor explanation to user's expertise level (check memory for user profile)
