---
name: assistant-ideate
description: "Generate and rank options. Use light mode for quick improvement scans and deep mode for explicit brainstorm requests or broad exploration."
---

# Generate Useful Options

Produce distinct, constraint-respecting ideas and explain which are most promising. Infer the goal and relevant constraints from the request and context; ask only when a missing answer changes the useful option set or ranking. Inspect local capabilities when needed and reuse what already exists. Respect prior attempts; do not repeat rejected approaches unchanged.

For a quick improvement scan or “what else” request, give a small set of meaningful alternatives, a qualitative ranking with the main trade-offs, and one recommended next step. Stop there. A numeric scoring matrix, mode label, phase transcript, or follow-up decision is unnecessary.

Use broader exploration when explicitly requested or when the decision needs it. Read `references/deep-ideation.md` for techniques and comparison guidance; `references/ideation-pipeline.md` gives a compact approach for either depth. Generate enough varied options to cover the real alternatives, without filling a quota. Refine only candidates that warrant further consideration.

Rank against the user's goals, constraints, costs, risks, and evidence. Label assumptions and proposed departures from hard constraints; do not quietly relax them. Distinguish a recommendation from the user's choice. Record a decision only after an explicit choice, and stop before unrequested implementation or persistence. When implementation is requested, carry the selected idea and its constraints into `assistant-workflow`.
