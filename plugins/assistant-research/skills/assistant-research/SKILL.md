---
name: assistant-research
description: "Gather and synthesize source-backed information. Use for explicit research, topic investigation, current evidence, or option comparison."
triggers:
  - pattern: "research|look into|find out about|compare (options|approaches|tools|technologies)|investigate (a |the )?(topic|technology|market|literature)|current state of|latest evidence on"
    priority: 65
    min_words: 4
    reminder: "This request matches assistant-research. Consider whether the Skill tool should be invoked with skill='assistant-research' for research and investigation."
---

# Research

## Goal

Answer research questions with source-weighted findings, verified URLs,
explicit conflicts, and honest evidence gaps at proportional depth.

## Success Criteria

- Research depth matches decision risk and available evidence.
- Findings cite supporting sources and calibrated confidence.
- Every URL presented is verified or omitted.
- Conflicts and gaps are reported, even when empty.
- Candidate mechanisms remain hypotheses until a validation method is executed.

## Constraints

- Ask only when scope changes source selection, jurisdiction/domain, depth, or
  decision criteria and cannot be inferred safely.
- Do not call a single-source claim HIGH confidence unless a primary/official
  source directly supports it.
- Fit evidence budgets and research angles to the active adapter; do not hardcode
  mandatory subagent counts.

## Progressive Contract Loading

Canonical tier files are `contracts/input.yaml`, `contracts/output.yaml`, and
`contracts/phase-gates.yaml`.

Read `contracts/index.yaml` first and load only the active boundary:

- `entry` for question, tier, method, role/goal, purpose, and known context;
- `current_phase` for SEARCH, SYNTHESIZE, or VERIFY;
- `source_research`, `five_lens`, or `investigate` only after method selection; and
- `completion` only for the artifact being returned.

Missing or invalid selectors fall back to the full named canonical contract. Do
not load every contract or research method at entry.

## Ownership

assistant-research owns source selection, evidence synthesis, confidence, and
URL verification. Generic workflow may coordinate the task, but specialist gates are authoritative.

## Method Selection

- **source_research** — factual lookup, comparison, and source collection. Load
  `source_research`; choose quick, standard, extensive, or deep tier by risk.
- **five_lens_briefing** — decision-grade work needing perspectives,
  contradictions, incentives, synthesis, and peer review. Load `five_lens`.
- **investigate** — deep entity/domain analysis with ethical boundaries. Load
  `investigate`.

Quick tier may use one strong primary source. Standard uses multiple sources.
Extensive/deep tiers expand perspectives and primary evidence only when the
decision warrants the cost.

Every finding needs confidence grounded in source quality and agreement. For
causal or improvement questions, return candidate mechanisms with evidence,
counterevidence, gaps, and a validation method—not proven-cause language.

## Output

Return status/confidence, concise answer, source-backed findings, candidate
mechanisms when applicable, verified sources, conflicts, gaps, and five-lens
artifacts only when that method ran.

## Stop Rules

- Ask every material, non-discoverable question when missing scope changes interpretation; group them by topic and keep them concise.
- Report a gap when sources are inaccessible, stale, conflicting, or too weak.
- Do not finalize with any unverified URL.
- Do not present candidate mechanisms as causes without executed validation.
