# Select verification

Load when choosing or materially reconsidering an approach. This reference guides the analysis; assistant-workflow remains responsible for planning and execution.

## Procedure

1. Name the requested outcome, changed behavior or content, acceptance claims, affected boundaries, and credible consequences of failure. Change size alone does not measure risk.
2. Inspect user, project, CI, and contract policy. Record mandates, prohibitions, preferences, and available capabilities separately. A unit-only rule excludes integration and end-to-end tests; a required unit suite still permits another scope when it covers a distinct material claim. Resolve genuine conflicts before choosing dependent work.
3. Inspect relevant assertions and existing results. A passing command with no assertion for the behavior is incidental coverage. Reuse a check design when applicable; reuse its old result only under existing identity, freshness, and acceptance-coverage rules.
4. Choose checks that observe distinct material claims. For each, name an action, method, scope when automated, technique, source or concrete procedure, prerequisites, exclusions, expected success, and a plausible wrong result. Add work only when current evidence leaves a material claim open.
5. Choose scope, technique, and TDD separately. An explicit binding TDD requirement remains active. Otherwise select TDD when a stable, inexpensive failing oracle can guide implementation or preserve a known regression; the selected technique or binding requirement determines the mode, not code size or artifact category.
6. Prefer the smallest reliable and diagnosable set within binding policy and available budget. A stated scope preference may break a reasonable tie; it does not make an unsuitable oracle adequate. Carry mandatory project checks even when focused evidence already passes.

Load only the directly linked method reference for each selected activity. Domain policy stays with the owning specialist. For an unknown-cause bug, route through assistant-debugging before selecting a regression oracle. Once TDD is active, assistant-tdd preserves meaningful RED before production; never invent a failure or remove preserved code to create one.

## Contrast

For two added menu documents with an unchanged loader and existing arbitrary-entry loading/opening coverage, reuse relevant coverage and inspect that each requested document has correct content and opens at the real boundary. Do not add two permanent filename assertions unless named entries themselves are a product invariant.

If that same change alters path resolution, identify the changed loader behavior and choose a focused regression oracle. The presence of new static entries no longer covers the changed behavior.

## Output and stop

Return a compact inline decision for small work or carry the same fields in the existing workflow packet. Record meaningful exclusions and significant rejected duplication, not every possible test layer. Stop when binding checks and material claims have credible evidence. Expand only for a new gap, changed scope, failure, material risk, relevant request, or mandate.
