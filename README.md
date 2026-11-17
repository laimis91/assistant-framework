# Assistant Framework

A Personal AI Assistant framework for developers. 16 first-class `assistant-*` skills: structured workflow, clarification, conditional TDD, debugging, thinking tools with option generation, research, disposable feasibility spikes, security analysis, advisory triage, documentation generation, codebase onboarding, CI and test-protection audit, review automation, skill creation, evidence-based verification selection and assessment, and exploratory UI QA.

## Documentation

Start with the [documentation map](docs/README.md) for task-specific guides, [durable specifications](docs/specs/README.md), evaluation instructions and historical context. Update the affected spec and guide alongside relevant features and fixes; development plans and execution state stay local and Git-ignored.

## What it does

1. **Structured Workflow** — adaptive Discover > optional Plan > Build > Review > Document flow with bounded repair and evidence-gated handoff
2. **Clarification** — Converts ambiguous, fragmented, or multi-intent prompts into an executable brief
3. **TDD** — Red-Green-Refactor with verification gates at each transition, when requested, required by project policy, or selected for checks
4. **Debugging** — Evidence-first root-cause workflow: reproduce, hypothesize, isolate, fix, verify
5. **Thinking Tools** — On-demand structured reasoning (first principles, multi-perspective debate, stress testing, etc.) and option generation: quick improvement scans and explicit brainstorms with qualitative ranking
6. **Research Tools** — Source-backed research with verified links, claim-specific evidence quality, and explicit conflicts and gaps
7. **Security Analysis** — STRIDE threat modeling, OWASP code review, CVE dependency audit, attack surface mapping, agent/installer/release boundary companions, and advisory triage with a shipped-release close bar
8. **Documentation** — Creates or updates API docs, architecture docs, README, changelogs, migration guides and code explanations written into docs or comments, from source truth
9. **Onboarding** — Systematic codebase learning: maps structure, identifies patterns, and reports actionable project orientation
10. **Review Automation** — Evidence-bounded review/fix/re-review with fresh independent passes; further rounds need new evidence, with no cumulative round ceiling
11. **Skill Creation** — Creates focused instructions, with schemas when a real consumer needs them
12. **Verification** — Selects proportionate checks and techniques, applies TDD only when appropriate, and assesses whether evidence supports the claim.
13. **Feasibility Spike** — Answers one feasibility question with a small disposable experiment and a control, returning validated, partial or invalidated without authorizing production changes
14. **Exploratory UI QA** — Explores a running UI through the available browser tools and reports reproducible issues with severity and tested, not tested and blocked coverage; acceptance stays with the QA Evaluator

## Install from the marketplace

This repository is a plugin marketplace for Claude Code and Codex. It ships one plugin, `assistant-framework`, with every skill in `skills/`.

**Claude Code** (CLI and the desktop app's Code tab):

```bash
claude plugin marketplace add laimis91/assistant-framework
```

```bash
claude plugin install assistant-framework@assistant-framework
```

Inside a session the same commands are `/plugin marketplace add laimis91/assistant-framework` and `/plugin install assistant-framework@assistant-framework`. Auto-update is off for third-party marketplaces: turn it on under **Marketplaces** in `/plugin`, or update by hand with `claude plugin update assistant-framework@assistant-framework`. Plugin skills are namespaced, so `assistant-workflow` runs as `/assistant-framework:assistant-workflow`; skills still activate from their descriptions.

**Codex** (CLI and app):

```bash
codex plugin marketplace add laimis91/assistant-framework
```

Then install `assistant-framework` from the Plugins Directory in the Codex app, or with the CLI. Refresh with `codex plugin marketplace upgrade`.

**One copy of each skill.** Remove a manual install (below) before installing the plugin, so the same skill is not loaded twice. If you also upload the chat skills to your Claude account, see [Claude chat skills](#claude-chat-skills).

**Agents are optional.** The plugin does not ship the subagent definitions in `agents/`. Without them, Workflow builds hands-on and gives each formal reviewer the role prompt shipped in the owning skill (`references/roles/`). You can copy `agents/claude/*.md` into `~/.claude/agents/` or `agents/codex/*.toml` into `~/.codex/agents/`, or use your own subagent setup.

**Releases.** The plugin version comes from `version.txt`. Users get a new copy only when that version changes, so a release bumps `version.txt` and runs `tools/skills/sync-plugin.py --apply`. The editable source stays `skills/`; the contract suites fail when `plugins/assistant-framework/` drifts from it.

### Claude chat skills

Three skills work in Claude chat on the web, desktop and mobile apps, with no repository and no subagents: `assistant-research`, `assistant-thinking` and `assistant-clarify`. Build their upload ZIPs:

```bash
python3 tools/skills/build-chat-zips.py
```

Upload each ZIP from `dist/chat-skills/` under **Customize → Skills → + → Create skill → Upload a skill**, with code execution turned on. Uploads are manual, so repeat them after each release. Mobile availability is not yet confirmed.

Skills on your account also sync into Claude Code (v2.1.273 or later). With the plugin installed too, Claude Code then has two copies of these three skills. Keep one: delete the account copy in Customize → Skills if you use Claude Code mainly, at the cost of losing it in chat.

### Optional instruction block

The skills work without any instruction file. To apply the framework's routing and working rules before a skill loads, paste the block from [docs/instruction-block.md](docs/instruction-block.md) into `~/.claude/CLAUDE.md` or a project's `CLAUDE.md` (Claude Code), or `~/.codex/AGENTS.md` or a project's `AGENTS.md` (Codex). Nothing writes it for you.

## Moving from a manual install

The manual installers (`install.sh`, `install.ps1`), the uninstallers and the `assistant-cleanup` skill were retired on 2026-11-17; the marketplace is the only supported channel. Gemini CLI and the Codex `codex-rules/` execution rules are no longer supported. Remove an earlier manual install by hand, in this order, before installing the plugin:

1. Remove Assistant Framework hook registrations: entries whose command points into `~/.claude/hooks/assistant/` in `~/.claude/settings.json`, and into `~/.codex/hooks/assistant/` in `~/.codex/hooks.json`.
2. Delete the framework skills and hook shims, `~/.claude/skills/assistant-*` and `~/.claude/hooks/assistant/`, and the framework's own entries in the shared folders, leaving anything else there in place:
   - in `~/.claude/tools/`: `evals/`, `patterns/`, `progress/`, `skills/`, `framework-ownership/` and `smoke-test-codex-agents.sh`, plus, from older releases, `change-impact/`, `cognitive-complexity/`, `memory-graph/`, `cleanup-memory-graph.sh`, `cleanup-memory-graph.ps1` and `plugins/sync-plugin-skills.sh`;
   - in `~/.claude/docs/evals/`: the entries that this repository's `docs/evals/` folder holds.

   Do the same under `~/.codex/`. On Windows Codex, also check `~/.agents/skills/assistant-*` and `~/.agents/tools/change-impact/` and `progress/`.
3. Remove the block between `<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_START -->` and `<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_END -->` in `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`, or replace it with the [optional instruction block](#optional-instruction-block).
4. Delete installed framework agents (`~/.claude/agents/*.md`, `~/.codex/agents/*.toml` with the names in `agents/`) unless you keep them deliberately, and `~/.codex/rules/workflow.rules`.

For Gemini CLI, delete `~/.gemini/skills/assistant-*` and the same framework entries in `~/.gemini/tools/` as in step 2.

## Skills

Only tracked `assistant-*` directories are first-class release skills.

### assistant-workflow
Core development pipeline: idea-to-action decomposition, discover, proportional planning, build and verification, independent review, bounded repair, and evidence-backed documentation.

| Pattern | Use | Combine with |
|---|---|---|
| Linear | One focused change with dependent steps; scale planning and review to risk. | Goal-driven checks and fresh review; a low-risk local change may use the direct lightweight path. |
| Skill-driven | A recurring task has a matching installed skill. | Any other pattern; the skill supplies the method. |
| Parallel | Independent work can progress together. Source-changing packets remain sequential in a shared or unknown workspace; overlap requires runtime-proven isolated workspaces. | Goal-driven integration: dependents wait for VERIFIED prerequisites, then full-scope validation precedes fresh review; due integration checks remain mandatory for one or multiple canonical packets. |
| Goal-driven | Acceptance checks must remain the completion condition through repair. | Linear, skill-driven, or parallel execution; bounded repair escalates instead of claiming false completion. |

For dependency-shaped uncertainty, the workflow defaults to
`uncertainty_shape=bounded`: size alone does not activate progressive Discover.
It enters that substate only when a predecessor decision must unlock an
outcome-shaping unknown. `assistant-clarify` owns prompt-level ambiguity, so
precise requests stay in the ordinary flow without duplicate ceremony.
Progressive Discover is a no-execution boundary; any mutation must use a
separate approved workflow and returned evidence. Once the route is clear, it
returns through bounded Discover to the normal Requirement Acceptance Map and
phase gates.

When a task changes a meaningful boundary, data lifecycle, public contract,
resource target, extension seam, or has genuinely competing designs, workflow
creates a conditional **Architecture Decision Pack**. It is source-backed and
freshness-checked, captures semantic interface types and justified primitive
exceptions, checks control/early exit, ownership/disposal, bounded resources,
extension registration, and a representative path before premature abstraction,
makes quality claims falsifiable with workload/budget/measurement, and travels
through the plan, task handoff, and independent review. It does not
add a permanent architect agent or force architecture ceremony onto local work.

### Shared-change impact

Behavior-bearing work records a compact local/shared/unresolved assessment before
choosing verification scope. Triggered shared-impact work records
assistant-review's expanded-work checklist (no script or runtime) and carries the
same artifact identity through workflow, debugging, and review. Discovery may
report gaps; completion also needs actual current verification and the existing
assistant-review manifest/coverage result, and the fresh independent reviewer
checks the checklist result against the diff. The checklist covers supplied
bounded evidence, not a universal runtime dependency graph. Shared fanout alone
does not add Architecture Decision Pack, strict-lane, or QA requirements.

For multi-slice work, Assistant Workflow uses descriptive outcome-oriented
packet identifiers rather than ordinal-only labels, explicit dependencies, and
optional native subagents only for independent packets.

The architecture is an adaptive loop implemented through native skill routing;
there is no installed lifecycle engine. Its conceptual states map to the public
workflow like this:

| Conceptual state | Public phase | Observable responsibility |
|---|---|---|
| ORIENT, RESOLVE | Discover | Inspect the request, repository, policy, and current task state; apply and record deterministic safe defaults, and ask only material questions with no safe default. |
| PLAN? | Optional Plan | Select `plan_mode`: `none`, `inline`, or `approval_required`. |
| EXECUTE SLICE, OBSERVE | Build | Implement one coherent slice, run its explicit verification command, and record evidence before marking it verified. |
| REVIEW | Review | Independently check requirements, regressions, quality, security, and QA evidence. |
| REPAIR | Build or Review | Build repair handles implementation or verification failures under the shared semantic progress guard, followed by fresh Review. The assistant-review Review-fix loop handles review findings inside Review with revalidation and a fresh review result. |
| HANDOFF | Document | Compose `final_handoff` and developer-facing manual test guidance only after acceptance evidence exists. |

For `execution_intent != prepare_only`, `plan_mode=none` is limited to small,
local, reversible, high-confidence work with known scope. `inline` records a
short plan without an approval wait. For `prepare_only` at any size, `plan_mode=none` is the default; optional readiness planning retains evidence and next-state context only, without executable packets or downstream Pack handoffs.
For prepare_only at any size, default to `plan_mode=none` unless optional readiness planning is explicitly requested.
For `execution_intent != prepare_only`, `approval_required` applies to medium-or-larger work and to risk, policy, or
public-impact changes. An explicitly requested `prepare_only` readiness Plan is always inline and no-wait. Build owns implementation, tests, verification, and
the [common task-level stagnation guard](tools/progress/operating-guidance.md),
with completed evidence retained before later blockers.
Build repair is implementation/verification-failure recovery. Review-fix work
for review findings stays within the bounded `assistant-review` loop and records
its own revalidation before a fresh review result.
Review owns independent acceptance evidence and fresh post-repair assessment;
it does not create the handoff. Document is the sole owner of `final_handoff`.
Integration fails closed when required validation is absent unless an explicit
skip reason is recorded.

Workflow consumes the canonical assistant-review Reviewer/QAEvaluator schemas
through validated result references; it does not restate those worker packets.
Reviewers must return a non-empty `reviewed_scope` alongside findings and
evidence, so a partial or differently scoped review cannot silently satisfy the
workflow's acceptance gate. The final handoff summarizes requirement coverage,
important changed areas, architecture decisions, verification evidence, manual
test steps, deviations, and remaining risks without claiming checks that did
not run.

Each canonical executable packet carries its exact selected verification procedure
(literal command argv/cwd or non-command method) and evidence requirement. Dependent slices wait for verified prerequisites. Read-only analysis
may run in parallel for independent packets with non-overlapping ownership.
Source-changing packets in a shared or unknown workspace remain sequential;
parallel source-changing packets require runtime proof of isolated workspaces.
Canonical v16 Plans use one implementation_steps collection with descriptive packet_id values. Coherent work defaults to one packet; additional boundaries require acceptance, ownership/context, prerequisite, recovery/rollout or binding protocol purpose. Stored packets reference one unchanged specialist decision and carry coordinator execution evidence. Deep worker projections cannot redefine approved work. Build runs directly in the main actor by default; native delegation is optional and chosen only for a concrete benefit. All due integrated selected/binding checks precede a newly created, independent reviewer for one or multiple packets; conditional QA/harness and exact final snapshot binding remain. The pure shipped admission helper checks current approval, graph, evidence, isolation and source-verified v12/v13/v14/v15 migration authority. Local checks do not establish native runtime consumption or efficiency; default promotion and a bounded comparative pilot remain separately gated.

For compression-safe work, the orchestrator keeps concise, root-scoped task and
session state under `.codex/`. Resume reconciles that journal with the newest
user request and current repository evidence before continuing; stale state
never overrides either source.

Loop readiness is conditional. Ordinary day-to-day development, such as taking a work item, prompting once, waiting for implementation, and manually testing the result, stays in the normal workflow. Add `loop_readiness_assessment` only before an explicit repeat, optimization, or experiment loop outside the standard phase gates. Examples include "keep fixing build/test failures until green", "iterate on this interface until the manual checklist passes", or "optimize until a measured target is reached". A loop plan must name the verifier, stop condition, the shared progress guard, optional source-backed iteration/resource limits, retry/empty-result handling, tool-error handling, low-confidence escalation, rollback/exit action, and harness routing. Loop readiness alone does not require Done Contract, Harness Recipe, Trace Ledger, Replay Packet, Artifact Reference Ledger, or QA evaluation unless harness or QA criteria independently apply.

Triggers on: build, implement, fix, refactor, plan, create, idea

### assistant-clarify
Resolves ambiguous or multi-intent requests using available context and material questions. Carries answers forward and shows a structured brief when useful.

Triggers on: messy prompt, unclear prompt, figure out what I mean, help me structure this

### assistant-tdd
Test-Driven Development when requested, required by project policy, or selected for checks by the verification decision: Red-Green-Refactor cycle with verification gates. Bug fix pattern (reproduce → fix → protect). Integrates with workflow's build loop and review cycle.

Triggers on: TDD, tests first, test-driven, write the test first, red green refactor, or an intersecting workflow-selected TDD check

### assistant-debugging
Evidence-first debugging: reproduce or bound the failure, rank competing hypotheses, isolate root cause, apply the smallest durable fix, and verify with original reproduction plus regression checks.

Triggers on: debug, root cause, investigate failure, flaky test, failing test, production issue

### assistant-thinking
Six structured reasoning tools: clarify, perspectives, stress-test, deep-think, hypothesize, creative. The creative method also generates and ranks options: a light mode compares a few useful alternatives quickly for an improvement scan, and a deep mode expands and refines alternatives when an explicit brainstorm or the decision needs it. It reads only the local context needed to shape useful options.

Triggers on: architecture decisions, complex trade-offs, stress tests, debate, first principles, hypotheses, brainstorm, feature ideas, what if, how could we, alternatives, or what-else improvement scans

### assistant-spike
Answers one observable feasibility question with the smallest disposable probe outside tracked files. It checks source and docs first, asks once for a probe plan that binds a fresh directory and exact commands (installs, network calls, credentials and real data still ask separately), runs the decisive case plus a control, and returns validated, partial or invalidated with evidence, limits and the consequence for a real build. Its handoff to Workflow authorizes no production change.

Triggers on: spike, try out, prove whether an approach can work, feasibility experiments that only execution can settle

### assistant-research
Source-backed research with verified links, claim-specific evidence quality, and explicit conflicts and gaps. Selected five-lens decision briefings retain five independent lens handoffs and separate peer review.

Triggers on: research, topic investigation, current evidence, source-backed comparisons

### assistant-security
STRIDE threat model, OWASP code review, CVE dependency audit, attack surface mapping. Three companions load only when the target has that surface: agent and tool authority, installer and filesystem ownership, and dependency and release provenance. Each reported item is either confirmed (with severity) or listed under Needs validation with its blocking fact and a safe owner check, and a full audit states assessed, blocked and excluded surfaces.

Triggers on: security, threat model, audit, vulnerability, OWASP

### assistant-advisory-triage
Decides what to do with an incoming security advisory or vulnerability report: `close`, `keep open` or `keep open but narrow`. Reads the trust model first, proves whether the latest shipped release is affected or contains the fix (fixed on main alone never closes), checks for duplicates, keeps hardening separate, and drafts maintainer text without posting anything unless the user authorizes that action.

Triggers on: GHSA, CVE report, advisory triage, vulnerability report disposition

### assistant-review
Evidence-bounded code review: trivial/small light review uses one fresh pass plus one fresh re-review after a fix, and plan review uses one fresh pass; medium+ audits use one frozen multi-pass batch at the canonical count of two independent narrow passes, plus integration for medium scope and architecture for large scope. Review-fix work normally uses an initial batch, authorized productive correction, and one fresh post-fix re-review batch. Additional rounds require new evidence and a recorded reason, under the same shared task guard. Prioritizes concrete bugs, regressions, risks, and missing tests.

Triggers on: review, fresh review, code review, review this, check the code

### assistant-docs
Documentation generation and maintenance: API docs, architecture overview, README, changelog, migration guide, and code explanations written into docs or comments. A plain chat question such as "explain this function" is answered directly. Checks source accuracy within the requested scope. A request for a diagram of existing code also routes here: the diagram draws only source-backed current elements, labels proposed ones, and states what render check actually ran. Concept sketches with no source use the general model. Prose edits follow an editing checklist that preserves meaning, technical terms and the existing voice.

Triggers on: document, write docs, update readme, changelog, API docs, architecture doc, diagram of existing code

### assistant-skill-creator
Creates, updates, or assesses concise skills. Adds contracts when an actual consumer, persisted state, validator, or user-requested schema needs a defined format.

Triggers on: create skill, new skill, add contracts, skill contracts, scaffold skill

### assistant-onboard
Maps a codebase to the requested depth: entry points, responsibilities, commands, conventions, relevant risks, and coverage gaps. An optional size/language inventory uses `git ls-files` and counters already installed, and reports counts as orientation facts, not quality. Persists orientation only when authorized.

Triggers on: learn this codebase, onboard, get familiar with, map this project

### assistant-ci-audit
Audits CI/test discovery, fixture fidelity, child/report/final-gate failures and
maintenance value. Inspection is the default; finite authorized local diagnostics
may use disposable controlled probes. Findings recommend protection-preserving
changes and measured comparisons; they grant no repair or dispatch authority.
Use debugging for one failing test and verification for selecting checks.

### assistant-ui-qa
Explores a running web or app UI in a local or named test environment through whatever browser runtime the session has. It exercises valid, invalid and empty states and navigation in each in-scope flow, reads console and network diagnostics at loads and significant interactions, and reports reproducible issues with severity and category plus tested, not tested and blocked coverage. Production targets stay off limits, real credentials are never entered, and irreversible actions wait for approval. It gives no acceptance verdict or score: inside a required-QA Workflow task the report is `verification_evidence` for the QA Evaluator, and it does not satisfy required manual verification. Fixes go through workflow, with debugging first when the cause is unknown.

Triggers on: test this app, dogfood the signup flow, click through the settings page and report bugs, exploratory UI testing

### assistant-verification
Selects proportional verification scope, methods, and TDD applicability, then assesses observed evidence and limitations. It guides verification without running checks. Workflow consumers retain canonical typed decisions; human-only assessments can use concise prose.

Triggers on: verify a change, choose tests, test strategy, assess evidence, are these checks enough

## Tools

### Skill Validator

Source validator for first-class skill metadata and contract structure:

Requires Ruby with Psych/YAML support (`ruby -ryaml`) for contract parsing.
The skill-eval runner requires Ruby with JSON and Psych/YAML support
(`ruby -rjson -ryaml`); per-skill response grading additionally requires
BigDecimal (`ruby -rbigdecimal`).

```bash
tools/skills/validate-skills.sh
```

By default it validates only the release inventory: tracked `skills/assistant-*/SKILL.md` skills and their `contracts/*.yaml` files.

Target a specific skill by name, directory, or `SKILL.md` path:

```bash
tools/skills/validate-skills.sh --skill assistant-thinking
tools/skills/validate-skills.sh --skill skills/assistant-thinking
tools/skills/validate-skills.sh --skill skills/assistant-thinking/SKILL.md
```

Use `--include-local` only when you explicitly want to validate every `skills/*/SKILL.md`, including local-only skill experiments:

```bash
tools/skills/validate-skills.sh --include-local
tools/skills/validate-skills.sh --include-local --list
```

### Skill Evals

Provider-neutral per-skill eval fixtures live at `skills/<skill>/evals/cases.json`
and run locally through `tools/evals/run-skill-evals.sh`:

```bash
tools/evals/run-skill-evals.sh --validate-fixture
tools/evals/run-skill-evals.sh --list
tools/evals/run-skill-evals.sh --emit-prompts /tmp/skill-eval-prompts
tools/evals/run-skill-evals.sh --responses /tmp/skill-eval-responses
tools/evals/run-skill-evals.sh --activation-results /tmp/skill-activation-results.json
```

The default eval inventory is 16 first-class `assistant-*` skills with fixtures.
Canonical first-class fixtures use schema `2.0` and include top-level
`activation_cases`: exact `{user_request, should_activate}` objects with at
least two normalized-distinct positive requests and one normalized-disjoint
nearby negative. Schema `1.0` custom/local fixtures may omit this field; when
they include it, the same shape is validated. Other schema versions are
rejected. Activation cases shape discovery
coverage only unless compared against externally observed native selections with
`--activation-results`; they are separate from response-graded `.cases` and
never SKILL.md metadata. The runner does not invoke native routing itself.
Local-only skill experiments remain opt-in through `--include-local`. Local grading is heuristic
substring-based checking, useful as a Level 4 conformance proxy but not a
replacement for semantic review. Detailed usage is in `docs/evals/README.md`.

### Optional Design-Pattern Library

The metadata-first `tools/patterns/pattern-library.sh` adapter can search a
private local collection without making it a company or repository dependency.
Configuration is deliberately opt-in and is never discovered automatically.

To configure it on one workstation:

1. Create a private configuration file outside this repository. A conventional
   location is `~/.config/assistant-framework/pattern-libraries.json`:

   ```json
   {
     "schema_version": "1.0",
     "libraries": [
       {
         "id": "design-patterns",
         "root": "/path/to/design-pattern-examples"
       }
     ]
   }
   ```

   Replace the example root with an existing directory that is not a symlink.
   Absolute roots are supported. Relative roots are resolved from the configuration file's directory.
   They are not resolved from the current working directory.
   The config supports only `schema_version`, `libraries`, `id`, and `root`.

2. Make the config path explicit in personal or project instructions so the
   workflow is allowed to use it. Do not put the library root itself in shared
   instructions. For Codex, a compact entry in `~/.codex/AGENTS.md` is:

   ```markdown
   ## Personal pattern library

   For optional design-pattern retrieval, use the explicit config at
   `~/.config/assistant-framework/pattern-libraries.json`.
   ```

3. Restrict the private config and validate it with the adapter from a checkout of this repository:

   ```bash
   chmod 700 ~/.config/assistant-framework
   chmod 600 ~/.config/assistant-framework/pattern-libraries.json
   tools/patterns/pattern-library.sh validate-config \
     --config ~/.config/assistant-framework/pattern-libraries.json
   tools/patterns/pattern-library.sh search \
     --config ~/.config/assistant-framework/pattern-libraries.json \
     --query "factory"
   ```

   A valid configuration returns `status: configured`; search returns metadata
   only and at most three results by default. No prebuilt index is required.
   The plugin does not ship the adapter, so retrieval needs that checkout.

See `docs/pattern-library.md` for index creation, bounded result limits, and the
safe explicit `show` command.

The dated eight-priority architecture, verification, and manual-testing handoff
is in `docs/assistant-framework-priority-handoff-2026-07-12.md`.

### Architecture verification status

The local P0-P4 contracts cover the adaptive-loop mapping, compression-safe
state, clarification and plan selection, bounded Build repair, independent
Review, Document-only handoff ownership, and the end-to-end ordered repair
fixture:

```bash
./tests/test-p0-p4-contracts.sh
```

The suites require ripgrep (`rg`) on `PATH` and stop with an error without it.
For the locked Draft 2020-12 evaluator checks in that aggregate, first use
Node.js 22 and run `(cd tools/evals && npm ci --ignore-scripts)`; `node_modules`
is Git-ignored, so each fresh clone or worktree needs this step. The shared
harness adds `-Ku` to `RUBYOPT` so Ruby checks read and parse UTF-8 framework text
under a non-UTF-8 locale such as `C`; it leaves the shell locale unchanged.

Pull requests and pushes to `main` also run
`.github/workflows/framework-validation.yml`, which executes the fast aggregate
contracts and four long-running contract suites as parallel shards, then runs
skill and plugin checks on hosted Linux runners.

The end-to-end fixture checks the observable order: implementation, focused
test pass, an exact trusted review invocation finding the seeded defect, repair,
focused revalidation pass, a fresh exact review pass, then final handoff. Its
closed-world verifier artifact binds the finding and repair to different source
hashes and records that the defect existed before repair and is absent after
repair. The runner accepts only exact trusted command forms and inspects
temporary Codex JSONL events before deleting them.

These deterministic repository checks validate the framework mechanics; they
do not by themselves prove current model behavior.
The previously recorded Terra snapshot predates the changed fixture and grader
and remains historical, non-promoting evidence. A new live promotion claim
requires fresh authorization for the exact four-call smoke and, if it passes,
separate authorization for the eight-case, three-repeat, two-variant pilot
(48 calls / 24 pairs). Every automatic and human gate in
`docs/evals/README.md` must pass.

## Structure

```
version.txt                        <- Framework and plugin version
.claude-plugin/marketplace.json    <- Claude Code marketplace
.agents/plugins/marketplace.json   <- Codex marketplace
plugins/assistant-framework/       <- Generated plugin (tools/skills/sync-plugin.py); edit skills/ instead
docs/instruction-block.md          <- Optional instruction block for CLAUDE.md / AGENTS.md

skills/
  assistant-workflow/
    SKILL.md                       <- Core pipeline (always loaded when triggered)
    references/                    <- Plan templates, checklists, prompt packs
    playbooks/                     <- Project-type architecture guides

  assistant-clarify/
    SKILL.md                       <- Clarification workflow for ambiguous or multi-intent prompts
    evals/cases.json               <- Pilot provider-neutral behavior eval fixtures

  assistant-ci-audit/
    SKILL.md                       <- Bounded CI/test protection and maintenance audit
    contracts/                     <- Typed input/output, gates and progressive index
    references/                    <- Investigation and protection/cost assessment
    evals/cases.json               <- Offline defect/control and authority fixtures

  assistant-tdd/
    SKILL.md                       <- Conditional TDD (Red-Green-Refactor cycle)

  assistant-debugging/
    SKILL.md                       <- Reproduce, isolate, then fix an unknown failure
    contracts/                     <- Typed input/output, gates and handoffs
    references/                    <- Reproduction, state inspection, lifecycle and change impact
    evals/cases.json               <- Behaviour and activation eval cases

  assistant-thinking/
    SKILL.md                       <- Tool descriptions and usage guidance
    clarify.md                     <- First principles: hard vs soft constraints
    perspectives.md                <- Smallest useful set of independent viewpoints
    stress-test.md                 <- Steelman + counter-argument
    deep-think.md                  <- 8 analytical lenses
    hypothesize.md                 <- Goal-first + hypothesis plurality
    creative.md                    <- Low-probability sampling
    evals/cases.json               <- Pilot provider-neutral behavior eval fixtures

  assistant-spike/
    SKILL.md                       <- Question, probe plan, control, verdict and Workflow handoff
    evals/cases.json               <- Provider-neutral behavior eval fixtures

  assistant-research/
    SKILL.md                       <- Tool descriptions and usage guidance
    research.md                    <- Direct source research scaled to the question
    five-lens-briefing.md          <- STORM-inspired decision briefing: perspective scan / contradictions / synthesis / peer review
    investigate.md                 <- Deep investigation with ethical framework
    url-verify.md                  <- URL verification protocol
    source-provenance.md           <- Source register and citation check, loaded only for substantial reports
    fetch-recovery.md              <- Bounded failed-fetch recovery and snapshot labelling, loaded only on a failed fetch
    legacy-compatibility.md        <- Pre-v5 records, loaded only for persisted history

  assistant-security/
    SKILL.md                       <- Tool descriptions and severity scale
    threat-model.md                <- STRIDE analysis
    code-review.md                 <- OWASP Top 10 review
    dependency-audit.md            <- CVE dependency checking
    attack-surface.md              <- Attack surface mapping
    agent-authority.md             <- Agent/tool authority and durable context
    install-boundaries.md          <- Installer and filesystem ownership boundaries
    release-provenance.md          <- Dependency and release provenance
    prompts/threat-model.md        <- Deep analysis prompt pack

  assistant-advisory-triage/
    SKILL.md                       <- Advisory verdict, shipped-release proof, read-only authority
    evals/cases.json               <- Behaviour and activation eval cases

  assistant-review/
    SKILL.md                       <- Autonomous review/fix/re-review loop

  assistant-ui-qa/
    SKILL.md                       <- Exploratory UI QA: scope, runtime, exploration, report, safety
    references/issue-taxonomy.md   <- Severity, category, duplicate and coverage rules
    evals/cases.json               <- Offline behavior and activation fixtures

  assistant-docs/
    SKILL.md                       <- Mode selection and general protocol
    api-docs.md                    <- API surface documentation
    architecture.md                <- System overview generation
    readme-gen.md                  <- README generation from code analysis
    editing-checklist.md           <- Prose editing: meaning, terms and voice preserved
    changelog.md                   <- Release notes from git history
    migration.md                   <- Breaking change migration guides
    explainer.md                   <- Code explanations written into docs or comments

  assistant-skill-creator/
    SKILL.md                       <- Instruction-first skill authoring and assessment

  assistant-onboard/
    SKILL.md                       <- Scoped codebase orientation
    inventory.md                   <- Optional size/language inventory with local tools

  assistant-verification/
    SKILL.md                       <- Verification selection and evidence assessment
    references/                    <- Selection, evidence quality, lifecycle and methods
    evals/cases.json               <- Behaviour and activation eval cases

tools/
  skills/
    validate-skills.sh             <- Source validator for first-class skill metadata and contracts
    sync-operating-guidance.sh     <- Copies tools/progress guidance into every skill
    sync-role-prompts.sh           <- Copies reconciled agent bodies into skills' references/roles/
    sync-plugin.py                 <- Builds plugins/assistant-framework/ and the marketplace files
    build-chat-zips.py             <- Builds Claude chat upload ZIPs into dist/chat-skills/
  evals/
    run-skill-evals.sh             <- Provider-neutral per-skill eval fixture helper
    run-framework-instruction-evals.sh <- Provider-neutral framework instruction eval helper
    run-codex-framework-evals.sh   <- Opt-in paired Codex behavioral adapter

tests/
  test-p0-p4-contracts.sh          <- Framework contract and migration tests

```

## How it works

### For ideas (vague)
```
You: "I want to add caching to our API"
Workflow skill: Inspects existing behavior, resolves material choices, and plans the agreed outcome
```

### For tasks (concrete)
```
You: "Fix the null reference in UserService.GetById"
Workflow skill: Triages as Small, quick discovery, lightweight plan, fix + test + fresh independent review
```

### For TDD
```
You: "Use TDD to add a password strength validator"
TDD skill: Activates Red-Green-Refactor. Writes failing test first, implements minimum to pass, refactors, and reports each cycle.
```

### For thinking
```
You: "Think about whether we should use microservices or modular monolith"
Thinking skill: Loads perspectives.md, runs a perspectives debate with only the roles that can change the decision
```

### For research
```
You: "Research the best .NET caching libraries"
Research skill: Researches with primary sources, URL verification and explicit gaps
```

### For security
```
You: "Audit the auth flow for vulnerabilities"
Security skill: Loads code-review.md, runs OWASP Top 10 analysis
```

### For documentation
```
You: "Document the API"
Docs skill: Scans endpoints, extracts parameters/types, generates API reference with examples
```

### For new projects
```
You: "Learn this codebase"
Onboard skill: Maps structure, identifies patterns, and reports project orientation
```

### For brainstorming
```
You: "What are some ideas for improving the search experience?"
Thinking skill: Uses the constraints to compare useful alternatives; expands the search when requested
```

## Native skill routing

Each supported agent discovers installed skills from required native `name` and
non-empty `description` fields. Body instructions apply after activation.
Skill instructions, relevant references, evaluations, project guidance, and
review provide the workflow discipline; there is no separate runtime router or
lifecycle enforcement layer. Ordinary skills start with concise instructions.
Contracts remain where persisted state, another agent, an explicit structured
response, or an executable validator consumes a defined format. A YAML rule
read by a model has the same instruction-following limits as prose.

Workflow metrics are optional, non-blocking observability.

SKILL.md frontmatter defines required native discovery fields and optional repository dependency metadata:

```yaml
---
name: my-skill
description: "..."
---
```

`name` and a non-empty `description` are required native discovery fields.
Repository skills may add optional `requires` only for validated hard
dependencies; omit it when none exist. Native discovery uses required `name`
and `description`; optional repository `requires` is not an activation signal.
Agents apply body instructions only after activation.
Top-level `effort` and `triggers` are retired and rejected by validation. Keep
representative activation examples in relevant references and positive/negative evals,
never in SKILL.md header metadata.

No runtime script changes are needed when adding a skill: add required discovery
fields, conditional `requires` when applicable, and focused evals, then run `tools/skills/sync-plugin.py --apply` and bump
`version.txt` so plugin users get the update.
Add contract files only for a named consumer or supported interface; validate
all supplied or explicitly referenced contracts. See the
[skill design guide](docs/skill-contract-design-guide.md).

### Trying the simplified skills

Test the skills on normal work and report the skill, source revision, request,
expected behavior, and actual behavior. Distinguish an inconvenient response
from a correctness, authority, or compatibility regression. Structural checks
and shorter instruction files do not establish better model results.

Plugin installs are cached per version, so updating the plugin replaces its
skill files; keep local edits in your own skills instead. Reverting a release
does not undo project work produced during testing.

## Design principles

- **Never guess** — Ask when ambiguous, state assumptions when clear
- **Right-sized ceremony** — Small tasks get lightweight treatment, large tasks get full workflow
- **Composable skills** — Each first-class `assistant-*` skill works standalone or together with the others
- **Progressive loading** — Each SKILL.md is small. Tool files load on demand.
- **Thinking tools are tools, not phases** — Use them when needed, not on every task
- **Evidence before change** — Current repository evidence, tests, and review gates guide delivery decisions
- **Covers weaknesses** — Documentation, diagrams, and onboarding compensate for developer blind spots


### Common guidance and unmatched activities

The canonical guidance is `tools/progress/operating-guidance.md` with its
`wire-boundary.md`. Each of the 16 first-class assistant skills carries a
byte-identical copy of both in its own `references/` folder and links to that
copy, so a skill folder works on its own, including inside the plugin cache.
After editing the canonical files, run
`tools/skills/sync-operating-guidance.sh --apply`, then
`tools/skills/sync-plugin.py --apply`; the contract suites fail on drift. The
guidance also defines `{agent_state_dir}` (`.claude` on Claude Code, `.codex` on
Codex), which skill text keeps as written.

For requests no skill matches, the [optional instruction block](#optional-instruction-block)
carries the short working rules: follow matched skills to their handoff, and
limit user interruptions to open decisions, risky or external actions, required
plan approval, a stagnation stop, and the final report.

Workflow v16 validates/migrates original v14/v15 authority, retaining original and
normalized digests, execution, actors, selected TDD and results. Review v10 and
five-lens research v5 use the same
[common task-level stagnation guard](tools/progress/operating-guidance.md).
Research v5 needs five separate lens agents and a newly created peer reviewer;
historical v4 fallback records stay readable only.
Productive attempts and review/QA rounds have no cumulative ceiling. Historical
counters/labels remain evidence; missing progress history is an explicit gap.
No native/model pilot, reduced-friction, quality, time or cost improvement has
been established by structural checks alone.
