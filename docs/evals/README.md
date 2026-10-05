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

## Observed execution-pattern evidence

The pattern cases distinguish a deterministic policy fixture from evidence the
Codex adapter actually observed in its JSONL event stream.

- `small-fix-stays-lightweight` requires its exact target-file discovery probe
  to be the first workspace command or file action; the matching command-start
  event may precede its successful completion. This rule and its no-web/MCP
  check apply only to the disposable local typo fixture, not delegated work.
  Its admitted command vocabulary is limited to that exact read-only probe,
  including bounded raw, argv, and shell-wrapper forms. Any other started or
  completed command is an unsupported scope observation, regardless of whether
  a later target-file event is present. The adapter reports unavailable only
  when response, final-content, plan, scope, observed-path, discovery-order, and
  external-tool checks reveal no independent failure. A grading artifact alone
  cannot pass the case. Every observed file-change event must name only the
  target or grading artifact; combined or separate out-of-scope paths fail even
  when the final workspace diff is clean. Malformed raw event structure follows
  the pre-grading unavailable policy, while well-formed unsafe paths and failed
  target completions remain observed failures. With no `file_change`, command
  text and final state still cannot prove which command edited the target or
  when, so the existing unavailable route remains. Observable pre-discovery
  actions, external calls, and incorrect final content remain completed
  failures.
- `pivot-restart-on-stagnation-or-code-writer-blocker` seeds a trusted failing
  check, fixture-owned failure/recovery receipts, recovery action, and fresh
  check. Its recovery artifact retains `terminal_completed=false`: a fresh-check
  pass validates the recovery protocol, not repair of the legacy bug or workflow
  completion. It admits only the three trusted fixture scripts and optional
  read-only `cat RECOVERY.md`; any other started or completed command fails the
  bounded case. Completed commands require numeric exit codes; a started command
  needs no exit or output. For the three trusted marker commands, the selected
  `aggregated_output`/`output` value must be a string. A numeric nonzero exit or
  wrong marker in a string remains behavioral failure evidence; small-fix
  output, passive message content, and optional recovery-read output are not
  consumed. A present command start must have a nonempty id and one later
  completion with the same admitted command kind; duplicate, unmatched, or
  mismatched starts, and duplicate nonempty completion ids fail. Each recovery
  artifact file-change event must also occur after the recovery start (or the
  completion when no start exists) and before the fresh-check start (or its
  completion when no start exists). Events before the trusted failure or
  recovery, after the fresh-check start, and after fresh-check completion fail;
  events during a matched recovery and after recovery completion but before the
  fresh check remain valid. Once that unique fresh check completes, any later
  started or completed command or file-change event also fails. This boundary
  applies only to the disposable recovery fixture.
- `isolated-parallel-a-b-then-c-with-integration` records the required A/B/C
  dependency and integration policy, but current Codex CLI JSONL does not expose
  authoritative worker, workspace, isolation, or overlap telemetry. The adapter
  therefore emits `adapter_unavailable` with `unknown_event_shape`, no metrics,
  and an excluded incomplete pair. Agent-message narrative never upgrades that
  result to observed native parallel execution.

The workflow policy fixtures still test shared-workspace sequencing,
runtime-proven isolation, VERIFIED prerequisites, integration validation, and
fresh review deterministically. They do not supply native execution telemetry.

## Generated workflow references

`assistant-workflow` phase and plan views are generated from their authoritative
Markdown sources. Run `tools/skills/sync-workflow-references.py --apply` after
changing those sources and `--check` in validation. The views provide static
selected-word measurements only; they do not establish token, latency, or model
quality effects.

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
- `workflow-kernel-activation-observation.schema.json` and
  `fixtures/workflow-kernel-activation-observation.contract.json` - bounded
  external native-selection attestation. The checked-in companion fixture is a
  `contract_test_fixture`, validates mechanics only, and can never promote.
- `../../tools/evals/run-framework-instruction-evals.sh` - offline helper for
  validating the fixture and imported traces, listing cases, emitting prompt
  packets, grading captured responses, and comparing variants locally.
- `../../tools/evals/run-codex-framework-evals.sh` - source-repository-only opt-in Codex CLI adapter
  for blind, exactly paired baseline/candidate behavioral trials.
- `../../tools/evals/finalize-workflow-kernel-review.sh` - source-repository-only human
  verdict template and promotion finalizer; it invokes no model.

### How To Use

The Draft 2020-12 promotion-decision contract test uses the locked local Ajv
tooling dependency. Before running that contract suite, install it once with
Node.js 22 and npm:

```bash
(cd tools/evals && npm ci --ignore-scripts)
```

The suite fails clearly when Node, npm, or this locked dependency is absent; it
never installs packages during validation.

For a quick response-builder completeness check, run:

```bash
bash tests/p0-p4/skill-eval-contracts.sh --fixtures-only
bash tests/p0-p4/progressive-discovery-contracts.sh --fixtures-only
```

Both suites also run this preflight automatically before semantic grading. It
uses the actual builders in fresh temporary directories and rejects builder
failures, missing/blank responses, and structured responses containing invalid
JSON or multiple JSON values. JSON is required for cases with structured
assertions or a semantic validator. It checks completeness and JSON syntax; the full
suites still verify semantics and mutation rejection. `--fixtures-only` is for
direct suite invocation and does not skip checks in the aggregate runner.

The aggregate runs the small preflight unit controls. Each of the two owning CI
shards separately runs its real-entrypoint probe before long semantic grading,
so excluded shards do not trigger full response-builder traversals in the
aggregate job. The probe checks both valid fixtures and an injected unhandled
case, and asserts that neither probe invokes the semantic grader. To run one:

```bash
python3 tests/p0-p4/lib/response-fixture-entrypoint-probe.py skill-eval-contracts.sh
```

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
assistant response using the packet basename with a `.txt` or `.md` extension.
Clarification packet names are opaque `task-NN` aliases; their numbering is
stable in full-fixture order, even when prompt emission filters cases. Other
packets keep their case-id names. Grade those saved responses locally:

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

### Clarification evidence boundary

Clarification behavior cannot be graded from required/forbidden substrings. The
offline framework and skill graders return `UNAVAILABLE` for affected cases;
phrase counts remain proxy diagnostics only. Prompt emission gives the actor an
opaque `task-01.md`-style packet containing only the current user request. The
frozen actor prompts and separate expected-behavior oracle live under
`fixtures/clarification/`; copy only one task's `actor-projects/task-*` directory
into a disposable workspace, and send only its current prompt to the actor.
Never copy evaluator fixtures or the oracle into that workspace.

For a retained runtime capture, create a review JSON conforming to
`fixtures/clarification/clarification-evidence-review.schema.json`, then import
it with the bounded local helper:

```bash
EVIDENCE_ROOT=/path/to/evidence
mkdir -p "$EVIDENCE_ROOT/actor-prompts"
cp docs/evals/fixtures/clarification/clarification-oracle.json "$EVIDENCE_ROOT/clarification-oracle.json"
cp docs/evals/fixtures/clarification/actor-prompts/task-08-answer.txt "$EVIDENCE_ROOT/actor-prompts/task-08-answer.txt"
node tools/evals/lib/clarification-evidence.cjs \
  --review "$EVIDENCE_ROOT/review.json" \
  --oracle "$EVIDENCE_ROOT/clarification-oracle.json" \
  --evidence-root "$EVIDENCE_ROOT"
```

The review binds controller-retained prompt/answer inputs, per-turn native
Codex JSONL, before/after workspace manifests and a diff by SHA-256. Every
completed response turn must contain at least one completed `agent_message`; an
empty message string still counts as an observed event, while a partial turn
remains incomplete. Artifact
paths are non-whitespace POSIX project-relative paths: they cannot be absolute,
contain backslashes or NUL, or have empty, `.` or `..` slash-separated segments.
The published schema mirrors these importer rules while retaining runtime-accepted
spaces, newlines, and drive-colon-relative names. A separate
semantic review must cite actual assistant questions, user answers, carry-forward
evidence and dependent edits. It can record an unsolicited controller answer as
`kind: "unsolicited"` with a null question reference and an explicit rationale;
this records the input without inventing an earlier question or satisfying an
open decision. Missing or unmatched turns, unsupported edit
ordering, absent semantic review or missing telemetry is `UNAVAILABLE`; a
supported missing material question is `FAIL`. The importer derives the earliest
observed edit for each reviewer-designated dependent path so a later write cannot
hide an earlier write. It retains all workspace manifest paths and counts
framework-owned `.codex/` journal changes separately from dependent project
edits. A confirmed file-change event may also establish ordering when a stable
project path is present with the same digest in both manifests; the reviewer
must still reference every observed project path. Events for paths absent from
the manifests remain `UNAVAILABLE`. The importer validates unified diff file
headers against their Git section and ignores marker-like text inside hunks.
For a path with changed before/after hashes, its retained section must include a
fully counted textual hunk with at least one added or deleted content line.
Pure renames with unchanged content and explicit rename metadata remain valid;
empty-file additions and deletions require the corresponding file-mode marker
and SHA-256 of empty bytes, with `/dev/null` headers when file headers are
present. Binary diff encodings are currently
unsupported and keep the evidence `UNAVAILABLE`.
Punctuation by itself is never a material question.
For a case with zero frozen material decisions, an actual `material` or
`non_material` question is `FAIL`; `punctuation_only` and `not_a_question`
assessments do not trigger that failure.

Each oracle case includes `initial_prompt_sha256` for its frozen actor prompt
and `initial_workspace_sha256`, a path-to-digest map for every file in that
case's frozen actor project. The importer compares the exact bytes of the
retained turn-1 controller input and the complete before-workspace manifest
with those bindings. Missing, changed, removed, or extra project files keep
behavior `UNAVAILABLE`; `.codex/` framework journal paths remain outside the
actor-project comparison. The owning contract test cross-checks every case map
against the frozen fixture manifest and checks that manifest against the exact
retained fixture file set and hashes, including the oracle digest.
The importer reads `docs/evals/fixtures/clarification/frozen-cases-sha256.json`
from its fixed repository-relative location and compares the supplied oracle's
raw bytes with its `clarification-oracle.json` entry. An altered or untrusted
oracle, or an unavailable manifest, keeps behavior `UNAVAILABLE` even when a
review repeats that oracle's digest; no review-provided digest can replace the
repository-owned manifest. The importer still evaluates supported evidence so
other specific unavailable reasons remain visible.

For task-04, a zero-question result requires turn 1 to retain successful
single-file `cat PATH` or `cat -- PATH` commands for both `docs/permissions.md`
and `src/issue_access.py`, before the final assistant response. An earlier
progress message is allowed. Each completed
command must have exit code zero, and its captured output bytes must hash to the
corresponding frozen workspace digest. The bounded parser accepts optional
`sh`, `bash`, or `zsh` `-lc` wrappers; search commands, echoed path strings,
failed or started-only commands, and output that differs from the frozen file
cannot establish inspection.

The task-08 prompt assigns the stable ID `link-access` only if an access
clarification is needed and permits the actor to proceed without asking when
access is already clear. Its retained continuation answer uses that ID as a
prefix: `link-access: Anyone who has the link should be able to open it without
an account.`

For an oracle case that declares `required_missing_policy_path`, task-specific
behavior remains `UNAVAILABLE` until turn 1 contains a completed, failed read
of that exact project-relative path and a matching `cat: PATH: No such file or
directory` diagnostic. The bounded importer recognizes only a single-file
`cat PATH` or `cat -- PATH` command, optionally wrapped by `sh`, `bash`, or
`zsh` with `-lc`. It only parses captured command text and never executes it.
Other readers, multiple file operands, search patterns, shell compounds,
successful commands, started-only events, and diagnostics for another path do
not establish the read. An optional `semantic_review.missing_policy_read_ref`
can bind the qualifying command to one exact turn/line event.

An oracle case with `continuation_answer_file` requires a top-level
`oracle_requirements` binding: the exact case ID and raw oracle hash, required
answer turns, required post-answer decision indexes, an expected answer artifact
for each required turn, and an applicability-basis artifact with a record
reference and rationale. The importer resolves `continuation_answer_file`
relative to the supplied oracle file and admits that exact path and its SHA-256
inside the evidence root. Stage the unchanged oracle and its declared answer
payload inside that root. The importer compares those bytes with the captured
controller input. Hashes bind the files but do not authenticate the applicability
assertion or the independent semantic review.

Required answer receipt, relevance, completed response and post-answer question
coverage are separate fields. A required answer is relevant when its captured
bytes match the oracle payload and the independent review links it to a
completed material question from an earlier turn. That initial question may
have an empty `decision_indexes` list: an access answer can trigger a later
lifecycle question without itself covering that hidden lifecycle decision. The
required post-answer question must separately be material and linked to its
frozen decision index. A completed relevant response with that question missing
is `FAIL`; an absent or incomplete required continuation keeps the top-level
`behavior_status` `UNAVAILABLE`, even when a separate supported violation makes
`semantic_status` `FAIL` and appears in `behavior_reasons`.

For a valid started transcript prefix, a completed dependent plan or edit before
clarification remains in `behavior_reasons` even if the turn later times out. In
that case `semantic_status` can be `FAIL` while top-level `behavior_status` stays
`UNAVAILABLE` because required scenario coverage is incomplete. Consumers must
preserve both fields and the supported reasons; they must not drop those
violations or relabel the top-level result. A timeout with no supported
premature action stays `UNAVAILABLE` without inferring a missing question
failure. A file-change `item.started` event alone does not prove a write. If a
matching `item.completed` event in the same turn has the same native item ID and
exact path, the importer uses the matching start for earliest write ordering
and the completion event as confirmation. An independent `dependent_edit_ref`
may cite either the completion line or that confirmed start line; an unpaired
start cannot support a semantic reference. Pairing requires the same turn, a
nonempty native item ID and the exact path. Event item IDs can be reused by
later turns, so starts never pair across turns.


For oracle cases that require asking before planning, the independent review must
also bind a `planning_applicability` assertion to the exact `case_id` and raw
oracle SHA-256. Its requirement must exactly match the frozen
`planning_requirement` field in that oracle case; a missing, unsupported or
mismatched value is `UNAVAILABLE`. A `before_plan`
assertion requires an explicit assessment for every frozen decision: either a
dependent plan with one or more evidence references, or an explicit
`no_dependent_plan` result. The reviewer attests that every completed agent
message was checked for dependent planning. When native `todo_list` events
occur, `native_plan_assessments` also covers each `item.started`, `item.updated`,
and `item.completed` event separately. An independent exploratory event has no
decision indexes; a dependent event maps to its decisions and must appear in
each matching decision's `plan_refs`. These native references use turn and line
without a text span. Message plan references still require bounded text spans.
Missing event coverage or conflicting no-plan assertions is `UNAVAILABLE`.

Task-05 also requires a `policy_conflict_assessment` bound to the exact case and
raw oracle SHA-256. The frozen oracle names decision 0 and exactly
`docs/security-link-rules.md` plus `docs/product-sharing-notes.md`; the
assessment must explicitly cover whether it identified their conflict and
explained its security impact, with at least one bounded nonempty span from an
actual completed message. Missing or malformed assessment evidence is
`UNAVAILABLE`. A complete supported assessment that explicitly denies either
claim is `FAIL`; incomplete transcript evidence does not infer a failure from
an explanation that may still be in progress. These boolean fields are
independent semantic judgments, not keyword checks, and transcript spans bind
them to retained message bytes without authenticating the reviewer.

Every completed `agent_message` needs an explicit question assessment:
`material`, `non_material`, `punctuation_only`, or `not_a_question`. Only
`material` and `non_material` are question events; punctuation-only and
not-a-question results remain explicit but are not counted as questions. The
importer does not infer message intent from punctuation. Message planning and
material-question references point to completed agent-message events and
bounded, nonempty text spans. Agent-message carry references also need such a
span, so a carried answer and plan in one message retain their internal order;
overlapping carry and plan spans are `UNAVAILABLE`, while a plan before the
carried span is `FAIL`. Span offsets are zero-based UTF-16 code units into the
captured message text. Within one event, plan and question spans must not
overlap; a dependent plan must follow each linked material question and a
carried-forward answer. Native command and file-change carries, like native
todo-list plans, retain event-line ordering and have no text span. Each native
todo-list started, updated, or completed observation retains its own ordering. A material question may have an empty
`decision_indexes` list when it concerns a choice outside the frozen decision
set; it does not satisfy any indexed decision. Offering options in a question
can be assessed as `no_dependent_plan` when no dependent plan was committed.
Cases whose oracle requires only clarification before edits use
`before_edit_only` and do not acquire a before-plan ordering check.

The review schema accepts POSIX roots, drive-qualified Windows roots, and UNC
roots while rejecting relative and drive-relative roots. This is a schema
contract; the importer still uses the host platform's path rules, so validating
a Windows root in the schema does not exercise the importer on Windows.

These applicability, coverage, and semantic classifications remain independent
reviewer assertions. Hashes and text spans bind those assertions to retained
oracle and transcript bytes; they do not authenticate the reviewer or prove
that the asserted meaning is correct. Older v1 evidence documents still parse
under the additive schema, but an importer run without the new applicability
and required coverage reports `UNAVAILABLE` rather than inheriting a pass.

Codex JSONL does not echo controller inputs or provide a dedicated native skill
selection event. Missing activation evidence, including native selection, a
forced-load receipt, or a staged skill command reference, contributes to
`UNAVAILABLE`. The result labels controller-captured input separately, reports
turn/event-line ordering without claiming wall-clock chronology, and keeps native
selection `UNAVAILABLE`. It may report that a completed command names a staged
`SKILL.md` path, but that text reference does not prove the file was read or the
native skill router selected it. A forced skill-load receipt is reported as
forced loading and cannot stand in for native activation. The semantic reviewer ID and independence role
are assertions; artifact hashing binds retained bytes but does not authenticate
the reviewer or prove that the review was independent.

A forced-load receipt must include `invocation_mode: "forced_skill_load"`, the
`skill_name`, a `skill_sha256` recorded by the loader for the staged skill bytes,
and a `run_binding_sha256`. The importer binds that claimed skill digest to the
current case and actor, the supplied oracle digest, and every admitted controller
input and transcript digest. It cannot independently authenticate the staged
skill bytes from Codex JSONL; the receipt remains a loader assertion. Reusing a
generic or stale receipt makes activation `UNAVAILABLE`.

Compute `run_binding_sha256` as SHA-256 over the UTF-8 bytes of the binding
object serialized with JavaScript `JSON.stringify`. Preserve this key order:
`case_id`, `actor_id`, `oracle_sha256`, `inputs`, `transcripts`, `skill_name`,
`skill_sha256`. Sort `inputs` by ascending turn; each input object uses the key
order `turn`, `kind`, `sha256`. Sort `transcripts` by ascending turn; each
transcript object uses `turn`, `sha256`. Python producers can reproduce the
serialization with `json.dumps(binding, separators=(",", ":"),
ensure_ascii=False).encode("utf-8")`, preserving insertion order.

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

Each directory variant supplies a root `SKILL.md` overlay. The adapter copies
the current canonical `assistant-workflow` contracts and references into both
disposable workspaces, then replaces only the root file. This holds behavior
contracts constant while measuring the smaller kernel intervention.

For an exact instruction-only variant, pass a regular JSON manifest as either
variant argument. It has the closed shape below and its payload files live next
to the manifest. The base hash is SHA-256 of the sorted lines
`relative-path SHA-256(file-bytes)` for the trusted canonical tree, excluding
the top-level `evals/` directory. Use the helper to print that value and to
validate a manifest before planning:

```bash
tools/evals/lib/instruction-overlay.py source-hash \
  --base-skill-tree skills/assistant-workflow
tools/evals/lib/instruction-overlay.py inspect \
  --base-skill-tree skills/assistant-workflow \
  --manifest /path/to/overlay.json
```

Compute each payload entry with `shasum -a 256 /path/to/payload-file | awk '{print $1}'`,
then place the manifest and only its listed payload files in one directory.

```json
{"schema_version":"1.0","mode":"hashed_instruction_overlay","base_skill":"assistant-workflow","base_source_sha256":"<64 lowercase hex>","files":[{"path":"SKILL.md","sha256":"<64 lowercase hex>"}]}
```

`files` must be unique and strictly sorted, include `SKILL.md`, and may contain
only `SKILL.md`, `references/**`, or `contracts/**`. The helper rejects stale,
unlisted, unsafe, symlinked, special, or oversized payloads before a plan is
written. Exact variants record only mode, manifest hash, base hash, and file
count; they are deliberately ineligible for workflow-kernel promotion.
The evaluated tree preserves the canonical base and listed overlay bytes without
placeholder substitution, including literal `{agent_state_dir}` text. If a trial
needs `.codex` paths, put those rendered bytes in the listed payload files before
hashing the manifest. Legacy directory overlays continue to render this token.
The run plan's instruction hash binds the complete materialized tree in both modes.
Exact-manifest planning requires Python 3 for bounded admission and Ruby for
the materialized-tree context measurement. Existing directory root overlays
retain their root-only reporter path and do not add either prerequisite.

Before any model call, adapter v7 runs only the reporter from the evaluator's
trusted repository; variant inputs can never supply executable tooling. It uses
`LC_ALL=C` over the already materialized snapshot root files. The run plan embeds one canonical,
count-only `context_budget_evidence` object plus its SHA-256. It binds the
reporter and both materialized instruction hashes. Generic manifest-free A/B
plans retain structural counts without applying workflow-kernel policy.
Manifest-backed promotion enforces fixed selected-skill caps of 1050 initial
words and 3000 entry-boundary words, zero standing-context growth, and the
hardcoded two-case smoke and eight-case/three-repeat pilot. Internally consistent
but false or loosened manifests fail closed. The evidence contains no
instruction bodies or absolute paths.

Add `--execute` only after reviewing that plan. Execution uses the existing
local Codex login, isolated temporary Git workspaces, `--ephemeral`,
`--ignore-user-config`, a workspace-write sandbox confined to the disposable
fixture, and JSONL events. The runtime prompt
contains only setup context and the user request. Expected behavior, pass
criteria, fail signals, and machine grading anchors remain hidden from Codex.
When an execute selection includes `viewing-route-technical-preparation`, the
adapter additionally requires a working `node --test` capability before it
persists a run plan or invokes Codex because it validates that case's trusted
seed fixture with Node's test runner. A bounded capability probe fails closed
before output admission or model calls; Python 3 supervises that probe so its
entire process group is reaped if Node hangs. This conditional prerequisite is separate from the
Node.js 22 and Ajv requirement for contract-suite validation; plan-only runs
and execute selections that omit the VIEWING case do not require it.
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
when an exact final persisted run plan already exists, exact validation
succeeds, no uncertain `in_flight` or evidence-loss state exists, and the
incomplete-pair breaker remains within its plan-bound limit. A missing plan or
an orphan atomic plan temp never authorizes a resume; use a separate new output
for replacement execution. The runner holds one crash-aware exclusive output
lease from validation through final artifact creation, so concurrent writers
fail before model invocation. It never automatically reclaims a stale-looking
lease: any existing lease remains untouched and requires explicit operator
cleanup or a new output directory.
Its `FRAMEWORK_EVAL_TEST_*` synchronization hooks are rejected unless an
isolated contract test explicitly enables test mode, supplies the repository
fake-Codex capture directory, and uses an executable `--codex-bin` override;
normal invocations never activate those hooks.
For preparation readiness, `existing_system` carries its exact unchanged feature-preparation evidence ref, while `not_applicable` carries `preparation_basis=not_applicable` and no feature-evidence ref. An explicitly requested `prepare_only` readiness Plan is inline and does not wait; only execution work can use `approval_required`.
Before the durable run plan is committed, execute mode writes a plan-hash-bound,
content-free pre-attempt authorization marker. Resume may create missing
`not_started` attempt records only while that exact marker remains and no trace,
checkpoint, comparison, semantic packet, or started attempt evidence exists; it
durably removes the marker before any Codex call. Missing execution evidence
without this positive marker is evidence loss, never retry authority.
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
`max_incomplete_pairs=1`. Only the known pre-dispatch unavailable traces for the
`isolated-parallel-a-b-then-c-with-integration` fixture are excluded; every other
incomplete pair counts toward the limit. The runner never retries an uncertain
call.

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

Each Codex invocation runs under a supervisor in a new process group. INT/TERM,
launch failure, and timeout terminate and wait for that complete group before
the lease or raw storage is released. The default per-run ceiling is 600 seconds and the
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
`codex-framework-eval-v7`; changing the contract or runner invalidates existing
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
traces, expand to the eight-case three-repeat pilot (48 runs), sequentially and
with the approved time/quota cap.

Native routing is not invoked by this repository. A human evaluator may capture
the six exact `assistant-workflow` activation selections from a native Codex
session, without retaining raw session content, then supply that bounded JSON
artifact to the adapter:

```bash
tools/evals/run-codex-framework-evals.sh --activation-observations /tmp/workflow-native-activation.json ...
```

The adapter records the artifact hash and a redacted admissibility summary in
`run-plan.json`, then copies the validated observation to
`activation-observations.json`. Freshness is checked when the runner admits a
manual observation; finalization verifies that immutable hash binding rather
than applying a second wall-clock freshness window. Promotion requires a fresh
`manual_native_observation` with `human_evaluator`, `manual_native_session`,
and `native_host=codex`, bound to the exact candidate skill and six activation
cases. Missing evidence, stale hashes, or the checked-in
`contract_test_fixture` fail closed with
`native_activation_observation_not_admissible`.
Authorization is invocation-bound: a replacement smoke, pilot, or retry that
would make new model calls needs fresh explicit authorization for its exact call
count. Prior authorization and a human verdict do not authorize a new 48-call
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
48/48 runs and 24/24 pairs against the current source, an admissible
hash-bound manual native activation observation, every automatic gate
passes, the bounded human semantic verdict covers the current packet, and the
finalizer writes `behavioral_promotion_eligible=true`. Repository contract tests
can validate the framework mechanics without consuming model quota, but they do
not substitute for that live promotion record.

Python 3 is required whenever the runner validates a `manual_native_observation`
freshness timestamp, including plan-only admission. The runner checks that
prerequisite before evaluating freshness; resume validates the persisted binding
without reapplying the admission-time freshness window.

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

For a static named `contracts/index.yaml` load set, add `--load-set NAME`. The
optional `selected_load_set_context` separates the declared boundary closure
from recursively projected worker return-schema additions. It measures the
static selected skill instruction surface only; it does not represent model
wrappers, dynamic dispatch, user conversation, or total runtime context.
`--skill-tree DIR` measures an already materialized, safe skill tree and cannot
be combined with the root-only `--skill-overlay FILE` mode.

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
instruction eval runner. Operational modes require local shell, `jq`, and Ruby
with JSON plus Psych/YAML support; response grading also requires Ruby
BigDecimal. It does not call provider SDKs, model APIs, or network services.

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

Every first-class fixture uses schema `2.0` and declares top-level
`activation_cases`. Each entry is exactly `{ "user_request": string,
"should_activate": boolean }`; fixtures need at least two
normalized-distinct positive requests and one normalized-disjoint nearby
negative. Schema `1.0` custom/local fixtures may omit activation cases, but an
included field is still structurally validated. Other schema versions are
rejected. These cases provide
native-description activation evidence and remain separate from response-grade
`.cases` and SKILL.md frontmatter.

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
