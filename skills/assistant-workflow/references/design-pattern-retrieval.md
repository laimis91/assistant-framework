# Optional Design Pattern Retrieval

Use configured external pattern libraries only when repository evidence does
not already provide a sufficient pattern and the change has a concrete design
force worth comparing. Missing configuration is `not_configured`; continue
normally without asking the user to configure a library.

"Configured" means the user, project instructions, or task packet supplies an
explicit config path. Do not search home or project directories for one.

## Retrieval order

1. Search repository-native patterns first and record the canonical example
   plus a counterexample or edge case when available.
2. Name the concrete design force: ownership, construction variability,
   substitution, lifecycle, coordination, state transition, extension seam, or
   another specific pressure.
3. If configured, run metadata-only search through
   `<framework-tools>/patterns/pattern-library.sh`, where `<framework-tools>` is
   the installed agent tools directory; load at most 1-3 selected examples.
4. For each selected example, record applicability, contraindications, and a
   `use` or `reject` decision.
5. Adapt the smallest relevant idea to current repository conventions. Never
   copy an educational example as authoritative production architecture.

## Guardrails

- KISS and YAGNI override pattern enthusiasm. Do not introduce a pattern when
  a direct implementation has lower coupling and equal correctness.
- SOLID, DRY, and design patterns are evidence lenses, not acronym quotas.
- Do not persist configured roots, source bodies, personal paths, or customer
  code in plans, indexes, logs, plugin mirrors, or company installations.
- Use library id plus relative path in evidence.
- Reject stale language/style, hidden dependencies, unsafe caching/lifecycle,
  and examples whose tradeoffs do not fit the current force.
- Configuration and indexes remain user-owned outside installed `tools/` so a
  reinstall cannot delete them.

The final pattern note records repository searches, optional library metadata
results, selected examples, contraindications, and the use/reject decision.
