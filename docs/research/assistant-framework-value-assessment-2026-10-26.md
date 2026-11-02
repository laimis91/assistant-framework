# Assistant Framework: what to borrow, add, improve, and remove

Research date: 26 October 2026. Revised after comparison with the [Hermes assessment](/Users/laimis/Developer/Projects/Assistant/comparable-skills-review-2026-10-25.md) and the separate [project audit](/Users/laimis/Downloads/assistant-v1-project-audit.md). Scope: all 52 skills in the supplied Comparable skills directory and the 16 existing framework skills. This report recommends changes; it does not implement them. Audit-derived lessons are included below; concrete defect repairs remain separate-session work.

## Recommended direction

**Prioritize request alignment and focused answers while preserving broad analysis. Borrow six focused method packs, add all three proposed skills, retire Telos and the standalone Diagrams skill, and remove protocol detail from ordinary skill execution.**

The most useful distinction is between an execution rule and the practical method that makes it achievable. “Reproduce the bug” is a sound rule; a ladder of reproduction techniques helps an agent actually do it. “Observe meaningful RED” is a sound gate; a worked example helps it write a test worth keeping. Several comparators provide that missing practical detail.

Broad analysis remains valuable: it can expose hidden costs, alternatives, risks, and counterevidence that change a recommendation. The answer should lead with the decisions and deliverables the user requested, with supporting analysis placed where it helps assess them. The original report underweighted practical method gaps and let broader cost analysis dominate that presentation.

| Decision | Recommendation |
|---|---|
| High priority: request focus | Adapt **sdlc-review** for mapping the original request to delivered answers, and **claude-design** for making each section serve the user's outcome. Preserve broad investigation and material supporting evidence. |
| Improve existing skills | Add practical reproduction, TDD, review, test-value, security, and research methods through focused references. |
| Include concrete audit lessons | Strengthen existing Security, Verification, CI Audit, and Review examples with user-content preservation, failed-versus-empty discovery, and installed-layout/configured-home checks. Repair the underlying defects in the separate session. |
| Add three skills — user agreed | Create **assistant-spike**, **assistant-ui-qa**, and **assistant-advisory-triage**. Keep their methods task-specific; settle bundled/selective distribution in their specifications. |
| Retire Telos — user decided | Remove the framework skill completely, including owned release/install surfaces. The user reports never using it. Preserve any user-authored purpose files. |
| Retire standalone Diagrams — requested direction | Continue generating diagrams through general capabilities and existing documentation/preparation owners. Migrate any genuinely consumed accuracy/traceability obligations before removing the dedicated skill. |
| Further consolidation proposal | Consider merging Ideate's overlapping generation/ranking method into Thinking. This remains a recommendation to resolve in specification, rather than an additional user-approved removal. |
| Remove from ordinary loading | Detailed progress/admission wire rules, irrelevant legacy migration instructions, and unused review score bookkeeping. |
| Keep out of the core | Commodity cloud, Office, email, social, mapping, and creative tool integrations. Use specialist skills/providers when the actual task needs them. |

Expected value comes from fewer failed approaches, better tests and findings, and less repeated instruction work. These are source-backed design recommendations; their size and runtime benefits have not been measured in a new behavioral comparison.

The user's latest decisions supersede the earlier recommendation to retain Telos/Diagrams as optional surfaces. They settle product direction; framework edits and uninstall actions have not begun. The proposed specification set and concurrency boundaries are in the [specification index](/Users/laimis/Developer/Projects/Assistant/V1/docs/plans/framework-value-improvements/specification-index.md).

## High priority: broad analysis, focused answers

### sdlc-review: check the answer against the original request

**Priority: high.** Its [requested-versus-delivered comparison](</Users/laimis/Developer/Comparable skills/devops/sdlc-review/SKILL.md:89>) maps each acceptance criterion to concrete output evidence. Its [contract lens](</Users/laimis/Developer/Comparable skills/devops/sdlc-review/SKILL.md:67>) explicitly returns to the original task, exposing omissions, changed meaning, and unrelated scope.

**Adapt:** identify the user's requested decisions and deliverables before investigating; use them to organize the answer; compare the complete draft with the original request before delivery. For this report, the required answers are each skill's benefit, improvements to existing skills, worthwhile new capabilities, removal candidates, and their value relative to cost. A broad analysis of framework overhead cannot substitute for those answers.

**Where:** Research and Workflow guidance, and existing Review when review is already required. Borrow the method without importing Kanban tools, round-based scheduling, another mandatory reviewer, or a new task ledger.

### claude-design: make the presentation serve the user's outcome

**Priority: high.** Its [Content Discipline](</Users/laimis/Developer/Comparable skills/creative/claude-design/SKILL.md:397>) requires every element to earn its place and rejects filler. Adapting that design principle to research answers is a proposed transfer, rather than a claim that the original skill is a general research method.

**Adapt:** lead with the requested conclusions and recommendations. Give each major section a clear role in helping the user decide or act. Keep supporting evidence near the claim; place useful broader detail in supporting sections or an appendix. Remove repetition and tangents that do not change an answer, its rationale, or a consequential limit. Retain material uncertainty, counterevidence, and risks even when that requires a longer answer.

**Where:** Research and Docs output guidance, with a compact check in the existing common outcome guidance. Keep the reusable wording authoritative in one place; the full visual-design skill is unnecessary for this purpose.

**Combined method:** identify requested outcomes → investigate broadly where useful → present direct answers first → check coverage and relevance against the original request. The intended improvement is relevance and decision usefulness, not brevity by itself. Assess it with a broad-but-unfocused draft and a superficially concise draft that omits a requested answer; both should fail the check. No evidence establishes that Hermes used these skills or that this adaptation guarantees the same results.

## 1. Six concrete method packs to absorb

### A. Debugging: teach how to build a reproduction

**Sources:** [systematic-debugging](</Users/laimis/Developer/Comparable skills/software-development/systematic-debugging/SKILL.md>), [Python debugging](</Users/laimis/Developer/Comparable skills/software-development/python-debugpy/SKILL.md>), [Node debugging](</Users/laimis/Developer/Comparable skills/software-development/node-inspect-debugger/SKILL.md>).

**Current gap:** [assistant-debugging](/Users/laimis/Developer/Projects/Assistant/V1/skills/assistant-debugging/SKILL.md) says to run the smallest safe reproduction and distinguish causes. Its references do not teach a range of reproduction or state-inspection techniques.

**Add:** a feedback-loop playbook that selects among an existing failing test, CLI/HTTP probe, trace replay, small harness, controlled flaky reproduction, bisection, and differential comparison. Explain how to assert the exact symptom, reduce setup cost, control timing/randomness, and remove inputs one at a time while retaining failure. Add short debugger recipes for unresolved state questions.

**Value:** replaces speculative fixes and repeated logging with a reusable way to obtain discriminating evidence.

**Do not import:** a hypothesis quota, forced TDD for every repair, a three-total-attempt architecture escalation, weakening system-wide debugger protections, or unsupported success-rate claims.

**Smallest change:** proposed Debugging references for feedback loops and state inspection. A representative failure should become reproducible for the right reason; a nearby unrelated failure must not satisfy the same check.

### B. TDD: add craft examples alongside the gates

**Source:** [test-driven-development](</Users/laimis/Developer/Comparable skills/software-development/test-driven-development/SKILL.md>).

**Current gap:** [assistant-tdd](/Users/laimis/Developer/Projects/Assistant/V1/skills/assistant-tdd/SKILL.md) has detailed RED/GREEN/REFACTOR ownership and evidence gates. It lacks worked examples showing how to choose an observable behavior and avoid testing a mock's own implementation.

**Add:** one good/bad test pair, an intended versus wrong-reason RED example, and a short vertical behavior slice. Explain why tests asserting internal call shapes, subject-generated expected values, or mock-supplied behavior can pass without protecting the requirement.

**Value:** improves the quality of the test that enters the existing TDD cycle. The addition earns its cost if it prevents plausible but useless tests.

**Do not import:** universal TDD activation, one test per function, deletion of preexisting implementation, or mandatory broad-suite runs. Keep the framework's selected TDD scope.

**Smallest change:** a TDD craft reference used during test authoring or correction, without another phase or report.

### C. Review: add practical preflight and distinct inspection questions

**Sources:** [requesting-code-review](</Users/laimis/Developer/Comparable skills/software-development/requesting-code-review/SKILL.md>), [simplify-code](</Users/laimis/Developer/Comparable skills/software-development/simplify-code/SKILL.md>), [sdlc-review](</Users/laimis/Developer/Comparable skills/devops/sdlc-review/SKILL.md>).

**Current coverage:** [review-batch](/Users/laimis/Developer/Projects/Assistant/V1/skills/assistant-review/references/review-batch.md) already requires independent narrow passes. [Review principles](/Users/laimis/Developer/Projects/Assistant/V1/skills/assistant-review/references/review-principles.md) already cover reuse, simplicity, and design coherence. The gap is practical examples and verification recipes, not absence of review principles.

**Add:** concrete briefs leading with contract/test-oracle risk, execution/failure behavior, connected consumers, or ownership/reuse. Preserve original criteria and source access in each. Ask simplification findings to explain the actual cost and why the apparent workaround is not an intentional compatibility boundary. Supply a targeted preflight recipe for suspicious added lines and baseline-versus-new failures.

**Value:** less duplicated review attention and fewer low-value findings; cheaper detection of obvious mistakes before a full batch.

**Do not import:** a mandatory four-agent fanout, diff-only context, automatic stashing of the user's dirty checkout, fixed round-to-lens scheduling, or counting failures without comparing their identities and causes. Baseline failures remain visible; they are not automatically irrelevant.

**Smallest change:** review-lens examples plus an optional preflight reference. Evaluate whether they find a concrete defect or eliminate a known source of noisy findings.

### D. Test value: make the audit questions executable

**Source:** [test-audit](</Users/laimis/Developer/Comparable skills/test-audit/SKILL.md>), including its [audit checklist](</Users/laimis/Developer/Comparable skills/test-audit/references/audit.md>).

**Current coverage:** [test-maintenance.md](/Users/laimis/Developer/Projects/Assistant/V1/skills/assistant-ci-audit/references/test-maintenance.md) already covers retained protection, duplicates, internal coupling, baseline failures, and measured cost. A second audit skill is unnecessary.

**Add:** the four authoring questions: what observable contract is protected; which credible regression fails; why existing proof misses it; and whether the test needs a production seam with no real caller. Add examples of fabricated receipts, wrong-guard negative tests, self-comparisons, and mocks supplying the asserted behavior. Show an owner-level cleanup example identifying the remaining proof before deletion.

**Value:** helps the agent distinguish an expensive weak test from an important exact-byte, platform, or protocol contract.

**Do not import:** a mandatory per-test campaign ledger, deletion counts, or blanket rejection of source checks. Exact prompt/schema/installer bytes can be legitimate independent contracts.

**Smallest change:** strengthen the existing maintenance reference; add campaign guidance only for an explicitly requested broad audit.

**Audit-backed example:** the project audit's F3 identifies a changed-file helper that suppresses Git discovery errors and then treats an empty file list as success. Use it to illustrate a wrong-outcome check: an invalid requested comparison must remain a failure, while a valid comparison with no relevant changes can be an ordinary empty result. This supplies a concrete example for Verification/CI Audit without another generic checklist. [Discovery code](/Users/laimis/Developer/Projects/Assistant/V1/tools/cognitive-complexity/run-complexity.sh:82).

### E. Security: add boundary-oriented depth selected by the target

**Sources:** [security-audit](</Users/laimis/Developer/Comparable skills/security-audit/SKILL.md>), particularly [AI/agent methods](</Users/laimis/Developer/Comparable skills/security-audit/AI-AND-LLM.md>).

**Current gap:** [assistant-security](/Users/laimis/Developer/Projects/Assistant/V1/skills/assistant-security/SKILL.md) already requires reachable attack paths, evidence, and authorization. Its supporting material is comparatively generic and web-oriented.

**Add:** focused companions for agent/tool authority and durable context, installer/filesystem boundaries, and dependency/release provenance. Distinguish a confirmed boundary failure from a source-grounded hypothesis awaiting runtime/deployment validation. For a full audit, show how to record assessed versus blocked/excluded surfaces and check the resulting coverage claim.

**Value:** improves relevance to this framework's actual risks: external instructions, shell/path handling, installer ownership, delegated authority, and action approval across resume/retry.

**Do not import:** the comparator's entire hunter/critic/verifier controller or claim OS isolation that the host cannot enforce. Structured coverage and sandbox setup belong to a genuine audit consumer, not every security question.

**Smallest change:** relevant companion references first; an audit ledger/validator only when a defined report consumer needs it.

**Audit-backed examples:** F1/F2/F4/F5 supply actual framework boundaries for these references: malformed managed markers, linked destinations and legacy-hook entrypoints, unrelated files in shared installation roots, and overlapping source/destination paths. Preserve user-owned sentinels and unchanged originals as the observable outcomes. Reuse the existing Windows preservation/ownership precedents when applicable. The cited paths were inspected; no destructive fixture or installer reproduction was run here. [Unix instruction replacement](/Users/laimis/Developer/Projects/Assistant/V1/install.sh:1080), [shared-root synchronization](/Users/laimis/Developer/Projects/Assistant/V1/install.sh:894), [Windows ownership precedent](/Users/laimis/Developer/Projects/Assistant/V1/install.ps1:1364).

### F. Research: make provenance and retrieval failures practical

**Sources:** [grounded-citations](</Users/laimis/Developer/Comparable skills/research/grounded-citations/SKILL.md>), [blocked-page-recovery](</Users/laimis/Developer/Comparable skills/web/blocked-page-recovery/SKILL.md>).

**Current coverage:** [Research](/Users/laimis/Developer/Projects/Assistant/V1/skills/assistant-research/SKILL.md) already requires near-claim citations, source identity, conflicts, and evidence-calibrated conclusions. It lacks a comparable mechanical source ledger; [URL verification](/Users/laimis/Developer/Projects/Assistant/V1/skills/assistant-research/url-verify.md) gives little help after a failed fetch.

**Add:** retrieval-time source registration for substantial reports; preserved version/date and supporting locations; checks for unknown/mismatched citation IDs. Add a bounded recovery path with official alternatives, dated accessible snapshots, and rejection of error/interstitial bodies.

**Value:** reduces fabricated/misassigned references and repeated unsuccessful retrieval.

**Do not import:** mandatory numbered citations, per-sentence quotas, a global mutable ledger, new API-key requirements, or treating quote presence as proof of claim support. Preserve access restrictions and distinguish historical copies from current facts.

**Smallest change:** two focused references; adapt a helper only if repeated ledger errors justify maintaining it.

## 2. New skills worth creating

### Recommend: assistant-spike

The job is **answering a feasibility question through a disposable experiment before committing to production implementation**. Candidate Search compares approaches, but does not supply a complete lightweight experiment-and-verdict method. A dedicated trigger makes this distinct activity easier to request.

Its minimum method should be:

1. State the question, constraints, decisive observation, and failure condition.
2. Check whether source inspection alone can answer it; experiment only where execution adds evidence.
3. Build the smallest isolated disposable probe, testing the riskiest assumption first.
4. Run the decisive case and a relevant control or limit.
5. Return **validated, partial, or invalidated**, with evidence, limits, and the consequence for a real build.

Use one question when sufficient. No fixed 2–5-question decomposition, compulsory multi-step interview, or production-readiness claim. “Throwaway” never waives existing cost, permissions, sensitive-data, or plan-approval boundaries.

Start instruction-only, with no new controller or schema unless a real consumer requires one. The handoff to Workflow carries the finding and constraints; it does not authorize production changes. [Comparator](</Users/laimis/Developer/Comparable skills/software-development/spike/SKILL.md>), [existing Candidate Search](/Users/laimis/Developer/Projects/Assistant/V1/skills/assistant-workflow/references/candidate-search.md).

### Add: assistant-ui-qa

Create for projects that repeatedly ask for exploratory user-flow testing. Borrow valid/invalid/empty states, console diagnostics, screenshots, reproducible steps, severity, and tested/not-tested coverage from [dogfood](</Users/laimis/Developer/Comparable skills/software-development/dogfood/SKILL.md>).

The existing QA evaluator owns an acceptance verdict; this skill supplies the exploration method and evidence. Keep that ownership explicit. It should also support standalone “test this app” requests without requiring a production Build. Use the actual supported browser runtime and avoid checking/capturing every trivial interaction.

### Add: assistant-advisory-triage

Create for maintainers who handle advisories. Borrow trust-model-first analysis, shipped-tag verification, duplicate checks, and separation of hardening from a vulnerability in [security-triage](</Users/laimis/Developer/Comparable skills/security-triage/SKILL.md>).

The unique value is preventing premature closure because main is fixed while a shipped release remains affected. Remove OpenClaw-specific policy, named-maintainer workflow, clipboard actions, and model-routing instructions. Publication or closure still requires actual task authority.

Creation of all three skills is agreed. Their activation stays tied to the actual job; this does not require loading UI QA or advisory procedures for unrelated work. Define bundled/selective distribution explicitly in specification using supported installation mechanisms, without inventing another profile system.

## 3. What to remove or consolidate

| Surface | Recommended action | Result and boundary |
|---|---|---|
| Shared progress/admission wire documentation | Move detailed lineage, replay, grouped-member, compaction, and migration rules to a reference loaded by their consumers | Ordinary activities retain concise outcome/authority/evidence/stagnation guidance. Persisted/delegated consumers retain the full protocol. |
| Ideate versus Thinking creative/options methods | **Proposed consolidation into Thinking**, subject to specification, carrying Ideate's concise light mode, ranking, and activation examples | Check callers and migrate references; preserve useful behavior. The user has not separately decided to remove Ideate. |
| Telos | **Remove completely from the framework**, following the user's explicit decision and reported lack of use | Retire release/docs/evals and ownership-safe installed copies; preserve user-authored files and unrelated content. No Telos replacement is required. |
| Diagrams | **Retire the standalone framework skill**; use general diagram generation and existing Docs/Workflow ownership | Generating Mermaid does not require this skill. Its source-backed accuracy and structured preparation bindings are real obligations where consumed, so migrate or explicitly retire those consumers before deletion. No measured claim of zero benefit is made. |
| Review score bookkeeping | Remove from ordinary use where no consumer needs it; migrate required fields before retirement | Concrete findings, coverage, acceptance, and actual checks control completion. Diagnostic arithmetic should not manufacture work. |
| Legacy compatibility detail | Load only for the matching historical state; keep a canonical compatibility reference | New tasks avoid repeated migration prose; supported old records remain readable. |
| Repeated protocol descriptions in README and skills | Replace duplicate definitions with canonical links; keep short task-relevant explanations | Fewer places can drift, without turning every skill into a router. |
| New mandatory formatting rules | Do not add universal section/word-count/“Done when” quotas | Use completion cues and examples where they help the task. A heading count is not evidence of capability. |
| Duplicate commodity integrations | Keep provider/format/creative skills outside the framework core | Avoid parallel OAuth clients, API maintenance, render stacks, and unnecessary catalog growth. |

Thinking's existing reference named clarify.md is first-principles analysis; it should not be merged blindly with the prompt-clarification skill. Keep **assistant-clarify**, **assistant-onboard**, and **assistant-verification**: their user jobs remain distinct. Give Onboard an optional inventory recipe and Docs a concise editing checklist. When retiring Diagrams, keep source-backed claims in the owning documentation/preparation path rather than retaining the whole dedicated skill.

The source has documentation drift worth fixing. At HEAD, CLAUDE.md said v0.3.0 while [version.txt](/Users/laimis/Developer/Projects/Assistant/V1/version.txt) says 0.2.0; the uncommitted working tree already corrects [CLAUDE.md](/Users/laimis/Developer/Projects/Assistant/V1/CLAUDE.md:9) to 0.2.0, so that item needs only to land. README describes finite review rounds and tier/confidence research wording that differs from current roots. Workflow's root names v14 interfaces as authoritative while its contracts state that new producers write v15 and keep v14 as historical. These are documentation inconsistencies, not demonstrated runtime defects.

## 4. Order the work by useful outcomes

| Order | Change | Observable benefit to check |
|---|---|---|
| 1 — high priority | Adapt sdlc-review request coverage and claude-design content discipline | Every requested outcome receives a direct answer; broad investigation still informs the recommendations; material evidence and limits remain visible. |
| 2 | Split the common guide; correct stale canonical references | Less irrelevant instruction loading; ordinary tasks and persisted continuation preserve their required behavior. |
| 3 | Add reproduction and TDD craft references | An exact symptom can be reproduced; a useful regression test rejects the intended wrong behavior. |
| 4 | Add review examples and concrete test-audit examples | More relevant unique findings; fewer weak findings/tests; important existing protection remains. |
| 5 | Add assistant-spike, assistant-ui-qa, and assistant-advisory-triage | Each distinct job has a clear trigger, observable output, and appropriate existing-owner handoff. |
| 6 | Add selected security and research references/helpers | Important trust boundaries or source provenance are checked more accurately with less repeated work. |
| 7 | Retire Telos/Diagrams; resolve the proposed Ideate/Thinking consolidation | Removed skills leave no broken consumers or stale installer-owned copies; required diagram evidence still has an owner. |
| 8 | Reconsider installer consolidation separately | Share genuinely common definitions only where it simplifies maintenance without weakening platform-specific safeguards. |

Installer size alone does not establish that generating both installers is simpler. Likewise, a shorter skill is useful only if the task still gets a correct result. Make concrete changes with focused checks; reserve matched model evaluation for behavioral claims or material uncertainty.

Use existing evaluation and context tools. The current context reporter omits a separate body component for the common guide, so its reported total cannot alone prove the benefit of splitting that file. Do not make a new monitoring/reporting system a prerequisite to these improvements.

Prepare the full specification set before implementation so shared guidance, retirement, and new-skill boundaries agree. The [draft slice map](/Users/laimis/Developer/Projects/Assistant/V1/docs/plans/framework-value-improvements/specification-index.md) identifies independent method/skill work and shared integration ownership. Separate chats can share a checkout; concurrent implementation requires verified isolated worktrees and coordinated integration. No new chats have been created by this preparation.

### Additional audit findings: include the lessons, separate the repairs

The [project audit](/Users/laimis/Downloads/assistant-v1-project-audit.md) supports the existing method recommendations with concrete producer/consumer failure paths. Include these three lessons:

| Lesson to include | Existing owner | Practical benefit |
|---|---|---|
| Check ownership and preservation at every affected installation boundary, including markers, links, shared roots, and path overlap | Security and Review; Verification selects the preservation checks | Makes “preserve user files” observable through exact retained bytes and rejection before mutation. Audit F1/F2/F4/F5 provide the cases. |
| Distinguish failed discovery from a successful empty selection | Verification and CI Audit | Prevents “nothing to analyze” from hiding an invalid requested comparison. Audit F3 supplies a concrete wrong-outcome example. |
| Verify the actual installed producer-to-consumer path and configured home | Workflow, Verification, and Review | Source-relative checks alone can miss split Windows skill/tool roots and reviewer commands selecting an old/default-home tool. Audit F6/F7 provide the cases. |

The installed-layout lesson follows directly from the Windows skills/tools destinations, eval inventory's source-relative lookup, and literal default-home paths in both reviewer roles. Keep installed, available, selected, executed, and outcome-verified claims distinct. [Windows layout](/Users/laimis/Developer/Projects/Assistant/V1/install.ps1:2464), [eval lookup](/Users/laimis/Developer/Projects/Assistant/V1/tools/evals/lib/skill-eval-inventory.sh:39), [reviewer command](/Users/laimis/Developer/Projects/Assistant/V1/agents/codex/code-reviewer.toml:81).

**Separate-session repair scope:** retain the audit's finding IDs so work is not duplicated:

| Follow-up | Audit IDs | Work reserved for the other session |
|---|---|---|
| Unix user-content preservation | F1, F2, F4, F5 | Marker replacement, destination/link/hook safety, owned-entry synchronization, and source/target overlap rejection. F1/F4 are the audit's high-priority conditional data-loss findings. |
| Changed-file analysis correctness | F3 | Validate required Git discovery and distinguish errors from valid empty results. |
| Installed tooling and configured homes | F6, F7 | Resolve the installer-owned skills/tool locations in Windows eval selection and Codex reviewer commands. |
| Hermes compatibility decision | Architecture insight 2 | Decide whether the private adaptation stays private or becomes a reproducible, source-supported target. Do not infer a fourth supported target from the comparator collection. |

The separate session should reproduce the relevant failure on disposable inputs and verify the repair. Installer preservation repairs take precedence over an installer consolidation proposal. This report does not begin those fixes or create a new chat.

The audit also reinforces preserving the native conditional architecture and evaluating new instructions against actual outcomes. Its parser checks establish parseability only, and its independent review coverage is explicitly incomplete; neither is adopted here as a clean-review or runtime-success claim. No new skill, schema, or universal lifecycle controller is needed to absorb these lessons.

## 5. Source evidence and limits

- All 52 comparator entrypoints and 16 framework roots were inspected, with supporting references/scripts selected by relevance. Long comparators were read through substantive sections and selected examples/constraints; this is not an exhaustive audit of their entire bundles.
- Framework HEAD was c920fd89ee232032aafd2541dd51c9c5bd9744f3, with existing dirty authoring and untracked pilot/REA work. Installed Debugging, Review, and Verification roots differed from this checkout. Recommendations target the supplied source; existing work is preserved. Line-numbered references to `install.sh` and `install.ps1` are relative to HEAD; both files have since been modified in the working tree (including managed Claude instructions and a renamed guidance function), so those line numbers have shifted. Re-resolve them against the integration baseline before use.
- The common guide measured **2,060 whitespace words**. The context tool reported **3,935 words** for Workflow entry within its stated static scope, excluding a separate common-guide body component. Disk/instruction sizes are not billed-token measurements. [Guide](/Users/laimis/Developer/Projects/Assistant/V1/tools/progress/operating-guidance.md), [tool](/Users/laimis/Developer/Projects/Assistant/V1/tools/context-budget-report.sh).
- The local debugging pilot's four pairs tied on primary conclusion/authority outcomes, with current-condition totals of 485,335 versus 254,929 input tokens and 300.245 versus 186.284 elapsed seconds. This is a bounded cost signal; it does not establish causal overhead, overall framework ROI, or that practical debugging methods are unnecessary. [Pilot](/Users/laimis/Developer/Projects/Assistant/V1/docs/plans/expert-method-pilot/results.md).
- No comparator was installed or run end to end, and no comparative live-model skill evaluation was run. No integration writes, schedules, framework-code changes, or skill changes were made by this research. Independent report review is separate from testing the proposed capability gains and savings, which remain unverified.
- The separate project audit was read and the cited installer, discovery, inventory, and reviewer-role paths were checked against current source. Its reported failures were not reproduced here; no installer, audit parser suite, or runtime qualification was rerun. Detailed repairs and the Hermes support decision remain separate-session work.
- The full per-skill decisions follow. “Already covered” identifies method overlap; it does not imply that additional worked examples cannot improve execution.

## 6. Individual assessment of all 52 comparable skills

“Adapt” means borrow a bounded method into an existing owner after validation. “Covered” means the main method already exists, although examples may help. “Separate” means potentially useful to framework users but unsuitable as a default core dependency. “Outside core” means no convincing direct framework benefit was identified. These are judgments of likely marginal value, not measured effectiveness rankings.

### Software development, review, security, and tests

| # | Skill and source | Benefit and current fit | Disposition and main cost/risk |
|---|---|---|---|
| 1 | [codebase-inspection](</Users/laimis/Developer/Comparable skills/software-development/codebase-inspection/SKILL.md>) | Fast language/size inventory with explicit generated/dependency exclusions. Useful as an Onboard recipe; less useful for an instruction-heavy repository where Markdown is classified as documentation. | **Adapt, low priority.** Prefer already available tools. Do not import its `pip --break-system-packages` setup or treat LOC/comment ratios as quality. |
| 2 | [dogfood](</Users/laimis/Developer/Comparable skills/software-development/dogfood/SKILL.md>) | Concrete exploratory user flows, console diagnostics, screenshots, and reproducible issue reports add practical detail to current conditional QA. | **Create assistant-ui-qa — user agreed.** Translate browser APIs and evidence output. Keep activation task-specific; avoid capture after every trivial action or another universal reporting burden. |
| 3 | [github](</Users/laimis/Developer/Comparable skills/software-development/github/SKILL.md>) | Strong concise routing into task-specific references; fresh remote-state checks, duplicate search, and full issue context prevent false delivery claims. | **Separate / adapt reference structure.** Use existing connectors or host CLI guidance. Supporting PR/auth references still contain older skill/path assumptions; do not copy credential fallback code wholesale. |
| 4 | [hermes-agent-skill-authoring](</Users/laimis/Developer/Comparable skills/software-development/hermes-agent-skill-authoring/SKILL.md>) | Demand-based bundling, platform auditing, meaningful helpers, and avoiding router-only skills are useful authoring questions. Framework already has consumer-based design and selective loading. | **Adapt selectively.** Hermes' 60-character descriptions, metadata, mandatory docs/tests, tools, and commit rules are host policy, not portable requirements. Use existing selective installation rather than a new profile registry. |
| 5 | [inspecting-hermes-desktop-dom](</Users/laimis/Developer/Comparable skills/software-development/inspecting-hermes-desktop-dom/SKILL.md>) | Inspect computed UI state before speculative CSS edits; avoid restarting the user's session; return small projected facts. Valuable execution habits for UI development. | **Separate.** Hermes ports, scripts, selectors, and environment are unavailable framework contracts. Adapt principles only through the authorized browser/computer runtime. No framework desktop app needs this recipe directly. |
| 6 | [node-inspect-debugger](</Users/laimis/Developer/Comparable skills/software-development/node-inspect-debugger/SKILL.md>) | Concrete breakpoint, call-stack, closure, child-process, and source-map techniques fill the gap between a general debugging method and actual state inspection. | **Adapt to Debugging references.** Start with built-in tools, establish process identity, keep inspector local, and avoid unverified helper/port assumptions. |
| 7 | [python-debugpy](</Users/laimis/Developer/Comparable skills/software-development/python-debugpy/SKILL.md>) | Provides situation-based selection among traceback, pdb, post-mortem, and remote debugging; explains captured-runner and subprocess limitations. Relevant to Python admission/progress helpers. | **Adapt to Debugging references.** Remove Hermes environment setup and system-wide ptrace weakening. Do not add a mandatory dependency or leave paused processes/breakpoints behind. |
| 8 | [requesting-code-review](</Users/laimis/Developer/Comparable skills/software-development/requesting-code-review/SKILL.md>) | Baseline-aware failures and fresh review are valuable, but already covered more carefully by Workflow, Verification, and Review. | **Adapt practical preflight examples.** Reject automatic stashing, diff-only context, two-file triggers, fixed two-cycle repair, and misleading verified labels. Existing baseline/regression policy needs examples rather than replacement. |
| 9 | [simplify-code](</Users/laimis/Developer/Comparable skills/software-development/simplify-code/SKILL.md>) | Findings must name concrete cost, evidence, reuse opportunities, and whether a fix sits at the right ownership level. Historical context helps avoid deleting intentional compatibility. | **Adapt small checklist deltas.** Existing reuse/design-coherence guidance overlaps heavily. Four full-context agents are not a justified default; parallel latency and total cost are different. |
| 10 | [spike](</Users/laimis/Developer/Comparable skills/software-development/spike/SKILL.md>) | Disposable, observable experiments and explicit partial/invalidated verdicts can prevent investing in an infeasible approach. Existing Candidate Search has less execution detail. | **Create assistant-spike.** Its distinct experiment/verdict job merits its own trigger. Preserve approval boundaries; omit arbitrary question counts, unconditional pauses, and universal hardcoding. |
| 11 | [systematic-debugging](</Users/laimis/Developer/Comparable skills/software-development/systematic-debugging/SKILL.md>) | Tight symptom-specific feedback loops, repro minimization, working/broken comparisons, and boundary observation are useful examples. Main cause-isolation method already exists. | **Adapt the reproduction method pack.** Practical loop construction/minimization adds value beyond the existing principle. Reject hypothesis quotas, forced TDD, three-total-attempt escalation, and unsupported performance claims. |
| 12 | [test-driven-development](</Users/laimis/Developer/Comparable skills/software-development/test-driven-development/SKILL.md>) | Meaningful RED and stage ownership are already covered. Worked behavior-first tests, wrong-reason failures, and vertical slices add craft that the current root does not demonstrate. | **Adapt a TDD craft reference.** Reject universal activation, “every function” tests, deletion of preexisting implementation, and rigid broad reruns. Keep selected TDD and retained user work. |
| 13 | [sdlc-review](</Users/laimis/Developer/Comparable skills/devops/sdlc-review/SKILL.md>) | Map the original request to delivered answers; detect omissions and scope drift. Complementary review lenses also improve independent inspection. | **High priority: adapt request coverage into Research/Workflow and relevant Review.** Preserve broad investigation while checking that each requested outcome is answered. Do not import Kanban APIs or rigid round scheduling. |
| 14 | [security-audit](</Users/laimis/Developer/Comparable skills/security-audit/SKILL.md>) | Excellent domain-specific boundary questions, separate confirmed/needs-validation states, source-grounded coverage, and focused companion references. Especially relevant to agents, installers, and tool execution. | **Adapt selected references.** Full mode carries many artifacts, reconnaissance/hunter/critic/verifier calls, and strong OS-sandbox prerequisites. Reserve such machinery for an explicit audit; do not promise its sandbox on an unqualified host. |
| 15 | [security-triage](</Users/laimis/Developer/Comparable skills/security-triage/SKILL.md>) | Distinguishes a fix on main from a fix in the affected shipped release, checks trust-model scope, and separates hardening from vulnerabilities. | **Create assistant-advisory-triage — user agreed.** Retain shipped-release proof; remove OpenClaw policy, named-maintainer pauses, clipboard actions, and model-routing instructions. No automatic comments or closures. |
| 16 | [test-audit](</Users/laimis/Developer/Comparable skills/test-audit/SKILL.md>) | Independent oracles, one primary proof owner, test-only production seams, and protection retained before removal directly support the value goal. Current CI Audit covers most of this. | **Adapt authoring and junk-pattern examples into CI Audit.** Its testing-guide and OpenClaw-testing links do not resolve here. Keep independent prompt/schema/platform contracts; no deletion targets or duplicate audit skill. |

### Research and web access

| # | Skill and source | Benefit and current fit | Disposition and main cost/risk |
|---|---|---|---|
| 17 | [arxiv](</Users/laimis/Developer/Comparable skills/research/arxiv/SKILL.md>) | Version-preserving paper IDs, withdrawal checks, structured search, and citation/reference discovery are useful for technical evidence. | **Adapt a small Research reference if used repeatedly.** Do not turn academic search into a required research phase or equate citation counts with correctness. API/rate claims need current verification before use. |
| 18 | [competitor-news-monitor](</Users/laimis/Developer/Comparable skills/research/competitor-news-monitor/SKILL.md>) | Event-level deduplication, materiality thresholds, successful-source cutoffs, and silence when nothing actionable changes generalize to upstream-guidance monitoring. | **Adapt only to an explicitly requested watch.** Creator already has read-only upstream refresh. Do not add a monitoring skill, schedule, or ongoing search cost merely for this assessment. |
| 19 | [grounded-citations](</Users/laimis/Developer/Comparable skills/research/grounded-citations/SKILL.md>) | Deterministic retrieval-time source IDs and exact evidence attachment can reduce fabricated or mismatched citations in large reports. | **Adapt selectively to Research.** A ledger and quote checker do not establish entailment. Avoid universal numbering, per-sentence quotas, global mutable ledgers, and mandatory tooling for short answers. |
| 20 | [llm-wiki](</Users/laimis/Developer/Comparable skills/research/llm-wiki/SKILL.md>) | Immutable source layer, provenance, contradiction retention, source drift checks, and orientation before updates can improve research/document maintenance. | **Adapt principles; avoid the complete workflow.** Mandatory cross-links, 5–15-page ingest fanout, indexes/logs/taxonomies, and repeated linting can create more upkeep than saved retrieval. Start with a current-docs map. |
| 21 | [blocked-page-recovery](</Users/laimis/Developer/Comparable skills/web/blocked-page-recovery/SKILL.md>) | Bounded alternative retrieval, interstitial detection, and explicit live-versus-snapshot provenance fill a practical research failure case. | **Adapt a conditional reference.** Honor access limits and current-data requirements; no automatic proxy/API-key dependency or forwarding private material. Helper heuristics and archive freshness are not content proof. |

### Creative work and visual artifacts

| # | Skill and source | Benefit and current fit | Disposition and main cost/risk |
|---|---|---|---|
| 22 | [architecture-diagram](</Users/laimis/Developer/Comparable skills/creative/architecture-diagram/SKILL.md>) | Standalone SVG/HTML diagrams can serve audiences that need visual layout beyond Mermaid, without a rendering library dependency. | **Keep outside core.** With standalone Diagrams slated for retirement, use general capabilities or existing Docs when a task needs this output. Preserve source-backed relationships; do not introduce a replacement diagram skill. |
| 23 | [ascii-video](</Users/laimis/Developer/Comparable skills/creative/ascii-video/SKILL.md>) | Preview key frames before expensive rendering; isolate clips for selective rerender; avoid encoder-pipe deadlocks. These are useful artifact-production patterns. | **Outside core.** No direct framework video task was established. Do not import the production stack, arbitrary visual thresholds, or “first-render excellence” as universal acceptance. |
| 24 | [baoyu-infographic](</Users/laimis/Developer/Comparable skills/creative/baoyu-infographic/SKILL.md>) | Separates information layout from visual style, preserves source figures, and supplies reusable visual references. Could aid optional research presentation. | **Separate.** Large galleries, intermediate files, option-confirmation steps, and image-generation cost outweigh default framework value. Do not add another design catalog. |
| 25 | [claude-design](</Users/laimis/Developer/Comparable skills/creative/claude-design/SKILL.md>) | Content Discipline makes each element serve the outcome. Applied to answers, it helps present requested decisions first while retaining useful broad evidence. Source-aware design/visual verification remains useful for UI work. | **High priority: adapt content selection into Research/Docs.** This is a proposed transfer beyond visual design. Preserve material risks and counterevidence; omit the full taste manual, hosted-tool assumptions, and blanket HTML preference. |
| 26 | [design-md](</Users/laimis/Developer/Comparable skills/creative/design-md/SKILL.md>) | Exact design tokens plus rationale and structural/contrast checks can make repeated UI work more consistent. | **Separate / optional Docs-Design reference.** No framework UI system requires it. Verify the referenced specification/CLI before adoption; do not mandate DESIGN.md or install a compiler for ordinary tasks. |
| 27 | [humanizer](</Users/laimis/Developer/Comparable skills/creative/humanizer/SKILL.md>) | Preserving meaning, using the user's writing samples, and removing unsupported rhetoric can improve docs and handoffs. | **Adapt a short editorial checklist.** Its 647-line entrypoint and extra critique/rewrite pass are expensive defaults. Avoid word blacklists as quality gates, forced personal voice, or rewriting accurate technical terminology. |
| 28 | [manim-video](</Users/laimis/Developer/Comparable skills/creative/manim-video/SKILL.md>) | Narrative-first explanation, draft quality before full render, independent scenes, and visual review are useful specialized production methods. | **Outside core.** Manim/LaTeX/FFmpeg maintenance lacks a demonstrated framework job. Treat version/performance/aesthetic claims as unqualified until exercised. |
| 29 | [p5js](</Users/laimis/Developer/Comparable skills/creative/p5js/SKILL.md>) | Seeded reproducibility, exposed parameters, controlled frame export, and preview before final render are useful for interactive demonstrations. | **Separate.** Existing visualization capabilities can serve the user. Do not inherit universal layering, color-mode, frame-rate, or error-system prescriptions without workload evidence. |
| 30 | [popular-web-designs](</Users/laimis/Developer/Comparable skills/creative/popular-web-designs/SKILL.md>) | Reusable visual tokens/examples reduce design invention for a specifically requested style. | **Separate.** Maintaining 54 templates is not a core framework need. Sampled template includes a tunnel/skill assumption; external fonts and brand resemblance need task-specific judgment. Its `triggers` header is rejected by framework conventions. |
| 31 | [songwriting-and-ai-music](</Users/laimis/Developer/Comparable skills/creative/songwriting-and-ai-music/SKILL.md>) | Situation-specific craft advice, short risky-fragment trials, and treating creative techniques as optional are useful authoring patterns. | **Outside core.** No development-framework music job was identified. Do not add music-model dependencies or copy its deprecated-for-framework `triggers` metadata. |

### Documents, productivity, and provider integrations

| # | Skill and source | Benefit and current fit | Disposition and main cost/risk |
|---|---|---|---|
| 32 | [airtable](</Users/laimis/Developer/Comparable skills/productivity/airtable/SKILL.md>) | Stable IDs, schema inspection, bounded pagination, partial updates, and upserts illustrate reliable data operations. | **Separate.** A full authenticated API cookbook introduces token/API maintenance without a demonstrated framework requirement. Borrow invariants in an integration example only when needed. |
| 33 | [box](</Users/laimis/Developer/Comparable skills/productivity/box/SKILL.md>) | Distinguishes actor permissions, stable IDs, metadata queries, AI work, and write readback. Useful examples of choosing deterministic retrieval before costly inference. | **Separate.** Box-specific OAuth, AI units, setup, and metadata behavior belong to its provider. No blanket adoption of its domain-specific implied-write permissions. |
| 34 | [document-to-action-items](</Users/laimis/Developer/Comparable skills/productivity/document-to-action-items/SKILL.md>) | Retains page provenance, document version, modality, OCR uncertainty, explicit owners, and unresolved dates when turning source material into work. | **Adapt examples into preparation/Docs.** Framework evidence binding already handles much of this. Do not create another task schema or external-write approval phase when existing authority already settles it. |
| 35 | [docx](</Users/laimis/Developer/Comparable skills/productivity/docx/SKILL.md>) | Concrete helpers for preserving formatted content, templates, revisions, comments, and package/readback checks provide a real artifact capability. | **Separate.** Use available document specialists. Package health is not visual fidelity; rendering/runtime dependencies need qualification. Avoid adding Office tooling to framework core. |
| 36 | [google-workspace](</Users/laimis/Developer/Comparable skills/productivity/google-workspace/SKILL.md>) | Schema-preserving CLI fallback, pagination, timezone handling, and verified provider operations are reusable integration principles. | **Separate.** Prefer connected provider tooling. Maintaining parallel OAuth clients, credentials, and a broad permission surface would add substantial ongoing cost. |
| 37 | [maps](</Users/laimis/Developer/Comparable skills/productivity/maps/SKILL.md>) | Illustrates a focused stdlib helper offering concrete location capabilities with explicit inputs. | **Outside core.** No framework location job was established. Service limits, privacy, routing correctness, and hardcoded Hermes script paths would need independent work. |
| 38 | [meeting-action-items](</Users/laimis/Developer/Comparable skills/productivity/meeting-action-items/SKILL.md>) | Separates decisions from proposals, keeps unknown owners/dates visible, reconciles duplicates, and checks ambiguous writes before retry. | **Adapt requirements-ingestion examples.** Use existing acceptance/evidence fields and provider tools. A separate meeting workflow adds little to core development orchestration. |
| 39 | [notion](</Users/laimis/Developer/Comparable skills/productivity/notion/SKILL.md>) | Runtime tool choice, typed properties, stable resource IDs, pagination, and explicit API-version distinctions are useful integration patterns. | **Separate.** API/CLI versions, installations, tokens, and Worker hosting are provider responsibilities. Do not copy dated support claims as current framework facts. |
| 40 | [pdf](</Users/laimis/Developer/Comparable skills/productivity/pdf/SKILL.md>) | Scan detection, OCR provenance, form-layout checks, field readback, and real page inspection address failures that generic prose checks miss. | **Separate; borrow verification examples.** Existing PDF specialists are a better capability owner. The helper's successful exit can accompany `rendered:false`; process success must not be interpreted as visual verification. |
| 41 | [powerpoint](</Users/laimis/Developer/Comparable skills/productivity/powerpoint/SKILL.md>) | Template fidelity, chart/relationship preservation, outline readback, and slide rendering are practical artifact evidence. | **Separate.** Deck rendering and format compatibility require specialist ownership. A zero exit with missing render tools is unavailable visual evidence, not a completed visual check. |
| 42 | [product-price-monitor](</Users/laimis/Developer/Comparable skills/productivity/product-price-monitor/SKILL.md>) | Exact item identity, one working foreground fetch, last-good observations, deterministic threshold entry, and duplicate suppression are good monitor design examples. | **Separate; optional general monitor example.** Framework has no shopping requirement. Do not create an automation from this research; polling and notification cost need an explicit use case. |
| 43 | [teams-meeting-pipeline](</Users/laimis/Developer/Comparable skills/productivity/teams-meeting-pipeline/SKILL.md>) | Operator runbook ties symptoms to status, stored jobs, replay, delivery, and expiring subscriptions; illustrates concrete operational guidance. | **Outside core.** It depends on Hermes' Teams pipeline and Graph setup. Expiration/permission claims require provider verification; automatic renewal setup is not authorized by inspecting it. |
| 44 | [weekly-review-planning](</Users/laimis/Developer/Comparable skills/productivity/weekly-review-planning/SKILL.md>) | Capacity-aware planning and reconciling stale commitments can help a deliberately requested personal review. | **Keep outside core.** Telos is slated for removal; this is not a reason to add a replacement personal-productivity skill or default scheduled review. |
| 45 | [xlsx](</Users/laimis/Developer/Comparable skills/productivity/xlsx/SKILL.md>) | Distinguishes formulas from cached results, preserves references during restructuring, and verifies touched ranges. Excellent examples of artifact-specific wrong outcomes. | **Separate; borrow evidence lessons.** Do not maintain another spreadsheet engine in core. Recalculation, charts, and round-trip fidelity need specialist tests and available runtimes. |

### Email, notes, media, and social

| # | Skill and source | Benefit and current fit | Disposition and main cost/risk |
|---|---|---|---|
| 46 | [email-inbox-triage](</Users/laimis/Developer/Comparable skills/email/email-inbox-triage/SKILL.md>) | Bounded full-thread retrieval, explicit dispositions, draft/action separation, and checking Sent before an ambiguous retry illustrate careful external work. | **Separate.** Not a development-framework core job. Its 20–50-sent-message voice calibration is potentially costly; use a supplied sample when adequate and keep mailbox scope explicit. |
| 47 | [himalaya](</Users/laimis/Developer/Comparable skills/email/himalaya/SKILL.md>) | Concrete mailbox, MIME, folder-alias, and pagination guidance adds tool expertise when that CLI is actually used. | **Separate.** Version-specific configuration and credential support belong to the connector. No need to add a mail-client dependency to the framework. |
| 48 | [obsidian](</Users/laimis/Developer/Comparable skills/note-taking/obsidian/SKILL.md>) | Filesystem-first notes, resolved absolute paths, focused edits, and existing links show how little machinery a local knowledge task may need. | **Separate / borrow simplicity.** Docs already handles local source-backed writing. Do not assume a home vault or create a second memory store without user intent. |
| 49 | [gif-search](</Users/laimis/Developer/Comparable skills/media/gif-search/SKILL.md>) | Focused API example with suitable small media formats. | **Outside core.** No convincing framework-development benefit; keys, endpoint upkeep, downloading, and presentation policy add cost. |
| 50 | [songsee](</Users/laimis/Developer/Comparable skills/media/songsee/SKILL.md>) | Audio feature visualization can be a useful independent check for audio-processing projects. | **Outside core.** No relevant framework audio behavior was established. External CLI and audio dependencies should remain specialized. |
| 51 | [youtube-content](</Users/laimis/Developer/Comparable skills/media/youtube-content/SKILL.md>) | Timestamped transcript provenance, language validation, chunking, and dependency isolation help when technical evidence arrives as video. | **Separate / optional Research reference.** Transcripts do not prove visual behavior or video truth. Use only when a video source materially contributes; no default transcription dependency. |
| 52 | [xurl](</Users/laimis/Developer/Comparable skills/social-media/xurl/SKILL.md>) | Explicit account selection, secret-file exclusion, rate/error handling, and stable post identity are useful provider practices. | **Separate.** No core social-posting requirement. Prefer the available provider integration; API access and write authority must be resolved for an actual task. |

## 7. What to retain from each assessment

Hermes provides the better starting structure for deciding what to absorb, add, and cut. Its reproduction ladder, TDD craft, review-method, test-value, security-depth, and new-skill proposals deserve direct consideration.

Several recommendations need narrower framing against source:

| Claim or proposal | Source-grounded adjustment |
|---|---|
| Review passes are identical | Current Review already requires narrow independent passes and names distinct concerns. Add concrete brief examples; do not assume identical runtime behavior. |
| Baseline failure handling is absent | CI Audit already distinguishes baseline/environment/regression failures. The useful addition is a safe practical recipe and examples. |
| Research is URL checking only | Current Research already requires source identity, near-claim citations, conflicts, and gaps. The missing contribution is mechanical bookkeeping and failed-fetch handling. |
| Required headings/60-character descriptions prove better skills | These are presentation/host conventions. Improve readability where useful; do not adopt Hermes-specific limits as cross-agent correctness rules. |
| Telos/Diagrams fire rarely | The user now reports never using Telos and requests its removal. Standalone Diagrams retirement follows the requested product direction, with consumer migration; neither statement establishes a general lack of diagram-skill benefit. |
| On-demand references add zero standing cost | Their bodies can be loaded selectively, but routing text, discovery, installation, and maintenance still have costs. |
| The existing context command validates the common-guide savings | Its current static components omit that guide's body. Account for it explicitly before interpreting a before/after total. |

These adjustments preserve the actionable recommendations without turning likely benefits into measured results. The next decision should be which concrete improvement to implement first, rather than whether every possible benefit has already been proven.
