# Instruction Behavior Eval Fixtures

## Evaluating framework simplification

Keep task outcomes and supported consumer formats separate from conversational
presentation. Removing a compulsory empty section, idea quota, or unused
contract file intentionally retires that protocol assertion; it does not waive
material clarification, accurate evidence, authorization, or a retained
producer/consumer binding. Update only assertions for the approved removed
requirement and preserve the behavioral oracle. Existing structured cases still
exercise their explicitly requested interfaces.

For comparisons, use the same task, model/effort, tools, starting files, and
acceptance criteria for baseline and candidate. Check connected consumers and
wrong-outcome controls. Report actual loaded instructions, work, corrections,
and quality alongside size. Explicit skill loading, native activation, source
validation, and task success are distinct evidence. Missing traces and
unavailable platforms remain gaps.

The per-skill runner below validates fixtures and grades supplied captures; it
does not execute models. The paired Codex adapter is scoped to Workflow and
cannot establish results for every other skill. No fixed live-model pilot is a
prerequisite for a simplification PR. User feedback should name the skill,
source revision, request, expected outcome, and actual result; a material
regression calls for a focused reproduction and repair or rollback.

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
- spec obligations folded into the final acceptance review, not replaced by quality findings
- structured worker status packets from subagents
- subagent opt-out keeps review isolation
- Native Codex role constraints without extra runtime reinforcement
- Done Contract debate and Harness Recipe before Build
- trace/replay artifacts and typed artifact refs for harness recovery
- separate Code Reviewer and QA Evaluator evidence
- QA loop behavior with conditional domain rubrics
- pivot/restart decisions for stagnation and Code Writer blockers
- shared review/QA guard with productive ordinals beyond ten

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

## Writer selection outcome controls

The five `writer-routing-*` cases reuse the existing disposable workspace,
allowed-path, seed, fixed-output verifier and offline adversarial controls. Exact
pattern work selects mechanical; deceptively small semantic and grader changes
select intelligent. Stale eligibility preserves a prior actual partial edit and
stops dependent mutations; a broken baseline returns to the Orchestrator without
mandatory model switching. The stale case seeds the prior worker invocation's
partial output and checks its preservation plus truthful cumulative changed files.

Acceptance checks exact output bytes, immutable dependent/evidence files,
selection, status, actual cumulative changed files, next action, selected-check
identity, binding tuple and no-TDD state. The fixed output oracle belongs to the
adapter, independently of the model's receipt. Offline controls reject plausible
wrong output with convincing role prose, mechanical semantic routing, missing
eligibility evidence, omitted partial work, continued dependent mutation, false
success, fabricated checks and automatic cascade. These are deterministic
contract/adapter checks, not native activation or model quality proof. Shared
selection remains an instruction contract with no executable routing controller.

For skill-only response grading, `actual_output`, `dependent_output`, `status`,
`failure_class` and `next_action` are bounded eval-only scalar projections; the
binding tuple remains under canonical `implementation_steps[0]`; coordinator execution is separate from worker status.

Claude and Codex intelligent/mechanical definitions and standalone deprecated code-writer retain the
logical CodeWriter verification, TDD, status and independent review contract.
Claude uses native Opus for intelligent-writer and Sonnet for fully specified mechanical-writer, retaining explicit deprecated code-writer intelligent compatibility. Gemini supported native/default tiers remain intact. Mechanical evidence must fix tests and implementation, including cases, expected values/oracles and assertion patterns.

Workflow v14 adds writer worker_stage test_authoring before independent RED, production after matching current RED, and refactor after current GREEN. Stage-only DONE cannot complete Build; Builder/Tester authors no tests or fixtures/snapshots/configuration. The focused ownership suite mutates the structured stage contract and checks provider profiles; it does not claim native enforcement or model-quality evidence.
Metadata and phrase/schema matches alone cannot prove task success. Source
migration, live installation and paid comparisons have separate authorization;
total cost/value claims require accepted outcomes, correction/review effort,
escalations, elapsed time and available whole-workflow usage. Missing telemetry
stays unknown; the bounded synthetic pilot does not establish production savings.


## Canonical packet admission controls

The closed `assistant-workflow.packet_admission_v15` semantic validator reuses
`skills/assistant-workflow/scripts/task-packet-admission.py`, the same install-portable
pure helper used at Plan/resume/dispatch/verification/completion. Closed grading
passes the inventory-selected `SKILL.md` separately from fixture and response
content. The adapter authenticates the selected Workflow under its physical
runner root's `skills` tree, or the current profile's `.agents/skills` only when
the runner is that profile's configured `CODEX_HOME` or default `.codex`. Profile
resolution uses nonblank `USERPROFILE`, then `HOME`, matching the PowerShell
installer. It imports only that selected owner's contained regular helper;
symlink escapes, arbitrary fixture adjacency, lookalike profile paths, missing
helpers and unresolved authority fail without alternate/stale-sibling fallback.
This does not expand default inventory or authorize fixture-selected code.
The existing two verification producer aliases and seven Workflow review aliases
load their unchanged safe-YAML schemas from the same recognized skills owner as
the actual consumer contracts. Split consumers cannot fall back to stale sibling
schemas when a companion is missing or escapes its owner. Existing temporary
custom contract-data fixtures retain runner-owned co-located producer schemas;
no new producer/alias or executable authority comes from fixture content.

Three fixed
workflow cases supply independent approval, requirement, obligation, input,
evidence and workspace authority. Candidate answers cannot rewrite those facts;
accepted answers include the exact admitted canonical Plan and deep projection,
and correct rejection of unsafe dependency facts passes. Vocabulary-only readiness
answers fail. Existing task-packet controls exercise current evidence, all five
prerequisite states, isolation, immutable projections, exact command/cwd and
non-command/TDD identity, caller-resolved test applicability, invalidation/recovery,
completion and conservative v12
one-to-one/one-to-many obligation conservation. Test-required applicability keeps
`authored|reuse` assertion provenance and native author equality. A current
independently resolved no-tests assessment permits an omitted `tests` object,
never invented reused tests. Both branches retain current identity, lane,
native writer, self-check, acceptance and all selected/binding result guards;
missing/unresolved/stale applicability blocks and active TDD requires tests.

These controls establish consistency of stated admission decisions. They do not
prove native worker behavior, isolation/overlap telemetry, implicit activation,
model quality or total-cost benefit. Missing native capability stays unavailable.
Default installation/promotion and a comparative pilot require separate approval
of exact runtime/model, call/elapsed/token limits, stop conditions and benefit
threshold. No native/model calls or real-user installation are part of these checks.


The shared progress guard is exercised by the existing packet admission control
module against fixed independent synthetic observations, including productive
fourth/later actions, three unproductive cycles, oscillation with fresh rechecks,
material unblock, replay, compaction and later blockers. These controls establish
bounded state/admission correctness. They do not measure native interruptions,
model quality, time or cost. The framework instruction cases retain matched
productive-later-round and genuine-stall scenarios; an optional authorized
matched native evaluation must freeze outcome oracles, report correctness,
avoidable user interruptions and limits before claiming reduced friction.
No such native pilot is implied by source or installer checks.
