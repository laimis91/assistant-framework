---
name: assistant-verification
description: "Analyze proportionate testing, validation, or evaluation for a change, or assess whether existing evidence is sufficient across code, skills, plugins, and non-code artifacts."
---

# Verification Selection And Evidence Assessment

Choose the smallest credible checks for the requested outcome, or assess whether
supplied evidence supports it. This skill selects and assesses; it does not run,
dispatch, repair, retry, edit, or approve delivery.

## Method

1. Identify the change, acceptance claims, affected boundaries, and plausible
   wrong outcomes. Read relevant existing checks and results before adding work.
2. Separate binding requirements, preferences, and capability limits. Preserve
   exact mandate sources; do not waive a required check or invent a universal
   count, ratio, coverage target, or test quota.
3. Preserve explicit reduced-testing scope/source in the existing scope and
   source-ref fields, not only preferences; use [selection.md](references/selection.md)
   for that boundary and controlling-check conflicts. Choose checks for distinct material claims. Reuse adequate current evidence;
   add tests only for a real uncovered behavior or failure. Zero new tests still
   needs evidence and meaningful exclusions. Choose scope, technique, and TDD
   independently; meaningful RED is required only when TDD is active.
4. Assess actual assertions, source/config identity, freshness, results, and
   limitations. A phrase/schema/file-existence pass is structural evidence,
   not proof of behavior or model quality. Missing, failed, partial, stale,
   skipped, and unavailable observations remain gaps.
5. Stop when binding checks and material claims have credible evidence. Expand
   only for a new gap, change, failure, material risk, request, or mandate.

Use [selection.md](references/selection.md) for disputed policy, coverage, cost,
or TDD selection and [evidence-quality.md](references/evidence-quality.md) for
reused, ambiguous, or incomplete evidence. Load only the method being considered:
[unit](references/methods/unit.md), [integration](references/methods/integration.md),
[end-to-end](references/methods/end-to-end.md),
[artifact validation](references/methods/artifact-validation.md),
[behavioral evaluation](references/methods/behavioral-evals.md),
[property/mutation](references/methods/property-and-mutation.md), or
[performance/resilience](references/methods/performance-and-resilience.md).

## Consumed results

An ordinary human-only assessment can state the selected checks or evidence,
conclusion, gaps, and next action concisely; no serialized object is required.
When workflow, skill-creator, a carried decision, or an executable consumer needs
structured results, load `contracts/index.yaml` and the applicable entry,
selection/assessment, current-phase, and completion sets. Missing/invalid selectors
load the full named contract. Preserve canonical `verification_decision`
(CheckSpec/TddChoice) and `evidence_assessment` unchanged; do not create a task-state
file or replacement schema. Human summaries need not dump these full objects.

For command checks, retain exact ID/argv/cwd. Bind result rows only to the selected
IDs and exact `{kind,value,source_ref}` obligations their observed procedure
supports. Preserve explicit required metrics/scopes/thresholds through an enforcing
CheckSpec or report a policy gap and block dependent Build.

Selection without results is planned; a requested assessment without adequate
results is insufficient or blocked. Sufficient closes the named scope and due
checks, with exclusions; it does not establish independent review or delivery
approval. assistant-debugging owns unknown causes, assistant-tdd owns active TDD,
and domain specialists retain their rules.
