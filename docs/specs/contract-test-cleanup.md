# Contract test cleanup

Status: **Accepted** by the user 2026-11-17, with decisions D-TC-1 to D-TC-6 as recommended. Slices A–D implemented 2026-11-18 in one pull request; the runtime target (D-TC-3) and the checks proposed for deletion are open decisions, see Implementation notes. Revised the same day after an independent review (5 major, 10 minor, 1 nit findings), all addressed below. Baseline: main 487b8d3.
Source: user request of 2026-11-17 to clean up the tests because they take too long to run and feel over-engineered, with too many checks. The check inventory and classifier behind this specification are local working material (`docs/plans/test-cleanup/`, Git-ignored); each pull request carries the evidence it relies on (R-TC-11).

## Problem and intended outcome

`./tests/test-p0-p4-contracts.sh` sources 51 suites in `tests/p0-p4/` holding 1,239 `test_start` checks, about 64,000 lines of test code (helpers included) against about 20,700 lines of skill prose and 18,600 lines of eval tooling. Every suite passes. Measured on 2026-11-17 on the user's Mac, each suite as its own process with six to eight suites running at once:

- The per-check times add up to about **6,870s (1h55m)**. That is a sum under contention, not a measured serial run; Slice A records a serial baseline. CI avoids the wait by running four suites as separate 60–75 minute shards (`.github/workflows/framework-validation.yml`).
- Five suites take 91% of the time: `skill-eval` 2,632s, `workflow-architecture-completion` 1,468s, `codex-behavioral-eval` 1,224s, `assistant-research` 469s, `progressive-discovery` 461s.
- The cost comes from mutation checks on eval cases and eval tooling. Each mutated response gets its own temporary skill folder and a fresh `tools/evals/run-skill-evals.sh` process, about 0.85s per call, and single checks make hundreds of calls (the slowest, "strict required-QA baselines satisfy the active small-elevated tier and lifecycle", takes 523s).
- Many checks assert only that a sentence or field exists in a skill's markdown, YAML contract or eval fixture. They fail on any rewording, so they add edit friction without testing behavior.

Intended outcome: one test command that runs in minutes, where each remaining check protects something a plugin user or maintainer would notice if it broke, and no safety safeguard, eval-case assertion or eval-tooling rule loses coverage without the user's agreement.

## Inventory summary

A heuristic classifier sorts every check by what it asserts and what it runs. A check reaches a delete or replace bucket (5–8) only through the mechanical gate in R-TC-2; everything uncertain goes to hand review. The time column is the contention-measured sum above.

| Bucket | Proposed action | Checks | Seconds |
|---|---|---:|---:|
| 1 Packaging and structure: skill validator, sync, plugin, self-containment, CI layout | keep | 72 | 131 |
| 2 Safety in the check's name | review each, default keep | 77 | 11 |
| 2b Safety terms in the check's body | review each, default keep | 123 | 17 |
| 3 Eval tooling and eval cases, few calls | keep | 294 | 234 |
| 4 Eval tooling and eval cases, mutation loops | shrink | 335 | 6,410 |
| 5 Contract field matching across contract files | replace with the generic validator | 10 | 0 |
| 6 Wording pins inside YAML contracts | delete | 1 | 0 |
| 7 Eval-fixture content pins | delete | 0 | 0 |
| 8 Prose wording pins in skill markdown | delete | 10 | 0 |
| 9 Reads files through variables the classifier cannot prove are skill text, runs code, or unclassified | review each | 317 | 62 |

The strict gate passes only 21 checks for removal without review. Most wording pins read their target through a suite-level variable or run a small script, so they land in bucket 9. Removing them is hand review, about 517 checks across buckets 2, 2b and 9; the runtime gain comes almost entirely from bucket 4.

## Requirements

### What a check must protect

- **R-TC-1. Test-value rule.** A contract check is kept only when it fails for a defect a user or maintainer would notice: a broken plugin, skill or CI structure, a lost safety safeguard, inconsistent contracts that consumers read, an eval case that stops rejecting a wrong response, or eval tooling that accepts a wrong response or rejects a right one. A check that only shows a sentence or literal exists in a skill file is not kept, with three exceptions: safety wording (R-TC-3), skill-description phrases pinned for activation precision (`tests/p0-p4/skill-activation-precision-contracts.sh`, see [skill activation](skill-activation.md)), and a check an accepted specification names as an ongoing guard (R-TC-4). `CLAUDE.md` and `AGENTS.md` gain this rule as a one-line convention so new checks follow it.
- **R-TC-2. Disposition and the delete gate.** Before any check is removed or rewritten, the inventory records its disposition (keep, shrink, replace, delete) and, for replace and shrink, what now covers it. A check may be deleted or replaced without hand review only when all of these hold:
  - every file it asserts on is skill or documentation text, not CI, agent configuration, tests or the harness;
  - it runs nothing (no child shell, `mktemp`, copy, tool or script beyond reading files);
  - neither its name nor its body matches the R-TC-3 term list.

  A variable counts as skill or documentation text only when every assignment in the suite gives it the same plain path under `skills/` or `docs/`; a variable filled by command substitution, assigned different values in the suite, or not resolvable fails the gate. Every other check that is not plainly packaging, structure or eval tooling (buckets 2, 2b and 9) is decided one at a time.
- **R-TC-3. Safety preserved.** The safety term list covers safety itself (`safe`, `safety`, `unsafe`), destructive operations, overwrite and force, permissions and sandboxes, secrets and credentials, untrusted input, injection and path traversal, approval and consent, commit and push, preservation of user work, and the user's real state (`HOME`, `CODEX_HOME`). A check that guards any of these is not deleted. It may be rewritten or merged only when the same defect still fails a kept check, shown by a kill probe (R-TC-9). The user decides any proposed deletion in bucket 2 or 2b.
- **R-TC-4. Specification-named checks.** When an accepted specification names a check as an ongoing guard for a current requirement (for example `skill-activation.md` R-DESC-5, `plugin-marketplace-packaging.md` R-MP-8), the check stays, or that specification is updated in the same change to name what now guards the requirement. Line-reference inventories, delivery-time verification sections and reports of past runs in implemented specifications are historical and stay as written, including the many suite line references in the [framework value improvements](framework-value-improvements/README.md) set. The search covers suite file names, check names and `file:line` references.

### Replacement and shrinking

- **R-TC-5. Generic contract-consistency rules.** The bucket-5 checks are replaced by rules in `tools/skills/lib/validate-contracts.sh`, which `tools/skills/validate-skills.sh` already runs and which already enforces `on_missing` and `enum_values`. Slice A first lists the rule families the bucket-5 checks enforce and maps each to an existing rule where one exists. A new rule is added only for a family that holds across the skills, or that the contract design guide requires, such as a producer's `return_fields` satisfying the consumer's `context_fields`. Each removed check maps to a rule, or is reclassified as a wording pin and deleted under R-TC-1. New rules have failing fixtures. A check moved into bucket 5 during Slice B's hand review maps to an existing rule, stays as a kept check, or is deleted as a pin; a new rule it needs is added in Slice B under the same fixture requirement.
- **R-TC-6. Representative mutations.** The unit of protection is one assertion of one eval case (a `structured_json_assertion`, `required_substring` or semantic-validator obligation), or one rule in eval tooling. A mutation's rejection reason is the assertion or rule the runner reports as failed. For each unit a bucket-4 check covers, at least one rejected mutation is kept, plus one accepted response per case. A mutation is removed when a kept mutation fails with the same rejection reason. A unit counts as safety when its assertion or rule matches the R-TC-3 term list, not because a variable is named `unsafe_response`. Safety units keep one mutation for each distinct unsafe input class they name. If a unit would lose its last mutation, the user decides.
- **R-TC-7. Batched grading.** A shared test helper grades several response mutations in one eval-runner process, and reports the same pass or fail per response as one call each. It covers response grading only. Fixture-validation mutations (`--validate-fixture`) stay one call each, because one invalid fixture stops the run. The runner finds a response by skill folder name and case id, and by task-packet basename for packet cases (`tools/evals/lib/skill-eval-grade.sh:11-26`). It also requires exact case-id sets for semantic-validator cases (`tools/evals/lib/skill-eval-fixtures.sh:1331-1350`), so distinct case ids per mutation cannot work for the research, creator and packet cases. Slice A picks the mechanism. Allowed: a new runner option that only changes how responses are found (for example a response map), never how they are graded, with the equivalence shown once for each lookup class: plain, packet basename and semantic validator.

### Runtime, CI and documentation

- **R-TC-8. Runtime and CI.** `./tests/test-p0-p4-contracts.sh` runs all kept suites serially within the target in D-TC-3 on the user's Mac. The plan sets a time budget per suite. CI runs the aggregate in one job with an explicit timeout and no long-suite shards; `P0P4_EXCLUDED_SUITES` and `p0p4_suite_is_excluded` are removed. The repo-guard schedule and CI checks (`tests/p0-p4/repo-guard-contracts.sh`: `validate_p0p4_ci_schedule` at `:6-132` and the checks at `:134`, `:146`, `:271-316`, `:324` and `:353-374`) are rewritten in the same change, not deleted:
  - they keep that every top-level suite except the compatibility wrappers is sourced exactly once by the aggregate, and the wrappers stay unsourced;
  - they keep the CI security assertions: read-only `contents` permission, `persist-credentials: false` on every checkout, no `pull_request_target` and no `secrets.` use;
  - they keep the ripgrep and Ruby prerequisite checks;
  - they drop only the shard-specific assertions.

  The response-fixture entrypoint probe moves to the single job. If the target is missed only because of safety or unit coverage, the report names the suites over budget and D-TC-5 applies.
- **R-TC-9. Kill probes.** Each slice that deletes, replaces or shrinks checks records reversible probes on a disposable copy. Each probe plants a defect the removed checks guarded and shows that a kept check fails, run against the owning suite or validator rather than the whole aggregate. Probes include:
  - a desynced skill copy;
  - a handoff field mismatch;
  - a referenced file renamed;
  - harness isolation broken (the ambient `CODEX_HOME` sentinel);
  - an eval-tooling rule switched off;
  - for each case whose mutations were shrunk, one of its assertions removed.

  A surviving probe gets a new check or the user's explicit acceptance.
- **R-TC-10. Documentation and references.** Current guides that describe the suites are updated in the same change: `README.md`, `AGENTS.md`, `CLAUDE.md`, `docs/evals/framework-fixtures.md` (the `--fixtures-only` commands and the entrypoint probe), `docs/harness-design-guide.md` and `docs/instruction-block.md`. References in `docs/evals/` and `tools/` (for example `docs/evals/framework-instruction-cases.json` and the stub suite written by `tools/evals/run-codex-framework-evals.sh`) are kept working. A suite left with no checks is deleted with its aggregate line, unless anything names it, including the compatibility wrappers (`tests/p0-p4/workflow-contracts.sh`, `tests/p0-p4/agent-status-contracts.sh`) and fixtures under `tests/`; then the reference is updated or the suite is kept. This index lists the specification.
- **R-TC-11. Evidence in the pull request.** Each pull request description lists the dispositions of the checks it removes or rewrites, the kill probes and their results, and the before and after timings, so reviewers do not need the local inventory.

## Delivery slices

Each slice is one branch, worktree and pull request from current main.

| Slice | Content | Depends on |
|---|---|---|
| A | Serial timing baseline; generic contract rules (R-TC-5); backtick paths in the containment check (D-TC-2); batched grading helper (R-TC-7). Additive, nothing removed | — |
| B | Hand review of buckets 2, 2b and 9; delete buckets 6–8 and replace bucket 5 (R-TC-1–R-TC-5) | A |
| C | Shrink bucket 4, one suite at a time (R-TC-6, R-TC-7) | A; for each suite, after B's change to that suite has merged |
| D | Single CI job and repo-guard rewrite, documentation, runtime confirmation (R-TC-8, R-TC-10) | B, C |

If Slice A's new rules find real inconsistencies in `skills/`, the fix lands first as its own pull request, with `tools/skills/sync-plugin.py --apply` and a `version.txt` bump as `CLAUDE.md` requires. A deliberate exception is allowlisted with its reason instead. Slice A never lands with `validate-skills.sh` failing. Slices B–D change only tests, tools, CI and documentation, so they need no version bump.

## Verification

- Slice A start: a serial run of every suite, one at a time, timed per suite; this replaces the contention sums as the baseline.
- Every slice: `tools/skills/validate-skills.sh`, the suites it changed, `./tests/test-skill-activation-tools.sh`, and the CI workflow on the pull request. The full aggregate runs once per slice, not per probe.
- Slice A: new rules and the containment extension reject their failing fixtures and pass on the repository. Batched and single-call grading give identical per-response results for one mutation set of each lookup class.
- Slices B and C: kill probes (R-TC-9); per-suite serial timing before and after.
- Slice D: one timed serial aggregate run against D-TC-3; a search of guides, `docs/evals/` and `tools/` for removed suites, flags and check names.

## Decisions

Approved by the user 2026-11-17 as recommended.

- **D-TC-1.** Wording pins are deleted, not moved into evals. Behavior belongs to the skill eval cases; a pin restated as an eval would still only check wording.
- **D-TC-2.** Pins that only show a skill names one of its files ("Load `references/x.md`") are replaced by one check in `tools/skills/check-skill-containment.py`, which today resolves `](…)` Markdown links but not backtick paths. A backtick path starting `references/`, `contracts/`, `evals/` or `scripts/` resolves from the skill root, then from the file's folder. Text that describes the structure of another skill or project, such as `assistant-skill-creator/SKILL.md` describing a skill being created, is allowlisted per file with a reason. Fixtures cover both outcomes.
- **D-TC-3.** The runtime target is 10 minutes serial on the user's Mac. Kept buckets other than 4 measure about 440s under contention, which leaves about 160s for bucket 4: a cut of about 97.5% from 6,410s through shrinking plus batching. The Slice A serial baseline rechecks this arithmetic before Slice C starts. If it shows 10 minutes is out of reach without breaking R-TC-3 or R-TC-6, the user picks a new target then.
- **D-TC-4.** One test command stays; no separate fast and full tiers.
- **D-TC-5.** If the target is missed only because of safety or unit coverage, a fast default tier with an opt-in full run is the fallback, decided then by the user.
- **D-TC-6.** `tests/test-skill-activation-tools.sh` (14s) is out of scope. How the eval runners grade is out of scope; R-TC-7 allows only an additive response-lookup option.

## Implementation notes

Recorded 2026-11-18 for the pull request that implements slices A–D.

- **One pull request.** The user asked for all slices on one branch and one pull request instead of one per slice.
- **No generic contract validator (R-TC-5).** None of the 10 bucket-5 checks matched fields across contract files; they pinned wording. They were deleted as pins under R-TC-1, and no rule was added to `validate-contracts.sh`.
- **No batched grading (R-TC-7).** One grader call measured about 0.25s of process start-up and 0.6–0.7s of grading, so batching would save about 25%. Suites instead grade single-rule mutations in-process with the grader's own functions, and keep one full runner call per case or runner path:
  - `skill-eval` sums `count_structured_json_assertion_failures` and the review envelope count, as the runner does.
  - `codex-behavioral-eval` sources the runner's functions, extracted up to its argument parsing; the extraction fails if the runner's shape changes. Its per-run grading sequence is a copy of the runner's `execute_one_run`, and the copy omits the forbidden-command count, the trusted VIEWING seed and the semantic extract. Paths that depend on those keep an end-to-end runner witness; a change to `execute_one_run` is caught only where such a witness covers it.
- **D-TC-2** is implemented as Rule 3 of `tools/skills/check-skill-containment.py`, with fixtures in `skill-self-containment-contracts.sh`. A path after a possessive naming a framework skill ("Workflow's `scripts/x.py`") resolves in that skill, and is skipped only when that skill is absent from the checked copy. Any other possessive ("the skill's") resolves as usual.
- **R-TC-8** is implemented: one CI job, `framework-contracts`, and the repo-guard checks rewritten. The job timeout is 90 minutes, because the serial aggregate takes about 32 minutes on the user's Mac and the old single-suite shards needed 60–75 minutes on CI. Set it from the first measured CI run.
- **Dispositions.** 1,226 checks were reviewed per suite. The other 13 of the 1,239 are in `repo-guard`, rewritten under R-TC-8, and `skill-contract-guide-sync`, unchanged. 232 were deleted and 151 shrunk. 126 were proposed for deletion but left in place, because they touch R-TC-3 safety terms or a spec names them; the user decides on these. The rest were kept. One deleted check, on not keeping whole model responses, was restored after review as a safety-term check. Five unused helpers were removed from `tests/p0-p4/lib/`.
- **Kill probes (R-TC-9).** These ran on disposable copies. The probes the suite agents ran for their own suites were all caught except two, which the user must accept or give new checks:
  - A dropped `required_substring` in `docs/evals/framework-instruction-cases.json` goes undetected.
  - Trimming `pilot_cases` in the workflow-kernel manifest goes undetected.

  The workflow-evidence-spine check "eval fixtures disclose every closed-world artifact constraint" was found to be vacuous: it cannot fail.

### Runtime

| Measurement on the user's Mac | Before | After |
|---|---:|---:|
| Serial aggregate, one suite at a time | 4,265s | 1,940s |
| `skill-eval`, standalone | about 2,632s (contention) | 618s |
| `codex-behavioral-eval`, standalone | 1,309s | 498s |
| `workflow-architecture-completion`, standalone | 1,579s | about 430s (under load) |
| `assistant-research`, standalone | 418s | 200s |
| `progressive-discovery`, standalone | 473s | 80s |

**The 10-minute target (D-TC-3) is not met.** The remaining time sits in kept units:
- one rejected mutation per eval assertion (R-TC-6);
- one accepted response per case;
- one end-to-end runner witness for each distinct runner path in `codex-behavioral-eval`.

Reaching 10 minutes would mean a coarser unit of protection or the D-TC-5 fast tier. The user picks between those and a new target.

### Known flakes, not caused by this change

- The skill validator intermittently rejects a valid fixture description with `FRONTMATTER_DESCRIPTION`. It was seen in the `skill-creator-semantic` and `skill-validator` suites, including on the unchanged baseline, and was not reproduced in four later runs under either locale.
- "supervisor cleanup confirms absence or fails within its deadline…" in `codex-behavioral-eval` failed only while two suites ran in parallel.
