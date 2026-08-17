# Assistant Framework

A Personal AI Assistant framework for developers. 14 first-class `assistant-*` skills: structured workflow, clarification, TDD enforcement, debugging, thinking tools, research, security analysis, documentation generation, codebase onboarding, idea generation, visual diagrams, review automation, skill creation, and purpose-driven context (Telos).

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
13. **Skill Creation** — Scaffolds V1 skills with contracts, phase gates, and handoffs
14. **Telos** — Purpose context framework ([Daniel Miessler's Telos Method](https://github.com/danielmiessler/Telos)): problems, mission, goals, strategies, projects — so agents prioritize work that matters

## Installation

Install all skills for any supported agent:

```bash
./install.sh --agent claude   # → ~/.claude/skills/assistant-*/
./install.sh --agent codex    # → ~/.codex/skills/assistant-*/
./install.sh --agent gemini   # → ~/.gemini/skills/assistant-*/
```

The release inventory is the tracked `skills/assistant-*` set. `skills/unity-*` directories are local-only and ignored by git; they are not installed or validated as framework release skills.

Plugin boundaries are contract-backed in `docs/plugin-architecture.md`. The current installer still uses the root `skills/assistant-*` release inventory by default, and it also supports focused profile installs:

```bash
./install.sh --agent codex --plugin assistant-core
./install.sh --agent codex --plugin assistant-research
./install.sh --agent codex --plugin assistant-dev
```

The repo also includes scaffolded Codex plugin manifests at `plugins/assistant-core/.codex-plugin/plugin.json`, `plugins/assistant-research/.codex-plugin/plugin.json`, and `plugins/assistant-dev/.codex-plugin/plugin.json`. The core scaffold contains `assistant-clarify` and `assistant-telos`; the research scaffold has three skills, and the dev scaffold has nine. These plugin-local copies are generated release artifacts from the root `skills/assistant-*` source of truth; verify or refresh them with `tools/plugins/sync-plugin-skills.sh --check` and `tools/plugins/sync-plugin-skills.sh --apply`. The installer performs manifest-aware dry-run validation for the core, research, and dev profiles, but the scaffolds are not marketplace-registered yet; root installs remain the compatibility path.

Install a single skill:
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

Use `install.ps1` from a checked-out copy of this repository. It supports Windows PowerShell 5.1 and PowerShell 7.

Close Codex App before installing or updating Codex so it releases `AGENTS.md` and managed framework files. The installer leaves `config.toml` untouched and does not invoke the Codex CLI. If a managed file is locked, close Codex App and rerun the same command. If a file becomes unavailable after preflight, the installer reports a partial installation; resolve the cause and rerun because reinstall is safe.

Install the complete release inventory for one agent:

```powershell
.\install.ps1 -Agent codex
.\install.ps1 -Agent claude
.\install.ps1 -Agent gemini
```

The same entry point supports a single skill, a focused profile, and a non-mutating preview:

```powershell
.\install.ps1 -Agent claude -Skill assistant-thinking
.\install.ps1 -Agent codex -Plugin assistant-dev
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

For multi-slice work, Assistant Workflow infers the repository's current local
target branch unless explicitly supplied, then uses a portable task branch
(`feature/<task>`) with collision-safe slice heads (`slice/<task>/<slice-id>`)
built from descriptive outcome-oriented slice identifiers rather than ordinal-only labels.
`review_gated` slices emit SHA-bound `REVIEW_PENDING` evidence; remote review
and policy mechanics remain in the configured provider adapter.

The architecture is an adaptive loop implemented through native skill routing;
there is no installed lifecycle engine. Its conceptual states map to the public
workflow like this:

| Conceptual state | Public phase | Observable responsibility |
|---|---|---|
| ORIENT, RESOLVE | Discover | Inspect the request, repository, policy, and current task state; apply and record deterministic safe defaults, and ask only material questions with no safe default. |
| PLAN? | Optional Plan | Select `plan_mode`: `none`, `inline`, or `approval_required`. |
| EXECUTE SLICE, OBSERVE | Build | Implement one coherent slice, run focused tests, and host-verify argv-array commands before marking evidence verified. |
| REVIEW | Review | Independently check requirements, regressions, quality, security, and QA evidence. |
| REPAIR | Build or Review | Build repair handles implementation or verification failures with bounded attempts, followed by fresh Review. The assistant-review Review-fix loop handles review findings inside Review with revalidation and a fresh review result. |
| HANDOFF | Document | Compose `final_handoff` and developer-facing manual test guidance only after acceptance evidence exists. |

`plan_mode=none` is limited to small, local, reversible, high-confidence work
with known scope. `inline` records a short plan without an approval wait.
`approval_required` applies to medium-or-larger work and to risk, policy, or
public-impact changes. Build owns implementation, tests, host verification, and
a bounded repair loop: at most three attempts, a no-progress limit of two, and
recorded failure signatures and progress before pivoting or reporting a block.
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

For executable slices, repository verification uses canonical argv arrays and
is bound to tracked files in the exact clean slice commit. Host verification
has bounded private logs and a hard process-group timeout; passing commits are
promoted from an isolated merge candidate with compare-and-swap protection.
Validation commands must leave the candidate tree unchanged. Parallel worktree
storage inside the repository must already be gitignored—the runner fails with
an instruction instead of editing `.gitignore`.

For compression-safe work, the orchestrator keeps concise, root-scoped task and
session state under `.codex/`. Resume reconciles that journal with the newest
user request and current repository evidence before continuing; stale state
never overrides either source.

Loop readiness is conditional. Ordinary day-to-day development, such as taking a work item, prompting once, waiting for implementation, and manually testing the result, stays in the normal workflow. Add `loop_readiness_assessment` only before an explicit repeat, optimization, or experiment loop outside the standard phase gates. Examples include "keep fixing build/test failures until green", "iterate on this interface until the manual checklist passes", or "optimize until a measured target is reached". A loop plan must name the verifier, stop condition, finite max iterations, budget limit, retry/empty-result handling, tool-error handling, low-confidence escalation, rollback/exit action, and harness routing. Loop readiness alone does not require Done Contract, Harness Recipe, Trace Ledger, Replay Packet, Artifact Reference Ledger, or QA evaluation unless harness or QA criteria independently apply.

Triggers on: build, implement, fix, refactor, plan, create, idea

### assistant-clarify
Clarification workflow for ambiguous, fragmented, or multi-intent prompts. Restates the likely goal, surfaces constraints, asks targeted questions, and produces a structured execution brief.

Triggers on: messy prompt, unclear prompt, figure out what I mean, help me structure this

### assistant-tdd
Test-Driven Development enforcement: Red-Green-Refactor cycle with verification gates. Bug fix pattern (reproduce → fix → protect). Integrates with workflow's build loop and review cycle.

Triggers on: TDD, tests first, test-driven, write the test first, red green refactor

### assistant-debugging
Evidence-first debugging: reproduce or bound the failure, rank competing hypotheses, isolate root cause, apply the smallest durable fix, and verify with original reproduction plus regression checks.

Triggers on: debug, root cause, investigate failure, flaky test, failing test, production issue

### assistant-thinking
Six structured reasoning tools: clarify, perspectives, stress-test, deep-think, hypothesize, creative.

Triggers on: think about, clarify, perspectives, stress test, brainstorm, debate

### assistant-research
Tiered research (quick/standard/extensive/deep), five-lens decision briefing, deep investigation, URL verification.

Triggers on: research, investigate, look into, find out, what is

### assistant-security
STRIDE threat model, OWASP code review, CVE dependency audit, attack surface mapping.

Triggers on: security, threat model, audit, vulnerability, OWASP

### assistant-review
Evidence-bounded code review: audits use one pass; review-fix work normally uses one review plus one fresh post-fix re-review. Additional rounds require new evidence and a recorded reason, within the terminal safety cap. Prioritizes concrete bugs, regressions, risks, and missing tests.

Triggers on: review, fresh review, code review, review this, check the code

### assistant-docs
Documentation generation and maintenance. Six modes: API docs, architecture overview, README, changelog, migration guide, code explainer. Detects stale docs and offers updates.

Triggers on: document, write docs, update readme, changelog, API docs, architecture doc

### assistant-skill-creator
Creates or updates V1 skills with input/output contracts, phase gates, and handoff definitions following the framework contract guide.

Triggers on: create skill, new skill, add contracts, skill contracts, scaffold skill

### assistant-onboard
Systematic codebase learning for new projects. Six-phase protocol: surface scan, architecture map, pattern recognition, knowledge gaps, record project context, report.

Triggers on: learn this codebase, onboard, get familiar with, map this project

### assistant-ideate
Mode-aware ideation: light mode returns 3-5 quickly ranked options for improvement scans; deep mode runs the full 8-15 idea, weighted-score, refine, and decide pipeline. Codebase-aware ideation scans only the local context needed to shape useful options.

Triggers on: brainstorm, feature ideas, what if, how could we, alternatives, or what-else improvement scans

### assistant-diagrams
Visual documentation from code analysis. Seven diagram types: architecture, sequence, entity-relationship, flow, component, class, state. All output as Mermaid for markdown embedding.

Triggers on: diagram, draw, visualize, show me the flow, architecture diagram

### assistant-telos
Purpose context framework based on [Daniel Miessler's Telos Method](https://github.com/danielmiessler/Telos). Guides you through building a purpose chain (problems → mission → goals → challenges → strategies → projects) stored at `~/.claude/telos.md`. Loaded at every session start so agents can prioritize work aligned with what actually matters to you.

Triggers on: telos, my purpose, why am I doing this, what matters most, my mission, update telos

## Tools

### Cognitive Complexity

Roslyn-based analyzer that scores method complexity. Used by the workflow skill's quality review stage. See `tools/cognitive-complexity/`.

### Skill Validator

Source validator for first-class skill metadata and contract structure:

```bash
tools/skills/validate-skills.sh
```

By default it validates only the release inventory: tracked `skills/assistant-*/SKILL.md` skills and their `contracts/*.yaml` files. Local-only `skills/unity-*` directories are excluded by default.

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

The default eval inventory is 14 first-class `assistant-*` skills with fixtures
and excludes local-only `unity-*` skills unless `--include-local` is passed.
Canonical first-class fixtures use schema `2.0` and include top-level
`activation_cases`: exact `{user_request, should_activate}` objects with at
least two normalized-distinct positive requests and one normalized-disjoint
nearby negative. Schema `1.0` custom/local fixtures may omit this field; when
they include it, the same shape is validated. Activation cases shape discovery
coverage only unless compared against externally observed native selections with
`--activation-results`; they are separate from response-graded `.cases` and
never SKILL.md metadata. The runner does not invoke native routing itself.
Local-only Unity skills remain opt-in through `--include-local`. Local grading is heuristic
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

Pull requests and pushes to `main` also run
`.github/workflows/framework-validation.yml`, which executes the aggregate
contracts, skill and generated-mirror checks, and all three Unix installer
dry-runs on a hosted Linux runner.

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
separate authorization for the six-case, three-repeat, two-variant pilot
(36 calls / 18 pairs). Every automatic and human gate in
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
    scripts/                       <- Mega task automation
    agents/                        <- Agent presets (claude/codex/gemini.conf)

  assistant-clarify/
    SKILL.md                       <- Clarification workflow for ambiguous or multi-intent prompts
    evals/cases.json               <- Pilot provider-neutral behavior eval fixtures

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
    SKILL.md                       <- V1 skill scaffolding with contracts and phase gates

  assistant-onboard/
    SKILL.md                       <- Six-phase onboarding protocol

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

  unity-*/                         <- Local-only skill experiments ignored by git, not release inventory

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
Workflow skill: Decomposes into 6-8 testable criteria, asks for confirmation, then triages
```

### For tasks (concrete)
```
You: "Fix the null reference in UserService.GetById"
Workflow skill: Triages as Small, quick discovery, lightweight plan, fix + test + self-review
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
Ideate skill: Understands context, generates 10+ ideas, scores them, refines top 3
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
Framework contracts, evals, project guidance, and review provide the workflow
discipline; there is no separate runtime router or lifecycle enforcement layer.

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
representative activation examples in contracts and positive/negative evals,
never in SKILL.md header metadata.

No runtime script changes are needed when adding a skill: add required discovery
fields, conditional `requires` when applicable, contracts, and evals, then reinstall.

## Design principles

- **Never guess** — Ask when ambiguous, state assumptions when clear
- **Right-sized ceremony** — Small tasks get lightweight treatment, large tasks get full workflow
- **Composable skills** — Each first-class `assistant-*` skill works standalone or together with the others
- **Progressive loading** — Each SKILL.md is small. Tool files load on demand.
- **Thinking tools are tools, not phases** — Use them when needed, not on every task
- **Evidence before change** — Current repository evidence, tests, and review gates guide delivery decisions
- **Covers weaknesses** — Documentation, diagrams, and onboarding compensate for developer blind spots
