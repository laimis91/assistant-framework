# Assistant Framework

A Personal AI Assistant framework for developers. 16 first-class `assistant-*` skills: structured workflow, clarification, TDD enforcement, debugging, thinking tools, research, security analysis, documentation generation, codebase onboarding, idea generation, visual diagrams, review automation, skill creation, purpose-driven context (Telos), and evidence-based verification selection and assessment.

Review, including standalone/selective `assistant-review`, requires Python3.9+.
Its pinned pure-Python YAML parser is bundled privately with the skill; users need
neither Ruby nor pip/LibYAML. Both installers probe the source helper and parser
before any writes, including dry-run. No package is installed or downloaded.
If Python or the parser is later removed, stop validation, restore the prerequisite
and rerun `python3 -I -S -B <loaded-review-skill>/scripts/review-tools.py --probe`.
The helper lives with the skill, including Windows Codex `.agents/skills`;
the measurement importer `tools/evals/review-efficiency-report.rb` stays source-only.

## What it does

1. **Structured Workflow** — adaptive Discover > optional Plan > Build > Review > Document flow with bounded repair and evidence-gated handoff
2. **Clarification** — Converts ambiguous, fragmented, or multi-intent prompts into an executable brief
3. **TDD Enforcement** — Red-Green-Refactor cycle with strict verification gates at each transition
4. **Debugging** — Evidence-first root-cause workflow: reproduce, hypothesize, isolate, fix, verify
5. **Thinking Tools** — On-demand structured reasoning (first principles, multi-perspective debate, stress testing, etc.)
6. **Research Tools** — Tiered information gathering with URL verification and confidence scoring
7. **Security Analysis** — STRIDE threat modeling, OWASP code review, CVE dependency audit, attack surface mapping
8. **Documentation** — Auto-generates API docs, architecture docs, README, changelogs, migration guides, code explanations
9. **Onboarding** — Systematic codebase learning: maps structure, identifies patterns, and reports actionable project orientation
10. **Idea Generation** — Diverge-converge-refine brainstorming pipeline with codebase awareness
11. **Visual Diagrams** — Mermaid diagrams from code: architecture, sequence, ER, flow, component, class, state
12. **Review Automation** — Evidence-bounded review/fix/re-review with calibrated scores and finite rounds
13. **Skill Creation** — Creates focused instructions, with schemas when a real consumer needs them
14. **Telos** — Purpose context framework ([Daniel Miessler's Telos Method](https://github.com/danielmiessler/Telos)): problems, mission, goals, strategies, projects — so agents prioritize work that matters
15. **Verification** — Selects proportionate checks and techniques, applies TDD only when appropriate, and assesses whether evidence supports the claim.

## Installation

Installations whose selected bundled closure includes `assistant-workflow` require Python 3.9+ for its packet-admission helper and Workflow eval adapter. Both installers probe a usable supported interpreter before writes, including dry-run; closures without Workflow or Review remain Python-independent. Install the runtime yourself, then rerun the installer. Unix probes `python3`; native Windows probes `py -3`, `python3`, then `python` and reports the supported invocation. No runtime is downloaded.

Install all skills for any supported agent:

```bash
./install.sh --agent claude   # → ~/.claude/skills/assistant-*/
./install.sh --agent codex    # → ~/.codex/skills/assistant-*/
./install.sh --agent gemini   # → ~/.gemini/skills/assistant-*/
```

The release inventory is the tracked `skills/assistant-*` set.

Install one root skill with its bundled hard dependencies:
```bash
./install.sh --agent claude --skill assistant-thinking
```

Preview without making changes:
```bash
./install.sh --agent claude --dry-run
```

Claude Code, Codex, and Gemini CLI discover and route installed skills through their native skill systems. Assistant Framework does not install lifecycle scripts or replace provider-native permissions, subagents, or compaction.

```bash
./install.sh --agent claude
./install.sh --agent codex
./install.sh --agent gemini
```

For one compatibility release, a normal install retires only older Assistant Framework lifecycle hook registrations. It removes only commands owned by this framework from the selected agent's existing settings, preserves unrelated custom configuration, and replaces detected stale framework entrypoints with silent exit-zero shims for already-running clients. It does not inspect or alter legacy Memory Graph configuration, runtime, or provider data. The deprecated `--no-hooks` option remains a warning-only no-op during this transition.

### Native Windows installation

Use `install.ps1` from a checked-out copy of this repository. It supports Windows PowerShell 5.1 and PowerShell 7. Workflow requires Python 3.9+ even when previewing with `-DryRun`; merely finding a launcher or app alias is insufficient. Use the interpreter invocation reported by preflight explicitly for `scripts/task-packet-admission.py`, for example `py -3 <skill-directory>\scripts\task-packet-admission.py`, rather than relying on `.py` file association. If Python is removed later or a manual install lacks it, stop at the admission gate, install a supported interpreter, and rerun before continuing.

Close Codex App and any Codex CLI sessions before installing or updating Codex so they release `AGENTS.md` and managed framework files. On Windows, the installer rejects Codex installs (including `-DryRun`) before any writes when a `Codex` process is running; it does not terminate processes. Keep Codex closed until installation finishes. The installer leaves `config.toml` untouched and does not invoke the Codex CLI. If a managed file is locked, close Codex App and rerun the same command. If a file becomes unavailable after preflight, the installer reports a partial installation; resolve the cause and rerun because reinstall is safe.

Install the complete release inventory for one agent:

```powershell
.\install.ps1 -Agent codex
.\install.ps1 -Agent claude
.\install.ps1 -Agent gemini
```

The same entry point supports one root skill with its bundled hard dependencies and a non-mutating preview:

```powershell
.\install.ps1 -Agent claude -Skill assistant-thinking
.\install.ps1 -Agent codex -DryRun
```

After pulling an update, reinstall by running the selected install command again:

```powershell
.\install.ps1 -Agent codex
```

Installer-owned directories are mirrored, while unrelated agent configuration and user-authored instruction content are preserved. Restart the selected agent after updating an older installation.

Windows destinations are:

| Agent | Skills | Configuration and tools |
|---|---|---|
| Codex | `%USERPROFILE%\.agents\skills\assistant-*` | `CODEX_HOME` when set; otherwise `%USERPROFILE%\.codex` |
| Claude Code | `%USERPROFILE%\.claude\skills\assistant-*` | `%USERPROFILE%\.claude` and `%USERPROFILE%\.claude.json` |
| Gemini CLI | `%USERPROFILE%\.gemini\skills\assistant-*` | `%USERPROFILE%\.gemini` |

The Windows installer itself does not require administrator access, create symlinks, download dependencies, or change PowerShell execution policy. If Windows marks the checked-out script as downloaded and blocks it, review the file and remove only that file's download mark:

```powershell
Unblock-File -LiteralPath .\install.ps1
```

Do not work around policy errors with `Set-ExecutionPolicy` or `-ExecutionPolicy Bypass`. The repository's remaining Bash-only maintenance and eval helpers still require Git Bash or WSL.

#### Windows manual verification

1. From a repository path containing spaces, run `Get-Help .\install.ps1 -Detailed` and `.\install.ps1 -Agent codex -DryRun`.
2. Close Codex App, run `.\install.ps1 -Agent codex`, then confirm that `%USERPROFILE%\.agents\skills\assistant-workflow\SKILL.md` exists.
3. Resolve the Codex configuration root and confirm its global instructions were installed. Existing `config.toml` content is left unchanged:

   ```powershell
   $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
    Test-Path -LiteralPath (Join-Path $codexHome 'AGENTS.md')
   Select-String -LiteralPath (Join-Path $codexHome 'AGENTS.md') -SimpleMatch 'ASSISTANT_FRAMEWORK_AGENTS_MD_START'
   ```

4. Run the isolated integration contracts in both Windows PowerShell 5.1 and PowerShell 7: `.\tests\windows\installer-contracts.ps1`.
5. Restart the selected agent and verify its installed skills are available.

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
choosing verification scope. Triggered shared-impact work uses one installed
Node 22 common checker and carries the same artifact identity through workflow,
debugging, and review. Discovery may report gaps; completion also needs actual
current verification and the existing assistant-review manifest/coverage result.
The checker validates closure against supplied bounded evidence, not a universal
runtime dependency graph. Shared fanout alone does not add Architecture Decision
Pack, strict-lane, or QA requirements.

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
the shared task-level guard: its source-bound effective window (default three consecutive unproductive semantic cycles),
with completed evidence retained before later blockers and no cumulative attempt ceiling.
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
Test-Driven Development enforcement: Red-Green-Refactor cycle with verification gates. Bug fix pattern (reproduce → fix → protect). Integrates with workflow's build loop and review cycle.

Triggers on: TDD, tests first, test-driven, write the test first, red green refactor, or an intersecting workflow-selected TDD check

### assistant-debugging
Evidence-first debugging: reproduce or bound the failure, rank competing hypotheses, isolate root cause, apply the smallest durable fix, and verify with original reproduction plus regression checks.

Triggers on: debug, root cause, investigate failure, flaky test, failing test, production issue

### assistant-thinking
Six structured reasoning tools: clarify, perspectives, stress-test, deep-think, hypothesize, creative.

Triggers on: architecture decisions, complex trade-offs, stress tests, debate, first principles, hypotheses

### assistant-research
Source-backed research with verified links, claim-specific confidence, and explicit conflicts and gaps. Selected five-lens decision briefings retain five independent lens handoffs and separate peer review.

Triggers on: research, topic investigation, current evidence, source-backed comparisons

### assistant-security
STRIDE threat model, OWASP code review, CVE dependency audit, attack surface mapping.

Triggers on: security, threat model, audit, vulnerability, OWASP

### assistant-review
Evidence-bounded code review: trivial/small light review uses one fresh pass plus one fresh re-review after a fix, and plan review uses one fresh pass; medium+ audits use one frozen multi-pass batch at the canonical count of two independent narrow passes, plus integration for medium scope and architecture for large scope. Review-fix work normally uses an initial batch, authorized productive correction, and one fresh post-fix re-review batch. Additional rounds require new evidence and a recorded reason, under the same shared task guard. Prioritizes concrete bugs, regressions, risks, and missing tests.

Triggers on: review, fresh review, code review, review this, check the code

### assistant-docs
Documentation generation and maintenance: API docs, architecture overview, README, changelog, migration guide, and code explanation. Checks source accuracy within the requested scope.

Triggers on: document, write docs, update readme, changelog, API docs, architecture doc

### assistant-skill-creator
Creates, updates, or assesses concise skills. Adds contracts when an actual consumer, persisted state, validator, or user-requested schema needs a defined format.

Triggers on: create skill, new skill, add contracts, skill contracts, scaffold skill

### assistant-onboard
Maps a codebase to the requested depth: entry points, responsibilities, commands, conventions, relevant risks, and coverage gaps. Persists orientation only when authorized.

Triggers on: learn this codebase, onboard, get familiar with, map this project

### assistant-ideate
Light ideation compares useful options quickly; deep ideation expands and
refines alternatives when the decision needs it. The task sets the depth and
criteria. Codebase-aware ideation reads only the local context needed to shape
useful options.

Triggers on: brainstorm, feature ideas, what if, how could we, alternatives, or what-else improvement scans

### assistant-diagrams
Visual documentation from code analysis. Seven diagram types: architecture, sequence, entity-relationship, flow, component, class, state. All output as Mermaid for markdown embedding.

Triggers on: diagram, draw, visualize, show me the flow, architecture diagram

### assistant-telos
Purpose context framework based on [Daniel Miessler's Telos Method](https://github.com/danielmiessler/Telos). Creates or updates a purpose chain (problems → mission → goals → challenges → strategies → projects) to the requested depth. Uses a user-approved location when persistence is requested; session loading depends on the user's configured setup.

Triggers on: telos, my purpose, why am I doing this, what matters most, my mission, update telos

### assistant-ci-audit
Audits CI/test discovery, fixture fidelity, child/report/final-gate failures and
maintenance value. Inspection is the default; finite authorized local diagnostics
may use disposable controlled probes. Findings recommend protection-preserving
changes and measured comparisons; they grant no repair or dispatch authority.
Use debugging for one failing test and verification for selecting checks.

### assistant-verification
Selects proportional verification scope, methods, and TDD applicability, then assesses observed evidence and limitations. It guides verification without running checks. Workflow consumers retain canonical typed decisions; human-only assessments can use concise prose.

Triggers on: verify a change, choose tests, test strategy, assess evidence, are these checks enough

## Tools

### Cognitive Complexity

Roslyn-based analyzer that scores method complexity. Used by the workflow skill's quality review stage. See `tools/cognitive-complexity/`.

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

3. Restrict the private config and validate it with the installed adapter:

   ```bash
   chmod 700 ~/.config/assistant-framework
   chmod 600 ~/.config/assistant-framework/pattern-libraries.json
   ~/.codex/tools/patterns/pattern-library.sh validate-config \
     --config ~/.config/assistant-framework/pattern-libraries.json
   ~/.codex/tools/patterns/pattern-library.sh search \
     --config ~/.config/assistant-framework/pattern-libraries.json \
     --query "factory"
   ```

   A valid configuration returns `status: configured`; search returns metadata
   only and at most three results by default. No prebuilt index is required.
   When using another installed agent, use that agent's tools directory instead
   of `~/.codex/tools/`.

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

For the locked Draft 2020-12 evaluator checks in that aggregate, first use
Node.js 22 and run `(cd tools/evals && npm ci --ignore-scripts)`.

Pull requests and pushes to `main` also run
`.github/workflows/framework-validation.yml`, which executes the fast aggregate
contracts and four long-running contract suites as parallel shards, then runs
skill checks and all three Unix installer dry-runs on hosted Linux runners.

The end-to-end fixture checks the observable order: implementation, focused
test pass, an exact trusted review invocation finding the seeded defect, repair,
focused revalidation pass, a fresh exact review pass, then final handoff. Its
closed-world verifier artifact binds the finding and repair to different source
hashes and records that the defect existed before repair and is absent after
repair. The runner accepts only exact trusted command forms and inspects
temporary Codex JSONL events before deleting them.

These deterministic repository checks validate the framework mechanics; they
do not by themselves prove current model behavior. Hosted Windows PowerShell
5.1 and PowerShell 7 have both run the committed Windows contracts successfully
for this architecture; changes to those surfaces must rerun the hosted workflow.
The previously recorded Terra snapshot predates the changed fixture and grader
and remains historical, non-promoting evidence. A new live promotion claim
requires fresh authorization for the exact four-call smoke and, if it passes,
separate authorization for the eight-case, three-repeat, two-variant pilot
(48 calls / 24 pairs). Every automatic and human gate in
`docs/evals/README.md` must pass.

## Structure

```
install.sh                         <- Top-level installer (skills + migration cleanup)
install.ps1                        <- Native Windows PowerShell 5.1/7 installer
version.txt                        <- Framework version

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
    evals/cases.json                <- Offline defect/control and authority fixtures

  assistant-tdd/
    SKILL.md                       <- TDD enforcement (Red-Green-Refactor cycle)

  assistant-thinking/
    SKILL.md                       <- Tool descriptions and usage guidance
    clarify.md                     <- First principles: hard vs soft constraints
    perspectives.md                <- Multi-perspective debate (4 roles, 3 rounds)
    stress-test.md                 <- Steelman + counter-argument
    deep-think.md                  <- 8 analytical lenses
    hypothesize.md                 <- Goal-first + hypothesis plurality
    creative.md                    <- Low-probability sampling
    evals/cases.json               <- Pilot provider-neutral behavior eval fixtures

  assistant-research/
    SKILL.md                       <- Tool descriptions and usage guidance
    research.md                    <- Tiered: quick / standard / extensive / deep
    five-lens-briefing.md          <- STORM-inspired decision briefing: perspective scan / contradictions / synthesis / peer review
    investigate.md                 <- Deep investigation with ethical framework
    url-verify.md                  <- URL verification protocol

  assistant-security/
    SKILL.md                       <- Tool descriptions and severity scale
    threat-model.md                <- STRIDE analysis
    code-review.md                 <- OWASP Top 10 review
    dependency-audit.md            <- CVE dependency checking
    attack-surface.md              <- Attack surface mapping
    prompts/threat-model.md        <- Deep analysis prompt pack

  assistant-review/
    SKILL.md                       <- Autonomous review/fix/re-review loop

  assistant-docs/
    SKILL.md                       <- Mode selection and general protocol
    api-docs.md                    <- API surface documentation
    architecture.md                <- System overview generation
    readme-gen.md                  <- README generation from code analysis
    changelog.md                   <- Release notes from git history
    migration.md                   <- Breaking change migration guides
    explainer.md                   <- Code explanation for learning

  assistant-skill-creator/
    SKILL.md                       <- Instruction-first skill authoring and assessment

  assistant-onboard/
    SKILL.md                       <- Scoped codebase orientation

  assistant-ideate/
    SKILL.md                       <- Diverge-converge-refine pipeline

  assistant-diagrams/
    SKILL.md                       <- Diagram type selection and protocol
    arch-diagram.md                <- Architecture (component) diagrams
    sequence-diagram.md            <- Interaction sequence diagrams
    er-diagram.md                  <- Entity-relationship diagrams
    flow-diagram.md                <- Flowcharts and decision trees
    component-diagram.md           <- Module dependency diagrams
    class-diagram.md               <- Type hierarchy diagrams
    state-diagram.md               <- State machine diagrams

  assistant-telos/
    SKILL.md                       <- Purpose context framework (Telos Method)

tools/
  skills/
    validate-skills.sh             <- Source validator for first-class skill metadata and contracts
  evals/
    run-skill-evals.sh             <- Provider-neutral per-skill eval fixture helper
    run-framework-instruction-evals.sh <- Provider-neutral framework instruction eval helper
    run-codex-framework-evals.sh   <- Opt-in paired Codex behavioral adapter
  cognitive-complexity/             <- Roslyn-based complexity analyzer

tests/
  test-p0-p4-contracts.sh          <- Framework contract and migration tests
  windows/installer-contracts.ps1  <- Isolated native Windows installer contracts

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
TDD skill: Activates Red-Green-Refactor. Writes failing test first, implements minimum to pass, refactors, logs each cycle in task journal.
```

### For thinking
```
You: "Think about whether we should use microservices or modular monolith"
Thinking skill: Loads perspectives.md, runs 4-perspective debate
```

### For research
```
You: "Research the best .NET caching libraries"
Research skill: Runs standard-tier research with URL verification
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
Ideate skill: Uses the constraints to compare useful alternatives; expands the search when requested
```

### For diagrams
```
You: "Draw the architecture diagram"
Diagrams skill: Traces code, maps components and dependencies, outputs Mermaid diagram
```

### For purpose alignment
```
You: "telos create"
Telos skill: Walks you through problems → mission → goals → challenges → strategies → projects
You: "Does this task align with my goals?"
Telos skill: Checks active work against your purpose chain
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
fields, conditional `requires` when applicable, and focused evals, then reinstall.
Add contract files only for a named consumer or supported interface; validate
all supplied or explicitly referenced contracts. See the
[skill design guide](docs/skill-contract-design-guide.md).

### Trying the simplified skills

Test the skills on normal work and report the skill, source revision, request,
expected behavior, and actual behavior. Distinguish an inconvenient response
from a correctness, authority, or compatibility regression. Structural checks
and shorter instruction files do not establish better model results.

Keep the previous source revision before updating. Reverting the change and
reinstalling that revision restores framework files; it does not undo project
work produced during testing. Installation mirrors managed skill directories,
so preserve any local edits there before updating and retain custom agent
configuration when reinstalling.

## Design principles

- **Never guess** — Ask when ambiguous, state assumptions when clear
- **Right-sized ceremony** — Small tasks get lightweight treatment, large tasks get full workflow
- **Composable skills** — Each first-class `assistant-*` skill works standalone or together with the others
- **Progressive loading** — Each SKILL.md is small. Tool files load on demand.
- **Thinking tools are tools, not phases** — Use them when needed, not on every task
- **Evidence before change** — Current repository evidence, tests, and review gates guide delivery decisions
- **Covers weaknesses** — Documentation, diagrams, and onboarding compensate for developer blind spots


### Common guidance and unmatched activities

All 16 first-class assistant skills reference
`tools/progress/operating-guidance.md`. Unix installs put tools beside skills
under `~/.claude`, configured `CODEX_HOME` (default `~/.codex`), or `~/.gemini`.
Windows Codex also mirrors progress into `~/.agents/tools/progress`, so
`../../tools/progress/operating-guidance.md` from shared skills resolves with
both default and custom `CODEX_HOME`. Existing installer safeguards preserve
user files; full, single-skill, repeated and dry-run installs use the same route.

Codex's installer-owned AGENTS.md explicitly loads the common file independently
of skill matching. For a Claude/Gemini session with no matching skill, use:

- Claude: `Read ~/.claude/tools/progress/operating-guidance.md as the operating guidance for this chat, then handle: <request>`.
- Gemini: `Read ~/.gemini/tools/progress/operating-guidance.md as the operating guidance for this chat, then handle: <request>`.

A user may place the same reference in an existing native instruction source
for standing coverage. Installers take no new global-file ownership. Source
references and installation parity do not prove native activation; automatic
provider coverage is claimed only for observed standing-instruction support.

Workflow v16 validates/migrates original v14/v15 authority, retaining original and
normalized digests, execution, actors, selected TDD and results. Review v10 and
five-lens research v5 use the same three-consecutive-unproductive-cycle policy.
Research v5 needs five separate lens agents and a newly created peer reviewer;
historical v4 fallback records stay readable only.
Productive attempts and review/QA rounds have no cumulative ceiling. Historical
counters/labels remain evidence; missing progress history is an explicit gap.
No native/model pilot, reduced-friction, quality, time or cost improvement has
been established by structural checks alone.

Review helper input details: run `python3 -I -S -B <loaded-review-skill>/scripts/review-tools.py --help`.
Mechanical validation consumes independently retained caller authority and keeps
transport receipts outside canonical v10 returns.
