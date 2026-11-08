# S05 — Review methods and test-value judgment

Status: **Accepted by the user**, 2026-11-06 (drafted and revised the same day). Drafted against main d11756d; evaluation baseline main 7c9bdf8. Implemented on branch `fvi/s05-review-test-value` (base main 7c9bdf8), not merged; **unaccepted**: the matched evaluation (R-S05-14) is prepared and awaits the user's authorization. The user confirmed the five-part decision rule as written and chose no requirement ID for decision 3 (checked by contract text pins) and no ninth corpus family, so the matched evaluation does not exercise the Verification examples (R-S05-15, R-S05-16, decision 3); focused evals cover them.
Source: report §1 C "Review" (`docs/research/assistant-framework-value-assessment-2026-10-26.md:97-110`), §1 D "Test value" (`:111-126`), §4 order 4 (`:214`), "Recommended direction" audit-lessons row (`:17`), "Additional audit findings" (`:226-249`, Verification ownership at `:232-233`), assessment rows 8, 9, 13, 16 (`:276-284`), §7 adjustments (`:342-358`); review techniques catalog (`docs/research/review-techniques-catalog-2026-10-28.md`, gap analysis `:106-162`, proposals `:374-409`, user decisions `:411-427`, implementation status `:429-441`); slice map row S05 and the unassigned F6/F7 item (`docs/plans/framework-value-improvements/specification-index.md`).

## Problem and intended outcome

Review already assigns distinct discovery perspectives by batch size, but nothing tells a reviewer pass what each perspective should lead with, so passes can converge on the same obvious findings. Simplification findings need not state their actual cost or rule out an intentional compatibility boundary. There is no practical recipe for a cheap preflight over added lines or for telling baseline failures from new ones without disturbing the user's checkout. CI Audit already covers retained protection, duplicates, coupling and cost. It lacks the four authoring questions, concrete junk-test examples, a worked cleanup example and a failed-discovery-versus-valid-empty example. The report also makes Verification the selector of preservation checks (audit lesson 1) and a co-owner, with CI Audit, of failed-versus-empty discovery (lesson 2) (`report:17`, `:232-233`), but Verification has neither example today. After the change, review passes should produce more unique concrete findings and fewer false or low-value ones. Test-value judgments should remove weak proof while keeping important exact-byte, platform and protocol contracts. A matched evaluation checks both outcomes.

## Requirements

Review briefs (owner: assistant-review)

- **R-S05-1** Review provides one concrete brief example for each existing discovery perspective (`contract_and_test_oracle`, `runtime_lifecycle_and_failure_paths`, `integration_compatibility_and_consumers`, `architecture_maintainability_and_reuse`). Each brief states what that pass leads with: contract and test-oracle risk; execution and failure behaviour; connected consumers outside the diff; or ownership and reuse. The single `light_contract_and_runtime` pass gets a combined example covering the first two.
- **R-S05-2** Every brief example keeps the pass's original review criteria (request, spec or acceptance criteria) and source access beyond the diff. A brief changes which questions a pass asks first. It does not remove the other questions, narrow the assigned scope or hide sibling-blind boundaries.
- **R-S05-3** The briefs fit the existing perspective, coverage-obligation and batch topology. They add no perspective, pass, round-to-lens schedule or reviewer count.

Simplification findings (owner: assistant-review)

- **R-S05-4** A simplification, reuse, altitude or workaround finding states its actual cost: what is duplicated, wasted or made harder to change, with file:line evidence.
- **R-S05-5** Such a finding also states why the apparent workaround is not an intentional boundary, such as a compatibility shim, staged migration, vendored-code isolation or documented divergence. Evidence can come from history, comments, consumers or docs. When intent cannot be determined, the finding stays low-confidence and non-blocking, unless the duplicate changes authoritative semantics or causes an observed defect; then the Reuse Search severity applies.

Optional preflight (owner: assistant-review)

- **R-S05-6** Review offers an optional, targeted preflight recipe. The orchestrator can use it before a review batch: scan only the added lines for suspicious patterns, and separate baseline failures from new ones. It is never a required step, gate or extra pass.
- **R-S05-7** A preflight hit is a lead to inspect, not a finding. It becomes a finding only after the normal findings bar (real situation, file/line, impact, confidence; `skills/assistant-review/SKILL.md:13-16`). Preflight leads never reach discovery passes as findings, so sibling and discovery blindness is unchanged.
- **R-S05-8** The baseline-versus-new recipe compares failures by identity and cause: check ID, failure signature and the reason it fails. It never compares counts alone. A failure present at baseline stays visible in the report and is not automatically irrelevant. The same check failing for a different reason counts as new.
- **R-S05-9** The baseline recipe never stashes, resets, checks out over or otherwise modifies the user's checkout, index, branches or dirty work. Execution follows the existing review authority: audit stays static (`references/script-execution.md:3`), and review-fix and workflow-composed review run checks as they do today.

Test value (owner: assistant-ci-audit `references/test-maintenance.md`, unless the junk-example owner decision below says otherwise)

- **R-S05-10** For a new or changed test, the test-value guidance asks four authoring questions: (1) which observable contract it protects; (2) which credible regression makes it fail; (3) why existing proof misses that regression; (4) whether it needs a production seam (export, flag, wrapper or hook) that has no real caller. A "yes" to (4) points the proof back to the real boundary.
- **R-S05-11** The guidance gives concrete junk-test examples with the reason each proves nothing:
  - a fixture that fabricates a receipt, ordering or persistence that the owner should produce;
  - a negative test that passes on the wrong guard or an unreachable rejection;
  - and, in one line without worked example code (S04's TDD craft reference owns those), the authoring-time classes: self-comparison or subject-generated expected value, internal call-shape assertions, and a mock that supplies the behaviour being asserted, each with CI Audit's keep/rewrite disposition.
  Each example sits next to a contrasting retained case: an exact prompt, schema or installer byte check, or a platform or protocol contract, that is a legitimate independent contract.
- **R-S05-12** The guidance includes one owner-level cleanup example. Before a removal is recommended, it names the remaining proof for each removed claim: the retained test or boundary and what it detects. When remaining proof cannot be named, the protection stays as an unresolved gap and the test is not removed.
- **R-S05-13** `test-maintenance.md` uses audit F3 (`tools/cognitive-complexity/run-complexity.sh` changed-file discovery) as a worked failed-discovery-versus-valid-empty example. `investigation.md` is not edited for F3; its discovery check (`investigation.md:19-21`) stays as is. An invalid requested comparison, such as a nonexistent base or a run outside a repository, must surface as a failure. A valid comparison with no relevant changes may report an ordinary empty result. The example identifies the defect; it does not repair the script (repair stays with the separate audit session).

Verification examples (owner: assistant-verification)

- **R-S05-15 Preservation-check selection (audit lesson 1).** Verification's `references/selection.md` gains one contrast example, next to the existing ones (`selection.md:50-54`): when a change writes into locations that may hold user-owned content (managed marker blocks, linked destinations, shared roots, overlapping source and target paths), the selected check observes the preservation outcome — exact retained bytes of a user-owned sentinel and rejection before the first write — rather than a structural check such as "the install completed" or "the managed files exist". Audit F1/F2/F4/F5 are named as the cases, without repairing them. Verification selects the observable check only. It does not enumerate or analyse the boundary classes; that analysis stays with Security's installer companion (S06 R-S06-3) and Review's user-owned file probe (`review-checklists.md:69`).
- **R-S05-16 Failed-versus-empty discovery (audit lesson 2).** Verification's `references/evidence-quality.md` "Wrong-outcome control" section (`:25-27`) gains one example: a discovery or selection step whose errors are suppressed can report "nothing to check" for an invalid requested comparison. A passing result whose selected set is empty is accepted only after confirming that discovery itself succeeded for a valid requested scope; otherwise it is a gap or failure, not passing evidence. The example names F3 as the case in one sentence and does not restate CI Audit's worked F3 example (R-S05-13), which is the full worked case. Both skills stay installable alone (no `requires`).

Evaluation

- **R-S05-14** S05 is accepted only after the bounded matched evaluation in Verification is run on frozen oracles and its pre-registered decision rule passes.

## Existing behaviour to preserve

- Findings bar and non-blocking style or speculation: `skills/assistant-review/SKILL.md:13-16`. Reviewer filtering: `agents/claude/code-reviewer.md:75-79` (mirrored in the other reviewer roles).
- Inspection beyond the diff ("connected callers/contracts/tests/configuration, including outside-diff consumers"): `skills/assistant-review/SKILL.md:13-14`. This rules out diff-only context.
- Additional tests need a distinct important uncovered failure: `skills/assistant-review/SKILL.md:17-20`, `references/review-checklists.md:5-11`.
- Dirty work is preserved and external operations need approval: `skills/assistant-review/SKILL.md:29-31`. This rules out automatic stashing.
- Perspective topology by scope size, not by round: `references/review-batch.md:6`, `contracts/handoffs.yaml:264-290` (trivial_small, medium and large canonical sets), perspective enum `contracts/handoffs.yaml:326`, and the reviewer role list `agents/claude/code-reviewer.md:68`. Sibling-blind passes: `references/review-batch.md:3-9`. `pre_batch_findings` are never dispatched to discovery passes: `contracts/handoffs.yaml:77`, `:366-370`.
- Existing reuse and simplicity lenses, including "intentional boundary duplication needs divergence control": `references/review-principles.md:19-34`. Principle reporting rule: `:64-73`.
- Existing test-oracle questions: "Ask whether a fake or incomplete implementation could still pass the tests" (`references/review-checklists.md:59-61`), the Document Review "Tests: could each fail against a plausible wrong implementation?" (`:148`), and eval coverage inheritance (`:88-90`).
- User-owned file rewrite probe (#79): `references/review-checklists.md:69`. Fixture-only script execution with `HOME`/`CODEX_HOME` isolation: `references/script-execution.md:1-31`.
- Document Review Checklist (#80): `references/review-checklists.md:142-148`. C# reference (#80, #83) in both reviewer load sets: `contracts/index.yaml:81-105`, `references/csharp-review.md:1-12`.
- Conditional lifecycle verification (#74): `references/review-checklists.md:137-140`, `contracts/index.yaml:93-105`; canonical `docs/lifecycle-verification.md` with generated copies (`references/lifecycle-verification.md:1-5`).
- Standalone review-fix runs build and tests; workflow-composed review runs due selected checks: `references/review-loop.md:38`.
- CI Audit authority and routing: findings grant no repair or deletion authority (`skills/assistant-ci-audit/SKILL.md:13-18`), with routing boundaries at `:20-24`. Inspect-only default and probe safety: `:28-40`, `references/investigation.md:27-48`.
- CI Audit maintenance rules: accepted behaviour first; failing expectations classified; exact text and schema checks valid when contractual (`references/test-maintenance.md:3-9`). Per-finding maintenance record rather than a per-test ledger (`:11-19`). Similar code or counts prove no waste (`:20-23`). Removal maps to retained protection, and uncertain protection stays a gap (`:25-30`). Measured cost only (`:35-48`).
- CI Audit discovery tracing: "whether a filter discovers the intended tests once"; empty findings are valid (`references/investigation.md:19-25`, `:50-53`).
- Verification wrong-outcome control rejects structural or phrase checks that would accept an empty, stale or incorrect artifact: `skills/assistant-verification/references/evidence-quality.md:27`. Verification selection names a plausible wrong result for each check (`references/selection.md:10`) and already carries worked contrast examples (`selection.md:50-54`). Its references are loaded on demand from `SKILL.md:36-37`. Neither reference mentions user-owned content, sentinels or failed-versus-empty discovery (grep "user-owned\|sentinel\|preserv\|empty" over `skills/assistant-verification`; `preserv` hits concern TDD mandates and instruction sources only, `selection.md:11,15,22`; `empty` hits are an array shape at `evidence-quality.md:13`, the general empty-artifact rule at `:27` and the TDD array at `selection.md:11`). Installed, activation, behaviour and comparative claims stay distinct: `:21`. Unit traps include private call-order assertions: `references/methods/unit.md:15`.
- Workflow Build failure classification includes baseline and environment failures, which "retain their blocking relevance": `skills/assistant-workflow/references/build-worker-protocol.md:214-225`.

## Scope and non-goals

In scope: brief examples and simplification-finding wording in Review's reviewer-loaded references; one optional preflight reference loaded only by the orchestrator; test-value additions to CI Audit's `test-maintenance.md` (questions, junk examples, cleanup example, F3 example); one preservation-check selection example in Verification's `selection.md` and one failed-versus-empty example in Verification's `evidence-quality.md`; new focused eval cases; the matched evaluation.

Out of scope and not imported:
- mandatory four-agent fanout;
- diff-only context;
- automatic stashing or any change to the user's checkout;
- fixed round-to-lens scheduling;
- counting failures without comparing identity and cause;
- per-test campaign ledgers;
- deletion counts or net-LOC targets;
- blanket rejection of source checks, since exact prompt, schema or installer bytes can be independent contracts;
- `[verified]` commit labels;
- the comparator's fixed two-cycle auto-fix;
- comparator Kanban or OpenClaw tooling.

Not included:
- repairs for audit F3, F6 or F7;
- new perspectives, passes, schemas or score mechanisms (score bookkeeping belongs to S02);
- changes to TDD craft (S04);
- request-coverage guidance (S01);
- security companions (S06).

## Affected owners and consumers

- `skills/assistant-review/references/review-principles.md` and/or `review-checklists.md`, reviewer-loaded through `contracts/index.yaml:81-105`. New brief examples land here, or in a new reference added to both reviewer load sets. Consumers: all four reviewer roles (`agents/claude/{code-reviewer,reviewer}.md`, `agents/codex/{code-reviewer,reviewer}.toml`). Their perspective list (`:68`/`:71`) should not need to change. No contract field changes, so no versioning is needed. `tests/p0-p4/assistant-review-reference-contracts.sh` pins the reference and load-set structure, so the plan must check its assertions.
- New orchestrator-only preflight reference in `skills/assistant-review/references/`. Its loading condition is named in `SKILL.md` or `review-loop.md`, and it must not enter the reviewer bundles.
- `skills/assistant-ci-audit/references/test-maintenance.md` (all CI Audit additions, including F3; `investigation.md` is unchanged). The CI Audit evals (`skills/assistant-ci-audit/evals/cases.json`, two cases today) and the response fixtures in `tests/p0-p4/lib/ci-audit-response-fixtures.sh` consume CI Audit behaviour.
- `skills/assistant-verification/references/selection.md` (R-S05-15) and `references/evidence-quality.md` (R-S05-16; also the F6/F7 example if Unresolved decision 3 is (a)). Consumers: Verification evals (`skills/assistant-verification/evals/cases.json`) and Workflow, which requires and consumes Verification's selection (`skills/assistant-workflow/SKILL.md:4-8`). No contract field changes.
- New eval cases in `skills/assistant-review/evals/cases.json` and `skills/assistant-ci-audit/evals/cases.json`. They are validated by `tools/evals/run-skill-evals.sh --validate-fixture` and `tests/p0-p4/skill-eval-contracts.sh`.
- Expert-judgment guidance rule (CLAUDE.md, `skills/assistant-skill-creator/references/expert-method-design.md:1-25`). The brief and test-value examples must trace to the cited comparator methods, the catalog's sources and the PR 77 replay (`review-techniques-catalog-2026-10-28.md:152-162`). They must not be model-invented.

## Evidence classification

| Item | behavior_status | work_status | Evidence |
|---|---|---|---|
| Distinct discovery perspectives by scope size | existing_behavior_to_preserve | no_open_decision | `review-batch.md:6`; `handoffs.yaml:264-290` |
| Prose saying what each perspective leads with (R1–R3) | new_behavior | implementation_gap | Not found. Grep of `skills/assistant-review/**/*.md` and `agents/**` finds the perspective names only as enum and list values (`handoffs.yaml:275-289,326`, `code-reviewer.md:68`). The catalog reports the same gap (`catalog:140`). |
| Inspection beyond the diff | existing_behavior_to_preserve | no_open_decision | `SKILL.md:13-14` |
| Reuse search, KISS/DRY/YAGNI | existing_behavior_to_preserve | no_open_decision | `review-principles.md:19-34` |
| Simplification finding states cost and rules out an intentional boundary (R4–R5) | explicit_change | implementation_gap | Reporting rule asks for lens, risk, evidence and fix (`review-principles.md:64-73`), but not cost or boundary intent. Only DRY mentions intentional boundaries (`:29`). |
| Added-line preflight and baseline-versus-new recipe (R6–R9) | new_behavior | implementation_gap | Not found in Review, Verification or CI Audit (grep "baseline" over those skills: only `script-execution.md:23` hash baseline and CI Audit probe baselines). Workflow classification exists (`build-worker-protocol.md:214-225`) without a recipe. |
| Failure classification including baseline | existing_behavior_to_preserve | no_open_decision | `test-maintenance.md:3-7`; `build-worker-protocol.md:214-225` |
| Four authoring questions (R10) | new_behavior | implementation_gap | Partial: plausible-wrong-outcome (`evidence-quality.md:27`, `review-checklists.md:59-61`). No test-only-seam or "why existing proof misses it" question. Grep "test-only\|production seam\|no real caller" over `skills/**/*.md` finds none. |
| Junk-test examples (R11) | new_behavior | technical_design_decision (owner) | Grep "self-compar\|fabricat.*receipt\|mock" over `skills/**/*.md`: no junk-test list. Nearest are `test-strategy.md:67` (mock at boundaries) and `unit.md:15`. |
| Exact bytes can be contractual | existing_behavior_to_preserve | no_open_decision | `test-maintenance.md:9` |
| Cleanup example naming remaining proof (R12) | explicit_change | implementation_gap | The rule exists (`test-maintenance.md:25-30`). No worked example. |
| F3 failed-discovery versus valid-empty example (R13) | new_behavior | implementation_gap | Defect still present: `run-complexity.sh:94-111` (`2>/dev/null \|\| true` at `:101-103`, exit 0 on empty at `:108-111`; silent `HEAD~1` fallback at `:89-90`). The CI Audit discovery check (`investigation.md:19-21`) does not separate failed discovery from empty selection. The worked example lands in `test-maintenance.md` (index "Weak-test examples" assigns F3 there). |
| Verification selects preservation checks (R15) | new_behavior | implementation_gap | Report assigns it (`report:232`). Not found in Verification (grep above); `selection.md:50-54` has contrast examples on other topics only. |
| Verification failed-versus-empty discovery example (R16) | explicit_change | implementation_gap | Report assigns it to Verification and CI Audit (`report:233`). The general rule exists (`evidence-quality.md:27`, empty artifact) with no discovery example. |
| User-owned file probe, script execution, C# reference, Document checklist, lifecycle verification | existing_behavior_to_preserve | no_open_decision | `review-checklists.md:69,142-148`; `script-execution.md`; `index.yaml:81-105` |
| Shared owner of junk-test examples (with S04 and Review) | materially_unknown | technical_design_decision | See Unresolved decision 1 |
| F6/F7 installed-path lesson | materially_unknown | product_question | See Unresolved decision 3 |
| Matched evaluation (R14) | new_behavior | evidence_gap | User decision 2026-11-06 (index); no prior run |

## Unresolved decisions

1. **One owner for the shared junk-test examples and the authoring questions** (technical_design_decision; coordinate with S04). Options:
   - (a) CI Audit `test-maintenance.md` is the sole owner. S04's TDD craft reference holds only positive worked RED and assertion examples and does not restate the junk list. Review keeps its existing oracle questions (`review-checklists.md:59-61,148`), and the new `contract_and_test_oracle` brief adds only a one-line question: could a fixture or mock supply the asserted behaviour?
   - (b) A canonical `docs/` file with generated skill-local copies in CI Audit, TDD and Review, kept in sync with a `--check` script, following the `lifecycle-verification.md` precedent (`references/lifecycle-verification.md:1-5`).
   - (c) Copies maintained by hand.

   **Recommended default: (a).** The report places these examples in CI Audit (`report:117,284`). TDD, Review and CI Audit declare no `requires` (frontmatter of each `SKILL.md`), so a cross-skill pointer is not install-safe. (b) adds a sync mechanism without a demonstrated second consumer. Switch to (b) only if the matched evaluation or S04's focused checks show that the Review or TDD consumer misses junk tests without the list. Never use (c).

   **Reconciled with S04 (coordinator, 2026-11-06): the set-wide default is S04's split by moment of use.** CI Audit `test-maintenance.md` owns the audit-time examples in R-S05-11 (fabricated receipts, wrong-guard negatives, owner-level cleanup, F3) and names the authoring-time classes (call shape, subject-generated expected value, mock-supplied behaviour) in one line with its own keep/rewrite disposition. S04's TDD craft reference owns the worked authoring-time examples. Neither restates the other's example text, and both stay installable alone. Option (a) above is superseded; (b) remains the fallback if focused checks show a consumer misses junk tests.
2. **Where the brief examples live** (technical_design_decision). Options: (a) add them to `review-principles.md` or `review-checklists.md`, which are already in both reviewer load sets; (b) add a new reference to both reviewer load sets. **Recommended default: (b).** A new file such as `references/review-briefs.md` keeps the four examples together and is easy to measure in the matched evaluation. Word limits were removed in PR 82 (`catalog:441`), so a separate file costs only an index entry.
3. **Proposal, from the unassigned F6/F7 report item: verify the actual installed producer-to-consumer path and configured home** (product_question: assign or defer). Evidence at d11756d:
   - Windows Codex installs skills under `~/.agents/skills` and tools under the agent home's `tools` (`install.ps1:2507-2523`).
   - The eval runner derives `REPO_ROOT` from its own location (`tools/evals/run-skill-evals.sh:7`) and resolves skills under it (`tools/evals/lib/skill-eval-inventory.sh:39-50`).
   - Reviewer roles hard-code `~/.codex/tools/...` (`agents/codex/code-reviewer.toml:85`, `agents/codex/reviewer.toml:87`) and `~/.claude/tools/...` (`agents/claude/code-reviewer.md:119`, `agents/claude/reviewer.md:121`).
   - Review's `script-execution.md:12-15` already isolates `HOME`/`CODEX_HOME` for fixture runs. Workflow and Verification have no equivalent, though `evidence-quality.md:21` already separates structural, activation and behaviour claims.

   Options:
   - (a) S05 owns one Verification example in `evidence-quality.md`: a check run from the source checkout does not establish the installed path. When a change affects installed tools or skills or home resolution, verify through the installed layout in a disposable configured home, and keep installed, available, selected, executed and outcome-verified claims distinct. Add one clause to Review's "Runtime surface sync" item (`review-checklists.md:71-72`) about literal default-home paths in roles and instructions. No Workflow text, because Workflow consumes Verification's selection (`skills/assistant-workflow/SKILL.md:4-8` requires assistant-verification).
   - (b) Defer to the audit-repair session together with F6/F7.
   - (c) Assign to S06 with the installer cases.

   **Recommended default: (a).** It is the smallest owner set that teaches the lesson where checks are selected and reviewed, and it uses F6/F7 only as examples, without repairing them. **Decided by user 2026-11-06:** S05 owns the installed-path / configured-home example (the recommended default).
4. **Pre-registered decision rule for the matched evaluation** (technical_design_decision; user acceptance requested with this spec). The recommended default is in Verification. **Confirmed by the user 2026-11-06** as written.
5. **Baseline isolation mechanism** (technical_design_decision for the plan). Options: a temporary `git worktree` at the base revision, or an exported copy of the base revision in scratch space. Both satisfy R-S05-9. A worktree writes metadata into `.git`, while an export does not. **Recommended default: export to scratch.** Use a worktree when the build needs repository metadata.

## Acceptance examples

- **R1–R3, positive:** a medium batch's `integration_compatibility_and_consumers` pass, given the example brief, starts from the renamed config key's consumers outside the diff, and still checks the acceptance criteria. **Negative (must fail):** a brief that tells that pass to "review only the changed files", or adds a fifth discovery pass.
- **R4–R5, positive:** "`parse_ref()` at `a.py:40` duplicates `refs.normalize()` at `refs.py:12`; the two diverge on trailing slashes, so two callers disagree; `git log` shows no compatibility reason; reuse `normalize`." **Negative:** "this wrapper looks unnecessary, remove it" with no cost stated, filed as should-fix against a shim whose commit message says it keeps the v1 API.
- **R6–R7, positive:** the preflight flags an added `2>/dev/null || true`. The orchestrator inspects it, confirms that an invalid input becomes success, and records a finding with file:line and impact. **Negative:** the preflight grep list is passed to discovery passes as a findings list, or an unconfirmed grep hit is reported as must-fix.
- **R8–R9, positive:** `test_export` fails at baseline with `KeyError` and after the change with `TimeoutError`. It is reported as a new failure with both causes, and the user's dirty checkout is unchanged. **Negative:** "baseline 3 failures, now 3 failures, no regressions", or `git stash` run on the user's checkout.
- **R10, positive:** a proposed test that adds `export function _resetCacheForTest()` is redirected to exercise cache expiry through the public API. **Negative:** the test is accepted because it passes, and no regression is named.
- **R11, positive:** the guidance flags a fixture that writes the payment receipt the service should produce, and retains a test asserting the exact bytes of an installed prompt block. **Negative:** both tests are recommended for removal because they "inspect source/text".
- **R12, positive:** "remove `test_order_total_internal`; remaining proof: `test_checkout_total` at `checkout_test.py:88` detects rounding regressions at the public boundary." **Negative:** "remove 14 duplicate tests" with no remaining proof named, or a cleanup reported as a count.
- **R13, positive:** the F3 example states that `--base nonexistent` with no local `.cs` changes exits 0 with "No .cs files to analyze.", while it should fail. A valid base with no `.cs` changes may legitimately print an empty result. **Negative:** the example treats every empty result as failure, or edits `run-complexity.sh`.
- **R15, positive:** for an installer change touching a managed marker block, Verification selects "seed a user-owned sentinel line outside the block and a sibling file in the shared root; after the run both are byte-identical, and an ambiguous-marker input is rejected before any write". **Negative:** the selected check is "install exits 0 and the managed block is present", or Verification's example lists and analyses the marker, link, shared-root and overlap boundary classes in the depth S06's installer companion does.
- **R16, positive:** a changed-file analysis step reports "0 files to analyze" for a requested base that does not exist; Verification records the result as a discovery failure or gap, not as passing evidence, while a valid base with no relevant changes is accepted as an ordinary empty result. **Negative:** "analysis passed, nothing to analyze" is accepted as sufficient evidence without checking that discovery succeeded, or Verification's reference copies CI Audit's full F3 walkthrough.
- **R14, positive:** both conditions are run on the frozen corpus, and the decision rule is computed from blind grades. **Negative:** the change is accepted from heuristic substring evals alone.

## Verification

Focused checks:
- `tools/skills/validate-skills.sh`;
- `./tests/test-p0-p4-contracts.sh`, in particular `tests/p0-p4/assistant-review-reference-contracts.sh` (reference and load-set pins) and `tests/p0-p4/skill-eval-contracts.sh`;
- `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-review --skill assistant-ci-audit --skill assistant-verification` for new eval cases, including one Verification case for R15 (sentinel-preservation check selected over a structural install check) and one for R16 (empty selection after failed discovery is not passing evidence);
- link checks for the changed references.

Each new eval case must have `fail_signals` that a plausible incomplete response triggers (`review-checklists.md:88-90`).

**Bounded matched evaluation (design):**
- **Question.** Do the changed instructions produce more unique concrete findings and fewer false or low-value findings than the current instructions, without losing retained protection?
- **Conditions.** Two conditions:
  - Current: main 7c9bdf8 (the S05 branch base, superseding d11756d per Ordering; S01 and S02 are present in both conditions), Review, CI Audit and Verification as installed.
  - Changed: the S05 branch.

  Model, host, effort, tools, case packets and prompts are identical. Each condition is installed into its own disposable home (isolated `HOME`/`CODEX_HOME`, following the `script-execution.md` pattern), so neither condition reads the other's or the user's installed copy. Run order is interleaved. Skills are invoked explicitly, so activation is not measured.
- **Corpus.** A fixed set of small seeded-defect fixtures, each with a request, a diff or suite, and a frozen oracle. The plan fixes the exact count and repetitions per case before any run. Recommended: one case per family below, three repetitions per condition.
  1. Contract or test-oracle: a mock supplies the asserted behaviour, so the test passes on a wrong implementation.
  2. Execution or failure: an error is suppressed, so a failure becomes success. Use an analogue of F3, not F3 itself.
  3. Connected consumers: a renamed key whose only consumer is outside the diff.
  4. Ownership or reuse: a re-implemented helper with divergent semantics.
  5. Simplification decoy: an intentional compatibility shim, which must not be filed as must-fix or should-fix, next to a genuine one-caller special case.
  6. Preflight: an added skipped test and debug leftover, plus a baseline failure whose cause changes.
  7. CI Audit test value: a fabricated-receipt fixture, a wrong-guard negative test, a self-comparison, and a contractual exact-byte test that must be kept.
  8. CI Audit discovery: a failed-versus-empty selection analogue.
- **Oracles.** Each seeded defect is identified by locus, mechanism and impact. Each decoy is identified with its correct disposition. Oracles are written and content-hashed before either condition runs and are never edited afterwards. Cases must not reuse the instances quoted in the changed instructions (F3 itself, the example tests), to avoid oracle leakage. An F3-identical case may be run only as a labelled contaminated illustration.
- **Measures, per run.**
  - Unique concrete findings matched to a seeded defect by locus and mechanism. Duplicates across passes count once.
  - Missed seeded defects.
  - False findings: contradicted by the oracle, including decoys filed as defects.
  - Low-value findings: must-fix or should-fix without concrete impact or cost, or style presented as a defect.
  - For CI Audit cases, correct keep or remove disposition with remaining proof named.
  - Tokens and elapsed time only where the host reports them; they never decide the outcome.
- **Grading.** Condition labels are stripped before grading. Code-based matching is used where the locus is exact. A separate grader actor matches locus and mechanism, and is not the authoring session. The user adjudicates disagreements or they are reported unresolved.
- **Pre-registered decision rule (confirmed by the user, 2026-11-06).** The changed condition is accepted when all of these hold:
  - its mean unique concrete findings is not lower overall;
  - false plus low-value findings are not higher overall;
  - no seeded must-find defect is found less often;
  - no retained-contract decoy is newly recommended for removal;
  - at least one target family (1–8) improves.

  Otherwise the specific failing instruction is revised or dropped.
- **Limits.** The sample is small and seeded, and its defects are not natural ones. The same model family generates and grades. The results do not show field benefit, native activation or cost savings. Per-run evidence stays in local Git-ignored state. Only the conclusion and its limits go into the durable record.

## Dependencies and overlap

- **S01** owns request coverage in Review's acceptance path. Briefs must not duplicate it; `contract_and_test_oracle` still receives acceptance criteria.
- **S02** owns Review's score bookkeeping (`SKILL.md:93`, `score-tracking.md`) and canonical documentation. S05 touches different Review files, and the plan must check for shared edits to `SKILL.md`.
- **S03** is unaffected except for the shared lifecycle precedent.
- **S04** coordinates through Unresolved decision 1. S04 owns the authoring-time worked examples and CI Audit the audit-time list (reconciled default); neither restates the other's example text.
- **S06** may touch the security specialist pass and installer examples. Boundary split: Verification selects the preservation checks (R-S05-15); Security analyses the installer ownership boundaries (S06 R-S06-3). S05's Verification example names the observable outcome and F1/F2/F4/F5 as cases only, and does not restate S06's boundary-class list. If decision 3 is (a), S05's Review "Runtime surface sync" clause must not duplicate S06's installer boundary text either.
- **Audit-repair session.** It owns F3, F6 and F7 fixes. If F3 is repaired first, the example must describe the defect historically, at d11756d, and stay accurate.
- **Ordering.** The matched evaluation's current-condition runs must use the baseline before any S05 edits land. Any S02 change to Review loading that lands first must be included in both conditions or recorded as a confound.
