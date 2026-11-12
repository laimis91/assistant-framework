# Per-skill evaluation

## Per-Skill Eval Fixtures

Skill-local eval fixtures live beside the skill they exercise:

```text
skills/<skill>/evals/cases.json
```

`tools/evals/run-skill-evals.sh` validates, lists, emits, and locally grades
those skill fixtures with the same provider-neutral constraints as the framework
instruction eval runner. Operational modes require local shell, `jq`, and Ruby
with JSON plus Psych/YAML support; response grading also requires Ruby
BigDecimal. It does not call provider SDKs, model APIs, or network services.

The assistant-skill-creator upstream freshness suite uses deterministic fetch
fixtures to check unchanged, changed, stale, partial, and unavailable source
responses, including bounded recovery and registry preservation. It performs no
network requests; the installed helper's actual transport is a separate check.

This inventory now covers all 17 first-class `assistant-*` skills. The current
tracked first-class fixtures are:

- `skills/assistant-advisory-triage/evals/cases.json`
- `skills/assistant-ci-audit/evals/cases.json`
- `skills/assistant-clarify/evals/cases.json`
- `skills/assistant-cleanup/evals/cases.json`
- `skills/assistant-debugging/evals/cases.json`
- `skills/assistant-docs/evals/cases.json`
- `skills/assistant-onboard/evals/cases.json`
- `skills/assistant-research/evals/cases.json`
- `skills/assistant-review/evals/cases.json`
- `skills/assistant-security/evals/cases.json`
- `skills/assistant-skill-creator/evals/cases.json`
- `skills/assistant-spike/evals/cases.json`
- `skills/assistant-tdd/evals/cases.json`
- `skills/assistant-thinking/evals/cases.json`
- `skills/assistant-ui-qa/evals/cases.json`
- `skills/assistant-verification/evals/cases.json`
- `skills/assistant-workflow/evals/cases.json`

The CI-audit fixtures consume supplied independent captures, including false
passes, early-rejected fixtures, retained distinct protection and incomparable
cost/authority controls. They use the existing fixed structured operators.
Three substring-only CI-audit cases cover test-value judgment: fabricated proof
and wrong-guard negatives beside a kept exact-byte contract, a removal that names
its remaining proof, and failed discovery versus a valid empty result.
Workflow scope/repair fixtures add only the missing boundary-retention and
switch/resume controls; existing QRG, relative-loader, TDD and review-reuse cases
remain the coverage for those behaviors. Canned-response grading tests the oracle,
not actual model compliance, native activation or comparative savings.

By default, the runner discovers first-class `skills/assistant-*/SKILL.md`
skills that have `evals/cases.json` fixtures. Use `--include-local` only when
you explicitly want to include local skill experiments that also have eval
fixtures.

Every first-class fixture uses schema `2.0` and declares top-level
`activation_cases`. Each entry is exactly `{ "user_request": string,
"should_activate": boolean }`; fixtures need at least two
normalized-distinct positive requests and one normalized-disjoint nearby
negative. Schema `1.0` custom/local fixtures may omit activation cases, but an
included field is still structurally validated. Other schema versions are
rejected. These cases provide
native-description activation evidence and remain separate from response-grade
`.cases` and SKILL.md frontmatter.

The registered `assistant-skill-creator` behavior cases also use a fixed domain
validator. It binds each response to an independently captured operation trace,
actual artifact bytes, and per-run source/output identities. Update fixtures
record changed files separately from unchanged preserved target files; assess
and refresh cases require observed read-only evidence. Comparison evidence
checks matched run conditions, held-out selection, raw outcome denominators,
and isolated outputs. See
`skills/assistant-skill-creator/references/behavioral-evaluation.md` for the
fixture envelope and evidence boundary. These deterministic checks do not
establish native activation or general model quality.

To evaluate externally observed native selections without adding a custom router
or provider API call, save one JSON result for every selected activation case:

```json
{
  "schema_version": "1.0",
  "results": [
    {
      "skill": "assistant-clarify",
      "user_request": "Clarify this ambiguous multi-intent request.",
      "selected_skills": ["assistant-clarify"]
    }
  ]
}
```

Each result binds the selected fixture skill and exact `user_request` to the
externally observed `selected_skills`. The runner requires exactly one result
per selected activation case and rejects missing, duplicate, or unexpected
results before comparing whether the expected skill was selected to
`should_activate`. It only evaluates supplied observations; it never invokes a
native router, provider API, SDK, or network service.

### How To Use

Validate all default per-skill fixtures:

```bash
tools/evals/run-skill-evals.sh --validate-fixture
```

Validate one skill by name, directory, or `SKILL.md` path:

```bash
tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-clarify
tools/evals/run-skill-evals.sh --validate-fixture --skill skills/assistant-thinking
tools/evals/run-skill-evals.sh --validate-fixture --skill skills/assistant-thinking/SKILL.md
```

List available cases as tab-separated `skill`, `case id`, `category`, and
`title` rows:

```bash
tools/evals/run-skill-evals.sh --list
tools/evals/run-skill-evals.sh --list --skill assistant-clarify
```

Emit provider-neutral prompt packets for manual or adapter-driven execution:

```bash
tools/evals/run-skill-evals.sh --emit-prompts /tmp/skill-eval-prompts
tools/evals/run-skill-evals.sh --emit-prompts /tmp/clarify-eval-prompts --skill assistant-clarify
```

Prompt packets are written under `<output>/<skill>/<case-id>.md`, except
clarification packets use an opaque `task-NN.md` basename. Clarification
numbering follows full-fixture order and remains stable when `--case` filters
emitted packets. A clarification packet takes precedence over any case-level
packet mode and contains only a neutral `User Request` heading and the prompt.

For other cases, the default mode and explicit `prompt_packet_mode: annotated`
emit the case title and identity, setup context, prompt, expected behavior, pass
criteria, fail signals, optional seeded defects / measurable assertions, machine
expectations, and an optional Structured JSON Assertions section. A case may
declare `prompt_packet_mode: task_only`; that packet contains a neutral
`Task Packet` heading, skill identity and path, setup context, and prompt, with
grading-only criteria omitted. The local grader always evaluates the complete
fixture and its expectations.

Run each prompt packet with the target assistant and save the captured response
using the emitted packet basename under `<response-dir>/<skill>/`, with a
`.txt` or `.md` extension. Opaque clarification packet basenames resolve to
their matching responses; existing case-id response filenames remain supported.
A flat response filename is accepted only when one skill fixture file is
selected.

Grade saved responses locally:

```bash
tools/evals/run-skill-evals.sh --responses /tmp/skill-eval-responses
tools/evals/run-skill-evals.sh --responses /tmp/clarify-eval-responses --skill assistant-clarify
```

The six `assistant-skill-creator` behavior cases are fail-closed when their
committed fixtures have no per-run binding. After an independent observer has
captured the response, companion trace, source snapshot, and output tree, supply
that observer's binding manifest explicitly:

```json
{
  "schema_version": "1.0",
  "cases": [
    {
      "case_id": "new-process-skill-designs-contracts-before-build",
      "run_binding": {
        "capture_id": "capture-2026-10-15-001",
        "run_id": "run-2026-10-15-001",
        "source_root": null,
        "source_snapshot_sha256": null,
        "output_root": "/tmp/creator-capture/output",
        "comparison_sha256": null
      }
    }
  ]
}
```

For example, when grading that one prepared case:

```bash
tools/evals/run-skill-evals.sh --responses /tmp/creator-responses \
  --skill assistant-skill-creator \
  --case new-process-skill-designs-contracts-before-build \
  --creator-run-bindings /tmp/creator-run-bindings.json
```

The manifest must contain exactly one entry for every selected creator
behavior case, with the existing six `run_binding` fields. Source and output
paths, snapshot hashes, and comparison hashes are checked against each captured
trace and response. A comparison digest is finalized from the complete observed
pair after both runs, before grading; predeclared run, settings, prompt, and
rubric identities remain fixed during execution. Do not derive bindings from a
response or companion file. The manifest is an explicit trusted evaluator
input, not an authenticated statement: the grader can reject missing, altered,
or inconsistent evidence, but cannot prove that a maliciously consistent
manifest came from an independent observer. The grader pins the manifest bytes
between whole-selection preflight and per-case checks. This option is limited
to `--responses`; it does not change generic skill grading or the existing
fixture-bound route.

Compare native-selection observations captured by a separate adapter or manual
run:

```bash
tools/evals/run-skill-evals.sh --activation-results /tmp/skill-activation-results.json
tools/evals/run-skill-evals.sh --activation-results /tmp/clarify-activation-results.json --skill assistant-clarify
```

Cases may additionally define `machine_expectations.structured_json_assertions`.
For these per-skill cases, the response must contain exactly one valid JSON
value. The local grader applies only the fixed provider-neutral operators:
`equals`, `one_of`, `nonempty_string`, `nonempty_array`, `empty_array`, `array_type`, `array_nonblank_strings`, `path_absent`, `absent_or_empty_array`, `equals_path`,
`required_when_equals`, `array_field_values_exact`, `array_object_values_exact`,
`object_keys_exact`, `array_items_nonempty_fields`, and
`array_items_nonempty_array_fields`. Assertion paths are JSON arrays for safe
`getpath` access. They are grader-only declarations, never executable fixture
content: arbitrary jq, code, or expressions are not accepted. `array_items_nonempty_fields`
requires the target array to contain at least one object, and every listed field
in every object must be a non-empty string.
`array_items_nonempty_array_fields` requires the target array to contain at
least one object, and every listed field in every object must be a non-empty
array whose every member is a nonblank string.
`object_keys_exact` requires the target to be an object whose keys exactly match
the declared `fields`; it rejects missing keys, extra keys, and non-object
values. Its path may be `[]` to check the JSON response root, or a declared
object path. It accepts at most 16 unique field names. Assertion paths follow
the declared shape one segment at a time: each numeric segment consumes one
array level, and string segments traverse fields only on an object. This admits
object-array element fields and primitive-array elements while rejecting
repeated or skipped indexes; schema descriptors are cloned when resolving an
array element so the declared root remains unchanged.
The assistant-workflow eval-only root registry explicitly projects the
`decision_item` and `decision_resolution` object arrays as single objects for
the `progressive-collaborative-contributor-evidence` fixture, whose prompt asks
for those projected roots. Their canonical array descriptors remain available
for indexed paths; this bounded compatibility does not permit skipped indexes
on other arrays.
`empty_array` requires the target path to resolve to an empty array.
`array_type` requires the target path to resolve to an array and permits an empty array. `array_nonblank_strings` requires every member to be a nonblank string and a required boolean `allow_empty` declares whether an empty array is valid.
In this exhaustive fixed operator list, `path_absent` passes only when its target
path cannot resolve; a present `null` value is present and therefore fails.
`absent_or_empty_array` passes when its target path is unresolved or resolves to
an empty array; a present `null`, non-array, or non-empty array fails.
`one_of` requires exact membership in its bounded declared scalar values.
`array_object_values_exact` compares each target object’s declared `fields` as
an unordered exact multiset against bounded `expected_objects`, preserving the
correlation among the declared fields while allowing response-object reordering.
`one_of` permits at most 32 scalar values. `array_object_values_exact` permits
at most 16 unique fields and 32 expected objects; absent projected fields fail,
while a present `null` matches only a present `null`.

Include local-only skill experiments explicitly:

```bash
tools/evals/run-skill-evals.sh --validate-fixture --include-local
tools/evals/run-skill-evals.sh --list --include-local
```

The response grader is heuristic/local grading. It checks missing files, empty
responses, exact fail-signal phrase hits where useful, missing required
substrings, forbidden substring hits, optional structured JSON assertions, and
optional `seeded_defects` measurable assertions. Seeded defects make evals more measurable by requiring captured
responses to detect fixture-specific planted risks with detection anchors,
evidence anchors, acceptable severity labels, and optional finding markers. Cases
can also define `false_positive_markers` plus `false_positive_budget` to fail
over-broad responses that invent too many unrelated blockers. These deterministic checks are
proxies for behavior conformance; they complement human review or a separate LLM
judge and do not replace semantic judgment.

Per-skill evals complement `tools/skills/validate-skills.sh`. The source
validator checks skill metadata and contract structure; per-skill eval fixtures
exercise observable skill behavior. For review-style skills, prefer
`seeded_defects` for important scenarios so the score answers "did the reviewer
catch the planted issue?" instead of only "did the response mention the expected
headings?" Together they are the current Level 4 per-skill conformance
foundation for first-class assistant skills, with local-only skill experiments
remaining opt-in through `--include-local`.

## Native activation trials

`tools/evals/skill-activation/` measures whether a description activates its skill
before work starts, in stateful single-agent trials. Cases are in its `cases/`
directory, generated plugins and results stay in `.codex/skill-activation/`, and
`docs/specs/skill-activation.md` owns the rules and gates. Real trials call a
model, so each batch needs authorization for its exact call count and cost. They
need a macOS keychain item for the service `deepseek-api-key` and a config
directory at `~/.claude-deepseek`.

`suite.py validate` rejects cases that contain identifying paths, secrets or
the running user's home path. It does not match a bare username, which can be an
ordinary word such as `root`. To reject names as well, set
`SKILL_ACTIVATION_PRIVATE_TERMS` to a comma-separated list:

```bash
SKILL_ACTIVATION_PRIVATE_TERMS="name,handle" tools/evals/skill-activation/suite.py validate
```

Generate an arm. `--stubs 40` gives the crowded listing condition, and
`--descriptions FILE` applies a candidate to the generated copy only:

```bash
tools/evals/skill-activation/generate_plugin.py --output .codex/skill-activation/plugins/current
```

See the plan. With `--authorized-calls 0` the runner prints the plan, refuses and
exits 2, so it makes no call:

```bash
tools/evals/skill-activation/run_trials.py --batch dev-1 --arm current --set development --host-version 2.1.317 --repeats 3 --max-cost-usd 60 --authorized-calls 0
```

Run it. `--authorized-calls` must equal the plan's `calls`, and `--host-version`
keeps every arm of a comparison on one installed host:

```bash
tools/evals/skill-activation/run_trials.py --batch dev-1 --arm current --set development --host-version 2.1.317 --repeats 3 --max-cost-usd 60 --authorized-calls 217 --run
```

Report. Existing `activation_cases` use `--set activation` with two baselines and
a candidate, and the report then lists regressions:

```bash
tools/evals/skill-activation/report.py .codex/skill-activation/results/dev-1/results.jsonl
```

```bash
tools/evals/skill-activation/report.py .codex/skill-activation/results/act-*/results.jsonl --baselines current,current-b --candidate c1
```

`tests/test-skill-activation-tools.sh` tests the generator, scorer, runner and
report offline. It does not show that a description activates in a real model.
