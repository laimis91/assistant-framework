# S09 — Exploratory UI QA (assistant-ui-qa)

Status: **Accepted by the user**, 2026-11-06 (drafted and revised the same day). Baseline: main d11756d. Implemented on branch `fvi/s09-assistant-ui-qa` (2026-11-07); held-out refreeze pending integration. On 2026-11-08 the user accepted the severity and coverage method text (T3 evidence row) and waived the R-EVAL-3 review of the six S09 activation cases. The R-DESC-7 crowded listing check passed with no model call: all 17 descriptions stay word for word for six Claude model names (16,288 listing characters). The optional manual smoke found the planted broken Save button, with steps, console error and coverage, and gave no verdict.
Source: report §2 "Add: assistant-ui-qa" (docs/research/assistant-framework-value-assessment-2026-10-26.md:175-179), §6 rows 2 and 5 (same file:270, :273), order 5 (same file:215); slice map row S09 (docs/plans/framework-value-improvements/specification-index.md, "Full specification set").

## Problem and intended outcome

The framework has no method for exploring a running UI to find defects. The QA Evaluator decides acceptance but is read-only and may not run builds or tests (agents/claude/qa-evaluator.md:4, :26-27; agents/codex/qa-evaluator.toml:3, :30), so it cannot drive a browser; it consumes `verification_evidence` produced by the main actor (skills/assistant-review/references/qa-evaluation-loop.md:26). Verification's end-to-end method confirms a named journey claim (skills/assistant-verification/references/methods/end-to-end.md:3-15) but does not explore for unknown issues. No skill, agent or reference names a browser tool (search of `skills/`, `agents/`, `docs/specs/`, README for "browser", "playwright", "screenshot", "console" found only playbook commands and rubric evidence wording). The intended result is a new instruction-only skill, `assistant-ui-qa`, that explores in-scope user flows through whatever browser runtime is actually available, produces reproducible issue evidence with severity and explicit tested/not-tested coverage, works for a standalone "test this app" request without a Build, and hands evidence to the QA Evaluator without issuing an acceptance verdict.

## Requirements

### Activation and scope

- **R-S09-1.** The skill activates for exploratory testing of a running UI or user flow: "test this app", "dogfood the signup flow", "click through the settings page and report bugs". It runs standalone, with no Workflow task, plan or Build required.
- **R-S09-2.** Before exploring, the skill records the target (URL or app), the flows or areas in scope, the environment (local, preview, staging), and the test data or accounts it will use. When the user names no scope, it takes the main user flows reachable from the entry point and says so.

### Runtime

- **R-S09-3.** The skill uses the browser or UI-automation capability actually available in the session: a host browser tool, a browser MCP server, or browser tooling already installed in the project and run through the shell. It names no single vendor API as required, and the report states which runtime was used.
- **R-S09-4.** When no browser runtime is available, the skill does not install a browser, driver or package, or start an external service, without the user's confirmation (skills/assistant-workflow/references/ai-usage-policy.md:87-93). It reports that the UI was not exercised and why, lists every in-scope flow as not tested, and may offer non-UI evidence (HTTP responses, existing test output) labelled as not UI exploration. It never reports a flow as tested without having driven it.

### Exploration method

- **R-S09-5.** For each in-scope flow, the skill exercises valid, invalid and empty states where the flow accepts input, plus navigation into and out of the flow.
- **R-S09-6.** The skill reads console (and, when the runtime offers it, network) diagnostics after each page load and each significant interaction, such as a submission, navigation or state change. It does not capture screenshots or diagnostics after every trivial interaction.
- **R-S09-7.** Screenshots are taken for issues and for key states that support a finding or a coverage claim, where the runtime supports them.

### Evidence and report

- **R-S09-8.** Each issue records: where it occurs (URL or screen), reproducible steps, expected versus actual behaviour, relevant console or network errors, a screenshot reference where one was captured, a severity (Critical, High, Medium, Low) and a category (Functional, Visual, Accessibility, Console, UX, Content). Duplicate manifestations are merged into one issue.
- **R-S09-9.** The report lists coverage explicitly: flows and states tested, flows not tested, and flows blocked, each with its reason (out of scope, no runtime, needs credentials, destructive action not authorized, environment error).
- **R-S09-10.** Severity is the skill's triage of an observed issue. The report contains no acceptance verdict (`accepted`, `rejected`, pass/fail of acceptance criteria) and no numeric quality score.

### Safety

- **R-S09-11.** The skill tests local or explicitly named test environments. It does not enter real credentials, payment or personal data; uses test accounts or data from the project or the user; and asks before any irreversible action in the app (delete, purchase, send, publish). Production systems stay forbidden: the skill does not explore a production system or database, preserving skills/assistant-workflow/references/ai-usage-policy.md:94-95 ("Never allowed: Accessing production systems or databases"). An explicit instruction from the user does not lift this; a possible narrow exception for publicly reachable sites is a separate product question (D7) and is not part of this requirement unless the user accepts it.
- **R-S09-12.** Screenshots and captured diagnostics are stored in the session's temporary or scratch directory or a Git-ignored location, are not committed, and are checked for secrets or personal data before they are shared.

### Ownership and handoff

- **R-S09-13.** The QA Evaluator owns acceptance. Inside a Workflow task with `qa_evaluation_mode=required`, the main actor passes the UI QA report as `verification_evidence`, and the in-scope UI notes as `domain_context`, through the existing QA inputs (qa-evaluation-loop.md:22-31). The QA Evaluator alone returns `final_verdict` and `result` (agents/claude/qa-evaluator.md:48-49). No new field, contract or schema is added.
- **R-S09-14.** UI QA exploration does not satisfy `manual_verification_mode=required`, which waits for the user's own verification (skills/assistant-workflow/references/review-qa-router.md:266-276), and does not replace the fresh acceptance review (same file:14-27).
- **R-S09-15.** When the user asks to fix an issue found, the fix goes through `assistant-workflow` (and `assistant-debugging` when the cause is unknown); the issue's reproduction steps carry into that work. The skill itself does not edit project source.

### Optional: inspect before editing

- **R-S09-16 (optional, see D3).** When a finding leads to a UI fix or a "why is this element still X?" question, the skill's guidance says to read the rendered state (computed styles, geometry, which rule applied, console) through the available runtime before speculative CSS or markup edits; to return small, specific facts rather than full DOM dumps; not to relaunch the user's running app session; and to leave aesthetic judgment to a screenshot or the user. Adapted from inspecting-hermes-desktop-dom principles only ("/Users/laimis/Developer/Comparable skills/software-development/inspecting-hermes-desktop-dom/SKILL.md":25-30, :53-64).

### Activation and distribution

- **R-S09-17.** The `description` follows docs/specs/skill-activation.md R-DESC-1 and R-DESC-2 and has no `effort` or `triggers`. Proposed wording (final text is an implementation decision): "Explores a running web or app UI for defects through the available browser tools: user flows, valid, invalid and empty states, console errors, screenshots, and reproducible issue reports with severity and coverage. Use when the user asks to test, dogfood, or click through an app. Acceptance verdicts stay with the QA evaluator."
- **R-S09-18.** `evals/cases.json` uses schema `2.0` with `activation_cases` meeting the fixture rules (tools/evals/lib/skill-eval-fixtures.sh:915-930) and a non-empty `cases` array (same file:1291-1292). Negatives cover writing automated UI tests, diagnosing a known failure's cause, a formal QA acceptance verdict, and code review.
- **R-S09-19.** The skill is bundled in the default install and installable alone with `./install.sh --skill assistant-ui-qa` or `.\install.ps1 -Skill assistant-ui-qa`. It declares no `requires`. Its `SKILL.md` links `../../tools/progress/operating-guidance.md`.

## Existing behaviour to preserve

- QA Evaluator runs only when `qa_evaluation_mode=required`, after build/test and code-review evidence, and owns acceptance, Done Contract readiness, verification evidence and scoped domain quality (skills/assistant-workflow/references/review-qa-router.md:20-27, :169-182; skills/assistant-review/references/qa-evaluation-loop.md:15-18).
- QA required triggers and non-triggers are unchanged; a UI QA run is not itself a trigger (review-qa-router.md:175-177; skills/assistant-workflow/contracts/input.yaml:357-365).
- QA Evaluator is read-only and does not run builds or tests (agents/claude/qa-evaluator.md:4, :23-29; agents/codex/qa-evaluator.toml:3, :30). Its return shape stays owned by assistant-review (review-qa-router.md:193-194).
- Domain rubrics load only when UI/visual acceptance is scoped; screenshots are already accepted evidence there (skills/assistant-review/references/domain-rubrics.md:9, :26-30).
- Manual verification waits only in its listed cases (review-qa-router.md:266-276).
- Verification's end-to-end method remains the confirmatory journey check (skills/assistant-verification/references/methods/end-to-end.md:3-17).
- Installs, external service calls and file writes keep their confirmation; production access stays forbidden (skills/assistant-workflow/references/ai-usage-policy.md:87-95).

## Scope and non-goals

In scope: new `skills/assistant-ui-qa/` (SKILL.md, optional issue-taxonomy reference, evals); activation fixture, routing row and stateful activation cases; inventory and documentation consumers.

Out of scope and not imported (report :177-179, :270, :273; comparator "/Users/laimis/Developer/Comparable skills/software-development/dogfood/SKILL.md"):
- Hermes `browser_*` tool names, `@eN` refs and `browser_vision` annotation (comparator :22, :56-89, :141-153);
- console check and visual capture after every interaction (:66-70, :86-89) — replaced by R-S09-6/7;
- a fixed five-phase workflow, mandatory `./dogfood-output/` directory and report template with emoji severity counts (:34-50, :121-139; templates/dogfood-report-template.md);
- `MEDIA:` inline-image convention (:134, :164);
- Hermes desktop CDP port, scripts, selectors and environment variables (inspecting-hermes-desktop-dom :45-80);
- any acceptance verdict, QA score, new QA agent, or change to the QA Evaluator's role;
- a new contract or schema for the UI QA report.

## Affected owners and consumers

| Owner / consumer | Change | Compatibility concern |
|---|---|---|
| `skills/assistant-ui-qa/SKILL.md`, `evals/cases.json`, optional `references/issue-taxonomy.md` | New | Instruction-only |
| `skills/assistant-review/references/qa-evaluation-loop.md` / `skills/assistant-workflow/references/review-qa-router.md` | Optional one-line note that a UI QA report is valid `verification_evidence` (D2) | No field or schema change; QA return validation unchanged |
| `agents/claude/qa-evaluator.md`, `agents/codex/qa-evaluator.toml` | None | Role stays read-only; keep both in parity if D2 adds wording |
| `README.md` | New `### assistant-ui-qa` section; counts at :3, :353, :701; structure tree | `tests/p0-p4/docs-drift-contracts.sh:14-31`; `tests/p0-p4/skill-eval-contracts.sh` block near :5956 |
| `docs/evals/skill-fixtures.md:22-39` | Count and fixture list | skill-eval-contracts block near :5981 |
| `docs/specs/skill-activation.md` table (:91-121), `tools/evals/skill-activation/routing.json` | New row | Parity test `test_routing_data_matches_the_spec_table` (test_skill_activation.py:535-542) |
| `tools/evals/skill-activation/cases/*.json`, `heldout.sha256` | At least three held-out positives | `suite.py:210-213` fails otherwise, in CI (`.github/workflows/framework-validation.yml:56-57`); held-out hash covers heldout.json and routing.json (`suite.py:139-145`), so held-out trial runs need a refreeze; the S09 branch adds the cases without refreezing (`validate_all` ignores the hash) and the integration step does one refreeze, with R-EVAL-3 human review |
| `tools/evals/skill-activation/suite.py:34-39` `NEIGHBOUR_PAIRS` | Optional new pairs (D4) | Needs a neighbour case in both sets |
| `install.sh`, `install.ps1`, validators, eval inventory | None | Verified auto-discovery: install.sh:800-805, :828-832; install.ps1:2471-2483; tools/skills/lib/validate-inventory.sh:55-70; tools/evals/lib/skill-eval-inventory.sh:73-86 |
| `tests/p0-p4/skill-install-path-substitution-contracts.sh:105-112` | None | Requires the operating-guidance link |
| S11 installer ownership records | New skill recorded as framework-owned | Coordinate with S11 |

## Evidence classification

| Item | behavior_status | work_status | Evidence |
|---|---|---|---|
| Exploratory UI QA method (R-S09-5–9) | new_behavior | implementation_gap | No skill or reference; dogfood :52-139 is the source |
| Runtime discovery and absence handling (R-S09-3, 4) | new_behavior | technical_design_decision | No browser tool named anywhere in skills/agents; ai-usage-policy.md:87-93 |
| Browser availability on Codex and Gemini hosts | materially_unknown | evidence_gap | Not documented in this repo; not checked |
| Standalone use without Build (R-S09-1) | new_behavior | no_open_decision | Report :179 |
| QA Evaluator owns acceptance (R-S09-10, 13) | existing_behavior_to_preserve | no_open_decision | qa-evaluator.md:13-29, :48-49; review-qa-router.md:20-27 |
| Handoff through existing `verification_evidence`/`domain_context` (R-S09-13) | new_behavior | no_open_decision | qa-evaluation-loop.md:22-31 |
| Not a substitute for manual verification (R-S09-14) | existing_behavior_to_preserve | no_open_decision | review-qa-router.md:266-276 |
| Safety and artifact storage (R-S09-11, 12) | existing_behavior_to_preserve | technical_design_decision | ai-usage-policy.md:87-95; docs/README.md:31 |
| Read-only exception for publicly reachable sites (D7) | materially_unknown | product_question | Would qualify ai-usage-policy.md:95 "Accessing production systems or databases"; needs user acceptance |
| Inspect-before-edit guidance (R-S09-16) | new_behavior | product_question | Report :273 "Separate… adapt principles only" |
| Activation description and cases (R-S09-17, 18) | new_behavior | implementation_gap | skill-activation.md R-DESC-1/2 |
| Precision against assistant-review's "QA" wording | materially_unknown | evidence_gap | Review's description ends "QA runs only when required"; no trial has run |
| Held-out cases and refreeze | explicit_change | implementation_gap | suite.py:139-145, 210-213 |
| Expert-method derivation for severity/coverage method | new_behavior | implementation_gap | Derived per skills/assistant-skill-creator/references/expert-method-design.md from the dogfood comparator (SKILL.md "Phase 2: Explore" to "Phase 4: Categorize", references/issue-taxonomy.md), the only accessible source; source recommendations kept apart from inference. Decisions and wrong-outcome checks: input flows get valid, invalid and empty states (source recommendation; rejected by `signup-valid-invalid-empty-with-diagnostics` for happy-path-only); diagnostics only at loads and significant interactions (source says after every significant interaction, but its every-interaction capture is dropped; same case, fail signal "after every click"); severity from observed user impact, then workaround (source levels; "lower level when unsure" and "do not raise for inferred impact" are inference; `issue-record-has-steps-severity-category`); blocked means tried and stopped by something outside the explorer's control, not tested means not tried (inference from the source's "what was not, any blockers"; `coverage-lists-tested-not-tested-blocked`, `no-browser-runtime-reports-not-exercised`); duplicates merge only when the same cause is evident (source "same bug manifesting in different places"; `issue-record-has-steps-severity-category`). Method text in skills/assistant-ui-qa/SKILL.md and references/issue-taxonomy.md; no behavioural gain is claimed until a model run |

## Unresolved decisions

- **D1. Severity taxonomy location (technical default).** Inline in SKILL.md or a reference loaded when classifying issues. Recommended: a short reference adapted from dogfood's `references/issue-taxonomy.md`, without Hermes-specific examples, loaded only when issues are found.
- **D2. QA-side note (technical default).** Whether qa-evaluation-loop.md gains one sentence naming a UI QA report as valid `verification_evidence`. Recommended: yes in assistant-review only; no agent-file or contract change. Without it the handoff still works through the existing field.
- **D3. Include R-S09-16 in the first version (product_question).** Options: include as a short optional section; leave out and revisit after use. Recommended: include as a short section, since the user asked for it to be noted and it only applies when a fix or factual UI question follows. **Decided by user 2026-11-06:** include the inspect-before-CSS-edits section (the recommended default).
- **D4. Neighbour pairs (product_question).** Add `(assistant-ui-qa, assistant-debugging)` and `(assistant-ui-qa, assistant-review)` to `NEIGHBOUR_PAIRS`? Recommended: yes; "QA" and "test" overlap Review's QA wording and Debugging's broken-UI cases. **Decided by user 2026-11-06:** both neighbour pairs (the recommended default).
- **D5. Routing row (product_question).** Proposed: "Exploratory testing of a running UI or user flow" — Required `assistant-ui-qa`; Optional `assistant-verification`, `assistant-debugging`; Forbidden none. Should a Workflow Review phase with required UI acceptance also list `assistant-ui-qa` as optional on the existing rows? Recommended: no change to existing rows; the Workflow body may direct it later if use shows the need. **Decided by user 2026-11-06:** a new routing row only (the recommended default).
- **D6. Workflow direction (product_question).** Should Workflow or Verification ever select UI QA automatically (for example when `qa_evaluation_mode=required` with UI scope)? Recommended: no for this slice; the report asks for activation tied to the actual job (:187) and the index says agreement to create the skill is not evidence that every task should load it. **Decided by user 2026-11-06:** no automatic selection by Workflow (the recommended default).
- **D7. Read-only exception for publicly reachable sites (product_question).** R-S09-11 keeps production systems forbidden, as ai-usage-policy.md:94-95 requires. Proposed exception for the user to accept or reject: read-only exploration of a publicly reachable site, as any anonymous visitor could do (no sign-in, no form submission, no state-changing action), on the user's explicit instruction naming the URL, is treated as distinct from "accessing production systems or databases". Accepting it would require qualifying ai-usage-policy.md:95 ("Accessing production systems or databases") with that exception in the same change, so the policy and the skill do not disagree. Options: (a) no exception (production stays forbidden, including public sites); (b) the exception as worded. Recommended: (a) until the user accepts (b) and the policy line is qualified; exploring a public site read-only is a common standalone request, which is why (b) is offered. **Decided by user 2026-11-06:** no exception for publicly reachable sites; production systems stay forbidden (the recommended default).
- **D8. Activation trial (product_question).** As in S08 D6. Recommended: fixture, suite-validator and R-DESC-7 listing checks only; any model trial needs fresh authorization of exact call counts. **Decided by user 2026-11-06:** no model activation trial now; ask the user for fresh authorization later if one is needed.

## Acceptance examples

- R-S09-1/2 positive: "Test the app at localhost:5173" with no plan; the skill records target, assumed scope (main flows from the landing page), environment and data, then explores. Negative: refuses or starts a Workflow Build/plan first.
- R-S09-3/4 positive: no browser tool is available; the report says "UI not exercised: no browser runtime in this session", lists all flows as not tested, offers to run the project's existing Playwright suite if the user approves. Negative: runs `npx playwright install` unprompted, or fetches HTML with curl and reports flows as tested.
- R-S09-5/6 positive: the signup form is tried with valid data, an invalid email and empty submit; console read after each submission and navigation, not after each keystroke or hover. Negative: only the happy path is tried, or a screenshot and console dump follow every click.
- R-S09-8 positive: "High / Functional — /settings: Save with empty name shows success but value reverts on reload. Steps 1–4; expected validation error; console `TypeError: …`; screenshot path." Negative: "settings seem buggy" with no steps, expected/actual or severity.
- R-S09-9 positive: coverage lists "tested: signup, login; not tested: billing (out of scope); blocked: admin (needs credentials)". Negative: report lists only issues, so a reader cannot tell billing was never opened.
- R-S09-10/13 positive: within a required-QA Workflow task, the report is passed as `verification_evidence`; the QA Evaluator returns `accepted_with_concerns`. Negative: the UI QA report says "Acceptance: accepted" or the workflow records it as `qa_evaluation_result`.
- R-S09-11 positive: a "Delete account" button is in scope; the skill asks before clicking it on staging. Negative: clicks it, or types the user's real password into a login form.
- R-S09-11 (production) positive: "Click through our live checkout at https://shop.example.com and report bugs" — the skill states that production systems are off limits under ai-usage-policy.md:94-95, explores nothing there, lists the flows as blocked (reason: production target), and offers a local or staging target instead. Negative (fails): explores the production site because the user named it, even read-only. If D7 (b) is accepted and the policy line is qualified, the positive becomes: read-only anonymous browsing of the named public URL with no sign-in, form submission or state change, and the report labels the target as a public production site.
- R-S09-14 positive: `manual_verification_mode=required`; after UI QA, Workflow still presents steps for the user and waits. Negative: UI QA evidence is recorded as the manual verification result.
- R-S09-16 positive (if D3 accepted): "Why is the header still 64 px?" — the skill reads the computed height and winning rule before proposing a CSS change. Negative: edits three CSS files speculatively, or restarts the user's dev app to attach a debugger.
- R-S09-19 positive: `./install.sh --agent codex --skill assistant-ui-qa --dry-run` lists only `assistant-ui-qa`. Negative: missing from the default dry run.

## Verification

Focused checks, no matched evaluation:
- `tools/skills/validate-skills.sh`.
- `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-ui-qa` and `--list --skill assistant-ui-qa`.
- `./tests/test-p0-p4-contracts.sh` (docs-drift, install-path substitution, instruction-quality, activation-precision), plus `skill-eval-contracts.sh` in its shard.
- `./tests/test-skill-activation-tools.sh` (routing parity, R-EVAL-6 count) passes on the S09 branch without a refreeze: `test_committed_suite_is_valid` checks `validate_all` only, not the held-out hash (tools/evals/skill-activation/test_skill_activation.py:518-521). The freeze state matters only for held-out trial runs (tools/evals/skill-activation/run_trials.py:83-88) and is restored by the integration step's single refreeze.
- `./install.sh --agent {claude,codex,gemini} --dry-run` and `--skill assistant-ui-qa --dry-run`; Windows installer contracts where a Windows host is available.
- A focused content check that SKILL.md states the no-runtime rule (R-S09-4), the coverage lists (R-S09-9) and the "no acceptance verdict; QA Evaluator owns acceptance" boundary (R-S09-10/13).
- If D2 is accepted, the existing QA-loop and Review contract tests still pass unchanged.
- R-DESC-7 listing check (no model call), with total description characters before and after reported as a measurement.
- Optional manual smoke on a small local static page with a known broken button, in a session that has a browser tool, to confirm the report shape; not a gate.

## Dependencies and overlap

- S08, S06 and S11 add skills and S10 removes two; they share counts, the routing table, routing.json and the held-out set. The S09 branch is green on its own: it adds its README `### assistant-ui-qa` section, updates the derived counts (README.md:3, :353, :701; docs/evals/skill-fixtures.md:22) and the fixture list, and adds its routing row and at least three held-out positives so `validate_all` passes. The integration step reconciles the final count across S06, S08, S09, S10 and S11 and does one held-out refreeze (held-out trial runs only); held-out case changes go through the user's R-EVAL-3 review, and model runs need fresh authorization.
- S05 edits Review methods and may touch qa-evaluation-loop.md or Review's description; D2 must be coordinated so the QA handoff boundary is frozen before both plans run (index "How to run implementation in parallel later", step 2).
- S01 (request-focused output) applies to the UI QA report's presentation; S02 owns common guidance the new SKILL.md links.
- S11 must record the new skill as framework-owned.
