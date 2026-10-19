# Select verification

Load when choosing or materially reconsidering an approach. This reference guides the analysis; assistant-workflow remains responsible for planning and execution.

## Procedure

1. Name the requested outcome, changed behavior or content, acceptance claims, affected boundaries, and credible consequences of failure. Change size alone does not measure risk.
2. Inspect user, project, CI, and contract policy. Record mandates, prohibitions, preferences, and available capabilities separately. Preserve each mandate's exact source and rationale. Preserve every explicitly mandated metric, scope, threshold, and source through its existing `required_check` tuple and a concrete enforcing CheckSpec; do not invent a universal/default target. If the current shape cannot represent the mandate, report that policy gap. A unit-only rule excludes integration and end-to-end tests; a required unit suite still permits another scope when it covers a distinct material claim. `required_tdd` accepts exactly `true` or `false`; false binds `mode=false`, `basis=not_selected`, and no applicable checks even when RED oracles exist. Conflicting true and false mandates block actionable selection. Resolve genuine conflicts before choosing dependent work.
3. Inspect relevant assertions and existing results. A passing command with no assertion for the behavior is incidental coverage. Reuse a check design when applicable; reuse its old result only under existing identity, freshness, and acceptance-coverage rules.
4. Choose checks that observe distinct material claims. For each, name an action, method, scope when automated, technique, source or concrete procedure, prerequisites, exclusions, expected success, and a plausible wrong result. Add work only when current evidence leaves a material claim open.
5. Choose scope, technique, and TDD separately. Record unique `applicable_check_ids` only for selected `automated_test` checks with executable meaningful RED oracles; `mode` is true exactly when that array is non-empty unless `required_tdd=false` binds it off. Preserve explicit TDD mandates for every required deliverable; when a required-true deliverable lacks a compatible executable automated-test RED oracle, report the policy conflict instead of silently omitting it or fabricating test artifacts. Otherwise select TDD when a stable, inexpensive failing oracle can guide implementation or preserve a known regression; code size or artifact category does not determine the mode.
6. For each command-based CheckSpec, record its literal `command.argv` and explicit `command.cwd` under that check's unchanged `check_id`. Keep non-command procedures in `check_ref_or_method`; never flatten multiple commands, infer a default cwd, or reconstruct shell text.
7. Prefer the smallest reliable and diagnosable set within binding policy and available budget. A stated scope preference may break a reasonable tie; it does not make an unsuitable oracle adequate. Carry mandatory project checks even when focused evidence already passes.

Load only the directly linked method reference for each selected activity. Domain policy stays with the owning specialist. For an unknown-cause bug, route through assistant-debugging before selecting a regression oracle. Once TDD is active, assistant-tdd preserves meaningful RED before production; never invent a failure or remove preserved code to create one.

## Explicit reduced-testing scope

Treat an explicit request for fewer tests focused on important behavior as a
source-bound acceptance boundary, not merely a preference. Preserve its source
in task constraints and `work_scope.source_refs`, and its meaning in
`verification_decision.scope`. Also preserve the exact instruction source as an
object row in existing `evidence_assessment.scope_and_evidence_refs`, including
when status is planned: `evidence_ref` is the exact source (for example
`user:reduced-tests`), `claim_kind: other`, `claim_scope` contains the exact
qualitative boundary, `selected_check_ids: []`, `binding_obligation_refs: []`,
`result_state: not_applicable`, `freshness: current`, `exclusions: []`. Omit
`executed_command`: this instruction row claims no run and closes no check.
Carry the assessment unchanged alongside the decision into materialized packets;
retain the row as actual results are added and reconcile the newest instruction
on resume. Qualitative boundaries are not `required_scope`/`prohibited_scope`
values, which remain unit/integration/e2e. Infer importance from accepted behavior, affected
boundaries and credible consequences; do not invent a count or quota. Reuse
adequate coverage first. Each additional test needs a distinct important uncovered
failure and an explanation of why existing evidence is inadequate. Record reuse
or extension rationale, exclusions and significant rejected duplication in the
existing CheckSpec/omission fields, with a completion boundary in `stop_rule`.
A controlling project/CI suite can require execution without new test authoring.
Resolve real conflicts with exact sources before expanding dependent work.
Zero new tests is valid with adequate evidence; reduced testing never implies
`required_tdd=false` or waives selected meaningful RED, security, integrity,
compatibility or other accepted protection. Keep the existing shapes/enums;
qualitative scope belongs in these fields, not a new policy value or schema.

Carry this unchanged boundary to execution, review and resume. Expansion needs a
named important gap and the existing selection/approval route, including when a
reviewer asks for generic coverage. A representation gap requires a design and
versioning decision before changing a contract.

## Contrast

For two added menu documents with an unchanged loader and existing arbitrary-entry loading/opening coverage, reuse relevant coverage and inspect that each requested document has correct content and opens at the real boundary. Do not add two permanent filename assertions unless named entries themselves are a product invariant.

If that same change alters path resolution, identify the changed loader behavior and choose a focused regression oracle. The presence of new static entries no longer covers the changed behavior.

## Output and stop

For a human-only selection, summarize the checks, rationale, and exclusions. When
a workflow/creator or other structured consumer needs a result, return the canonical
decision fields unchanged inline or in the existing packet; human summaries need
not serialize them. In an evidence assessment, bind each result to exact selected check IDs and exact `{kind,value,source_ref}` obligations it actually observes; close every due selected ID and applicable due/executable binding tuple with resolved current procedures/oracles. Do not invent execution checks for unrelated policy constraints solely to fill evidence arrays. Resolve a carried decision through the existing `work_scope.source_refs`; without one, qualify the scope assessment and do not claim unknown selected-check closure. Record meaningful exclusions and significant rejected duplication, not every possible test layer. Stop when applicable binding checks and material claims have credible evidence. Expand only for a new gap, changed scope, failure, material risk, relevant request, or mandate.
