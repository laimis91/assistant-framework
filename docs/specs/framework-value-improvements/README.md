# Framework value improvements — specification set

Status: **Accepted by the user**, 2026-11-06. Baseline: main d11756d. S01 to S04 are implemented (see their rows); each remaining slice still needs an approved implementation plan before any edits.

Source: [framework value assessment](../../research/assistant-framework-value-assessment-2026-10-26.md). The user accepted the S01–S11 slice map and its decisions on 6 November 2026: matched evaluation for S01 and S05 only; new skills bundled by default with `--skill` for single installs; a cleanup skill plus uninstall script (S11); no word or character budgets.

## Specifications

| Slice | Specification | Adds | Depends on |
|---|---|---|---|
| S01 | [Request alignment and focused delivery](S01-request-alignment.md) | Shared request-coverage and relevance terms in the common guide, applied by Research, Workflow, Docs and Review's document checklist. Implemented; matched evaluation supported as a tie | — (foundation) |
| S02 | [Conditional instruction loading and maintenance](S02-conditional-loading.md) | Score bookkeeping loaded only where consumed, canonical links, README drift fixes, optional Onboard and Docs recipes. Implemented | — (foundation) |
| S03 | [Practical debugging](S03-debugging-reproduction.md) | Reproduction and state-inspection references for assistant-debugging. Implemented | S01 terms only |
| S04 | [TDD craft](S04-tdd-craft.md) | One craft reference with worked authoring-time examples for assistant-tdd. Implemented | Shared-example split with S05 |
| S05 | [Review methods and test value](S05-review-and-test-value.md) | Perspective briefs, optional preflight, CI Audit test-value questions and audit-time examples | Shared-example split with S04 |
| S06 | [Security and advisory triage](S06-security-and-advisory-triage.md) | Three Security companion references; new assistant-advisory-triage skill | Integration count reconciliation and held-out refreeze |
| S07 | [Research provenance and recovery](S07-research-provenance.md) | Source register for substantial reports, citation checks, bounded failed-fetch recovery | S01 terms only |
| S08 | [assistant-spike](S08-assistant-spike.md) | New disposable-experiment skill and a prose handoff to Workflow | Integration count reconciliation and held-out refreeze |
| S09 | [assistant-ui-qa](S09-assistant-ui-qa.md) | New exploratory UI QA skill feeding the QA evaluator | Integration count reconciliation and held-out refreeze |
| S10 | [Skill retirement and Ideate consolidation](S10-skill-retirement.md) | Remove Telos; retire Diagrams after migrating its obligations to Docs/Workflow; merge Ideate into Thinking and remove Ideate (user decision 2026-11-06) | S11; integration count reconciliation and held-out refreeze |
| S11 | [Cleanup and uninstall](S11-cleanup-and-uninstall.md) | New cleanup skill with a deterministic ownership helper; `uninstall.sh`/`uninstall.ps1`; one retired-item inventory; installers auto-remove proven-owned retired skills and agents through the same helper (user decision 2026-11-06) | Audit repairs F5, F4, F2; integration count reconciliation and held-out refreeze |

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
- **S10:** D-S10-1 (a) migrate the per-element evidence binding to Docs; D-S10-2 (a) ad hoc diagrams through the general capability; D-S10-4 **merge Ideate into Thinking now** (user's choice; brings the consolidation into S10).
- **S11:** D-S11-4 (a) the skill gives the uninstall command; D-S11-5 (a) keep and report modified files; D-S11-7 (a) keep and report the `~/.agents` link; D-S11-8 **(b) installers auto-remove proven-owned retired skills and agents** (user's choice; R-S11-25 to R-S11-27); D-S11-9 offer shim removal only when unregistered, with the installers writing shims until the user declares the compatibility window closed.

Follow-up decisions, settled 2026-11-06 when the user accepted the set with the recommended defaults:

- **D-S11-13:** no opt-out flag for installer removal; `--dry-run` is the preview.
- **R-S11-25:** installer removal also runs on `--skill` single installs, as retired-tool removal does today.
- **D-S11-12, D-S10-6, D-S10-7, D-S10-8 (technical defaults, accepted):** inventory reading in `install.sh` without Python ((b): a generated, test-checked tool list as the one allowed derivative of the inventory); keep the option-ranking routing row under Thinking; extend `creative.md` rather than add a method value; drop Thinking-to-itself neighbour fields.
Still open:

- **Held-out activation cases** change with the Ideate merge and the new skills; they need the user's R-EVAL-3 review before any rerun.

Unowned report items not covered above (document-to-action-items, meeting-action-items, hermes-agent-skill-authoring, github reference structure) are proposed as deferred.

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
