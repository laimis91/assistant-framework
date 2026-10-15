# Creator Behavioral Evaluation Evidence

This reference applies only when a registered offline creator behavior fixture is graded. It defines an evaluation envelope and companion capture; it does not add fields to an ordinary user-facing result, replace artifact validation, or alter the canonical `assistant-verification` producer contracts.

## Independent capture

The fixture fixes the operation, expected outcome, target name and category, required and allowed paths, preserved metadata, assessment criteria, and whether comparison evidence is expected. The evaluator binds each execution to a fresh `capture_id`, `run_id`, source root and `SKILL.md` digest when applicable, output root, and comparison digest when applicable. The response cannot choose or replace those bindings. A case without its per-run binding is not gradable.

The companion JSON is captured by the harness beside the response. It records `schema_version`, `case_id`, `capture_id`, `run_id`, `operation`, `outcome`, `skill_name`, `source_root`, `source_snapshot`, `output_root`, `events`, `artifact_manifest`, and `preserved_files`; comparison cases also carry the frozen `comparison` record. File manifests contain safe relative paths and SHA-256 digests. The harness reads files as data, rejects empty, stale, symlinked, or escaping paths, and never executes authored files.

Events are ordered observations, not claims. They may record `design_presented`, `approval_received`, `target_inspected`, `target_file_written`, `target_file_preserved`, `guidance_source_checked`, and baseline or candidate completion. A successful write must match the non-empty file bytes. The fixed narrow-update case freezes one body-text replacement and validates the actual source and output bytes against that exact replacement, so a no-op or unrelated body edit fails. An update lists changed outputs in `artifact_manifest` and unchanged target files separately in `preserved_files`; each preserved path must have matching before/after bytes and a successful preservation event. A read-only operation has no output files, writes, or preservation actions.

## Response evidence

The response includes one JSON `creator_evidence` object with exactly these fields:

```json
{
  "schema_version": "1.0",
  "case_id": "fixture case id",
  "capture_id": "harness capture id",
  "run_id": "harness run id",
  "operation": "create | update | assess | refresh_guidance",
  "outcome": "design_pending_approval | authoring_complete | read_only_assessment | read_only_refresh | comparison_assessment",
  "skill_name": "target skill name",
  "source_snapshot_sha256": null,
  "evidence_sha256": "sha256 of the exact companion JSON bytes",
  "design": null,
  "design_sha256": null,
  "artifacts": [],
  "assessment": null,
  "refresh": null,
  "comparison": null
}
```

The response envelope is correlated with the harness capture, then checked against actual files and events. It does not make self-reported digests trustworthy: the companion digest binds exact captured bytes, and the harness independently reads every referenced source and output file.

When a design is required, include its target, purpose, category, value kind, success criteria, and typed contract boundaries. Required input fields carry `on_missing`; required output artifacts carry `on_fail`; phase gates include conditions, assertions, and recovery; Process handoffs match producer and consumer fields. The successful design presentation is captured before approval or writes. An awaiting-approval outcome has no successful approval and no target writes. A completed authoring outcome has approval before its first successful write when the fixture requires a design.

Assessment evidence names inspected paths and gives one result for each fixture criterion. A genuine inspection may have no findings. A failed criterion needs a finding tied to inspected evidence; an unassessed criterion needs a concrete gap. Refresh evidence binds source identity, check time, available revision or digest, relevance, disposition, affected consumers, and access limits. A fetch alone never means adoption; `adopted` remains `false`.

## Comparisons

A comparison record freezes prompt-set and rubric digests, host/model/runtime and settings/tool/permission/input digests, distinct baseline and candidate run IDs and source snapshots, isolated non-nested output roots, disjoint training/validation/final-acceptance partitions, candidate-selection IDs, blind labels, raw outcomes, and metrics. Each completion event binds its run to the exact prompt-set and rubric digests, as well as the same conditions and its source and output identities; changing either scoring identity requires fresh completion events for both runs. Each run must retain at least one non-empty raw output artifact. Candidate selection may use validation IDs only; final acceptance stays held out. Derive metrics from raw outcome counts. If a class denominator is zero, report its metric as unavailable with a null value rather than inventing a score.

The registered validator is deliberately closed to the fixed creator case IDs. Fixture text or response phrases cannot register new validation logic or override the per-run capture. These deterministic checks establish the specific fixture behavior only; they do not prove native skill selection, activation, or general model quality.
