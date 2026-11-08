# S04 — TDD craft

Status: **Accepted by the user**, 2026-11-06 (drafted and revised the same day). Baseline: main d11756d. Implemented on branch `fvi/s04-tdd-craft` (from main 7c9bdf8), merged to main as 841a755 (#90): `skills/assistant-tdd/references/test-craft.md`, linked from the RED step; two offline eval cases; no contract change. Live runs of the two new eval cases have not been made (they need the user's authorization). SKILL.md, guide and contract line citations rechecked against main 0f5fc76.
Source: report §1.B "TDD: add craft examples alongside the gates", §6 row 12, §4 order 3; slice map row S04. Overlap analysis with report §1.D / slice S05.

## Problem and intended outcome

assistant-tdd defines when TDD is active, who owns RED/GREEN/REFACTOR, and what counts as meaningful RED evidence, but it shows no worked example of a test worth entering that cycle. A writer can satisfy the gates with a plausible test that asserts a mock's configured return, a private call shape, or an expected value computed by the code under test, and such a test can pass without protecting the requirement. The change adds one craft reference, loaded while authoring or correcting a test inside selected TDD, with original worked examples. Observable result: a useful regression test rejects the intended wrong behaviour, and its RED fails for the intended reason.

## Requirements

- **R-S04-1** assistant-tdd gains one craft reference under `skills/assistant-tdd/references/` (the skill has no `references/` directory today), linked from the RED step of `SKILL.md` and loaded only when TDD is already active and a test is being authored or corrected.
- **R-S04-2** The reference contains one good/bad test pair for the same requirement. The good test exercises observable behaviour through a public entry point with an expected value taken from the requirement; the bad test would still pass if the requirement were broken.
- **R-S04-3** The reference contains one intended-RED and one wrong-reason-RED example for the same test: the intended failure shows the missing behaviour (for example "expected 900, got 800"); the wrong-reason failure comes from setup, import, fixture, environment or an unrelated assertion and does not authorise production edits.
- **R-S04-4** The reference contains one short vertical behaviour slice: the next behaviour is taken through RED and GREEN before the next test is written, contrasted with writing a batch of tests for imagined layers first. The example stays within one active behaviour and does not conflict with the separated-workers stage order.
- **R-S04-5** The reference explains, with one short illustration each, why these tests can pass without protecting the requirement: (a) asserting internal call shapes or call order; (b) deriving the expected value from the subject under test; (c) asserting behaviour that a mock or stub supplies. Each explanation names the defect the test would miss.
- **R-S04-6** The reference states that substitutes remain valid at unstable or external boundaries when the assertion is on the subject's own observable result, and that exact-text, schema or call checks are valid when those bytes or interactions are themselves the contract.
- **R-S04-7** The reference adds no phase, report field, gate, test quota, activation rule or broad-suite requirement; it changes no contract file.
- **R-S04-8** Shared junk-test examples have a single owner across S04 and S05 (see Unresolved decision 1); the TDD reference does not duplicate the CI Audit examples verbatim, and neither skill depends on the other being installed.

## Existing behaviour to preserve

- Selected-TDD scope: TDD only when requested, required by project policy, or activated for selected checks; inactive TDD never needs a fabricated RED (`skills/assistant-tdd/SKILL.md:13-15`). Description unchanged (`SKILL.md:3`).
- RED: meaningful behaviour assertion, intended missing-behaviour failure before production edits; syntax/import/environment/flaky failures do not authorise production; a passing RED triggers inspection of existing behaviour and the oracle, never removal of working code or invented failure (`SKILL.md:19-23`).
- GREEN: smallest change; selected regressions and binding checks; no inferred full suite; incidental assertions do not justify production changes (`SKILL.md:26-31`).
- REFACTOR with optional `none needed` and v3 `reuse_green` (`SKILL.md:32-39`).
- Ownership: `bounded_executor` vs `separated_workers` with the same selected writer for `test_authoring`, `production`, `refactor` (`SKILL.md:54-59`); one intersecting CheckSpec ID per active packet and exact RED binding (`SKILL.md:61-66`).
- Unknown-cause bugs go through assistant-debugging before selecting the regression oracle (`SKILL.md:70-71`).
- Contract gates: RED1 one behaviour-focused assertion when tests need creation/repair; RED2 executed and failed; RED3 right reason, excluding syntax, missing import or wrong setup; RED4 no production code during RED and no deletion of prior work (`contracts/phase-gates.yaml:18-35`).
- One cycle per behaviour; split complex behaviours (`contracts/input.yaml:44-49`). Meaningful-failure oracle binding (`contracts/output.yaml:55`, `:115`, `:119`).
- Related guidance owned elsewhere, not to be contradicted: tests must distinguish expected behaviour from a plausible wrong outcome; tautological assertions give no evidence (`skills/assistant-workflow/references/ai-usage-policy.md:42-44`); "Mock at boundaries, not at implementation details" (`skills/assistant-workflow/references/prompts/test-strategy.md:67`); unit traps including private call-order assertions (`skills/assistant-verification/references/methods/unit.md:11`, `:15`); CI Audit's internal-coupling and exact-bytes guidance (`skills/assistant-ci-audit/references/test-maintenance.md:8-9`, `:20`).

## Scope and non-goals

In scope: one new reference file in assistant-tdd; one conditional link in `SKILL.md`; focused eval case(s) in `skills/assistant-tdd/evals/cases.json`.

Out of scope (report "Do not import" and slice brief):
- Universal TDD activation (comparator `test-driven-development/SKILL.md:24-37`).
- One test per function (comparator `:282` "Every new function/method has a test").
- Deletion of pre-existing implementation (comparator `:45-53`, `:259-276`).
- Mandatory broad-suite runs (comparator `:146-150`, `:315`).
- "Test passes immediately? Fix the test" (comparator `:109`), which conflicts with `SKILL.md:21-23` (inspect existing behaviour and oracle first).
- Copying the comparator's examples: its "bad" example injects a mock as the retried operation (`:80-87`); injecting a fake operation is a legitimate seam for a retry helper, so it is not a clean illustration of mock-supplied behaviour. Write original examples.
- Any new phase, report, schema, gate or contract change; changes to Workflow, Verification or CI Audit files (CI Audit changes belong to S05).

## Affected owners and consumers

- Owner: `skills/assistant-tdd/SKILL.md` (one link); new `skills/assistant-tdd/references/<craft>.md`; `skills/assistant-tdd/evals/cases.json` (five cases today: `bugfix-starts-with-red-evidence`, `green-refactor-runs-selected-regressions`, `tdd-covers-carried-architecture-obligations`, `unknown-cause-bugfix-waits-for-debugging-evidence`, `ownership-separated-stage-order`).
- Consumers of TDD text: `tests/p0-p4/tdd-contracts.sh` (evals and contracts), `tests/p0-p4/skill-instruction-quality-contracts.sh:236-253` (RED/REFACTOR gates as consumed interfaces), `tests/p0-p4/test-ownership-contracts.sh:279`. Workflow's build-worker protocol and `separated_workers` writers consume the RED rules; the reference is advisory to the writer and changes no handoff.
- Single-skill install: assistant-tdd declares no `requires` (`SKILL.md:1-4`), so the reference must be self-contained.
- No contract compatibility concern: no contract file changes.

## Evidence classification

| Item | behavior_status | work_status | Evidence |
|---|---|---|---|
| Selected-TDD activation and ownership | existing_behavior_to_preserve | no_open_decision | `SKILL.md:13-15`, `:54-66` |
| RED right-reason gate | existing_behavior_to_preserve | no_open_decision | `contracts/phase-gates.yaml:27-30` |
| No `references/` directory in assistant-tdd | new_behavior | implementation_gap | `find skills/assistant-tdd` lists only `SKILL.md`, `contracts/*`, `evals/cases.json` |
| Worked good/bad pair, RED pair, vertical slice | new_behavior | implementation_gap | No examples in `SKILL.md` or contracts |
| Principles against call-shape, tautological and mock-at-implementation tests | existing_behavior_to_preserve | no_open_decision | Stated, without worked TDD examples, in `ai-usage-policy.md:42-44`, `test-strategy.md:67`, `unit.md:11-15`, `test-maintenance.md:8`, `:20`. Report §1.B does not mention these; the gap is examples, not principles |
| Overlap with S05 junk-test examples | source_conflict | technical_design_decision | Report §1.D adds self-comparisons and mock-supplied behaviour to `test-maintenance.md`; §1.B adds subject-generated expected values and mock-supplied behaviour to TDD |
| RED for a behaviour behind a not-yet-existing symbol | materially_unknown | product_question | RED3 rejects missing-import failures (`phase-gates.yaml:29`) and RED4 forbids production code during RED (`:32-34`); no source says whether a signature-only stub counts as production code (searched `skills/assistant-tdd`, build-worker protocol, verification references for "stub", "skeleton", "compile") |
| Comparator "fix the test if it passes" | source_conflict | source_conflict_resolution | comparator `:109` vs `SKILL.md:21-23`; keep the framework rule |

## Unresolved decisions

1. **Single owner for shared junk-test examples** (technical_design_decision; reconcile with S05 before either is implemented). Options:
   - (a) CI Audit `test-maintenance.md` owns all examples; TDD links to it. Breaks standalone TDD install: no `requires` relation exists between the skills.
   - (b) Canonical doc under `docs/` with generated skill-local copies, like lifecycle verification (`skills/assistant-debugging/references/lifecycle-verification.md:3-5`). Adds sync tooling for a small text.
   - (c) **Recommended:** split by moment of use, no shared text. TDD craft owns the *authoring-time* worked examples for the three classes in R-S04-5 (call shape, subject-generated expected value, mock-supplied behaviour), each tied to "this RED cannot fail for the intended reason". CI Audit (S05) owns *audit-time* examples on existing suites — fabricated receipts, wrong-guard negative tests, owner-level cleanup with remaining proof, and the F3 wrong-outcome case — and names the authoring classes in one line with its own keep/rewrite disposition, without restating TDD's example code. Reason: both skills stay self-contained, each example appears once, and the boundary follows the existing TDD-vs-audit split. **Reconciled with S05 (coordinator, 2026-11-06): (c) is the set-wide default.** CI Audit owns audit-time examples; TDD owns authoring-time worked examples; neither restates the other's example text.
2. **Not-yet-existing symbol RED** (product_question). Options: (a) a signature-only stub that returns nothing meaningful is test scaffolding and allowed before RED; (b) it is production code, so the first RED must go through an existing entry point or the cycle records the missing symbol as a blocker; (c) leave undecided and keep examples on existing entry points. Recommend (c) for this slice: the craft examples use an existing entry point and do not settle the rule; a gate interpretation change would belong to a contract change, not a craft reference. **Decided by user 2026-11-06:** option (c), leave undecided (the recommended default).
3. **Example language** (technical default). Recommend Python for brevity with a one-line note that the shape applies in C#/TypeScript; the repo's C# guidance stays with Review's C# reference.

## Acceptance examples

Requirement used throughout: "A 100-cent promotion is applied once to an order; a 1000-cent order totals 900."

- **R-S04-2 positive:** Test builds a real order and promotion, calls `checkout(order)`, asserts `total == 900`. Introducing a double-application bug makes it fail with `800`. Passes.
  **Negative:** Test replaces the pricing rules with a mock returning `900` and asserts `checkout(order).total == 900`. With the double-application bug in the real rules it still passes. Fails R-S04-2.
- **R-S04-3 positive:** RED output "expected 900, got 800" before the fix; recorded as the meaningful failure. Passes.
  **Negative:** RED output "ModuleNotFoundError: promotions" (or a missing fixture file) is recorded as RED and production edits begin. Fails (matches RED3's exclusion).
- **R-S04-4 positive:** Slice 1: "promotion applied once" RED→GREEN; slice 2: "second identical promotion rejected with a named error" RED→GREEN, each through `checkout`. Passes.
  **Negative:** Writer authors tests for parser, rule engine and receipt formatter first, then implements all layers. Fails. (Also negative: the example implies `separated_workers` may author tests for several active IDs in one stage, contradicting `SKILL.md:61-64`.)
- **R-S04-5 positive (each class):** the reference shows that `rules.apply.assert_called_once_with(order)` passes while totals are wrong; that `expected = compute_total(order); assert checkout(order).total == expected` passes with the bug because both share it; and that a stubbed rate service returning the asserted discount tests the stub. Each names the missed defect. Passes.
  **Negative:** The reference forbids all mocks or all call assertions. Fails R-S04-6.
- **R-S04-6 positive:** An example notes that asserting the exact request sent to an external payment API is valid when that request format is the contract. **Negative:** Text implies exact-byte checks are always brittle. Fails.
- **R-S04-7 negative:** The reference adds "write at least one test per public method" or "run the full suite after GREEN". Fails.
- **R-S04-8 negative:** The same mock-supplied-behaviour code example appears in both the TDD reference and `test-maintenance.md`. Fails.

## Verification

- `tools/skills/validate-skills.sh`.
- `./tests/test-p0-p4-contracts.sh`, especially `tdd-contracts.sh`, `skill-instruction-quality-contracts.sh` and `test-ownership-contracts.sh`, to confirm the RED/REFACTOR interfaces are unchanged.
- One or two focused eval cases in `skills/assistant-tdd/evals/cases.json` in the existing shape: given a draft test asserting a mock-supplied value (or a subject-generated expected value), the response rejects it as RED evidence, rewrites it against the requirement, and keeps selected-TDD scope (no universal activation, no deletion of existing code, no broad-suite mandate).
- A source check that the reference adds no gate, field, quota or activation text, and that no example code is duplicated with S05's `test-maintenance.md` changes.
- No matched evaluation (reserved for S01/S05). Behavioural eval runs need the user's authorisation.

## Dependencies and overlap

- **S05** (Review methods and test value): shares the junk-test example classes; Unresolved decision 1 must be settled jointly before either slice is implemented. S05 owns `skills/assistant-ci-audit/references/test-maintenance.md`; S04 does not edit it.
- **S03** (Practical debugging): a minimised exact-symptom reproduction from S03 can become the RED oracle; S04's wrong-reason RED example should use the same "exact symptom, not generic failure" language as R-S03-2/3.
- Existing Workflow and Verification guidance (`ai-usage-policy.md`, `test-strategy.md`, `unit.md`) states the principles; S04 should link nothing cross-skill and must not contradict them.
- No dependency on S01/S02 beyond the unchanged operating-guidance link (`SKILL.md:10`). Independent of S06–S11.
