---
name: assistant-telos
description: "Create or update Telos purpose, mission, goals, challenges, and strategies. Use for explicit purpose or Telos work."
---

# Telos Context

Help a person, team, or organization express purpose and connect it to action. Based on [Daniel Miessler's Telos](https://github.com/danielmiessler/Telos).

Use this chain when useful:

`Problems → Mission → Narratives → Goals → Challenges → Strategies → Projects → Journal`

Preserve the user's values, wording, identifiers, and existing file format. Do not invent goals, history, personal beliefs, organizational facts, or priorities. Point out a disconnected project or stale goal as a question or observation; the user decides what matters.

## Create

Establish personal, team, or organizational scope from context. Start with the requested focus and known information. Problems, mission, and goals are a useful core for a new full context file; leave unknowns open rather than filling them in. Interview only the sections needed for the request, grouping material questions so the user need not repeat themselves.

Optional sections include history, narratives, ideas, predictions, metrics, wisdom, challenges, strategies, projects, and journal. Do not require a full interview, biographical history, or step-by-step confirmation when the user has already supplied enough context. Use P1/M1/G1/C1/K1 identifiers for a new file if helpful; keep existing conventions on updates.

## Update or Review

Locate and read the existing file before changing or assessing it. Use a supplied or configured path; ask if it cannot be found or the destination is ambiguous. For updates, change the requested sections and preserve the rest. Add history, sensitive personal details, or journal entries only when the user's intent covers storing them.

For a review, assess the requested sections and their relevant connections: projects to goals, goals to mission, challenges to strategies, and dated predictions or metrics to current evidence. Report specific gaps and useful next steps. Do not rewrite the file as part of a read-only review.

## Storage and Use

A Telos request does not establish automatic loading at session start. Use the location and persistence authorized by the user or project; do not assume a global home path. Draft in conversation if no file write was requested or authorized. Keep personal context private and do not share or log it externally.

When asked to apply Telos to planning or prioritization, use the supplied goals as context. It never overrides an explicit user request. Return the result, file location if read or changed, affected sections, and remaining material questions. Omit empty reporting slots. Stop when missing intent would require inventing values or rewriting mission-critical content.

## Optional File Format

For a new file, adapt this outline to the requested focus. Omit unknown or unused sections; preserve an existing file's format on updates.

```markdown
# Telos Context File
*Last updated: YYYY-MM-DD*

## Problems
- P1: [user-stated problem]

## Mission
- M1: [mission addressing P1]

## Goals
- G1: [specific target linked to M1, with a deadline if known]

## Challenges and Strategies
- C1: [obstacle to G1] → [strategy]

## Projects
- [project and current state] → G1, M1
```

Add narratives, metrics/KPIs, predictions, team context, or other sections when useful to the request. History and dated journal entries require intent to store that content.
