# Skill Contract Design Guide

docs/skill-contract-design-guide.md is canonical. The skill-local copy is
generated for installed-skill portability; refresh it with
`tools/skills/sync-skill-contract-guide.sh --apply` and verify it with `--check`.

## Start with instructions

A skill is instructions for a concrete job. A valid `SKILL.md` with precise
routing and sufficient instructions can be the whole skill. Describe the outcome,
necessary steps, constraints, output, and when to ask or stop. Use headings only
when they help. Move detailed examples to references loaded when needed.

For new or materially changed capability guidance that depends on expert
judgment, derive the consequential cue-to-method decisions from representative
expert cases or an authoritative method. Connect raw inputs, expected artifacts,
applicability limits, and an independent wrong-outcome check to existing
success criteria. Keep unsupported model proposals provisional; more procedure
or expert vocabulary does not establish improvement. Mechanical and
preference-only changes do not require this process. The creator's
`references/expert-method-design.md` contains the conditional detail; reuse
existing design and verification outputs rather than adding an authoring report.

Before adding a file, field, phase, controller, or dependency, name its consumer
and the failure it prevents. Reuse an existing producer format or helper. Do not
create contracts to satisfy a category, a field count, or a checklist. Utility,
Analysis, and Process describe the work; they do not require two, three, or four
contract files. Do not introduce an opt-in profile or metadata registry.

Keep a contract when a tool validates it, another agent consumes its exact shape,
or persisted state needs reconciliation. Preserve those interfaces, their
consumers, and their compatibility rules. Human-only summaries can stay prose.
An explicit user request for a schema is also a reason to author one.

Ask only when missing information materially changes correctness, scope, public
contract, security, data shape, rollout, or verification, cannot be discovered
from supplied context or source, and has no safe default. Ask every remaining
material question, grouped with its impact and risk if guessed. Otherwise proceed
with stated assumptions; there is no question quota.

## Routing and metadata

Required discovery fields are `name` and a non-empty `description`. Names use
1–64 ASCII lowercase letters, digits, and single hyphens, with no leading,
trailing, or repeated hyphen. Descriptions use 1–1024 characters; optional
compatibility uses 1–500 characters. Preserve supported metadata and invocation
policy unless explicitly changed.

Repository `requires` is optional and declares validated hard dependencies only.
Use ordered plain block-sequence items and omit the key when empty. On update,
omitted dependencies preserve canonical `requires`; explicit dependencies,
including an empty list, replace or remove them. Do not add dependencies merely
because a skill can consult another skill. `allowed-tools` is experimental;
distinguish host support from portable behavior. Top-level `effort` and `triggers`
are deprecated and rejected. Do not weaken permissions or host safety settings.

Activation examples shape descriptions and evals; they are not header metadata.
For first-class schema `2.0` `evals/cases.json`, `activation_cases` contains exact
`{user_request, should_activate}` objects: two normalized-distinct positives and
one normalized-disjoint nearby negative. Schema `1.0` custom/local fixtures may
omit them; validate them when present and reject other schema versions. Derive
adequate examples from an existing description and evals before asking for gaps.

## Optional contracts

Supplied contracts remain authoritative at their actual boundary. Load only the
needed input, output, phase, or handoff; a shorter loading path never relaxes its
rules. Preserve producer outputs unchanged when carrying them to another skill.
In particular, use `assistant-verification/contracts/output.yaml` for an actual
verification selection or evidence assessment; do not invent a local replacement
or require that object for every human-only assessment. Preserve its independent
method, scope, TDD choice, literal commands, and source-bound obligations.
Active TDD needs the selected meaningful RED before production edits.

Use existing YAML shapes for actual consumers:

```yaml
schema_version: "1.0"
contract: input  # input | output | phase-gates | handoffs
skill: assistant-example

fields:  # output contracts use artifacts
  - name: request
    type: string
    required: true
    description: "The requested operation"
    validation: "Non-empty request within the supported scope"
    on_missing: ask
    ask_prompt: "Which operation should I perform?"
```

Field types: `string`, `int`, `boolean`, `enum`, `string[]`, `object`, `object[]`, `float`, `file`, `jsonl_line`

- Required input fields declare actionable `on_missing`: `ask`, `infer`, `skip`,
  `fail`, or `re-dispatch`; explain an inference or safe default.
- Required output artifacts declare validation or actionable failure recovery;
  author explicit `on_fail` when recovery matters to the consumer.
- Enums declare bounded `enum_values`. Use `object_fields` for nested fields.
- Use `required: conditional` with a plain-English `condition` for fields needed
  only in one operation. Do not force irrelevant artifacts into read-only work.
- Keep descriptions, validation predicates, and corrective actions concrete.
  Add realistic examples when ambiguity remains; no fixed example count applies.
- A gate has a named `phase`, optional condition, binary `entry_assertions` or
  `exit_assertions`, and actionable `on_fail`. Check entry assertions before
  mutation or dispatch. Add invariants only for real cross-phase constraints.
- A handoff names `from`, `to`, `phase`, `context_fields`, and `return_fields`.
  The producer's return fields must satisfy the consumer's context fields.
  Validate a failed return before continuing; retry only within approved bounds.

Changes to public or serialized contracts need a compatibility decision. Adding
optional fields can preserve a major version; removing or weakening required
fields needs a major `schema_version` bump, a migration note in `SKILL.md`, and
updated consumers, evals, and mirrors. Deleting an unconsumed schema does not
justify deleting the safety or behavior it described from the instructions.

### Indexes

`contracts/index.yaml` is optional. Keep it only when progressive loading is
useful to a real consumer. When present, declare `schema_version`,
`contract: index`, `skill`, and the actual `authoritative_contracts`. Include
supplied and explicitly referenced canonical files, rather than category quotas.
Use selector-bounded `load_sets` with positive `budget_words`. Select entry
inputs, current gates, handoffs, or completion fields by explicit keys and names.
Both missing and invalid selectors use `load_full_authoritative_file`; never
silently skip the canonical file. Paths stay inside the skill root, including
through symlinks. Declared files, selector addresses, references, and word budgets
must resolve. Static closure reports exclude runtime context.

### Semantic boundaries and workflow safety

Use named semantic types when values have domain, public-contract, lifecycle,
unit, validation, ownership, security, or extension meaning. YAML field types are
transport primitives, not permission to erase those meanings. Primitive
representations are reasonable for local temporary values, wire/storage or
foreign/framework boundaries, or values with no domain semantics. Record the
exception, conversion point, and validation. Prefer cohesive request/result
types to generic property bags; do not invent wrappers without a consumer.

When architecture decisions are material, preserve the applicable decision
record: facts and assumptions, ownership, control and early exit, resource
disposal and bounds, extension registration, representative producer-consumer
path, compatibility, and falsifiable quality checks. Ordinary local work needs
no architecture ceremony. Do not claim memory, performance, or extensibility
benefits without measurements or a clearly stated unknown.

Existing-system preparation distinguishes requirements, design evidence, current
implementation, observable effects, tests, conflicts, and evidence gaps. Missing
inspection is an evidence gap, not a Product decision. Preserve tested behavior
only within the actor, data, and authorization context supported by the evidence.
Persisted task state must be reconciled with current user intent and repository
or artifact identity before trusting its next action. Keep unanswered material
choices and provisional recommendations out of applied defaults or confirmed
criteria in responses and task state. Source-backed technical defaults remain
automatic.

For shared impacts, preserve source identity and gaps. Mutation requires current
valid pre-build evidence; completion requires verification and review evidence.
Missing loaded-path runtimes block. Fanout alone does not escalate architecture,
QA, or execution lane. Keep review and QA responsibilities distinct. Metrics are
optional, non-blocking observability; they never determine completion.

For actual long-running controllers, reuse the owning workflow's Done Contract,
Harness Recipe, typed references, trace/replay, and pivot/restart formats when
needed. Load `references/harness-patterns.md` in the creator for those patterns.
Do not add this machinery to single-pass work. Review/QA/fix loops remain bounded
by the common task-level guard: its source-bound effective window (default three consecutive unproductive semantic cycles),
with no cumulative attempt or round ceiling. Preserve explicit user/resource
bounds, material-change approval and actual blocker reasons. Material scope,
access, cost, risk or acceptance changes require an explicit pivot or restart decision
under existing authority.

## Validation and evidence

Run focused checks first, then the aggregate checks appropriate to changed
consumers. Source validation accepts instruction-only skills; supplied contracts,
explicit local contract references, and declared indexes still validate. Missing
literal local `contracts/*.yaml` references fail. Cross-skill producer references
are not local file declarations. This is not a general Markdown link checker.

```bash
tools/skills/validate-skills.sh
tools/skills/validate-skills.sh --skill assistant-thinking
tools/skills/validate-skills.sh --include-local
tools/evals/run-skill-evals.sh --validate-fixture
```

Source checks cover metadata, dependencies, contract headers, required-field
recovery, enum declarations, field types, passive YAML, and indexes. They do not
prove execution adherence, host activation, or model quality. Installed path
substitution remains covered by installer tests.

Keep structural validation, explicit invocation, implicit native selection, and
post-activation behavior separate. Native activation observations must bind to
the actual host, skill inventory, source identity, requests, and available trace;
unavailable telemetry stays unavailable. `run-skill-evals.sh --activation-results FILE` checks captured selections without invoking a custom router or API.

Local substring grading is heuristic. Structured assertions check bounded JSON
shapes using the eval runner's fixed operators, never arbitrary fixture code.
Before authoring `machine_expectations.structured_json_assertions`, read
`../../docs/evals/README.md#per-skill-eval-fixtures`, resolved from the directory
containing the active creator `SKILL.md`, for the exact operator list, bounds,
and null/absence rules. Accepted declaration keys are defined by installed
`../../tools/evals/lib/skill-eval-fixtures.sh`; validate authored fixtures with
`run-skill-evals.sh --validate-fixture`. For Windows Codex shared skills, resolve
these docs/tools under configured `CODEX_HOME` (default `~/.codex`), not `.agents`;
the installer reports the actual tools location.
Creator semantic fixtures bind operation claims to independent run capture and
actual artifact bytes; see `references/behavioral-evaluation.md`. They preserve
canonical producer envelopes for that consumer without making them a requirement
for every user-facing reply. Comparative claims need matched conditions and
held-out acceptance evidence. A source fetch does not establish adoption, native
activation, behavioral improvement, or freshness beyond the captured evidence.
