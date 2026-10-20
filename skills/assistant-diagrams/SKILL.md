---
name: assistant-diagrams
description: "Create Mermaid architecture, sequence, ER, flow, class, or state diagrams. Use for explicit diagram or system-flow visualization requests."
---

# Draw the Relevant System

## Shared operating guidance

Load [the common outcome guidance and shared stagnation policy](../../tools/progress/operating-guidance.md) for this activity. Keep specialist methods, authority and completion evidence below; single-pass work needs no progress artifact.


Create a readable Mermaid diagram from inspected code, configuration, tests, or supplied source material. Choose the type that fits the question; ask only when unresolved scope or type would materially change what is drawn.

| Type | Reference | Useful for |
|---|---|---|
| Architecture | `arch-diagram.md` | System context and components |
| Sequence | `sequence-diagram.md` | Request and interaction paths |
| ER | `er-diagram.md` | Entities and data relationships |
| Flow | `flow-diagram.md` | Decisions and algorithms |
| Component | `component-diagram.md` | Modules and dependencies |
| Class | `class-diagram.md` | Types and inheritance |
| State | `state-diagram.md` | Lifecycle transitions |

Load only the relevant reference. Trace actual paths, use project terminology, and show only the detail needed to answer the question. Group related elements and label relationships. Split a diagram when it becomes hard to read, regardless of project size.

Every represented current component and relationship needs source evidence. A requested proposed design may include new elements, clearly labeled as proposed and separated from observed behavior. Disclose missing or inaccessible source and omit unsupported claims. For an Architecture Decision Pack, preserve the supplied ownership, boundary, and flow decisions rather than inventing architecture.

Return the diagram in a fenced Mermaid block, a brief explanation, source references, and material gaps. An ordinary diagram does not need a separate per-element ledger. Use inline output unless the user or active documentation task calls for a file. Respect the requested destination and existing project format.

Check syntax for the target renderer and render/parse with an available project tool when practical. State what was actually checked; mental inspection is not a successful render. Stop or label an incomplete result when missing evidence prevents an accurate diagram.

## Integrated and Structured Output

For workflow/preparation calls or a caller requesting the supported structured format, apply [`contracts/input.yaml`](contracts/input.yaml) and [`contracts/output.yaml`](contracts/output.yaml). These retain the existing schema v3 fields and structured-eval interface, including `diagram_code`, evidence sources, `element_trace`, and `coverage_gaps`.

Existing-system feature-preparation diagrams carry exact `{evidence_ref, item_id}` bindings at the root and for every traced node and edge. Match current input evidence rows exactly; keep underlying source refs and disclose unavailable or untraced elements as gaps. Broad artifact-only, stale, unresolved, or mismatched bindings cannot establish completeness. These trace requirements apply at this integrated boundary, not to an ordinary inline diagram.
