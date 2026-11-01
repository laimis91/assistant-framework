# Clarification evidence

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

For the exact frozen task-03 and task-04 cases, a completed response establishes
that the actor proceeded only when the final manifest retains a net change to
`src/issue_detail.py`, a completed edit to that path is bound in
`dependent_edit_refs`, and an independent `semantic_review.implementation_outcome_assessment`
binds the exact oracle and admitted diff. Its `reviewed_paths` must cover every
final changed project path and match the after-manifest hashes; a deleted path
uses `after_sha256: null`. A complete no-op, refusal, promise-only, README-only,
reverted-source, or inspection-only response is `FAIL`. A changed owning source
with missing or invalid assessment remains `UNAVAILABLE`; a supported
`not_implemented` assessment is `FAIL`. The semantic outcome assertion does not
prove execution correctness or authenticate the review. These bindings connect
the semantic judgment to the retained diff and manifests; they do not prove
that the diff reconstructs the final workspace bytes.

For task-04, a zero-question response also requires turn 1 to retain successful
single-file `cat PATH` or `cat -- PATH` commands for both
`docs/permissions.md` and `src/issue_access.py`, before the first completed
assistant message and before the earliest project edit. Each completed command
must have exit code zero, and its captured output bytes must hash to the
corresponding frozen workspace digest. The bounded parser accepts optional
`sh`, `bash`, or `zsh` `-lc` wrappers; search commands, echoed path strings,
failed or started-only commands, and output that differs from the frozen file
cannot establish inspection. Supported reads alone do not satisfy the project
edit requirement.

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
can bind the qualifying command to one exact turn/line event. That completed
failed read must precede every cited task-06 authority-explanation span,
each validated material question assessment linked to decision 0 (including
one omitted from its selected question references), and every selected question
reference. An explicit reference to a later read is not replaced by an earlier
matching command; without an explicit reference, the importer uses the earliest
qualifying read. Missing or out-of-order evidence keeps
`missing_policy_read_status` unavailable.

Controller input and transcript turn 1 is always eligible for admission. Later
answer and response turns are admitted only when the trusted oracle declares
the continuation; undeclared extra turns keep behavior `UNAVAILABLE`.

An oracle case with `continuation_answer_file` requires a top-level
`oracle_requirements` binding: the exact case ID and raw oracle hash, required
answer turns, required post-answer decision indexes, an expected answer artifact
for each required turn, and an applicability-basis artifact with a record
reference and rationale. Generic declared continuations may have an empty
post-answer decision list; task-08 requires at least one reassessment decision. The importer resolves `continuation_answer_file`
relative to the supplied oracle file and admits that exact path and its SHA-256
inside the evidence root. Its bytes must also match the helper-relative frozen
manifest entry keyed by the oracle-declared path; changing both the staged bytes
and review-provided hashes cannot replace the trusted expected answer. Stage the
unchanged oracle and its declared answer payload inside that root. The importer
compares those trusted bytes with the captured controller input. Hashes bind the
files but do not authenticate the applicability assertion or the independent
semantic review.

Required answer receipt, relevance, completed response and post-answer question
coverage are separate fields. A required answer is relevant when its captured
bytes match the oracle payload and the independent review links it to a
completed material question from an earlier turn. That initial question may
have an empty `decision_indexes` list: an access answer can trigger a later
lifecycle question without itself covering that hidden lifecycle decision. The
required post-answer question must separately be material and linked to its
frozen decision index, and it must occur in that exact required relevant answer
turn; a later unrelated controller turn cannot satisfy the requirement. A
completed relevant response with that question missing
is `FAIL`; an absent or incomplete required continuation keeps the top-level
`behavior_status` `UNAVAILABLE`, even when a separate supported violation makes
`semantic_status` `FAIL` and appears in `behavior_reasons`.

For the exact frozen task-08 case, the independent
`semantic_review.lifecycle_question_assessment` separately binds bounded
turn-2 material-question spans for link lifetime and owner revocation to
decision 0 and to the selected question reference. A compound question may
support both choices. Empty arrays are valid negative assessments and produce
separate `required_lifetime_question_missing` and
`required_revocation_question_missing` failures after a completed relevant
response. Missing, malformed, unbounded, unlinked, or stale-oracle assessment
evidence is `UNAVAILABLE`; incomplete responses retain the existing top-level
unavailable result.

For a valid started transcript prefix, a completed dependent plan or edit before
clarification remains in `behavior_reasons` even if the turn later times out. In
that case `semantic_status` can be `FAIL` while top-level `behavior_status` stays
`UNAVAILABLE` because required scenario coverage is incomplete. Consumers must
preserve both fields and the supported reasons; they must not drop those
violations or relabel the top-level result. A timeout with no supported
premature action stays `UNAVAILABLE` without inferring a missing question
failure. A file-change `item.started` event alone does not prove a write. Malformed
started change arrays or entries make that transcript prefix `UNAVAILABLE`;
valid starts remain available for ordering and supported partial-prefix
violations remain in the result. A successful file-change completion must have
an earlier matching `item.started` in the same turn with the same nonempty
native item ID and exact path. Failed terminals settle matching starts without
inferring writes. An unmatched completion, or any nonempty start left unmatched
when its turn completes, makes file-change ordering unavailable. Completion
time cannot stand in for a missing start. On a genuine incomplete prefix,
unmatched starts alone do not infer writes; earlier supported violations remain
in the result. The importer uses the matching start for earliest write ordering
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
Each native `todo_list` item ID must be a nonempty string with a same-turn
`item.started`, zero or more `item.updated` events, and one `item.completed`
event. Duplicate starts, unmatched updates or completions, and events after
completion make the transcript unavailable. A completed response turn must
close every started todo item; a genuine partial prefix may retain an open item
so supported pre-timeout plan violations remain visible.

Every terminal `command_execution`, including a nonzero exit, requires exactly
one `command_effect_assessments` entry keyed by turn and line. The independent
reviewer classifies actual effects as `read_only` (no affected paths),
`framework_state_only` (only safe `.codex/` paths), or `project_write` (at least
one safe project path, optionally with framework paths). This covers writes
restored before final capture; shell text and equal manifests do not establish
absence of writes. Project writes join the existing dependent-edit inventory
only with an unambiguous earlier same-turn `item.started` bearing the same
nonempty native item ID. The start determines order and terminal completion
confirms the effect. Missing, cross-turn or ambiguous starts produce
`command_write_order_unavailable`; completion time never substitutes for start
time. Explicit completion-only read-only and framework-state assessments remain
usable. Missing, duplicate, extra or invalid assessments are `UNAVAILABLE`.
An unfinished command confirms no write; a genuine partial prefix retains
earlier supported violations while its behavioral result remains unavailable.

Task-06 requires `missing_authority_assessment`, bound to its frozen oracle
case and SHA-256, decision 0 and the exact missing policy path. Independent
boolean claims cover all retained response messages: the assistant explained
that the controlling authority cannot be inspected, and it did not invent the
policy's contents. At least one bounded nonempty completed-message span and a
rationale bind these claims to retained evidence. Missing or malformed evidence
is `UNAVAILABLE`; either explicitly false claim yields `FAIL` only with complete
supported response evidence. Partial responses do not imply omitted explanations.
The existing attempted failed-read requirement remains independently binding.
Like task-05, these semantic judgments are assertions, not authenticated facts.
Legacy v1 envelopes remain parseable; missing current assertions cannot establish
behavioral PASS.

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
them to retained message bytes without authenticating the reviewer. The
assessment also requires successful exact-path reads of both frozen source
files whose captured output hashes match their `initial_workspace_sha256`
entries. Both reads must precede every cited explanation span, each
`decision.question_refs` entry, and every associated material question
assessment in the admitted initial response. Missing, search-only,
output-mismatched, or late reads keep behavior `UNAVAILABLE`; semantic negative
claims remain `FAIL` when the required reads and response evidence are
supported.

Every completed `agent_message` needs an explicit question assessment:
`material`, `non_material`, `punctuation_only`, or `not_a_question`. Only
`material` and `non_material` are question events; punctuation-only and
not-a-question results remain explicit but are not counted as questions. The
importer does not infer message intent from punctuation. For task-04, both
frozen-target reads must complete in the initial response before its first
completed assistant message and before the earliest observed project edit
across all retained response turns. Matched file-change starts determine edit
order, including stable or reverted paths; `.codex/` framework-state paths are
excluded. Message
planning and
material-question references point to completed agent-message events and
bounded, nonempty text spans. Agent-message carry references also need such a
span, so a carried answer and plan in one message retain their internal order;
overlapping carry and plan spans are `UNAVAILABLE`, while a plan before the
carried span is `FAIL`. Span offsets are zero-based UTF-16 code units into the
captured message text. Within one event, plan and question spans must not
overlap; a dependent plan must follow each linked material question and a
carried-forward answer. Native command and file-change carries, like native
todo-list plans, retain event-line ordering and have no text span. A completed
command carry requires an integer `exit_code` exactly equal to `0`; nulls,
booleans, strings, and other coercible values do not establish successful
carry evidence. Each native todo-list started, updated, or completed
observation retains its own ordering. A material question may have an empty
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
forced loading and cannot stand in for native activation. The importer compares
actor and reviewer IDs after trimming surrounding whitespace; IDs remain
case-sensitive. The semantic reviewer ID and independence role are assertions;
artifact hashing binds retained bytes but does not authenticate the reviewer or
prove that the review was independent.

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
