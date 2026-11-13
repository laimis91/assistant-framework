# Framework value improvements — specification set

Status: **Accepted by the user**, 2026-11-06. Baseline: main d11756d. S01 to S11 are implemented (see their rows). Integrated on branch `fvi/integration` from main 5861363 (2026-11-12): final count of 17 first-class skills reconciled, held-out set refrozen after the user's R-EVAL-3 approval of all 28 held-out changes since d11756d, aggregate validation and a fresh integrated review, with commands and results recorded in the integration pull request. The authorized live activation trials and live behaviour eval runs followed on 2026-11-13; see [Live runs after integration](#live-runs-after-integration-2026-11-13).

Source: [framework value assessment](../../research/assistant-framework-value-assessment-2026-10-26.md). The user accepted the S01–S11 slice map and its decisions on 6 November 2026: matched evaluation for S01 and S05 only; new skills bundled by default with `--skill` for single installs; a cleanup skill plus uninstall script (S11); no word or character budgets.

## Specifications

| Slice | Specification | Adds | Depends on |
|---|---|---|---|
| S01 | [Request alignment and focused delivery](S01-request-alignment.md) | Shared request-coverage and relevance terms in the common guide, applied by Research, Workflow, Docs and Review's document checklist. Implemented; matched evaluation supported as a tie | — (foundation) |
| S02 | [Conditional instruction loading and maintenance](S02-conditional-loading.md) | Score bookkeeping loaded only where consumed, canonical links, README drift fixes, optional Onboard and Docs recipes. Implemented | — (foundation) |
| S03 | [Practical debugging](S03-debugging-reproduction.md) | Reproduction and state-inspection references for assistant-debugging. Implemented | S01 terms only |
| S04 | [TDD craft](S04-tdd-craft.md) | One craft reference with worked authoring-time examples for assistant-tdd. Implemented | Shared-example split with S05 |
| S05 | [Review methods and test value](S05-review-and-test-value.md) | Perspective briefs, optional preflight, CI Audit test-value questions and audit-time examples. Implemented | Shared-example split with S04 |
| S06 | [Security and advisory triage](S06-security-and-advisory-triage.md) | Three Security companion references; new assistant-advisory-triage skill. Implemented | Integration count reconciliation and held-out refreeze |
| S07 | [Research provenance and recovery](S07-research-provenance.md) | Source register for substantial reports, citation checks, bounded failed-fetch recovery. Implemented | S01 terms only |
| S08 | [assistant-spike](S08-assistant-spike.md) | New disposable-experiment skill and a prose handoff to Workflow. Implemented | Integration count reconciliation and held-out refreeze |
| S09 | [assistant-ui-qa](S09-assistant-ui-qa.md) | New exploratory UI QA skill feeding the QA evaluator. Implemented | Integration count reconciliation and held-out refreeze |
| S10 | [Skill retirement and Ideate consolidation](S10-skill-retirement.md) | Remove Telos; retire Diagrams after migrating its obligations to Docs/Workflow; merge Ideate into Thinking and remove Ideate (user decision 2026-11-06). Implemented in main 02cfeff (#110) | S11; integration count reconciliation and held-out refreeze |
| S11 | [Cleanup and uninstall](S11-cleanup-and-uninstall.md) | New cleanup skill with a deterministic ownership helper; `uninstall.sh`/`uninstall.ps1`; one retired-item inventory; installers auto-remove proven-owned retired skills and agents through the same helper (user decision 2026-11-06). Implemented in main 1e18c8a (#108) | Audit repairs F5, F4, F2; integration count reconciliation and held-out refreeze |

## Coordinator reconciliations

These resolve conflicts between the slice drafts. Individual specifications record the same choices.

- **Weak-test examples:** split by moment of use. S04's TDD reference owns worked authoring-time examples (call shape, subject-generated expected value, mock-supplied behaviour). S05's CI Audit `test-maintenance.md` owns audit-time examples (fabricated receipts, wrong-guard negatives, owner-level cleanup, F3) and names the authoring classes in one line. Neither restates the other, and each skill stays installable alone.
- **Shared terms:** S01 defines requested outcome, direct answer, material support, coverage check and relevance check once, in `tools/progress/operating-guidance.md`. Other slices cite them and do not restate them. That guide is loaded on every turn through the managed instruction block, so S01 keeps its additions there compact: the five definitions and the coverage and relevance checks, stated once. Each consuming skill holds only application text for its own outputs and links to the guide without restating the method (S01 D1).
- **Activation suite:** `test_committed_suite_is_valid` (`tools/evals/skill-activation/test_skill_activation.py:518-521`, run in CI by `tests/test-skill-activation-tools.sh` via `.github/workflows/framework-validation.yml:56-57`) checks `suite.validate_all()` only. `validate_all` fails any directory under `skills/` with fewer than three held-out positive cases (`tools/evals/skill-activation/suite.py:200-213`) and any case naming a row missing from `routing.json` (`suite.py:176-178`); it does not check the frozen held-out hash. The hash matters only for held-out trial runs: `run_trials.py:83-88` refuses a held-out batch when `suite.heldout_frozen()` is false, and the `suite.py` CLI reports a changed freeze (`suite.py:331-333`). Therefore each slice that adds or removes a skill (S06, S08, S09, S10, S11) makes its own branch green: it adds or removes at least three held-out positive cases and the routing rows (spec table and `routing.json`) so the suite validator passes. The integration step does **one** held-out refreeze (`suite.py freeze --refreeze`) after the slices merge; that refreeze matters only for held-out trial runs. Held-out case changes go through the user's R-EVAL-3 review, and any model run needs fresh authorization.
- **Skill counts:** the contract tests derive the count rather than pinning 16. `tests/p0-p4/docs-drift-contracts.sh:14-33` counts `skills/assistant-*/SKILL.md` and fails when README lacks a `### <skill>` section for any of them or lacks "N first-class" for that count (`:15`, `:28`); `tests/p0-p4/skill-eval-contracts.sh:5949-5967` (count at `:5950`) derives N from the default fixtures and requires "default eval inventory is N first-class" in README and "covers all N first-class" in `docs/evals/skill-fixtures.md`. Each slice that adds or removes a skill therefore adds or removes its README `### <skill>` section and updates the derived counts (README.md:3, :353, the literal "All 16" at :701, and `docs/evals/skill-fixtures.md:22` with its fixture list) in its own change. The integration step reconciles the final count across merged slices. Dated measurements in `docs/specs/skill-activation.md` stay as history.
- **Evidence for new methods:** the contract design guide requires expert-judgment methods to come from representative cases or an authoritative method (`docs/skill-contract-design-guide.md:14-22`). The new skills' methods currently rest on comparator skills and the report. S06 (advisory-triage close bar), S08 (experiment-and-verdict method) and S09 (severity and coverage method) each record this as an `evidence_gap` row in their Evidence classification, to close before acceptance of the method text; S11 adds the equivalent row in its own revision.

## Implementation order

1. S01 and S02, one owner, coordinated edits to shared files.
2. In parallel, in isolated worktrees after path checks: S03, S04, S07; then S05, S06, S08, S09.
3. Audit repairs F5 → F4 → F2 (separate session), then S11, then S10.
4. Integration: reconcile the final skill count and README inventory across the merged slices (each slice already kept its own branch green), do one held-out refreeze for held-out trial runs, run aggregate validation, then integrated verification and a fresh independent review.

## Decisions for the user

The user decided every product question on 2026-11-06. Each specification records the choice as "Decided by user 2026-11-06" under its decision. Except where noted, the user took the recommended default.

- **S01:** D3 request alignment also applies to tickets and specifications written without Workflow.
- **S02:** D1 (a) load score bookkeeping conditionally; D2 leave the QA scorecard out; D3 include the Onboard recipe; D4 add the context-tool component (schema 3.0); D5 include the unconditional legacy prose in S02; D6 S02 owns README drift, installer consolidation deferred.
- **S03:** decision 3, Python, Node **and .NET** recipes (user's choice; shell scripts stay a later proposal).
- **S04:** decision 2, (c) leave the signature-only stub question undecided.
- **S05:** decision 3, S05 owns the installed-path/configured-home example.
- **S06:** decision 1, **no model activation trial now; ask for fresh authorization later if one is needed** (user's wording); 3, latest release per channel plus policy-declared lines; 4, a general disclosure rule.
- **S07:** decision 1, (a) substantial = deliverable report, five-lens run or explicit request; 5, defer arxiv, youtube-content, competitor-news-monitor and llm-wiki.
- **S08:** D4 both neighbour pairs; D5 Workflow handoff optional; D6 no model trial now (as S06).
- **S09:** D3 include the inspect-before-CSS-edits section; D4 both neighbour pairs; D5 new routing row only; D6 no automatic selection by Workflow; D7 no public-site exception, production stays forbidden; D8 no model trial now (as S06).
- **S10:** D-S10-1 (a) migrate the per-element evidence binding to Docs; D-S10-2 (a) ad hoc diagrams through the general capability, amended 2026-11-12 to (c): diagrams of existing code route through Docs, concept sketches stay with the general capability; D-S10-4 **merge Ideate into Thinking now** (user's choice; brings the consolidation into S10).
- **S11:** D-S11-4 (a) the skill gives the uninstall command; D-S11-5 (a) keep and report modified files; D-S11-7 (a) keep and report the `~/.agents` link; D-S11-8 **(b) installers auto-remove proven-owned retired skills and agents** (user's choice; R-S11-25 to R-S11-27); D-S11-9 offer shim removal only when unregistered, with the installers writing shims until the user declares the compatibility window closed.

Follow-up decisions, settled 2026-11-06 when the user accepted the set with the recommended defaults:

- **D-S11-13:** no opt-out flag for installer removal; `--dry-run` is the preview.
- **R-S11-25:** installer removal also runs on `--skill` single installs, as retired-tool removal does today.
- **D-S11-12, D-S10-6, D-S10-7, D-S10-8 (technical defaults, accepted):** inventory reading in `install.sh` without Python ((b): a generated, test-checked tool list as the one allowed derivative of the inventory); keep the option-ranking routing row under Thinking; extend `creative.md` rather than add a method value; drop Thinking-to-itself neighbour fields.

Still open:

- **R-RUN-10 baseline arms.** The 76 `activation_cases` ran with one arm, so no regression verdict exists. The two baseline arms need fresh authorization: about 456 calls and $126.
- **Behaviour eval reruns.** Four cases produced no answer within the per-run cap, and the cleanup cases need a fixture home with the ownership helper and a filesystem sandbox before their result means anything. Any rerun needs fresh authorization.

Unowned report items not covered above (document-to-action-items, meeting-action-items, hermes-agent-skill-authoring, github reference structure) are proposed as deferred.

## Live runs after integration, 2026-11-13

The user authorized each run with a call count and a cost cap. Every run used `deepseek-flash` on host 2.1.321. The held-out, `activation_cases` and behaviour runs used main 79e6a74. The development batch used 77b9240, the integration branch head before merge, with the same plugin tree. Per-run records stay in local Git-ignored evaluation state.

- **Activation.**
  - The 21 new and changed held-out cases passed 63 of 63 trials, with no misroute ($16.43).
  - The 76 `activation_cases` ran with one arm: 72 pass, 3 fail, 1 inconclusive ($62.78).
  - A development batch from the integration branch before merge passed 82.1% of graded trials, with no false activation ($64.07).
  - Details and failing cases are in [skill activation, Integration runs](../skill-activation.md#integration-runs-2026-11-13).
- **Behaviour evals.**
  - 26 cases each ran once ($11.59 in total): the new cases of S03, S04, S07, S10 and S11, plus Workflow's changed trigger case.
  - Each subject got a task-only packet, the setup context and the request without grading criteria, in a fresh temporary home and empty working folder. It had the generated `current` plugin, Read, Grep and Glob only, no MCP servers, no settings sources and a $0.90 cap.
  - Responses were graded offline with `tools/evals/run-skill-evals.sh --responses`.

| Skill | Pass | Notes |
|---|---|---|
| `assistant-debugging` (S03) | 4/5 | `exact-symptom-reproduction-rejects-nearby-failure` ran out of the per-run cap with no answer |
| `assistant-tdd` (S04) | 0/2 | Both answers reject the bad RED evidence, but lack the required phrases "double application" and "shares the defect" |
| `assistant-research` (S07) | 1/5 | Two cases ran out of the cap with no answer; the other two lack "gap", "official alternative" or "not sent" |
| `assistant-thinking` (S10) | 0/5 | Each answer lacks one or two required phrases, such as "trade-off", "next step", "risks" or "vulnerabilities" |
| `assistant-docs` (S10, code diagrams) | 1/2 | `architecture-doc-diagram-uses-source-evidence` ran out of the cap with no answer |
| `assistant-workflow` (changed trigger) | 0/1 | Lacks "Triage" |
| `assistant-cleanup` (S11) | 3/6 | Two misses come from the test environment and one is a substring false positive; see the limits below |

Total 9 of 26. The grader checks required and forbidden substrings, so it does not separate a wrong answer from a right one worded differently. The phrase misses above need a reading of each answer before they count as behaviour gaps.

Limits:

- **Reads outside the workspace.** The Read tool was not sandboxed. Despite the temporary home, the cleanup subjects read the real installed homes, found no ownership helper there and correctly refused to proceed. That caused the apply and dry-run misses. The one forbidden-word hit, "rmdir", is the answer saying it will not use it. Some thinking answers also quote the real repository. All tools were read-only, so nothing changed.
- **Run coverage.** One trial per case and one model. No shell, so command-running behaviour was not exercised. The four capped cases were not rerun.
- **No before/after claim.** The S07 before-condition did not run.
- **Runner not committed.** The runner script is local, not part of the repository.

## Corrections to the source report found while drafting

The drafts verified the report against d11756d and found these differences. The specifications use the verified facts.

- Review score bookkeeping is consumed (Review output and gate X3, Workflow gate R6, tests), not unused.
- Legacy compatibility text still loads on every Research activation and in the common guide's migration section; only Workflow and Review load it conditionally.
- Workflow and Review already reconcile the original request with the plan and delivery; S01's new work is on authoring and presentation.
- Research contracts are v5 (v4 is history).
- Workflow already has a `spike` task type and Spike gate pack; S08 resolves that overlap.
- The QA evaluator is read-only and cannot produce UI evidence; the main actor runs S09's exploration.
- Diagrams' structured contract has no runtime producer; only tests consume it.
- Installer, reviewer-role and F3 line numbers have moved since c920fd8.

Return to the [specifications index](../README.md).
