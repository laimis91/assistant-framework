# Evaluation documentation

Choose the guide for the evidence you need; load fixture payloads only for the selected cases. These guides distinguish source validation, captured behavior and native activation. Offline checks do not prove model quality.

| Task | Guide | Source owner |
|---|---|---|
| Validate framework cases and understand instruction controls | [Framework fixtures](framework-fixtures.md) | `tools/evals/run-framework-instruction-evals.sh` and framework schemas |
| Evaluate clarification from retained evidence | [Clarification evidence](clarification-evidence.md) | `tools/evals/lib/clarification-evidence.cjs` and frozen clarification oracle |
| Import traces, run an authorized Codex comparison, or measure source context | [Codex trials](codex-trials.md) | Codex adapter, promotion finalizer and context-budget reporter |
| Validate skill fixtures, activation observations and structured operators | [Per-skill fixtures](skill-fixtures.md) | `tools/evals/run-skill-evals.sh` and `tools/evals/lib/skill-eval-fixtures.sh` |
| Maintain research validator protections | [Research obligations](research-semantic-obligations.md) | Research semantic validator and its direct controls |

Commands assume the source repository unless their guide explicitly describes an installed route. The installer copies this directory, including sibling guides and fixtures, to the provider's `docs/evals/`. Source-only helpers retain that limit. For Windows Codex, use configured `CODEX_HOME` for installed docs/tools as described in the skill contract guide.

Update the owning guide when changing a runner, schema, observable evidence boundary or operator. Keep fixture assets at their consumed paths. Repository navigation starts at `docs/README.md` in the source checkout.

The headings below preserve existing entry links; each points to its owning guide.

## Evaluating framework simplification

See [Evaluating framework simplification](framework-fixtures.md#evaluating-framework-simplification).

## Observed execution-pattern evidence

See [Observed execution-pattern evidence](framework-fixtures.md#observed-execution-pattern-evidence).

## Generated workflow references

See [Generated workflow references](framework-fixtures.md#generated-workflow-references).

## Framework Instruction Fixtures

See [Framework Instruction Fixtures](framework-fixtures.md#framework-instruction-fixtures).

## Clarification evidence boundary

See [Clarification evidence boundary](clarification-evidence.md#clarification-evidence-boundary).

## Trace import and A/B comparison

See [Trace import and A/B comparison](codex-trials.md#trace-import-and-ab-comparison).

## Blind Codex behavioral A/B execution

See [Blind Codex behavioral A/B execution](codex-trials.md#blind-codex-behavioral-ab-execution).

## Current evidence boundary

See [Current evidence boundary](codex-trials.md#current-evidence-boundary).

## Source-only context budget

See [Source-only context budget](codex-trials.md#source-only-context-budget).

## Per-Skill Eval Fixtures

See [Per-Skill Eval Fixtures](skill-fixtures.md#per-skill-eval-fixtures).

## Writer selection outcome controls

See [Writer selection outcome controls](framework-fixtures.md#writer-selection-outcome-controls).

## Canonical packet admission controls

See [Canonical packet admission controls](framework-fixtures.md#canonical-packet-admission-controls).

## Instruction Behavior Eval Fixtures

See [Framework fixtures](framework-fixtures.md).

### Files

See [Framework fixture files](framework-fixtures.md#files).

### How To Use

See [Framework usage](framework-fixtures.md#how-to-use).

### How To Use

See [Per-skill usage](skill-fixtures.md#how-to-use).
