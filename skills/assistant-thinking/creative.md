# Creative Options

Use for naming, quick improvement scans, brainstorming, and ranked options. Produce distinct, constraint-respecting options and explain which are most promising.

## Shared rules

Infer the goal and relevant constraints from the request and context. Inspect local source only where it changes the option set; do not run a ritual repository scan. Reuse existing capabilities. Keep hard constraints and prior attempts visible throughout, and do not re-propose a rejected approach unchanged. If a branch relaxes a hard constraint, label it and say what would need to change.

Rank against the criteria relevant to the decision: expected benefit, feasibility, fit with goals, constraints, cost, risk, and evidence strength. Explain rankings in plain language. Use scores or weights only when requested or when they make a difficult comparison clearer, and justify them. Do not invent sampling probabilities, quality gains, or numerical precision from guesses or without an observed evaluation.

## Light

For a quick improvement scan or "what else" request, give a small set of meaningful alternatives, a qualitative ranking with the main trade-offs, and one recommended next step. Stop there. A numeric scoring matrix, mode label, phase transcript, or follow-up decision is unnecessary.

## Deep

Use broader exploration when explicitly requested or when the decision needs it. Generate varied options before selecting favorites, using the techniques that help: inversion, analogy, combining existing capabilities, scale changes, stakeholder lenses, and subtraction. If ideas are near-copies, try inversion or a different analogy instead of padding the list. Consider an unconventional option when it exposes a real alternative; do not add novelty for its own sake. Keep generation apart from evaluation long enough to avoid narrowing too early.

Refine only promising candidates: how they work, dependencies, risks, and the smallest validation step. Stop when the comparison answers the request, without idea or candidate quotas. Offer selection, combination, or further exploration when useful; do not force a full decision ritual.

## Decision authority

A recommendation is not the user's choice. Record a decision only after an explicit choice. Offer a choice packet only when requested or needed to resolve a material choice, and stop before unrequested implementation or persistence. When implementation is requested, carry the selected idea and its constraints into `assistant-workflow`.
