# Review techniques by SDLC/PDLC artifact, and gaps in assistant-review

Date: 2026-10-28 (revised across thirteen review-fix rounds the same day). Method: ordinary source
research, 28 standard web searches plus 11 page fetch attempts (9 succeeded; iso.org returned 403 and the IEEE 1028 page body was empty). Motivating case: PR 77 in
laimis91/assistant-framework, where Codex found two defects the review skill missed.

## Evidence quality, read first

Labels used in the tables:

- **fetched**: the page was opened in this session and the cited point was seen on it.
- **excerpt**: seen only as a search-result excerpt or abstract.
- **secondary**: blog, vendor, exam-prep or aggregator page. Carries no weight on its own.
- **not retrieved**: the source is named, but its text was not opened; the claim comes from search summaries or memory.
- **read locally**: a repo file read in this session, cited by line range.
- **composed / practice**: reviewer-synthesized or common industry practice; no source was retrieved.
- "primary" describes the source type (paper, standard, official docs), not how much was read.

Bounds:

- No full papers or standards were read. Reading-technique experiments (PBR, checklist, ad hoc)
  use small student samples and disagree with each other.
- Not retrieved: ShellCheck docs, Klein HBR 2007, Bolton's original HICCUPPS write-up, testsmells.org, chaos and fault-injection sources, the ISO/IEC/IEEE 29148 text (iso.org returned 403), the IEEE 1028 page body
  (fetch returned empty), the Anthropic skill-authoring best-practices page, the OWASP GenAI
  red-teaming guide, and Microsoft Learn pages on nullable reference types, the Dispose pattern
  and DI service lifetimes.
- Still unverified: the IEEE 1028 current status (sources conflict), the origin of the pre-mortem
  30% figure, and the exact 29148 quality-characteristic list.
- No counterevidence search was run for most techniques (for example, how often mutation testing
  or perspective-based reading fails to help).
- PR 77 was inspected through the PR page and inline comments via `gh`. It merged on 2026-10-28
  with later commits that fixed both defects (`b0ab7ff` marker validation, `f39bf87` file mode;
  final head `0de49eb`; merge commit `32fbe01`).
- Revision basis. Installer citations (`install.sh`, `install.ps1`,
  `tests/p0-p4/installer-contracts.sh`, `tests/p0-p4/windows-installer-contracts.sh`,
  `tests/windows/installer-contracts.ps1`) refer to PR 77's first commit, `673eb6e` (the commit
  Codex reviewed first), fetched with `gh api`, except citations marked HEAD (for example
  `tests/p0-p4/installer-contracts.sh:971-986`); "verified at 673eb6e" means read from that
  commit. Every other citation (the review skill, sibling skills, tools, agents, other tests)
  refers to local HEAD `32fbe01`, except `docs/skill-contract-design-guide.md`, `CLAUDE.md` and
  `tests/p0-p4/lib/p0p4-harness.sh`, which had uncommitted edits and are cited against the working
  tree on top of `32fbe01`. The checkout moved while this work ran: commits `d25fd00` (#73,
  expert-method guidance), `dacd17c` (#74, lifecycle verification, which changed the review skill)
  and `32fbe01` (#77) entered it in one fast-forward (`c920fd8` to `32fbe01`) between the eighth
  and tenth review rounds. Re-anchor before relying on any line number.

  R1, R2 and R3 tags are defined by the reuse key in the Ownership note. A bare `:N` continues the last file named in the same sentence or cell; where no file is named in a gap-analysis table cell it means `skills/assistant-review/references/review-checklists.md`.

- The gap analysis was checked by two independent read-only review passes over
  `skills/assistant-review/SKILL.md` and all its `references/*.md`, with targeted greps of
  `contracts/*.yaml` and `evals/cases.json`. Later passes also read `tools/`, `tests/`, `agents/`
  and the sibling skills named in the reuse routes (assistant-workflow, assistant-verification,
  assistant-ci-audit, assistant-skill-creator, assistant-tdd, assistant-thinking, assistant-clarify, assistant-security, assistant-docs). A "no hit" below means no keyword hit in the files
  and directories named here.

## Cross-cutting techniques

| Technique | What a reviewer does | Source (type, how seen) |
| --- | --- | --- |
| Perspective-based reading | Each pass reads as one role (user, tester, developer, operator, attacker) following a scenario. | Basili et al., Empirical Software Engineering 1(2), doi 10.1007/BF00368702 (primary, excerpt); replications show mixed individual-level results |
| Checklist reading | Walk a short, specific list per artifact type. | Mixed results: [arXiv 0909.4260](https://arxiv.org/abs/0909.4260v1) found no difference from ad hoc, [LAUJET](https://laujet.com/index.php/laujet/article/view/125) found gains (both primary, excerpt, small student samples) |
| Defect-based reading | Reader hunts one named fault class per pass. | PBR literature summaries (secondary, excerpt) |
| Formal review types | Choose walkthrough, technical review, inspection or audit deliberately. | [IEEE 1028-2008](https://ieeexplore.ieee.org/document/4601584) (primary, excerpt only; page body did not load; status conflicting) |
| Understanding first | Reviews find fewer defects than expected; the main work is understanding the change. Build a model of intent before hunting. | [Bacchelli and Bird, ICSE 2013](https://2013.icse-conferences.org/content/expectations-outcomes-and-challenges-modern-code-review.html) (primary, excerpt; consistent across sources) |
| Oracle heuristics | Name the reference used to call something a problem: history, claims, purpose, standards, user expectation, image, internal consistency, comparable products, familiar problems (list partial). | HICCUPPS, Bolton, developsense.com 2012 (secondary, excerpt; original not retrieved); the "A FEW HICCUPPS" mnemonic's full list not verified (not retrieved) |
| Pre-mortem | Assume the change failed in production, write reasons, then revise. | Klein, HBR 2007 (primary, not retrieved); the 30% figure reportedly traces to Mitchell, Russo and Pennington 1989, not Klein (secondary, excerpt) |
| Hazard analysis | Ask which control actions or interactions become unsafe. Complements component FMEA, which misses interaction hazards. | [arXiv 1703.03657](https://arxiv.org/abs/1703.03657), [controlled experiment](https://ar5iv.labs.arxiv.org/html/1612.00330) (primary, excerpt); STPA took novices longer |
| Bidirectional traceability | Forward: requirement to design, code, test. Backward: every built element to a requirement. Built elements with no backward link ("orphans") must be reviewed. | [NASA SWE-059](https://swehb.nasa.gov/spaces/7150/pages/16449675/SWE-059+-+Bidirectional+Traceability+Between+Software+Requirements+and+Software+Design) (primary, fetched). The page uses "orphan"; tying orphans to gold plating is inference, since the page mentions gold plating only for new requirements |
| Mutation of the change | Inject small faults into changed lines; a test that does not fail is weak. | [Google, practical mutation testing at scale](https://research.google/pubs/practical-mutation-testing-at-scale-a-view-from-google/) (primary, fetched: changed-code-only mutation, 24,000+ developers, 1,000+ projects) |
| Metamorphic and property checks | When no oracle exists, check relations between inputs and outputs. | [Segura et al., IEEE TSE 2016](https://eprints.whiterose.ac.uk/id/eprint/110335); [Barr et al. oracle survey](https://web.eecs.umich.edu/~weimerw/2018-481/readings/testoracles.pdf) (primary, excerpt) |
| Grader hygiene for model reviewers | Use code-based, model-based and human graders; grade what was produced, not the path; read transcripts; swap order; avoid same-model judging. | [Anthropic evals post](https://anthropic.com/engineering/demystifying-evals-for-ai-agents) (primary, fetched: three grader types, outcome over path, transcript reading, pass@k vs pass^k); [LLM-judge survey](https://arxiv.org/pdf/2411.15594) (primary, excerpt) |
| Independent challenge | A second reader attacks the first reader's conclusions without seeing them. | Skill mechanisms: sibling-blind discovery passes (`SKILL.md:46-47`) and inspection of an Architecture Decision Pack's independent-challenge evidence under `review_intensive` (`SKILL.md:62-63`, `review-checklists.md:111`; read locally). Gap: nothing challenges a review verdict itself. Not assessed further; no external source gathered |
| False-positive control | Report only findings with a real input, location and impact; expect many tool warnings to be ignored by developers. | [Yedida et al., arXiv 2205.10504](https://arxiv.org/pdf/2205.10504): cites 35% to 91% of tool-reported warnings ignored in earlier work (primary, excerpt). No study of code-review-comment usefulness was found |
| Severity calibration | Keep severity stable across rounds and tied to impact. | No code-review-specific source found. In-repo evidence only: `references/review-rubric.md:103-109` (stable standards, read locally) and the reviewer agent's data-loss rule (`agents/claude/code-reviewer.md:43`, read locally) |
| Shell and installer static checks | Run a linter for portability and subtle shell errors; check idempotency. | ShellCheck docs (primary, not retrieved); idempotency guides (secondary, excerpt) |

## Technique catalog by artifact

Each row lists checks that find real problems, beyond "does it read well".

| Artifact | Checks | Source (type, how seen) |
| --- | --- | --- |
| Specification / requirements | Per requirement: unambiguous, verifiable, singular, complete. Per set: consistent, no missing cases. Read as tester, developer and user. | ISO/IEC/IEEE 29148 not retrieved. [arXiv 1611.08847](https://arxiv.org/abs/1611.08847) (requirements smells, fetched; abstract page only) does not mention the standard on that page; it is a related method, not a source for the list |
| Jira ticket / user story | INVEST, testable acceptance criteria, linked dependencies, definition of ready. | Team DoR templates (secondary, excerpt) |
| Refinement / intent | Example Mapping: story, rules, examples, open questions. Many open questions mean the story is not ready; a vague story can end the session early. | [Cucumber Example Mapping docs](https://www.cucumber.io/docs/bdd/example-mapping) (primary, excerpt); sources disagree on the 25 vs 30 minute time-box |
| Plan | Pre-mortem; trace each step to a requirement and each requirement to a step; name rollback and verification per step; flag steps with no owner or oracle. | Klein, HBR 2007 (primary, not retrieved); NASA SWE-059 (primary, fetched); the rollback and owner checks are composed |
| Plan versus code | Trace both ways. Unplanned behavior is an orphan to review; planned item with no code or test is a gap. | NASA SWE-059 (fetched) |
| Documentation | Classify each page as tutorial, how-to, reference or explanation and flag mixing. Run the commands and check every path, flag and version. | [Diataxis via Canonical](https://canonical.com/blog/diataxis-a-new-foundation-for-canonical-documentation) (secondary, excerpt); the "run the commands" step is practice, not sourced |
| Code change, general | Design first, then functionality including edge cases and concurrency (these two seen only in a search excerpt of the guide), complexity, tests, naming, comments, documentation. | [Google eng-practices, review index](https://google.github.io/eng-practices/review/) (primary, fetched: design, functionality, complexity, tests, naming, comments, style, documentation) |
| Code change, approval bar | Approve once the change clearly improves overall code health, even if imperfect; mark optional points as nits. | [Google reviewer standard](https://google.github.io/eng-practices/review/reviewer/standard.html) (primary, fetched) |
| Code change, security | Entry point analysis, input validation, file operations and path handling, data-flow tracing from source to sink. | [OWASP Secure Code Review Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secure_Code_Review_Cheat_Sheet.html) (primary, fetched) |
| C# change | Async: `async void`, sync-over-async, cancellation tokens passed through the call chain, `ConfigureAwait` in library code, two queries on one EF Core context under `Task.WhenAll`. | [Microsoft TAP docs](https://learn.microsoft.com/en-us/dotnet/standard/asynchronous-programming-patterns/consuming-the-task-based-asynchronous-pattern) (primary; page fetched and mentions CancellationToken and ConfigureAwait, but the specific guidance sentences were seen only in a search excerpt: excerpt) for cancellation and ConfigureAwait; the `async void` and EF Core points come from blogs (secondary, excerpt) |
| C# change, not yet sourced | Nullable reference types and the `!` operator; `IDisposable` / `IAsyncDisposable` ownership; LINQ multiple enumeration; DI lifetimes and captive dependencies; analyzer and warnings-as-errors evidence. | not retrieved (no authoritative page). Fetch Microsoft Learn before writing these into a checklist. The repo's `tools/cognitive-complexity/` is available as an evidence tool |
| Script that edits user-owned files | Not found as a named technique. Combine: input hostile to the parser (unbalanced, nested, duplicate markers), file mode and ownership, atomic write, idempotency, dry-run, failure partway, parity with sibling implementations and with other implementations of the same operation in the same repo. | Composed (from ShellCheck, idempotency guides and hazard analysis); not sourced as a unit |
| Unit and focused tests | Can this test fail for the right reason? Flag assertion-free, tautological, status-only, over-mocked, conditional, disabled, order-dependent tests. Run mutants against the changed lines. | Test-smell catalogs (secondary, excerpt; testsmells.org not retrieved); Google mutation publication page (fetched) |
| Test cases and test design | Equivalence partitions, boundary values, decision tables, state transitions. | [ISTQB CTAL-TA syllabus](https://www.istqb.org/wp-content/uploads/2024/11/ISTQB_CTAL-TA_Syllabus_v3.1.2.pdf) (primary, excerpt: table of contents only) |
| Hostile / adversarial tests | Malformed, duplicated, nested, oversized, concurrent and hostile-permission inputs; injected faults. | Composed; chaos and fault-injection sources not retrieved |
| Happy path / broad / E2E | Confirm they exist, but check that failure paths and oracles are covered; a passing broad suite proves little about edges. | Practice (no source retrieved) |
| Exploratory / QA | Use oracle heuristics and a variation catalog (structure, function, data, interfaces, platform, operations, time). | HICCUPPS (see above); SFDIPOT not verified (not retrieved) |
| UI test | Automated scan plus manual; one secondary source says 8 of the 9 new WCAG 2.2 criteria need human checks. Keyboard, focus, target size, authentication flows. | WCAG 2.2 summaries (secondary, excerpt); visual regression not covered |
| Game | Functional, compatibility matrix, performance, soak (leaks), multiplayer, platform compliance (suspend/resume, controller disconnect, storage). | Vendor blogs only (secondary, excerpt) |
| AI / LLM feature | Combine grader types; test prompt injection including indirect injection through retrieved content; require approval for high-risk actions. | Anthropic evals (fetched); OWASP LLM Top 10 2025 summaries (secondary, excerpt) |
| Skill / prompt | Description is the trigger: test activation with and without the skill; keep `SKILL.md` lean; behavioral evals instead of unit tests. Owned by assistant-skill-creator (user decision). Mechanically enforced by `tools/skills/validate-skills.sh` and `tools/skills/lib/validate-contracts.sh` and `tools/skills/lib/validate-frontmatter.sh` (read by review passes, ranges re-checked by later passes): frontmatter and structure, name and description length and the retired `effort` and `triggers` keys (frontmatter library), contract headers, field-type whitelist, `enum_values`, `on_missing` on top-level required input fields (`input.yaml` only, not conditional or nested fields; handoff `context_fields` are not checked, so a reviewer must), `on_fail` or `validation` on required output artifacts, activation-case shape (two distinct positives, one disjoint nearby negative) through the fixture validator `tools/evals/lib/skill-eval-fixtures.sh:885-909` run by `run-skill-evals.sh --validate-fixture` (`docs/skill-contract-design-guide.md:184`), index selectors and word budgets (for skills with a contract index). Reviewer judgment, from `docs/skill-contract-design-guide.md`: expert-judgment guidance needs cue-to-method decisions derived from representative expert cases or an authoritative method (`:14-22`; the creator routes this through `expert_method_design`, `skills/assistant-skill-creator/SKILL.md:70-76`); continuing with `docs/skill-contract-design-guide.md`: name the consumer and the failure a contract prevents before adding it (`:24-33`); removing or weakening required fields needs a major `schema_version` bump, a `SKILL.md` migration note and updated consumers, evals and mirrors (`:110-114`); check the generated skill-local guide copy with `sync-skill-contract-guide.sh --check` (`:3-5`); source checks do not prove activation or quality and substring grading is heuristic (`:187-197`); named semantic types (`:131-137`). Activation review has an existing runner: `tools/evals/run-skill-evals.sh --activation-results FILE` (`docs/skill-contract-design-guide.md:195`). The creator already has a skill design checklist, `skills/assistant-skill-creator/references/contract-design-checklist.md:1-27` (lines 24-27 hold the versioning and migration paragraph) (`skills/assistant-skill-creator/SKILL.md:50` says only "use it for the changed boundary" and names no operation; the `validation` load set, `skills/assistant-skill-creator/contracts/index.yaml:113-122`, lists it, but no instruction selects that set; it asks whether handoff fields match their consumer, which covers the handoff `context_fields` gap above, and separates structural validity from activation evidence). Review questions: does the description trigger on the right requests and not near misses; does the body contradict the description; is every instruction testable by an eval; do reference files duplicate an authority | [Destefanis, arXiv 2607.25032](https://arxiv.org/abs/2607.25032) (primary, fetched title and abstract); guide lines above read locally (cited ranges only); validator facts read locally by review passes; the Anthropic skill-authoring page was not retrieved |
| Presentation | Not researched. | none (not researched) |

## Gap analysis against assistant-review

Review modes and rules the skill runs, which every proposal must fit (from `SKILL.md`,
`review-loop.md`, `qa-evaluation-loop.md`, `change-impact.md`, `operating-guidance.md`,
`CLAUDE.md`). A bare `:N` continues the last file named in the same sentence or cell; where a gap-table cell names no file it means `references/review-checklists.md`.

- **Audit**: one read-only batch, no fixes.
- **Review-fix**: Spec PASS before quality review, authorized fixes, validation, then a fresh
  complete batch. Standalone review-fix retains mandatory build and tests
  (`review-loop.md:16`, `review-loop.md:38`).
- **Workflow-composed**: consumes current Spec Review result (`spec_review_pass_ref`) and due-check evidence; verification goes
  through `F_REVIEW_VERIFICATION_SELECTION` before mutation (`SKILL.md:64-67`).
- **QA lane**: separate. Product, UX, docs, DX or domain issues only when scoped by acceptance
  criteria, Done Contract, `domain_context` or `rubric_refs` (`qa-evaluation-loop.md:98`).
  Generic code, security and test-coverage gaps stay with the code reviewer unless they directly
  cause an acceptance failure (`qa-evaluation-loop.md:100`).
- **Change-impact projection**: kept outside the reviewer bundle (`change-impact.md:5-7`).
- **Stopping**: the shared stagnation guard and the audit one-batch stop (`SKILL.md:87-94`).
  No proposal below changes either.
- **Extra testing**: additional tests need a distinct important uncovered failure and an
  inadequate-existing-evidence rationale, and material expansion returns to selection or approval
  (`SKILL.md:16-20`).
- **Approval boundaries**: external scans, reviews and installs retain explicit approval
  (`SKILL.md:30-31`); the repository says not to weaken permission prompts or
  destructive-operation safeguards (`CLAUDE.md`, "Codex execution policy rules").
- **Reviewer-context budget**: SKILL plus index plus the selected bundle and its declared
  worst-case reference closure must stay strictly below 5653 words (`contracts/handoffs.yaml:80`,
  `contracts/index.yaml:85`; enforced by `tests/p0-p4/review-round1-regressions.sh`). A reference
  that loads only conditionally still counts at worst case.

| Technique | What the skill has today | Remaining gap |
| --- | --- | --- |
| Checklists | Agentic loop safety, behavioral contract, semantic contract, Architecture Decision Pack checklists. Docs, UI and DX have rubrics in `references/domain-rubrics.md`, but they run in the QA lane only when scoped | No code-review checklist for spec, ticket, plan or plan versus code; docs and UI quality is reachable only through scoped QA |
| Understanding first | "Identify the existing behavior, invariants..." (`review-checklists.md:51-53`) and the Design Coherence Pass for medium+ | Partial; no standing "state intent and invariants" step for non-code artifacts |
| Distinct pass lenses | Pass perspectives exist as enum values assigned by batch size (`review-batch.md:6`; `contracts/handoffs.yaml:272,279,286`): `contract_and_test_oracle` and `runtime_lifecycle_and_failure_paths` for trivial and small, plus `integration_compatibility_and_consumers` at medium, plus `architecture_maintainability_and_reuse` at large. Security and closure passes are additive (`review-loop.md:24`). No prose file defines what each lens must check; each expected pass carries explicit `coverage_obligations` (`handoffs.yaml:319-323`), and the required coverage tuples combine them with the scope manifest's concerns (`handoffs.yaml:333-334`) | No defined obligation covers hostile input to scripts, user-owned state, or behavioral parity. Adding one means a rule for how passes are planned, filling each pass's `coverage_obligations`, with the method text in reviewer-bundle files (5653 budget) and the planning rule in orchestrator files (5000 first-review boundary) |
| Mirror and parity | "Mirror surfaces" (`review-checklists.md:57`, `:99`), "Runtime surface sync" (`:70`), and installer/global-instruction template sync (`:100`); an independent capability and reuse search in every review (`review-principles.md:29-30`, `review-loop.md:26`) | Template sync is covered. Behavioral parity is not: `install.ps1` guards marker balance (`Test-InstructionMarkerState`, `install.ps1:2196`, present since commit e7e1539, before PR 77) and `install.sh` did not. Also not covered: parity with the same operation elsewhere in one file (`install.sh:620` preserves mode with `os.chmod`; `install.sh:339-349` has `metadata_preserving_temp`; the temp-file-and-move rewrites at `install.sh:1106-1107` and `install.sh:1111-1112` used neither). Test-suite parity is a further probe: `tests/windows/installer-contracts.ps1:2033-2045` already has an unbalanced-markers contract (fixture: user text before the start marker and `CUSTOM AFTER MUST SURVIVE` after it), and `tests/p0-p4/installer-contracts.sh:654-661` asserts mode 600 on `config.toml`; at 673eb6e no bash test covers an unbalanced `ASSISTANT_FRAMEWORK_AGENTS_MD` start marker (HEAD has one: `tests/p0-p4/installer-contracts.sh:971-986`, a reusable fixture) (`tests/p0-p4/windows-installer-contracts.sh:86` only checks the PowerShell suite); the bash suite does cover an interrupted retired memory-protocol marker (`tests/p0-p4/installer-contracts.sh:392-427`), a fixture pattern to reuse. Further parity route for the mode defect: `install.ps1` writes instruction files through `Write-AtomicText` (`install.ps1:2285` at 673eb6e, in `Update-AgentInstructions`) and its Windows suite pins DACL preservation on replace (`tests/windows/installer-contracts.ps1:720` and `:1104`, at 673eb6e) |
| Side effects on user-owned state | `review-checklists.md:53` names idempotency and cleanup as bypass checks; `:68` requires rollback and failure-mode handling for deletion and irreversible actions | No hit for file mode, permissions on disk or marker parsing in the review checklists. Nearby coverage and routes: `lifecycle-verification.md:24` (work then cleanup failure), `:26` (cleanup retry) and `:28` (atomic publication) in the lifecycle bundle, plus idempotency and failure handling as general guardrails; dry-run is already required as a high-impact guard (`review-checklists.md:68`); the workflow Config/Infra gate pack mentions dry-run and smoke (`skills/assistant-workflow/references/triage-rubric.md:124-125`, consult only) and `skills/assistant-security/prompts/threat-model.md:73` covers path traversal for hostile path inputs (R2; assistant-security declares no `requires`), and the security specialist pass already applies the assistant-security checklist when triggered (`handoffs.yaml:304`, `review-loop.md:27`; `skills/assistant-security/SKILL.md:24` lists file paths) but nothing ties file rewrites to its trigger. Existing fixtures to reuse: `tests/windows/installer-contracts.ps1:2048-2100` (marker prose and interleaved blocks preserved, at 673eb6e), `:2102` (dry-run is byte-for-byte non-mutating) and HEAD `tests/p0-p4/installer-contracts.sh:988` (CLAUDE.md file-mode preservation) and `:1003` (read-only and symlinked CLAUDE.md); `skills/assistant-docs/SKILL.md:27` (verify documented commands, R2, assistant-docs declares no `requires`) for the Documentation row; and `skills/assistant-workflow/references/triage-rubric.md:128-129` and `skills/assistant-workflow/SKILL.md:101-102` are existing security-review trigger lists that mention persistence, shell calls and config changes (consult only) |
| Baseline change | "including outside-diff consumers" (`SKILL.md:13-15`). The change-impact checker records the union of base and candidate edges with presence `base`, `candidate` or `both` (`tools/change-impact/README.md:73-81`), so candidate-only edges are captured when it runs (shared, unresolved or carried work, `change-impact.md:11-13`) | Partial. No always-on reviewer question asks what the change newly touches. Proposed: reuse the `presence: candidate` notion rather than inventing a parallel one. Note: `tools/change-impact` was outside the first grep scope |
| Execute the change | After a fix, due selected checks and tests run (`SKILL.md:68-70`) | No step to run a changed script with hostile input |
| Test-suite review | "Ask whether a fake or incomplete implementation could still pass the tests" (`review-checklists.md:60-61`); evals must fail on incomplete responses (`:87-89`); `review-rubric.md:76`; the `contract_and_test_oracle` lens | No named test-smell list; no running of real mutants. Reuse routes (workflow items consult only, verification and ci-audit items R2): `skills/assistant-workflow/references/prompts/pr-review.md:81-88` (R1 candidate) (can the tests fail, order dependence); `skills/assistant-verification/references/methods/property-and-mutation.md:11` defines a mutation method; `skills/assistant-verification/references/methods/performance-and-resilience.md:11` defines bounded, reversible fault injection; `skills/assistant-ci-audit/SKILL.md:38-44` covers brittle and duplicate tests and isolated fault probes. More reuse routes (tagged individually; none is a pointer): `skills/assistant-verification/references/evidence-quality.md:7` (R2; the oracle must fail for a plausible wrong outcome; phrase match and file existence are not proof), `skills/assistant-workflow/references/prompts/test-strategy.md:32` (consult only: authoring text; name a plausible wrong outcome) and `:67` (mock at boundaries, the over-mocking smell), `skills/assistant-tdd/contracts/phase-gates.yaml:29` (consult only: a gate line inside a consumed contract; failed for the right reason) |
| Traceability | Spec PASS before quality review (`SKILL.md:54`) | Standalone review only: no backward trace. Workflow-composed review already consumes a Spec PASS whose Spec Review flags extra scope (`skills/assistant-workflow/references/prompts/spec-review.md:20,36`), and `skills/assistant-workflow/references/prompts/pr-review.md:45-47` (R1) asks for plan steps not implemented and code not in the plan |
| Hazard / pre-mortem | No hit for pre-mortem or hazard analysis. Near ground: failure-mode handling (`review-checklists.md:68`) and the `runtime_lifecycle_and_failure_paths` lens | No explicit pre-mortem step for plans. Reuse route (R2): `skills/assistant-thinking/perspectives.md:19` (the Skeptic role: what breaks, edge cases, failure modes) |
| AI and skill evals | Eval coverage inheritance (`review-checklists.md:87-89`, `review-checklists.md:102`), which stays for skill changes reviewed inside a code review | Skill activation review is out of scope for assistant-review: it belongs to assistant-skill-creator (proposals 4b and 4c). Shape example only, not a reference (the creator does not require assistant-review): `activation_cases` in `skills/assistant-review/evals/cases.json:10`. Existing tooling: the fixture validator `tools/evals/lib/skill-eval-fixtures.sh:885-909` and `tools/evals/run-skill-evals.sh --activation-results`, which only checks captured selections and needs an observed host run (`docs/skill-contract-design-guide.md:192-195`) |
| False-positive control and severity | Findings require real input, evidence, impact and calibrated confidence (`SKILL.md:14-15`); stable severity (`review-rubric.md:103-109`) | New probes proposed below must report through this same bar; see the Findings bar note |
| C# specifics | A C# cognitive-complexity gate (`contracts/phase-gates.yaml:297-299`) and an optional `project_type` dispatch field described as enabling language-specific checks, though no reference consumes it (`contracts/handoffs.yaml:633`); nullable and enum modeling (`review-principles.md:38-48`); disposal ownership and cancellation checks inside the Architecture Decision Pack checklist (`review-checklists.md:114`, `:119`), which apply only when a Pack is carried | No dedicated C# defect checklist (nullable, disposal, DI, LINQ); partial checks exist in `skills/assistant-workflow/references/prompts/pr-review.md` (`:123` sync-over-async is an R1 candidate; `:98-117` complexity threshold is consult only, procedure to reconcile per the C# placement row); sources still to fetch (see C# rows above). Proposed: build on the existing `V3` gate and `project_type` field |

### PR 77 replayed against this table

- Finding 1 (an unbalanced start marker deletes the user's later content): static reading of
  `sed -i.bak "/START/,/END/d"` at `install.sh:1103` against the unbalanced-marker probe in
  proposal 1 catches it at every batch size without running anything. Parity with `install.ps1`
  (which already guards marker balance) is a second route through sibling-implementation parity (the integration lens at medium and larger batches). Same-file parity does not apply to this finding, because `install.sh` has no balance guard elsewhere in the file; the widened reuse search (proposal 2) also runs in every pass at every size
  (`review-loop.md:26`, `reuse_search` required on every return).
- Finding 2 (file mode 0600 becomes 0644): the rewrites at `install.sh:1106-1107` (reinstall) and `install.sh:1111-1112` (prepend) write a fresh
  temp file and move it over the original. A same-file consistency question ("how does this
  script already preserve mode?") finds `install.sh:620` and `install.sh:339-349`, through proposals 1 (file-mode probe), 2 and 3 at every size. The security specialist pass is only a conditional route: it runs when `security_specialist_triggered` is true, and `handoffs.yaml:288-290,304` defines no trigger criteria, so nothing ties file-permission changes to it. Verified at 673eb6e.
- The review finding wording "CLAUDE.md not updated in install script", quoted by the user at the start of this work, was not found in PR 77's description, reviews or inline comments.

## Mode placement for the proposed changes

Lens assignment is by batch size (see the lens row above). A triggered checklist loads at every
size when its dispatch boolean is true (`contracts/handoffs.yaml:54-64`). Obligations that must
apply to a small change therefore go in a small-batch lens or a triggered checklist.

| Proposed technique | Where it lives | Audit | Standalone review-fix | Workflow-composed |
| --- | --- | --- | --- | --- |
| State-mutation probes | Routing depends on how an installer change is classified, which is an inference: `contracts/input.yaml:371-375` maps generated instruction templates to `skill_or_workflow`, application source to `code`, and multiple categories to `mixed`, and does not name installer scripts. The Behavioral checklist loads for `code` or `mixed` changes that touch behavior-bearing surfaces, or on user request (`input.yaml:390`, `:393`); the Semantic checklist loads for `skill_or_workflow` and some `mixed` (`input.yaml:382`). Placing the probes in either checklist alone can leave them unloaded; writing them in both duplicates text in the 5653-word bundle and creates two authoritative copies (`review-principles.md:25,29`), and neither checklist has a reporting slot for them (Semantic: `mirror_surface_sync`, `handoffs.yaml:1020-1023`; Behavioral: `high_impact_operation_guards`, `handoffs.yaml:985-988`). Proposed: one new inferred flag ("the change rewrites user-owned files", `on_missing: infer`, `infer_from`) independent of `change_kind`, driving both the probe checklist and the matching `coverage_obligations`, with its own return field. Proposed `infer_from` cues: writes under `HOME` or an agent home; in-place edits (`sed -i`, rename or `mv` over an existing file, `>` onto an existing file; PowerShell `Set-Content` or `Move-Item`; .NET `File.WriteAllText`, `File.Move` or `File.Replace`); marker-delimited regions; false when the script only writes new files inside the repo or a temp directory it creates; set true when unsure, which deliberately deviates from the existing inference rules, which default to false or name specific false cases (`input.yaml:382` (general otherwise-false) and `input.yaml:393`, `input.yaml:403` (specific false cases)); the new handoff context field should keep `default: false` for dispatches that omit it (as at `handoffs.yaml:662` and `:669`), and the deviation must be recorded. Evals need to pin the flag, infer it, and include one non-mutating negative case | Static probes only (proposed) | Static first; fixture execution per the Approval note (proposed; explicit approval if not confirmed) | Static first; execution route is open work, see the Approval note |
| "What does this newly touch, and how does the repo do the same operation elsewhere" | Extend the independent capability and reuse search. Its scope is carried by the category list at `review-principles.md:29` and the instruction at `review-loop.md:26`, then by the instruction field `reuse_search_instruction` (`handoffs.yaml:50`, `handoffs.yaml:654-657`) and the return field `reuse_search`, described "for rule-like changes" (`handoffs.yaml:1092-1096`); the gate `RS_REUSE_SEARCH` (`phase-gates.yaml:154`) carries no scope. Widen all of those so a reviewer cannot return `not_applicable` for file-rewrite mechanics; a clean search is then recorded in `reuse_search`. Constraint: `tests/p0-p4/task-packet-contracts.sh:948-966` requires the reviewer `reuse_search` return schema to be identical to the CodeMapper, Architect, CodeWriter and BuilderTester boundaries in `skills/assistant-workflow/contracts/handoffs.yaml` (workflow scope wording: `skills/assistant-workflow/contracts/phase-gates.yaml:236-237`, `D_REUSE_SEARCH`), so only description and validation-text edits are free (the signature compares field names, nesting, type, required, condition, enum values and min items, `task-packet-contracts.sh:79-91`); any field or condition change must change all boundaries together. A formal change-impact capture exists only when the checker runs, for shared, unresolved or carried work (`change-impact.md:11-14`; edges carry `presence` of `base`, `candidate` or `both`, `tools/change-impact/README.md:73-81`) | Yes | Yes | Yes |
| Hostile-input, side-effect and parity obligations | One inferred flag (above) fills `coverage_obligations` for `runtime_lifecycle_and_failure_paths` (runs at every size): hostile input, user-owned state, and parity with other implementations of the same operation in the same file or script. Obligations about owned resources, cleanup or retry may also switch the pass to `lifecycle_reviewer_context` (`handoffs.yaml:68-70`), so both 5653-word reviewer sets must be measured. That bundle adds `skills/assistant-review/references/lifecycle-verification.md`, a generated copy: `docs/lifecycle-verification.md` is canonical and `tools/skills/sync-lifecycle-verification.sh --apply` writes copies into assistant-debugging, assistant-verification and assistant-review (`lifecycle-verification.md:3-5`), so editing the review copy fails the `--check` and editing the canonical file changes three skills and their budgets. Proposed: keep the probes in the new checklist and cross-reference `lifecycle-verification.md:24` (work then cleanup failure) and `lifecycle-verification.md:28` (atomic publication) instead of restating them. Once the flag fires, the obligations attach to every item the runtime pass covers (tests, docs, `install.ps1`), producing `inspected_no_risk` entries; the cost is real under the current contract. Required tuples are the cross product of the pass perspective, each assigned item, that item's `applicable_concerns` and every `coverage_obligation` of the pass (`handoffs.yaml:333-334`, `evals/cases.json:41-46`); obligations are not tied to concerns, so a dedicated concern on the file-rewriting items would add tuples, not remove them, and `E_CHANGE_IMPACT` (`phase-gates.yaml:47`) is a batch-level precedent, not an item-level one. Either accept the cost, or make an explicit contract change that binds obligations to concerns when deriving `required_coverage_tuples` (schema version bump; updated evals; `tests/p0-p4/assistant-review-reference-contracts.sh`; and every consumer that hard-codes the cross product or the tuple field: `tools/evals/lib/skill-eval-fixtures.sh:702-706`, `tools/evals/lib/skill-eval-grade.sh:496,507`, `required_coverage_tuples` in `contracts/output.yaml`, `tests/p0-p4/skill-eval-contracts.sh`, `skills/assistant-workflow/evals/cases.json` and `tests/p0-p4/lib/feature-preparation-response-fixtures.sh`). Sibling-implementation parity (for example `install.sh` against `install.ps1`) goes to `integration_compatibility_and_consumers` at medium and larger | Yes | Yes | Yes |
| Skill review checklist | Ownership by assistant-skill-creator is the user's decision; proposed: extend its existing `references/contract-design-checklist.md` and assess operation (ASSESS gates SA1-SA3, `skills/assistant-skill-creator/contracts/phase-gates.yaml:140-153`; loading mechanism: see 4b), leaving assistant-review's Semantic Contract checklist unchanged | n/a for assistant-review | n/a for assistant-review | n/a for assistant-review |
| Spec, plan and plan-versus-code checklists | Ownership by assistant-review is the user's decision for spec and plan; proposed: new on-demand references, reusing only the reviewer questions from workflow PR review (`pr-review.md:45-47`) under option (1) for plan-versus-code, with generic plan questions written as new assistant-review text (R1; the workflow already requires assistant-review), while the Spec Review protocol and the Requirement Acceptance Map stay workflow-owned and the plan-versus-code checklist consumes the current Spec Review result (`spec_review_pass_ref`; standalone review has no carried Spec PASS, `handoffs.yaml:130`) (plan-versus-code is a proposal, not a recorded decision). Traceability lives in these checklists, not in a lens. Code-review lane for correctness, completeness and traceability; QA lane only when acceptance criteria, a Done Contract or a rubric scope them (`qa-evaluation-loop.md:98`). See the non-code note | Yes | Yes, with the non-code note | Yes, with the non-code note |
| Jira ticket and refinement checklist | Ownership by assistant-review is the user's decision; proposed: a new on-demand reference that defines its boundary with workflow story preparation, `assistant-clarify` and `assistant-verification`, so native discovery does not pick the wrong skill. Trigger and `change_kind` handling are the non-code note's prerequisites | Yes | Review-fix returns proposed ticket text locally; any write-back to Jira keeps explicit approval (`SKILL.md:30-31`) | Same as standalone, with the non-code note |
| Test review checklist | Ownership of test review by assistant-review is the user's decision; proposed: limit it to tests in a change, add a new on-demand reference for tests in a change; ci-audit keeps suite maintenance, and any shared test-smell list needs option (2) (R2), because assistant-review may not point at ci-audit files and option (1) is unavailable (ci-audit does not require assistant-review); not the QA lane | Static (reading only; real mutants are a deferred gap) | Static (reading only) | Static (reading only) |
| C# checklist | Ownership by assistant-review is the user's decision; proposed: a new on-demand reference. Trigger: an entry input inferred from changed `*.cs` and `*.csproj` files, with `on_missing: infer` and `infer_from`, because `project_type` is an optional handoff string with no `on_missing` and is project-level, not diff-level (`handoffs.yaml:630-633`; the workflow's CodeMapper returns it as a required field, `skills/assistant-workflow/contracts/handoffs.yaml:227-231`), and gate `V3` runs only in review-fix (`contracts/phase-gates.yaml:280-299` of assistant-review); make `V3` consume that flag. Conditional on fetching Microsoft Learn sources first | Static reading only (proposed); the complexity tool is execution (`tools/cognitive-complexity/run-complexity.sh:60-76`, `CognitiveComplexity.csproj:14`) and, proposed, runs in audit only with explicit approval | Open item: the orchestrator runs the tool under `V3`, but `V3` is a VALIDATE_STEP exit assertion that runs only after fixes, so round-1 discovery never sees complexity results; either the orchestrator runs it before the batch and carries the result through a new dispatch field (`pre_batch_findings` is never dispatched to discovery passes, `handoffs.yaml:357-358`) or complexity is recorded as checked only after a fix; existing instructions to reconcile: `agents/codex/reviewer.toml:83` and `agents/codex/code-reviewer.toml:81` tell reviewers to run `run-complexity.sh --changed`, `agents/claude/reviewer.md:115-117` and `agents/claude/code-reviewer.md:114-115` route it to the orchestrator, `pr-review.md:98-111` marks it auto-run, and severity conflicts (`pr-review.md:109,116` must-fix, the reviewer agents SHOULD-FIX) | Same as standalone review-fix |
| PR 77 eval cases | `evals/cases.json`, using its existing fields (`seeded_defects`, `must_detect`, `detection_anchors`, `evidence_anchors`, `finding_markers`, `false_positive_markers`; text substrings, not semantic grading, `evals/cases.json:18`). Base fixture 1 on the existing Windows contract fixture (`tests/windows/installer-contracts.ps1:2033-2045`) and fixture 2 on a target file with mode 0600. Anchor on behavior ("unbalanced start marker deletes trailing user content", "0600 becomes 0644"), not working-tree line numbers. Set `acceptable_severities` and `false_positive_budget`: must-fix only for the data-loss case, since the reviewer agent already classes data-loss risk as MUST-FIX (`agents/claude/code-reviewer.md:43`) and the rubric caps the score for data loss (`review-rubric.md:129`); the file-mode case needs a severity decision with a rationale (it silently widens access to a user-authored file). Use the existing `small_base` template (`evals/cases.json:22-46`, two discovery passes) with `scope_size: small` for both PR 77 cases, so the small-batch routing is what is proved. Add cases that pin the new flag, leave it to inference, and include one non-mutating negative case, so the routing itself is tested; because the flag is independent of `change_kind`, `change_kind` is not what routes the probes | n/a | n/a | n/a |

The QA lane takes none of these: they are code-review-lane obligations, except documentation or
UX acceptance explicitly scoped by criteria. After a fix, any selected fixture execution is a due
check that re-runs against the new source before the fresh batch (`SKILL.md:68-70`).

Notes:

- **Approval.** The user's decision (below) is: a changed script that still works within its
  designed scope may run without approval; one that modifies directories or files beyond what it
  touched before needs approval. Read alone, that conflicts with `SKILL.md:30-31` (external scans, reviews and installs retain
  explicit approval) and, more directly, the repository rule not to weaken destructive-operation
  safeguards,
  because an installer's designed scope is the user's real home paths (`install.sh:1051-1055`).
  Proposals the user has not yet confirmed:
  - "Same write targets as before" is not a safety test. The PR 77 defect wrote only to a prior
    target (`install.sh:1103-1107`) and still deleted user content. Proposed narrowing: run
    without approval only inside a throwaway fixture, under these conditions:
    - Before running, the orchestrator lists every environment variable and path the changed
      script reads, and blocks if any path source cannot be overridden. A fixed variable list is
      not enough, because a change can add a new path source.
    - Overrides cover at least the variables the current installers and the repo's harnesses
      use. For the PowerShell installer: `USERPROFILE`, `HOME`, `CODEX_HOME`, `APPDATA`,
      `LOCALAPPDATA`, `XDG_CACHE_HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `DOTNET_CLI_HOME` and
      the `NUGET_*` cache variables, with `PATH` saved and restored rather than overridden
      (`tests/windows/installer-contracts.ps1:165-202`; `CODEX_HOME` override at
      `install.ps1:2458-2460`; home resolution at `install.ps1:2635-2636`). For `install.sh`:
      `HOME` and `CODEX_HOME` (`install.sh:779-781`), with the bash harness pattern of saving and
      unsetting ambient `CODEX_HOME` (`tests/p0-p4/lib/p0p4-harness.sh:24-31`).
    - Other path sources count too: the script's own directory (`install.sh:760` derives
      `FRAMEWORK_DIR` from `$0`; `install.ps1:2643` uses `$PSScriptRoot`), the current directory,
      argument-supplied paths, and temp directories (`TMPDIR`, `TEMP`, `TMP`). Run a copy of the
      framework tree (every `FRAMEWORK_DIR`-relative source the script reads, including `skills/`,
      `tools/`, `agents/`, `docs/`, `codex-rules/` and `hooks/scripts`; `install.sh:760-763` fails
      without `skills/`, and the other directories are skipped silently when absent, which would
      make the fixture test less than a real install) from inside the fixture, with the working directory and temp variables pointing
      into it, so a write relative to the checkout cannot reach the real working tree. The
      current installers were checked: their temp files are created next to their targets, and
      they run no git, shell-profile or package-manager writes.
    - Inputs are disposable, with a baseline, cleanup and hashes of the originals before and
      after (the pattern in `skills/assistant-ci-audit/SKILL.md:38-40`, which itself allows
      execution only with `local_diagnostics` and explicit local authority, `:37-38`). The hashes
      are detection evidence after the fact, not prevention, and cover only the files hashed.
    Overriding `HOME` alone is not enough, because `CODEX_HOME` takes precedence for the Codex
    agent home (`install.sh:779`, `install.ps1:2458-2460`); the test harnesses unset ambient
    `CODEX_HOME` for that reason (`tests/windows/installer-contracts.ps1:190`,
    `tests/p0-p4/lib/p0p4-harness.sh:27-31`). Anything on real user paths needs approval.
  - Who runs it: the orchestrator, since reviewer passes are read-only. Standalone review-fix:
    the fixture rule above applies if confirmed, otherwise explicit approval; an approved fixture
    run cannot simply join the standalone build and test evidence: `evidence_ref` there needs current passed evidence (`handoffs.yaml:147-148`), and a discovery run succeeds by failing. This route is open work too. Candidate slot for both modes: `pre_batch_findings` (`handoffs.yaml:353-363`, orchestrator-owned and merged at aggregation, `phase-gates.yaml:132`) needs a new `source_kind` value such as `fixture_execution`, because no existing kind fits (a fixture run is neither a Spec Review nor a review pass, and `review_pass` provenance must keep its pass-id namespace, `handoffs.yaml:388`; `source_pass_ids` is review_pass only, `output.yaml:476`); the value would have to be added to every contract, fixture validator, grader and test that enumerates `source_kind` or finding-id prefixes (grep for them), including `input.yaml:586`, `handoffs.yaml:614`, `output.yaml:469,533,1234`, `pre_batch_findings`, `tools/evals/lib/skill-eval-fixtures.sh:563,568-573`, `tools/evals/lib/skill-eval-grade.sh:552,556,560,696,710` and `tests/p0-p4/assistant-review-reference-contracts.sh:1070`, with a version bump and closure-normalization text; the post-fix passing re-run stays in `build_test_verification_ref`. The extra-testing rationale and any carried reduced-testing boundary
    (`SKILL.md:16-20`) apply to this route as well. Workflow-composed review: there is no
    existing admission point for discovery-time execution. `F_REVIEW_VERIFICATION_SELECTION` is a
    FIX_STEP entry check that applies only in review-fix mode and only when
    `review_preparation_mode == workflow_composed` (`phase-gates.yaml:239-251`), so it covers
    regression checks after a finding, not a run meant to find one. A route through
    `build_test_verification_ref` does not fit as written, because each due check there needs
    current passed evidence (`handoffs.yaml:142`, `handoffs.yaml:148`) and a discovery run
    succeeds by failing; it needs its own evidence slot that accepts failing results, or a
    contract change. Either way it must meet the extra-testing rationale in `SKILL.md:16-20`.
    This is open work.
  - Audit's read-only scope is existing policy (`tools/progress/operating-guidance.md:79-80`).
    Proposed, awaiting confirmation: treat fixture execution as not read-only, so audit stays
    static-only.
  - If the user does not confirm the narrowing, execution of changed scripts keeps explicit
    approval everywhere; no approval-free execution ships, and the static probes still do.
- **Non-code material.** The skill is described as reviewing code (`SKILL.md:3`), review-fix
  retains mandatory build and tests, and `change_kind` allows only code, docs, skill_or_workflow,
  config and mixed (`contracts/input.yaml:368`). Before the spec, plan and ticket checklists
  ship: define what Spec PASS and validation mean for document-only material (a re-read plus a
  consistency and traceability check); extend `change_kind` or add a trigger flag (with `on_missing: infer` and `infer_from`) for
  spec, plan and ticket material; and update the skill description and evals; and define `change_impact_applicability` for document-only material (for example not_applicable with a reason), which `E_CHANGE_IMPACT_APPLICABILITY` requires before dispatch and `F_CHANGE_IMPACT_APPLICABILITY` before any review-fix mutation (`contracts/phase-gates.yaml:42-44`, `:245-247`).
- **Expert-method rule.** The guide requires cue-to-method decisions in expert-judgment guidance to be derived from representative expert cases or an authoritative method (`docs/skill-contract-design-guide.md:14-22`). The probe list, the `infer_from` cues, proposal 3's obligation set and the per-artifact checklists are currently composed or excerpt-sourced, so label them provisional until derived through `skills/assistant-skill-creator/references/expert-method-design.md`.
- **Ownership (decided by the user on 2026-10-28).** Skill review is done by `assistant-skill-creator` (`skills/assistant-skill-creator/SKILL.md:3`); specification, plan, C#, test, Jira ticket and refinement review are done by
  `assistant-review`. Everything below the ownership itself is a proposal, including the use of the creator's assess operation (`skills/assistant-skill-creator/SKILL.md:30-31`). Check each against
  `review-principles.md:25,29` (no second authority):
  - Skill review: assistant-skill-creator already has a skill design checklist
    (`skills/assistant-skill-creator/references/contract-design-checklist.md:1-27` (lines 24-27 hold the versioning and migration paragraph)), assess phase
    gates SA1-SA3 (`skills/assistant-skill-creator/contracts/phase-gates.yaml:140-153`) and an
    assess eval that separates structural validity, activation evidence and outcome quality
    (`skills/assistant-skill-creator/evals/cases.json:439-511`). The `assessment_inputs` load set
    (`skills/assistant-skill-creator/contracts/index.yaml:30-37`) loads no reference, while the
    `validation` set (`index.yaml:113-122`) loads the checklist. So 4b is a gap statement
    against current assess, not a new checklist. The existing Semantic Contract checklist in
    assistant-review (`review-checklists.md:75-102`) already touches skills, contracts, evals and
    prompts; it stays as it is, and its overlap with assess needs a boundary statement. Open
    question: the creator's scope is "V1 skills" (`skills/assistant-skill-creator/SKILL.md:3`);
    whether the user's company skills use the V1 format is not established. If not, widen the
    creator description and its assess `activation_cases`, or mark the V1-only mechanical checks
    as conditional. Note that no assess or review activation case exists today: the creator's
    `evals/cases.json:10-23` has a create positive, an update positive and a "run the existing
    skill" negative, so nothing pins it activating on "review this skill"; add one under 4c.
  - Specification, plan, plan-versus-code, C#, test and ticket checklists are new assistant-review
    references (proposed). Reuse is constrained by how skills install: the validator rejects index
    references outside the skill root (`tools/skills/validate-skills.sh:449-455`),
    assistant-review declares no `requires` (`skills/assistant-review/SKILL.md:1-4`),
    assistant-workflow requires assistant-review (`skills/assistant-workflow/SKILL.md:4-7`), so
    review requiring workflow would be a cycle, `references/change-impact.md:12-13` deliberately
    avoids requiring workflow, and the guide says not to add dependencies just to consult another
    skill (`docs/skill-contract-design-guide.md:52-53`). So a reviewer-bundle pointer from
    assistant-review to a workflow, ci-audit, thinking or verification file would either escape
    the 5653 budget check or dangle after `install.sh --skill assistant-review`. Options: (1) move the check questions (only the reviewer questions, not the Requirement
    Acceptance Map or the Spec Review protocol, which stay workflow-owned) into assistant-review and
    make the workflow prompts point at them; this gives one authority, although the workflow-side pointer target is not counted in workflow's own load sets (the validator rejects references outside the skill root, `validate-skills.sh:449-455`; `triage-rubric.md` and `plan-template.md` are budgeted workflow references), so measure or accept that per moved asset; it is install-safe only where
    the source skill already requires assistant-review (assistant-workflow and assistant-debugging;
    assistant-ci-audit, assistant-thinking, assistant-verification and assistant-tdd declare no
    `requires`), and must update every test that references the affected workflow files. Those tests assert different things: `tests/p0-p4/spec-review-contracts.sh:7-33` pins the Spec Review protocol steps and output template (`spec-review.md:17-21,27-33`) and `tests/p0-p4/spec-review-contracts.sh:58-71` requires `pr-review.md` to contain `HAS_REMAINING_ITEMS`, so protocol text does not move; `tests/p0-p4/review-loop-cap-contracts.sh:32` and `tests/p0-p4/workflow-architecture-completion-contracts.sh:667` scan for stale terms with `pr-review.md` as a target; `tests/p0-p4/workflow-evidence-spine-contracts.sh:151-164`, `tests/p0-p4/workflow-architecture-completion-contracts.sh:289`, `tests/p0-p4/requirements-sufficiency-contracts.sh:12` and `tests/p0-p4/progressive-discovery-contracts.sh:1251,1355,3633` reference the Requirement Acceptance Map by path or variable, so the Map does not move; a grep of `tests/` finds no test pinning the `pr-review.md` question text itself. `skills/assistant-workflow/references/plans/medium.md` is a generated view of `plan-template.md:508-517` (same section in `plans/large.md:481-490`), kept in sync by `tools/skills/sync-workflow-references.py --check` (exercised in `tests/p0-p4/workflow-reference-loading-contracts.sh:18-24`), so a plan-review edit starts at `decomposition-plan-review.md` and `plan-template.md`, but these are consult only; (2) a canonical file plus
    generated skill-local copies checked by a sync `--check`, as `lifecycle-verification.md:3-5`
    does, the only option that puts content inside a budgeted bundle for sources without a
    `requires`; (3) a recorded `requires` decision , which only makes a pointer install-safe (a fourth route exists for framework-level files outside the skill root, such as `../../tools/progress/operating-guidance.md` at `skills/assistant-review/SKILL.md:10`, installed with `tools/` by `install.sh`; like option (3) it falls outside the budget check): the
    validator rejects any index reference outside the skill root even when `requires` exists
    (`tools/skills/validate-skills.sh:449-455`), so option (3) cannot place content in a budgeted
    reviewer bundle or creator load set without a validator change, and the guide forbids adding a
    dependency just to consult another skill (`docs/skill-contract-design-guide.md:52-53`). Pointers
    from assistant-review to other skills' files are excluded unless option (1), (2) or (3)
    applies; the same limit applies to assistant-skill-creator pointers into
    assistant-verification, which are install-safe (the creator requires it) but not budgeted.
    Reuse key used below: R1, R2, R3 mean options (1), (2), (3). R1 applies only to workflow text that is purely reviewer questions and not pinned by tests (candidates: `pr-review.md:45-47`, `:81-88` and `:123`, which are pure reviewer questions that no test pins); every other workflow route below is workflow-owned procedure, contract or authoring text and is "consult only" (no move, no pointer). For content loaded by reviewer passes or the creator's assess path from sources that do not require the consuming skill, only R2 is viable (R3 needs a validator change); a route tagged R2 is a canonical file plus generated copies, not a pointer. Assets and what they serve: `skills/assistant-workflow/references/prompts/spec-review.md:3,16-21` (protocol steps that the Spec PASS comes from, pinned by `tests/p0-p4/spec-review-contracts.sh:19-22`; nothing to move, so it is not an R1 reuse source and the plan-versus-code checklist consumes the current Spec Review result (`spec_review_pass_ref`; standalone review has no carried Spec PASS, `handoffs.yaml:130`) instead), `skills/assistant-workflow/references/prompts/pr-review.md:45-47` (R1; plan versus code),
    `skills/assistant-workflow/references/decomposition-plan-review.md:7-25` (consult only: workflow gate procedure for splitting work into packets, used by gate DC8 at `skills/assistant-workflow/contracts/phase-gates.yaml:304-306` and pinned by the workflow eval at `skills/assistant-workflow/evals/cases.json:3372-3406`; `plan-template.md:508-517` and the generated `plans/*.md` copies follow it; the generic plan questions in the checklist, such as trace, rollback, owner and oracle, and pre-mortem, are new assistant-review text)
    and `skills/assistant-workflow/references/requirement-acceptance-map.md:4-6` (stays workflow-owned; traceability
    spine). No dedicated in-repo asset reviews specification quality (ambiguity, verifiability), but partial workflow routes exist (both consult only): criteria must be "atomic, binary (pass/fail), and testable" (`skills/assistant-workflow/contracts/input.yaml:183` (a consumed contract, consult only)) and requirements sufficiency checks intent, conflicts, gaps and failure paths (`skills/assistant-workflow/references/phases.md:59-77`; consult only, because tests pin that text and `phases/discover.md:61` is a generated view of it). The catalog's specification row has no retrieved primary source, so the checklist combines those routes with external sources.
  - Test review: `assistant-ci-audit` already owns suite maintenance, brittle and duplicate tests
    (`skills/assistant-ci-audit/SKILL.md:3`, `:13-15` (its scope), `:16-18` (the boundary with other skills), `:41-44`; classification in
    `skills/assistant-ci-audit/references/test-maintenance.md:4-5,20-26`); assistant-review reviews
    the tests in a change. Proposed: a named test-smell list is a single file shared through option (2), a canonical file plus generated copies in both skills (option (3) cannot place content in a budgeted bundle); an assistant-review pointer to a ci-audit file is excluded. Further
    reuse routes: `skills/assistant-workflow/references/ai-usage-policy.md:42-47` (consult only; tautological or
    phrase-only assertions; targeted mutation for a concrete oracle concern),
    `skills/assistant-workflow/references/prompts/test-strategy.md:84` (consult only; no order dependence) and
    `skills/assistant-workflow/references/prompts/migration.md:48,121` (consult only; idempotency and safe
    re-run if interrupted). For C#: `skills/assistant-workflow/playbooks/dotnet-api.md:33-41`
    (consult only; DI and layer rules).
  - Ticket and refinement review: `assistant-workflow` covers feature, epic and story preparation
    (`skills/assistant-workflow/SKILL.md:3`), `assistant-clarify` structures unclear intent
    (`skills/assistant-clarify/SKILL.md:3`) and `assistant-verification` assesses evidence for
    non-code artifacts (`skills/assistant-verification/SKILL.md:3`); the new reference must state
    its boundary with each.
  - Routing boundary (proposed, see proposal 4c): update both skills' descriptions and the
    nearby-negative `activation_cases` so native discovery does not pick the wrong skill. An
    edit to assistant-review's `SKILL.md` description counts against all nine load sets, including
    change_impact at 2550.
- **Budget.** The validator gives every index load set the same base, `SKILL.md` plus
  `index.yaml`, and enforces each set's `budget_words` (`tools/skills/validate-skills.sh:412-414`,
  `:517-522`). Sets and limits: entry 5000, architecture_pack_input 3000, change_impact 2550,
  current_round 12000, selected_handoff 5000, reviewer_context 5653, lifecycle_reviewer_context
  5653 (the same three references plus `references/lifecycle-verification.md`,
  `index.yaml:86-98`; selected when assigned scope or coverage obligations affect lifecycle
  boundaries, `SKILL.md:47-48`, `handoffs.yaml:68-70`), return_validation 5000, completion 10000 (`index.yaml:28,36,50,64,73,85,98,107,116`). `index.yaml` edits (entry `names`, `reviewer_context.references`, `allowed_names`) count in that
  base too, so every new checklist adds words to all of them. A `SKILL.md` edit also counts
  against every set, including the smallest (change_impact, 2550). The 5653 figure is also pinned
  exactly by a test (`tests/p0-p4/review-round1-regressions.sh:145-160`). A separate first-review
  boundary is entry words plus `review-loop.md` and `review-batch.md`, below 5000
  (`review-round1-regressions.sh:118`, `:128`). Which sets a proposal touches: gates and
  invariants go to current_round; output artifacts and `allowed_names` to completion;
  `return_validation` text to return_validation; a bundle item to selected_handoff,
  reviewer_context and lifecycle_reviewer_context (which selects the same `fresh_reviewer_context`
  bundle, `index.yaml:93-97`); new entry fields to entry and the first-review boundary. The `review_batch`
  declaration is outside the reviewer bundle (`handoffs.yaml:72`), but each pass's
  `coverage_obligations` value is dispatched to the reviewer (`handoffs.yaml:50`, `:542-547`). A non-description `reuse_search`
  change also touches the assistant-workflow handoffs and phase-gates load sets. No
  current closure or headroom has been measured for any set; measure each one the proposal touches
  before editing.
- **Implementation prerequisites for any new checklist or trigger.** Mirror every location where
  an existing checklist flag appears. Found by grep for `behavioral_contract_review_required` and
  `behavioral_contract_checks`, plus the generic return-validation and output-artifact entries: the input flag with `on_missing: infer` and `infer_from`; the
  dispatch field list (`context_fields_from_dispatch`, `handoffs.yaml:50`) and the context field
  (`handoffs.yaml:666`); the index entry and entry-selector `names` (`index.yaml:27`); the
  `worker_references` condition, which lives in `handoffs.yaml:51-64`; the conditional return
  field (`handoffs.yaml:963-1023`); the output artifact (`output.yaml:1006,1035`) and completion
  `allowed_names` (`index.yaml:115`); `return_validation` (`handoffs.yaml:98`); the entry-resolution
  and per-checklist return gates (`phase-gates.yaml:52-53`, `:163-165`) and invariants INV7/INV8
  (`phase-gates.yaml:429-440`, `index.yaml:63`); input log comments (`input.yaml:750-753`,
  `:794-797`) and the output validation comment (`output.yaml:1269`); the reviewer agent prompts
  (`agents/claude/reviewer.md:38`, `agents/claude/code-reviewer.md:38`,
  `agents/codex/reviewer.toml:41`, `agents/codex/code-reviewer.toml:41`);
  `tests/p0-p4/assistant-review-reference-contracts.sh:1700-1701`; and an eval case asserting the flag's inference (the pattern at `evals/cases.json:1140-1153` covers inference only) and a new assertion for the conditional return field, which no existing case asserts. Leaving any item of this list out puts producer and consumer contracts out of step. Declaration of a new reference file has two layouts. Option 1 (must keep the pinned reference order, `tests/p0-p4/assistant-review-reference-contracts.sh:1985-2002`): declare it in
  `index.yaml` `load_sets.reviewer_context.references` (`index.yaml:75-78`) and in
  `lifecycle_reviewer_context.references` (`index.yaml:87-91`), because every reviewer reference
  already sits in the lifecycle set, with a `worker_references` condition in `handoffs.yaml`; the
  validator sums every declared reference in a set (`tools/skills/validate-skills.sh:439-448`), so
  all declared artifact references count at worst case toward both 5653 limits whether or not a
  pass loads them, and four or more new references plus the probe checklist may not fit. Option 2:
  the pattern `lifecycle-verification.md` uses, a superset set selected instead of
  `reviewer_context` (`lifecycle_reviewer_context` is the three base references plus one file under
  the same 5653 budget, `index.yaml:86-98`, `handoffs.yaml:68-70`). Costs: selection is either/or
  (`SKILL.md:46-49`, `review-loop.md:25`, wording pinned by
  `tests/p0-p4/assistant-review-reference-contracts.sh:1985-2002`, which requires the lifecycle references to equal the ordinary ones plus `lifecycle-verification.md` in that exact order, the exact condition string in `handoffs.yaml` and `review-loop.md`, and the phrase "condition worker references identically"), so a pass needing two optional artifacts or an
  artifact plus lifecycle needs a combination set or a rule that a pass loads at most one; and it
  edits `SKILL.md` (counts against all nine sets), `review-loop.md` (the 5000 first-review
  boundary), the closure gate RS2B (`phase-gates.yaml:119-121`, which gates only `reviewer_context`),
  the handoff condition and the regression test. Measure before choosing; an undeclared file would load for
  reviewers but escape the budget check.
- **Findings bar.** All new probes report through the existing evidence and severity bar (real
  input, location, impact, calibrated confidence). A hostile input outside the script's designed
  scope is a finding only with a concrete failure; otherwise it stays non-blocking.

## Proposed changes, in proposed order

1. Add the state-mutation probes (unbalanced, nested and duplicate markers, and the marker token inside user prose (match the full delimited marker line, `installer-contracts.sh:971-980` at HEAD); file mode and
   ownership; target is a symlink, hard link or junction (preserve or refuse, never silently replace; the `mv` rewrites at `install.sh:1106-1107` and `install.sh:1111-1112` replace a link with a regular file, and `tests/windows/installer-contracts.ps1` at 673eb6e already covers junction containment (`:2217`) and hard-link replacement (`:2358`) as contract categories); atomic write; idempotency; dry-run; failure partway) as one checklist behind a
   single inferred flag that does not depend on `change_kind`, with its own return field. The
   same flag fills the matching `coverage_obligations` (proposal 3). Static probes first. Provisional until derived through the expert-method route (see the Expert-method note).
2. Widen `reuse_search_instruction`, the `reuse_search` return field and its gate to name
   same-operation implementations (file rewrite, mode preservation, marker parsing), and ask what
   the change newly touches that it did not touch before. A clean search is recorded in
   `reuse_search`; a `presence: candidate` edge exists only when the change-impact checker runs.
3. Define a pass-planning rule filling `coverage_obligations` for `runtime_lifecycle_and_failure_paths` (hostile input,
   user-owned state, parity with other implementations of the same operation in the same file or
   script) so small batches (PR 77's batch size was not established here; this assumes it was small) run it (accepting the cross-product cost described in the placement table, or making the explicit contract change named there); add sibling-implementation parity (for example
   `install.sh` against `install.ps1`) to `integration_compatibility_and_consumers` for medium and
   larger batches.
4. Per-artifact checklists, each provisional until derived through the expert-method route.
   The user's order is specification, plan, skill, C#, then Jira ticket and
   refinement; test review was assigned later and its position is a proposal (last).
   4a, in assistant-review (ownership of specification, plan, C#, test and ticket and refinement review is the user's decision; plan-versus-code and everything else is proposed): new on-demand
   references for specification, plan and plan versus code, C# (after sourcing), Jira ticket and
   refinement, then test review, with the plan checklist including a pre-mortem step (a reuse route is `skills/assistant-thinking/perspectives.md:19`, the Skeptic role, which needs option (2) (R2) because assistant-thinking declares no `requires`), under the reuse constraints in the Ownership note (no assistant-review pointers to other skills' files); resolve the non-code review-fix semantics, trigger fields and the
   pointer-versus-move sub-question first.
   4b, in assistant-skill-creator (ownership is the user's decision, the rest is proposed): close
   the gaps against current assess by extending `contract-design-checklist.md` and loading it through an assess-scoped instruction in creator `SKILL.md` (the assess bullet at `:30-31`), because `SKILL.md:52-56` scopes index loading to structured operation and fixture consumers, `SKILL.md:61-62` says ordinary human-only assessments need no canonical envelope, and `SKILL.md:50` ties the checklist to "the changed boundary", which an assessment lacks; adding it to the existing `assessment_inputs` set (`skills/assistant-skill-creator/contracts/index.yaml:30-37`) is secondary, for structured consumers only and only if it fits the 1400 budget; do not reuse the `validation` set, because `validation` selects `validation_summary`, an authoring artifact required only for create and update (`skills/assistant-skill-creator/contracts/output.yaml:61-64`) that assess must not require (`skills/assistant-skill-creator/SKILL.md:30-31`, assess eval `skills/assistant-skill-creator/evals/cases.json:453,461-462`); add
   only the questions the checklist lacks; note that assess already keeps structural validity, invocation, native selection and post-activation behavior separate and reports unavailable telemetry as unavailable (`skills/assistant-skill-creator/SKILL.md:98-101` for the four-way split; the assess eval `skills/assistant-skill-creator/evals/cases.json:451,463` separates structural validity, activation evidence and outcome quality and fails unsupported activation claims), so do not restate it; settle the V1 versus
   company-skill scope question; measure that skill's load sets (entry 1500, assessment_inputs
   1400) and update its assess evals (`evals/cases.json:439-511` and the frozen-comparison case at `:683-751`) and fixtures. Budget statement: a creator `SKILL.md` or `index.yaml` edit counts against all 13 of its load sets (`skills/assistant-skill-creator/contracts/index.yaml:13-140`), extending `contract-design-checklist.md` grows its `validation` set (2500), and every closure must be measured before editing.
   4c: the routing boundary between assistant-review and assistant-skill-creator, including where the sentence about the Semantic-checklist overlap with assess goes (inside `review-checklists.md` it counts against both 5653 reviewer sets) and a boundary with `assistant-verification`, whose description claims to assess evidence sufficiency across code, skills and non-code artifacts (`skills/assistant-verification/SKILL.md:3`), for skill, specification and plan review; also the missing assess activation case and the ticket
   boundary with workflow, clarify and verification: description edits, `activation_cases`
   edits and a budget measurement for each edited skill.
5. Add PR 77's two Codex findings as eval cases as specified in the placement table.
6. Record the script-execution exception in `SKILL.md` after the user confirms the narrowing.

Deferred gaps without a proposal yet: running real mutants (reuse route `skills/assistant-verification/references/methods/property-and-mutation.md:11`, R2); an independent challenge of the review verdict itself (reuse route, R2: `assistant-thinking` defines an evidence-backed challenge with independent roles, `skills/assistant-thinking/stress-test.md:3-7`); a standing "state intent and invariants" step for non-code artifacts. Placement but not content is proposed for a named test-smell list (shared via R2 per the Ownership note) and an explicit pre-mortem step for plans (plan checklist in 4a as new text; assistant-thinking's Skeptic role is an optional R2 source).

Deferred by the user's decision: game, UI and presentation checklists. Also deferred (proposed; departs from the decided order): the C# checklist until Microsoft Learn sources are fetched.

## Decisions from the user (2026-10-28)

- Most-reviewed artifacts: specifications, plan documents, and C# code delivered by other
  developers. Second: Jira ticket descriptions, intent and specifications for refinement
  meetings. Write checklists in that order. Game, UI and presentation checklists are deferred.
- Added later the same day: the user develops AI skills for a company individually, so reviewing
  skills is also very important. Treat skill review as a top-priority artifact alongside
  specification, plan and C#; checklist order becomes specification, plan, skill, C#, then Jira ticket and refinement.
  Proposed, not decided: plan-versus-code as its own checklist and test review as the last item.
- Executing changed scripts during review: approval is conditional. If the changed script still
  works within its designed scope, it can run without approval. If it modifies directories or
  files beyond what it touched before, approval is required. The fixture-only narrowing, the
  orchestrator-as-runner rule, the standalone-approval route and the audit static-only rule in
  the Approval note are proposals awaiting the user's confirmation, not part of this decision. Proposed default, not part of the decision: if the narrowing is not confirmed, execution of changed scripts keeps explicit approval everywhere, which is stricter than the recorded decision.
- Ownership (later the same day): skill review is done by `assistant-skill-creator`;
  specification, plan, C#, test, Jira ticket and refinement review are done by `assistant-review`.
  The user gave ownership only; how each is built is proposed.

## Implementation status (2026-11-03)

Built in PRs 79 and 80 and the follow-up that carries this note: user-owned file rewrite probes (widened `behavioral_contract_review_required`, Behavioral checklist probe, reuse-search wording), a compact Document Review Checklist, a C# reference loaded only in `reviewer_context`, the skill-review route in `assistant-skill-creator` (assess), the fixture-only script-execution reference (a reference file; the `SKILL.md` edit in item 6 was not made, for budget reasons), and eval cases for each except the fixture-only execution exception. A document-only review needs no new `change_kind` value: `docs` already exists, and the standalone Spec Review gate already checks the user's request and review scope, so the eval `document-review-applies-spec-review-and-document-checklist` pins that behavior.

Not built, with the reason:

- **Typed evidence slot for discovery-run results.** A new `source_kind` touches the input, output and handoff contracts and every consumer, so it needs its own versioned change. Until then a discovery run is reported as an orchestrator-run probe (`references/script-execution.md`).
- **Deeper per-artifact checklists.** The sources for specification, plan and Jira review are mostly "not retrieved" above, and the repository rule requires an evidenced method before expert-judgment guidance grows.
- **Company-skill V1-format question.** Answered (most company skills are plain), built in PR 82: the creator reviews a plain `SKILL.md` alone.

Known limit: a pass that resolves `lifecycle_reviewer_context` on C# material does not load `references/csharp-review.md`, so it relies on `lifecycle-verification.md` and general judgment. The C# eval states this.

Word-count limits (load-set `budget_words`, the standing-guidance and first-review word ceilings, the specialist entry cap, and the eval-promotion word caps) were removed in PR 82. The budget reasoning in the sections above records the constraints that applied when the note was written.
