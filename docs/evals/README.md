# Instruction Behavior Eval Fixtures

This directory contains provider-neutral prompt and instruction evaluation fixtures
for comparing framework behavior across model versions, including GPT 5.4 and
GPT 5.5. These are not model-specific API calls and do not prescribe any
provider SDK, endpoint, or scoring harness.

The fixtures focus on whether an assistant follows the framework instructions
under common operating conditions:

- lightweight handling for small fixes
- plan-before-build behavior for medium features
- complete implementation -> focused test -> failed trusted review -> repair ->
  focused revalidation -> fresh trusted review -> handoff behavior
- deterministic clarification for ambiguous prompts
- task-state recovery after context compaction
- TDD RED-before-GREEN handoff behavior
- executable task packet requirements before build
- per-slice verification before advancing
- separate spec review and quality review gates
- structured worker status packets from subagents
- subagent opt-out direct fallback
- Native Codex role constraints without extra runtime reinforcement
- Done Contract debate and Harness Recipe before Build
- trace/replay artifacts and typed artifact refs for harness recovery
- separate Code Reviewer and QA Evaluator evidence
- QA loop behavior with conditional domain rubrics
- pivot/restart decisions for stagnation and Code Writer blockers
- terminal max 10 review/QA round behavior

## Framework Instruction Fixtures

### Files

- `framework-instruction-cases.json` - machine-readable eval cases with prompts,
  setup context, expected behavior, pass criteria, failure signals, and local
  machine expectations.
- `framework-instruction-trace-result.schema.json` - strict, redacted result
  contract for importing completed runs or unavailable-adapter records.
- `framework-semantic-review-packet.schema.json`,
  `framework-semantic-review-verdict.schema.json`, and
  `framework-promotion-decision.schema.json` - bounded synthetic-review and
  fail-closed promotion contracts.
- `../../tools/evals/run-framework-instruction-evals.sh` - offline helper for
  validating the fixture and imported traces, listing cases, emitting prompt
  packets, grading captured responses, and comparing variants locally.
- `../../tools/evals/run-codex-framework-evals.sh` - source-repository-only opt-in Codex CLI adapter
  for blind, exactly paired baseline/candidate behavioral trials.
- `../../tools/evals/finalize-workflow-kernel-review.sh` - source-repository-only human
  verdict template and promotion finalizer; it invokes no model.

### How To Use

Validate the fixture before using it:

```bash
tools/evals/run-framework-instruction-evals.sh --validate-fixture
```

List the available cases:

```bash
tools/evals/run-framework-instruction-evals.sh --list
```

Emit provider-neutral prompt packets for manual or adapter-driven execution:

```bash
tools/evals/run-framework-instruction-evals.sh --emit-prompts /tmp/framework-eval-prompts
```

Run each prompt packet with any model or provider, then save the captured
assistant responses as `<case-id>.txt` or `<case-id>.md` in a response directory.
Grade those saved responses locally:

```bash
tools/evals/run-framework-instruction-evals.sh --responses /tmp/framework-eval-responses
```

Each case includes `machine_expectations.required_substrings` and
`machine_expectations.forbidden_substrings`. These arrays contain literal
observable substrings for deterministic local checks. Required substrings must
appear in the captured response, and forbidden substrings must not appear.

The response grader is intentionally heuristic/local grading. It checks for
missing files, empty responses, exact fail-signal phrase hits where useful,
missing required substrings, and forbidden substring hits. These deterministic
substring checks are proxies that complement human review or a separate LLM
judge; they do not replace natural language judgment.

### Trace import and A/B comparison

Model or provider execution stays outside this repository runner. An adapter,
manual session, or replay system may execute an emitted prompt packet, but it
must export one redacted JSON result per run using
`framework-instruction-trace-result.schema.json`. The local runner does not
invoke a model, provider SDK, endpoint, or network service.

Validate imported files with the `--validate-traces DIR` mode:

```bash
tools/evals/run-framework-instruction-evals.sh --validate-traces /tmp/framework-eval-traces
```

A `completed` result records only run identity and these measurements: input
and output tokens, latency, tool calls, question-mark-count proxy, time to first
useful action, rework count, and acceptance. It must not contain a raw prompt,
response body, credential, or secret. An `adapter_unavailable` result records a
structured error for diagnostics; it means the local execution adapter could
not run and is not counted as an acceptance failure.

Use baseline and candidate variants for the same case and model, then produce a
deterministic paired comparison with the `--compare-traces DIR` mode:

```bash
tools/evals/run-framework-instruction-evals.sh --compare-traces /tmp/framework-eval-traces
```

The comparison reports per-variant means and acceptance rates, candidate minus
baseline absolute and percentage deltas, and a separate redacted list of
unavailable runs. Percentage delta is `null` when the baseline is zero. Adapter
error messages are deliberately omitted from aggregate output.

### Blind Codex behavioral A/B execution

Use the Codex adapter when a real behavioral comparison is explicitly intended.
Its default mode only validates inputs and writes a paired run plan; it does not
invoke a model:

```bash
tools/evals/run-codex-framework-evals.sh \
  --model gpt-5.6-sol \
  --baseline-variant /path/to/baseline/assistant-workflow \
  --candidate-variant /path/to/candidate/assistant-workflow \
  --cases small-fix-stays-lightweight,medium-feature-plans-before-build \
  --repeats 1 \
  --output /tmp/codex-framework-plan
```

Each variant supplies a root `SKILL.md` overlay. The adapter copies the current
canonical `assistant-workflow` contracts and references into both disposable
workspaces, then replaces only the root file. This holds behavior contracts
constant while measuring the smaller kernel intervention.

Before any model call, adapter v5 runs only the reporter from the evaluator's
trusted repository; variant inputs can never supply executable tooling. It uses
`LC_ALL=C` over the already materialized snapshot root files. The run plan embeds one canonical,
count-only `context_budget_evidence` object plus its SHA-256. It binds the
reporter and both materialized instruction hashes. Generic manifest-free A/B
plans retain structural counts without applying workflow-kernel policy.
Manifest-backed promotion enforces fixed selected-skill caps of 1050 initial
words and 3000 entry-boundary words, zero standing-context growth, and the
hardcoded two-case smoke and six-case/three-repeat pilot. Internally consistent
but false or loosened manifests fail closed. The evidence contains no
instruction bodies or absolute paths.

Add `--execute` only after reviewing that plan. Execution uses the existing
local Codex login, isolated temporary Git workspaces, `--ephemeral`,
`--ignore-user-config`, a workspace-write sandbox confined to the disposable
fixture, and JSONL events. The runtime prompt
contains only setup context and the user request. Expected behavior, pass
criteria, fail signals, and machine grading anchors remain hidden from Codex.
Skill-local `evals/` directories are excluded from materialized variants, and
the native `.agents/skills/assistant-workflow` copy is exposed. Seeded Git baselines
make unexpected created, changed, or deleted paths measurable; review-only
cases fail verification on any workspace edit.
The `medium-final-handoff-is-reconstructable` case also seeds an incomplete
`SearchPolicy`, a focused contract command, and a trusted review command. The
review command owns a closed-world `.assistant-eval/review-evidence.json` with
only `schema_version`, `defect_id`, `first_review`,
`pre_repair_source_hash`, `defect_present_before_repair`, `repair`,
`post_repair_source_hash`, `defect_present_after_repair`, `revalidation`, and
`fresh_review`. The workspace verifier bounds and validates that artifact,
requires distinct before/after hashes plus a real seeded defect before repair
and its absence afterward, and checks the temporary JSONL event order. Trusted
test and review evidence must use an exact accepted command form; substrings or
commands padded with unrelated operations do not count. The grader also checks
focused-test exit codes, the expected nonzero first-review result with its
bounded must-fix marker, and the zero-exit fresh-review PASS marker before raw
storage is deleted. Stable
failure IDs distinguish a missing failed review (`workspace-011`), repair
(`workspace-012`), revalidation (`workspace-013`), and fresh-review-before-
handoff boundary (`workspace-014`). The fake adapter exercises the valid path
and each omission; it is deterministic contract coverage, not live-model
evidence.
Because `--execute` may use network access and model quota, obtain the applicable
approval before running it in personal or company environments.
On macOS, real Codex execution must run host-side, including an explicitly
supplied real Codex path. Before catalog lookup,
output creation, or any model call, the runner verifies that the current process
can create the nested Seatbelt sandbox required by `--sandbox workspace-write`;
an outer Codex Seatbelt context is rejected without consuming authorization.
Promotion additionally requires an `--execute` plan using the default Codex
binary and exact requested model `gpt-5.6-terra`. The runner resolves that
executable once, records its version and SHA-256, and hashes the one exact Terra
entry returned by `codex debug models` before any model call. Resume and finalization
recompute that bounded evidence, and execute mode rechecks it after every attempted
pair once both variants have durable trace records, and before producing a comparison
or semantic packet. All stages fail closed
on drift. The catalog is streamed through exact-entry selection and hashing; neither
the full catalog nor selected instruction-bearing entry is written to disk. Catalog
reads use a bounded Python subprocess watchdog (30 seconds by default, plan-bound
through `model_catalog_timeout_seconds`), a 4 MiB byte ceiling, and process-group
TERM/KILL cleanup on timeout or malformed/oversized output. Any `--codex-bin`
override, plan-only run, unavailable adapter, fake runner, or other model is
permanently ineligible even when behavioral and human-review gates pass.
Codex JSONL exposes `thread.started.thread_id` but does not expose a runtime
resolved-model identity. Traces therefore record
`runtime_model_attestation=not_exposed_by_codex_jsonl`; the requested slug and
catalog-entry evidence are never relabeled as backend resolution. Promotion
means the trusted local CLI advertised the exact slug, was explicitly invoked
with it, and completed successfully. Only provider-signed runtime telemetry
could prove the backend's physical model identity.
The top-level trace `model` field is a deprecated compatibility alias for
`provenance.requested_model`; strict validation requires equality and consumers
must not treat it as runtime-resolved telemetry.
The default executable resolution remains an accepted local PATH trust boundary;
its recorded hash detects later drift but does not make a compromised PATH trusted.

If an execute run is interrupted, repeat the exact command with `--resume` only
when exact validation succeeds, no uncertain `in_flight` or evidence-loss state
exists, and the incomplete-pair breaker remains within its plan-bound limit.
Before any Codex invocation, the runner atomically transitions the plan-bound,
content-free record in `run-attempts/` from `not_started` to `in_flight`; it
marks the run `completed` only after durable trace evidence exists. Resume
recomputes the plan and context evidence from the current trusted source and
materialized variants, then requires an exact match with the persisted run
plan. It deletes only recognized atomic temp names, rejects unknown or finalized
artifacts, strictly validates every existing trace, semantic checkpoint, and
run-attempt record, and executes only runs still proven `not_started`.
After each attempted pair has two durable trace records, the runner rechecks
model-selection evidence and counts incomplete pairs. A second incomplete pair
stops the batch before any later call,
leaves remaining attempt records `not_started`, and withholds comparison and
semantic-review artifacts. The exact limit is bound into the run plan as
`max_incomplete_pairs=1`. The runner never retries an uncertain call.

An `in_flight` record without a valid trace is quota-uncertain: resume exits
before every model call, reports only the bounded run ID, and requires separate
explicit authorization rather than silently repeating it. A `completed` record
without its trace is evidence loss and also fails closed. Starting a separately
authorized replacement run is the conservative recovery path for uncertain
pilot evidence. A changed fixture, grader, adapter, model, manifest, reporter,
baseline, or candidate fails before another model call.

Execute mode uses fsync-backed temporary-file writes, atomic rename, and parent
directory fsync for paid-call state and trace/checkpoint evidence. It requires
Python 3 for that narrow durability syscall. Fresh and resumed output paths
must resolve to real non-symlink directories; the parent is canonicalized
before any result write.

Each Codex child is tracked. INT/TERM is forwarded with a five-second grace
period before forced termination, and the runner waits for the child before
removing raw storage. The default per-run ceiling is 600 seconds and the
plan-bound total evaluation ceiling is 5,400 seconds. Override them only in the
reviewed command with `--run-timeout-seconds` and
`--total-timeout-seconds`; their values participate in exact resume-plan
matching. The earliest persisted attempt timestamp carries the total ceiling
across resume invocations.

Each baseline/candidate trial shares an exact `pair_id` and `trial_index`.
Pair execution order is deterministically counterbalanced and recorded so the
candidate is not always assigned the second-run condition.
When execution reaches aggregation,
`comparison.json` includes only complete pairs; missing or unavailable partners
are listed under `incomplete_pairs` and excluded from aggregates. Redacted trace
summaries include fixture, case, instruction, grader, and seeded-workspace
hashes, CLI and model
provenance, adapter version, exit status, acceptance item counts, seeded-defect
recall, known false-positive marker hits, scope deviations, and verifier results. Unknown JSONL
event shapes produce `adapter_unavailable` with a bounded error code instead of
fabricated zero metrics.
The comparison includes medians, paired recall/known-marker/scope deltas,
verifier failures, and a fail-closed `behavioral_promotion_eligible` verdict
covering every behavioral gate in the kernel manifest.

Non-zero Codex exits are diagnosed from machine-readable `error` and
`turn.failed` events before stderr using one 4 MiB-bounded diagnostic pass per
channel. Provider failure text is inspected ephemerally only to select a bounded
code and is never persisted; ordinary response events are never inspected for
failure classification.
An unknown structured failure becomes `codex_reported_failure`, while an exit
without a recognized structured failure becomes `codex_exit_nonzero`. These
codes are diagnostic only: either result remains `adapter_unavailable`, excludes
its pair, blocks promotion, and never authorizes an automatic retry.
`codex_exit_nonzero` is deliberately not a root-cause attribution and must not
be relabeled as model, quota, authentication, or network failure without a
recognized bounded signal.

Known marker hits are a bounded lexical proxy, not a semantic false-positive
count. The adapter reports automatic behavioral gates separately and keeps
`behavioral_promotion_eligible=false` until an explicit semantic review of
candidate findings is recorded. For synthetic `seeded_review` cases only, the
runner converts the temporary structured response into controlled claim codes
and writes `semantic-review-packet.json`. It never persists the whole model response.
Malformed, unsafe, or unclassified findings produce only a bounded
reason code and make the packet non-reviewable. Completed traces retain only
bounded positional criterion IDs alongside their counts; the case and grader
hashes bind those IDs to the exact local fixture without retaining matched
response text. When one seeded-review variant is unclassified, the blocked
packet keeps `pairs` empty and records only normalized claim codes plus bounded
variant, finding, reason, and hash diagnostics.

For a ready synthetic-only semantic packet, each normalized finding also keeps
its already validated, at-most-240-character `review_summary`. Summaries are
restricted to printable ASCII and reject both slash characters, so path-like
or Unicode-obfuscated content cannot enter the packet. This lets the human
reviewer detect when a lexical anchor was used in an unrelated sense.
The summary is never emitted for non-synthetic cases or copied into blocked
unsafe packets; whole response bodies and JSONL remain temporary and deleted.
For completed synthetic seeded-review runs, `semantic-checkpoints/` retains a
bounded normalized extract plus the already-sanitized trace draft. The final
trace binds the checkpoint SHA-256. These checkpoints contain no prompt,
response body, event stream, stderr, workspace, credential, or private source;
they exist only so an interrupted run can rebuild the packet without repeating
an already completed paid call.

The seeded review source is the committed, bounded synthetic fixture at
`docs/evals/fixtures/seeded-code-review-regressions/`. The packet records that
safe relative reference and its directory hash so a delayed human reviewer can
inspect the exact three synthetic files without retaining model prose or any
private project source.

After an exact pilot, create and complete the enum-only human verdict template,
then finalize it against the current candidate:

```bash
tools/evals/finalize-workflow-kernel-review.sh \
  --results /tmp/workflow-kernel-pilot \
  --baseline-variant skills/assistant-workflow \
  --candidate-variant docs/evals/variants/workflow-kernel-v1 \
  --write-verdict-template /tmp/workflow-kernel-verdict.json

# A human reviews every normalized candidate finding and explicitly replaces
# the pending reviewer attestation and finding-verdict enums.

tools/evals/finalize-workflow-kernel-review.sh \
  --results /tmp/workflow-kernel-pilot \
  --baseline-variant skills/assistant-workflow \
  --candidate-variant docs/evals/variants/workflow-kernel-v1 \
  --verdict /tmp/workflow-kernel-verdict.json
```

The finalizer verifies manifest, instruction, comparison, packet, pair, the
canonical full trace-set snapshot, run-plan, every current case/grader and
adapter identity, committed synthetic fixture, seed-workspace, and
current baseline/candidate hashes. It rematerializes both variants and
recomputes context-budget evidence with the current reporter before writing a
template or decision, so reporter, manifest, instruction, or evidence drift
cannot be reviewed as current. The evidence hash is carried through the run
plan, packet, human verdict, and promotion decision. It independently checks exact manifest pilot case,
repeat, and pair identities before accepting automatic gates. It writes
`promotion-decision.json`; this is the
only artifact that may set `behavioral_promotion_eligible=true`. Missing pilot
coverage, a stale binding, a non-human reviewer, an uncovered finding, or a
`false_positive`/`unverifiable` verdict fails closed. No free-form review notes,
credentials, absolute paths, private source, or extra model judge are accepted.
Run plans, content-free run-attempt records, traces, bounded semantic
checkpoints, comparisons, semantic packets,
verdict templates, semantic verdicts, and promotion decisions use same-directory
temporary files plus atomic rename. If finalization
is interrupted after exactly one generated final artifact, the same validated
verdict can be retried safely; a mismatched lone verdict or an already complete
two-artifact decision is rejected.

`grader_sha256` binds both the canonical case grading contract and the complete
Codex eval-runner implementation. Current promotion evidence requires adapter
`codex-framework-eval-v5`; changing the contract or runner invalidates existing
traces instead of retroactively re-grading deleted response or workspace data.

Metrics without native Codex event timestamps are explicitly labeled as
proxies in each trace: time to first useful action is a completion-latency upper
bound, unnecessary questions are a question-mark-count proxy, and rework is the
count of additional file-change events after the first.

Run-attempt records contain only bounded plan/run identity, state, and integer
timestamps; they never contain prompts, responses, events, stderr, workspaces,
environment values, credentials, private source, or token usage. Raw JSONL,
stderr, and final response bodies are held under mode-0700 temporary
storage and deleted after each run. They are not copied into the output
directory. The runner accepts no API-key option and never writes credentials.
An untrappable process kill, host crash, or power loss can leave a mode-0700
`codex-framework-evals.*` directory under the system temporary directory; this
is a filesystem residual, not promotion evidence, and should be removed under
the applicable local retention policy after confirming no eval process is live.

The committed `workflow-kernel-v1` overlay is measured without changing the
production root:

```bash
tools/context-budget-report.sh --agent codex --skill assistant-workflow \
  --skill-overlay docs/evals/variants/workflow-kernel-v1/SKILL.md \
  --format json
```

Use the exact `smoke_cases` and `pilot_cases` declared in the variant manifest.
The smoke uses one repeat (four runs total). Only after valid/redaction-safe
traces, expand to the six-case three-repeat pilot (36 runs), sequentially and
with the approved time/quota cap.
Authorization is invocation-bound: a replacement smoke, pilot, or retry that
would make new model calls needs fresh explicit authorization for its exact call
count. Prior authorization and a human verdict do not authorize a new 36-call
execution.

GPT-5.6-Terra represents the common simple-task smoke profile. Pin it explicitly
when generating and executing the reviewed four-run smoke plan.
The general runner default remains `gpt-5.6-sol` for other invocations:

```bash
tools/evals/run-codex-framework-evals.sh --execute \
  --model gpt-5.6-terra \
  --baseline-variant skills/assistant-workflow \
  --candidate-variant docs/evals/variants/workflow-kernel-v1 \
  --cases small-fix-stays-lightweight,seeded-code-review-regressions \
  --repeats 1 \
  --output /tmp/codex-framework-kernel-terra-smoke
```

### Current evidence boundary

The committed ordered-workflow fixture and runner changed the case and grader
hashes. Any earlier Terra snapshot is therefore historical evidence only and
cannot establish current behavioral promotion. Do not describe the architecture
as currently Terra-validated unless a newly authorized exact pilot completes
36/36 runs and 18/18 pairs against the current source, every automatic gate
passes, the bounded human semantic verdict covers the current packet, and the
finalizer writes `behavioral_promotion_eligible=true`. Repository contract tests
can validate the framework mechanics without consuming model quota, but they do
not substitute for that live promotion record.

### Source-only context budget

The promotion evaluator, finalizer, evidence helper, and context reporter are
source-repository-only and are deliberately excluded from agent installs;
installed copies retain only the legacy offline eval runner and fixtures.
Generate the reproducible native Codex inventory from the source repository.
The reporter is intentionally Codex-only until equivalent installed-context
semantics are defined and tested for other agents:

```bash
tools/context-budget-report.sh --agent codex --skill assistant-workflow --format json
```

The reporter requires a successful isolated temporary install and emits counts,
not instruction text. Installation failures stop the report instead of emitting
partial or zero-filled inventory. `project_agents` measures the repository
`AGENTS.md`.
`generated_global_agents` measures its installer-owned marker block.
`native_skill_catalog_descriptions`
measures the first-class `assistant-*` description catalog. The selected
skill's initial boundary is `SKILL.md` plus `contracts/index.yaml` when present;
its entry boundary adds references declared for the `entry` load set and only
the contract items selected there. Schema 2.0 reports only native instruction
components; totals exclude retired lifecycle registrations and their output.

Pass a prior JSON report with `--baseline FILE` to add current-minus-baseline
absolute and percentage deltas. A zero baseline produces a `null` percentage.
The report never includes prompt bodies, instruction bodies, responses,
credentials, or environment values.

The cases are intended for prompt/instruction behavior comparisons. They should
be useful whether the evaluated assistant is backed by GPT 5.4, GPT 5.5, Claude,
Gemini, or another provider.

The eval flow is provider-neutral: the helper only reads local fixture and
response files. It does not invoke provider APIs, provider SDKs, or network
services.

## Per-Skill Eval Fixtures

Skill-local eval fixtures live beside the skill they exercise:

```text
skills/<skill>/evals/cases.json
```

`tools/evals/run-skill-evals.sh` validates, lists, emits, and locally grades
those skill fixtures with the same provider-neutral constraints as the framework
instruction eval runner. It uses local shell and `jq` only; it does not call
provider SDKs, model APIs, or network services.

This slice now covers all 14 first-class `assistant-*` skills. Local-only Unity
skills remain excluded from the default inventory unless `--include-local` is
passed. The current tracked first-class fixtures are:

- `skills/assistant-clarify/evals/cases.json`
- `skills/assistant-debugging/evals/cases.json`
- `skills/assistant-diagrams/evals/cases.json`
- `skills/assistant-docs/evals/cases.json`
- `skills/assistant-ideate/evals/cases.json`
- `skills/assistant-onboard/evals/cases.json`
- `skills/assistant-research/evals/cases.json`
- `skills/assistant-review/evals/cases.json`
- `skills/assistant-security/evals/cases.json`
- `skills/assistant-skill-creator/evals/cases.json`
- `skills/assistant-tdd/evals/cases.json`
- `skills/assistant-telos/evals/cases.json`
- `skills/assistant-thinking/evals/cases.json`
- `skills/assistant-workflow/evals/cases.json`

By default, the runner discovers first-class `skills/assistant-*/SKILL.md`
skills that have `evals/cases.json` fixtures. Local-only `skills/unity-*`
skills are excluded from the default inventory. Use `--include-local` only when
you explicitly want to include local skill experiments that also have eval
fixtures.

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

Prompt packets are written under `<output>/<skill>/<case-id>.md` and include the
setup context, prompt, expected behavior, pass criteria, fail signals, optional
seeded defects / measurable assertions, and machine expectations.

Run each prompt packet with the target assistant and save captured responses as
`<response-dir>/<skill>/<case-id>.txt` or `<response-dir>/<skill>/<case-id>.md`.
When a single fixture is selected, the runner also accepts flat
`<response-dir>/<case-id>.txt` or `<response-dir>/<case-id>.md` files.

Grade saved responses locally:

```bash
tools/evals/run-skill-evals.sh --responses /tmp/skill-eval-responses
tools/evals/run-skill-evals.sh --responses /tmp/clarify-eval-responses --skill assistant-clarify
```

Include local-only skill experiments explicitly:

```bash
tools/evals/run-skill-evals.sh --validate-fixture --include-local
tools/evals/run-skill-evals.sh --list --include-local
```

The response grader is heuristic/local grading. It checks missing files, empty
responses, exact fail-signal phrase hits where useful, missing required
substrings, forbidden substring hits, and optional `seeded_defects` measurable
assertions. Seeded defects make evals more measurable by requiring captured
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
