# Clarify (First Principles)

Break down a problem to its fundamental truths. Distinguish what's real from what's assumed.

## When to use
- You're stuck or going in circles
- A solution feels imposed by convention rather than necessity
- Cost/complexity seems too high — challenge whether it has to be

## Process

### Step 1: Deconstruct
Break the problem into its constituent parts. Ask: "What is this actually made of?"

List every element, requirement, constraint, and dependency.

### Step 2: Classify each element

| Category | Definition | Example |
|---|---|---|
| **Hard constraint** | Physics, laws, platform limits, mathematical truths | "HTTP is request-response", "SQL Server max row size is 8060 bytes" |
| **Soft constraint** | Policy, convention, team decision — changeable | "We always use repository pattern", "PRs need 2 approvals" |
| **Assumption** | Unvalidated belief — may not be true | "Users won't need offline access", "This endpoint is low traffic" |

### Step 3: Reconstruct
Build the solution using ONLY hard constraints. For each soft constraint, ask: "Does removing this open a simpler path?" For each assumption, ask: "What if this is wrong?"

## Output format

```
DECONSTRUCTION
- [element 1]
- [element 2]
- ...

CLASSIFICATION
| Element | Type | Evidence | Can we challenge it? |
|---------|------|----------|---------------------|
| ...     | Hard/Soft/Assumption | ... | Yes/No — [why] |

RECONSTRUCTION
Given only the hard constraints, the simplest solution is: [...]
Soft constraints we should keep: [...]
Assumptions to validate: [...]
```

## Tips
- The highest-ROI insight is usually in the assumptions — things everyone "knows" but nobody verified
- If you can't classify something, it's probably an assumption
- 5-10 minutes is usually enough. Don't over-systematize.
