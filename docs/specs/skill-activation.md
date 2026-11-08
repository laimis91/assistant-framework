# Skill activation requirements

Status: **implemented for `deepseek-flash`, candidate c1 adopted; see [Current state](#current-state).** Date: 2026-11-03, updated 2026-11-05. Rationale and sources: [skill activation research](../research/skill-activation-research-2026-11-02.md). Measured benefit applies only to the model and host stated in Current state.

Owners: skill descriptions and `activation_cases` stay in each `skills/assistant-*/`; authoring rules stay in the [contract design guide](../skill-contract-design-guide.md); eval commands stay in the [per-skill fixtures guide](../evals/skill-fixtures.md). Exact serialized formats belong with the runner that consumes them, not in this document.

## Problem

In the "Review process improvements" session, the assistant skipped `assistant-workflow`, `assistant-skill-creator` and `assistant-verification` on repository and skill changes. It also needed a user prompt about `assistant-research` and followed that skill only in part. The misses happened mostly on mid-flow turns such as a plan approval, a CI failure, "create pr" and a pasted bot comment, not on fresh task requests.

Before this work, the repository could not detect this failure: its activation cases were short single-turn requests, and nothing measured whether a skill ran before work started.

## Goals

1. Applicable skills activate before work starts, including on mid-flow turns and after compaction.
2. No current use case or precision protection is lost when descriptions change.
3. Any activation gain is measured against a baseline on frozen cases before it is adopted or claimed.

## Non-goals

- **Adherence after activation.** A skill being invoked and then only partly followed, as happened with `assistant-research`, is a separate failure. Existing per-skill `.cases` remain its owner. This spec records it as residual risk.
- **Forced-decision instruction** and **hook backstops.** Both are deferred by the user; see [Decisions](#decisions).
- **`deepseek-delegate`.** It is a local skill under `~/.claude`, and global `CLAUDE.md` owns its routing.
- **Automated Codex or Gemini collection.** The existing manual Codex observation route stays as it is. Descriptions remain portable across agents.

## Decisions

| Decision | Source | Effect |
|---|---|---|
| Resolve the "directly" versus "do not skip" contradiction | User, 2026-11-02 | Done in the installer Skills bullet |
| Forced-decision line in `CLAUDE.md` | User, 2026-11-02 | Deferred; reopen only through [R-GATE-4](#promotion) |
| Hook backstop | User, 2026-11-02 | Deferred; reopen only through [R-GATE-4](#promotion) |
| Skill review belongs to `assistant-skill-creator`; spec, plan, C#, test, Jira and refinement review belong to `assistant-review` | User, 2026-10-28 | Fixed routing in the oracle; see [OD-4](#accepted-defaults) for a boundary case |
| Evals must go beyond the four failing prompts | User, 2026-11-02 | [Eval suite](#eval-suite) |
| Existing use cases must be verified and kept | User, 2026-11-02 | [Use-case ledger](#use-case-ledger) |
| Typo routing, thresholds, models and review of skill changes | User, 2026-11-03 | [Accepted defaults](#accepted-defaults) |

## Constraints found in source

These limit the design and any implementation must respect them.

- **"explicit" is deliberate.** PR #40 "Tighten skill activation" replaced broad trigger lists with the current wording, including "explicit", to stop over-triggering. The research note's advice to drop the word therefore reverses an earlier decision and cannot be applied as a blanket edit.
- **Contract tests pin descriptions in both directions.** `tests/p0-p4/skill-activation-precision-contracts.sh` forbids phrases such as "what is" and "improve this", fails if a description shares two or more words of five or more letters with certain near-miss prompts, and requires two such shared words with seven named prompts. So both adding and removing words can break it. `tests/p0-p4/skill-instruction-quality-contracts.sh` requires the workflow description to contain plan, build and implement, and not brainstorm.
- **The "matches the request" wording is pinned.** Several contract tests check that exact phrase, including `installer-contracts.sh` and `workflow-basics-contracts.sh`. `install.sh` and `install.ps1` must stay in parity.
- **`activation_cases` has a closed format.** The validator requires exactly `user_request` and `should_activate`, so stateful cases cannot be added to it.
- **The runner never calls a model.** `run-skill-evals.sh --activation-results` only grades supplied observations, and it requires exactly one result per selected case.
- **Model calls need authorization.** The Codex trial guide requires fresh explicit authorization for each exact call count. It also forbids raw prompts and responses in results.
- **Claude Code's listing has limits.** Its [skills documentation](https://code.claude.com/docs/en/skills) states that the listing budget scales at 1% of the context window, that descriptions of the least-invoked skills are dropped first on overflow, and that each entry is capped at 1,536 characters. A skill that is rarely invoked can therefore lose its description and become less likely to be invoked. The repository's own limit is 1,024 characters per description.
- **Skill composition was undefined.** Neither the workflow nor the skill-creator `SKILL.md` defined how the two compose on a skill change. R-ROUTE-4 now does.
- **Declared chains are legitimate.** `assistant-workflow` declares `requires` on review, verification and tdd, and its body directs other skills, so a second activated skill is not automatically a false positive.

## Requirements

### Use-case ledger

- **R-LED-1.** Before any description changes, each of the 16 first-class skills has a ledger built from its description clauses, `activation_cases` (61 today: 40 positive, 21 negative), body scope and boundary statements, eval cases, and the contract tests that pin descriptions.
- **R-LED-2.** Description clauses and positive `activation_cases` map to the new description, because a body loads only after activation and a trigger moved there no longer helps. Other scope lines may map to the description or the body. Any removal records a reason the user has approved.
- **R-LED-3.** The ledger is local task state, per the [documentation rules](../README.md#update-documentation-with-the-change). Only the resulting descriptions, fixtures and documentation are committed.

The ledger must include at least these easily lost use cases:

| Skill | Must keep |
|---|---|
| `assistant-workflow` | Technical preparation without implementing, including Architecture Pack preparation; implementation, fixes, migrations, refactors; resuming task state; artifacts; backlog items; intended-change ideas |
| `assistant-review` | Review-fix and report-only audit; the workflow Review phase; QA only when required; spec, plan, C#, test, document, Jira and refinement review; its checklist for changes to skills and agent instructions, subject to [OD-4](#accepted-defaults) |
| `assistant-skill-creator` | Create, update, assess, review; plain `SKILL.md` targets outside V1; compliance; read-only check of registered upstream guidance |
| `assistant-verification` | Selecting proportionate checks; judging whether existing evidence is sufficient; code, skills, plugins and non-code artifacts |
| `assistant-research` | Source-backed research, topic investigation, current evidence, option comparison; must not claim "what is" questions or failure investigation |
| `assistant-security` | Threats, vulnerabilities, dependencies, attack surfaces; implicit triggers on auth, input and sensitive data, plus the workflow's list: external input, secrets, persistence, network or shell calls, dependency or config changes, external integrations |
| `assistant-tdd` | Tests-first requests, project TDD rules, workflow-selected checks |
| `assistant-debugging` | Unknown failures, root causes, flaky tests, unexplained breakage; not an already diagnosed fix |
| `assistant-ci-audit` | False passes, discovery gaps, stale fixtures, brittle or duplicate tests, cost |
| `assistant-ideate` | Light mode for improvement scans, deep mode for brainstorming; must not claim "improve this function" |
| `assistant-thinking` | Architecture trade-offs, stress tests, debate, first principles, hypotheses; must not claim clarification |
| `assistant-clarify`, `-docs`, `-diagrams`, `-onboard`, `-telos` | All current description clauses, plus body scope such as code explanation in docs, component diagrams, and Telos review |

### Descriptions

- **R-DESC-1.** Every candidate description states what the skill does and when to use it, in third person, with the key use case first, within the existing 1,024-character limit.
- **R-DESC-2.** Triggers stay in `description`. `when_to_use` and other Claude Code-only fields may add to the portable description, never replace a trigger in it.
- **R-DESC-3.** "explicit" is changed per skill with a recorded reason, not removed across the board. Skills with low false-activation cost and real misses are candidates first (`assistant-review`, `assistant-research`, `assistant-security`). `assistant-telos` and `assistant-ideate` keep their guard unless evals show it is safe to loosen.
- **R-DESC-4.** Descriptions gain state and target cues where the routing table needs them, such as `SKILL.md` and skill files for `assistant-skill-creator`, or review-comment and CI-fix work for `assistant-workflow`.
- **R-DESC-5.** `./tests/test-p0-p4-contracts.sh` and `tools/skills/validate-skills.sh` pass without changing any contract. Changing a contract or an existing case requires its own user-approved reason.
- **R-DESC-6.** No existing activation case regresses, as measured by [R-RUN-10](#collection-and-safety).
- **R-DESC-7.** The change reports total description characters before and after (2,193 before c1, 3,536 after). In the crowded listing condition from [R-RUN-3](#collection-and-safety), no first-class description may be dropped or truncated, assessed as R-RUN-9 determines.

### Routing oracle

This table is the expected behavior the evals grade. "Required" means activated before the first mutation, or before the final answer on a read-only turn. `assistant-verification` is required on non-trivial implementation rows because the workflow and debugging bodies both require it before a build or fix.

| Situation | Required | Optional | Forbidden |
|---|---|---|---|
| Feature, fix, refactor or migration, including right after plan approval | `assistant-workflow`, `assistant-verification` | `assistant-tdd` | |
| Technical preparation without implementing, including Architecture Pack preparation | `assistant-workflow` | `assistant-verification`, `assistant-thinking` | |
| Resume of task state, backlog item, or intended-change idea | `assistant-workflow` | `assistant-clarify` | |
| Tests-first request, project TDD rule, or workflow-selected TDD check | `assistant-tdd` | `assistant-workflow`, `assistant-verification` | |
| Failure with an unknown cause, diagnosis only | `assistant-debugging` | | |
| Failure with an unknown cause, fix authorized | `assistant-debugging`, `assistant-verification` | `assistant-workflow`, `assistant-tdd` | |
| CI fix or review comment with a known cause | `assistant-workflow`, `assistant-verification` | | |
| "create pr" with changes that never went through workflow | `assistant-workflow` | `assistant-review`, `assistant-verification` | |
| Change to `skills/**`, contracts or skill evals in this repository | `assistant-workflow`, `assistant-skill-creator`, `assistant-verification` | `assistant-review` | |
| Create or update a standalone skill outside this repository's delivery | `assistant-skill-creator` | `assistant-verification` | |
| Assess or review a skill | `assistant-skill-creator` | | `assistant-review` |
| Review and fix a skill in this repository | `assistant-skill-creator`, `assistant-workflow`, `assistant-verification` | | |
| Formal review of a delivered diff that touches skills | `assistant-review` | `assistant-skill-creator` | |
| Check of registered upstream skill guidance | `assistant-skill-creator` | | |
| Review of code, spec, plan, tests, documents, Jira ticket or refinement material | `assistant-review` | | `assistant-skill-creator` |
| Selecting checks or judging evidence, as its own request | `assistant-verification` | | `assistant-tdd` |
| Weak, slow or false-passing CI and tests | `assistant-ci-audit` | | `assistant-debugging` |
| Source-backed research or option comparison | `assistant-research` | | |
| Change touching auth, external input, secrets, sensitive data, persistence, network or shell calls, dependencies or config, or external integrations | `assistant-workflow`, `assistant-verification`, `assistant-security` | `assistant-tdd` | |
| Threat model, vulnerability audit, dependency audit or attack-surface analysis | `assistant-security` | | |
| Triage of a security advisory or vulnerability report | `assistant-advisory-triage` | `assistant-security` | |
| Request whose intent is still unresolved after inspection | `assistant-clarify` | | |
| Architecture trade-off or stress test | `assistant-thinking` | | |
| Generating and ranking options | `assistant-ideate` | | |
| Documentation work | `assistant-docs` | `assistant-workflow` | |
| Diagram request | `assistant-diagrams` | `assistant-workflow` | |
| Unfamiliar codebase | `assistant-onboard` | | |
| Purpose, mission or goals | `assistant-telos` | | |
| Narrow question, or running an existing test command | None | | Every skill |
| One-word typo | See [OD-1](#accepted-defaults) | | |

- **R-ROUTE-1.** Each case names the most specific rows it matches; a general row is not also matched when a specific one covers the same work. For example, a delivered diff touching skills uses the formal-review row for skills, not the general review row. When several rows still match, the required skills are their union, required beats optional, and Forbidden beats Optional. A case may not match rows whose Required and Forbidden sets conflict; such a conflict is a defect in the case or the table.
- **R-ROUTE-2.** A skill not listed on a matched row is not a failure if it is in the transitive `requires` of a required skill, or the body of a required skill directs it. Any other extra skill counts against precision without failing the trial. Only Forbidden fails.
- **R-ROUTE-3.** An activation in the replayed prefix satisfies a requirement, except in compaction cases as [R-EVAL-9](#eval-suite) defines.
- **R-ROUTE-4.** After a candidate is adopted, the workflow and skill-creator documentation defines how they compose on a skill change. This lands after adoption so it cannot confound the comparison. The evals do not grade order between the two, only that both precede the first mutation.

### Eval suite

- **R-EVAL-1.** The suite is separate from `activation_cases`, which stays unchanged as a fast regression layer.
- **R-EVAL-2.** Each case has a replayable conversation prefix, a final user turn, its matched routing rows, and any case-specific Forbidden skills. A prefix that says work was already done carries a setup that makes the disposable repository match it.
- **R-EVAL-3.** Seed cases come from real misses in local session transcripts. Mining stays in a local Claude session and uses no external delegate, including DeepSeek. Raw material stays in ignored storage readable only by the owner, with a stated deletion date. Committed fixtures are synthetic rewrites: no raw transcript content, private paths, credentials, personal data or private endpoints. A secrets and path scan and a human review both pass before commit.
- **R-EVAL-4.** Cases are split into a development set and a held-out set before any candidate is written, and held-out cases are frozen by hash. Candidates are written by a fresh actor that has not read the held-out cases. Held-out baseline results reach that actor only as aggregates.
- **R-EVAL-5.** Pairwise coverage across these dimensions is required. The full product is not, because it exceeds 1,600 combinations.
  - Size: typo, small, medium, large.
  - Phase: new request, plan approval, mid-build, CI failure, review feedback, PR creation, resume after compaction.
  - Input form: terse, conceptual, keyword-heavy, pasted artifact, multi-intent.
  - Wording: names the skill, implies the task, no process words.
  - Target: repository code, skill files, specs and plans, tests and CI.
- **R-EVAL-6.** Every skill has at least three stateful positive cases in the held-out set, with development cases on top, so a per-skill rate does not rest on one case. `assistant-workflow` and `assistant-skill-creator` also have one for each phase they apply to.
- **R-EVAL-7.** Negative cases are of two kinds, reported separately:
  - No skill should fire.
  - A neighbour must win. Required pairs: review and skill-creator; verification and tdd; debugging and ci-audit; debugging and thinking; research, thinking and ideate; workflow preparation and thinking.
- **R-EVAL-8. Sensitivity check.** A control arm installs the current source with only the Skills bullet reverted to its text before commit `36c59c5`, so later skill changes do not confound the result. It then replays cases derived from the real failing turns.
  - If the control does not miss at the [OD-2](#accepted-defaults) rate, the replay is not faithful. Fix it before any comparison.
  - If the control misses and the current baseline does not, the result is "already improved by the wording". Report that to the user before writing candidates.
  - If both miss, continue.
- **R-EVAL-9. Compaction cases.** Two kinds are reported separately: the skill never activated in the prefix, where the requirement must be met after compaction, and the skill activated before compaction, where re-invocation is reported but not graded at first. Claude Code's documentation advises re-invoking, but the evidence does not yet show it is needed for bodies that fit the retained size.

### Collection and safety

- **R-RUN-1.** Grading stays separate from model execution and makes no model calls, following the existing runner design. Collection is a separate command that needs explicit opt-in.
- **R-RUN-2. Containment.** A trial runs in a disposable repository and a temporary home. Its skills come from a plugin generated in ignored local state from the installer's output for the version under test, plus any crowded-condition stubs. No real-home content is copied in. The only credential is model authentication. The run also requires:
  - an environment scrubbed of other tokens and agent sockets, such as `GH_TOKEN` and `SSH_AUTH_SOCK`;
  - for runs that grant Bash, an OS sandbox confining writes and reads to the workspace and temporary home; for runs without Bash, the host's permission layer, shown by a refused write outside the workspace, because the eval documentation promises OS confinement only for Bash. The user accepted this for runs without Bash on 2026-11-03;
  - no git remote, no `gh` authentication and no MCP servers;
  - network egress limited to the model endpoint;
  - no real hooks, including Assistant Memory capture;
  - a stated permission mode in the run plan.

  If containment cannot be established, trials do not run. A changed `HOME` alone is not containment.
- **R-RUN-3. Listing conditions.** Every result records one of two: **isolated** (framework skills plus whatever the host itself lists) and **crowded** (isolated plus 40 inert synthetic stub skills, with description sizes stated in the run plan). The stubs give about the number of skills listed in the motivating environment.
- **R-RUN-4. Activation.** Activation is a `Skill` tool call, or a read of the skill's `SKILL.md` at its installed path in the generated plugin, through `Read` or a shell command that prints the file. A command that only mentions the path, such as `ls`, does not count. As an approximation, a file reader counts even when its output is piped or discarded. Reads of `skills/**` inside the fixture repository do not count, because skill-edit cases open those files as targets.
- **R-RUN-5. Mutation.** Mutation means `Edit`, `Write`, `NotebookEdit`, or a Bash command that commits, pushes, opens a PR or writes files. Nested tool calls in subagents count, and so does a refused attempt, because the decision was already made. The runner holds a shared read-only allowlist for all trials, such as `git status`, `git diff`, `ls` and `rg`. A case may add its own read-only and reproduction commands, such as its test command. Allowlisted commands are not mutations and do not stop a trial.
- **R-RUN-6. Decision point.** The host cannot stop a trial at a mutation, so `max_turns` bounds its length and the scorer reads the ordered trace only up to the first mutation, final answer, or unclassified Bash command, meaning one that is neither allowlisted nor a known mutation. A trace ending at an unclassified command scores as inconclusive, unless the host refused the command because Bash was not granted: it never ran, so reading continues. A trial that reaches `max_turns` before any of these stops passes if every required skill has activated and no Forbidden skill has, fails if a Forbidden skill has, and is otherwise inconclusive. A case with no required skills has nothing to show at the limit, so it is inconclusive there unless a Forbidden skill activated. A run error, an unreadable trace or a trace with no result is inconclusive, unless a mutation came first. Inconclusive trials leave the pass rate and are reported with their own denominator.
- **R-RUN-7. Authorization.** Each stage states its exact call count (cases × repeats × arms × models × listing conditions) and a cost cap, and needs fresh user authorization, following the Codex trial convention. This covers feasibility and sensitivity calls too. Defaults:
  - Smoke: 4 cases, 1 repeat, 1 model, isolated.
  - Pilot: development set, 3 repeats, 1 model, isolated.
  - Full: both sets, 5 repeats, 2 models, both listing conditions.
  - Pilot and full also add the R-RUN-10 term: 64 × 3 repeats × arms × models.
- **R-RUN-8. Retention.** Per-run results stay in local ignored state. Each records source commit, description hash, model, host version, listing condition, calls, tokens and time, and contains no raw prompt, response, credential or secret. Committed fixture text is not raw content, so a transient grader input may hold an `activation_cases` request; retained results use case identifiers. Temporary homes, including host-written session logs, are deleted after each run.
- **R-RUN-9. Feasibility, before building a collector.** This is a go/no-go check on:
  - whether containment from R-RUN-2 can be established;
  - whether `claude -p` structured output gives ordered tool calls;
  - whether a prefix can be replayed with fidelity, including a compaction;
  - whether a mutation can be intercepted without changing behavior;
  - whether the delivered listing can be captured, under what seeded usage history and context window size, and what evidence to fall back on if it cannot, such as the debug-log overflow warning;
  - whether `claude plugin eval` with its `tool_used: Skill` grader can be reused. It targets plugins, and this repository is not currently packaged as one;
  - whether `paths` frontmatter loads a skill in a way R-RUN-4 can observe.
- **R-RUN-10. Existing cases.** The 64 `activation_cases` (61 before S06 added `assistant-advisory-triage`) are collected as single-turn trials at the pilot and full stages, 3 repeats each, in the isolated condition, in every arm and on the same models. The rules are:
  - **Selection.** On a positive case, the selected skills are all those activated before the stop, so firing order does not matter. On a negative case, only the first activated skill counts, so a chained skill does not fail a neighbour's negative case.
  - **Run-only cases.** Two cases must run a command, such as "Run the existing route test command". Trials grant no Bash, so they cannot run it. They are collected anyway, because what they measure is whether a skill activates, and the report counts those trials. If a later stage grants Bash, a runner table keyed by case supplies the command, because the `activation_cases` format cannot declare it.
  - **Passing.** A case passes when a majority of its conclusive repeats agree with `should_activate`. A case with no conclusive majority is reported as inconclusive and is neither a pass nor a regression.
  - **Grading.** The new scorer applies the existing grader's comparison rule per repeat and aggregates. `--activation-results` needs one row per selected case and has no inconclusive state, so it is used only when every selected case is conclusive.
  - **Regression.** A regression is a case that passes in both baseline arms and fails on the candidate, on the same model. Cases where the baseline arms disagree are reported but not gated. The report says "not evaluated" and exits nonzero when a named arm has no valid rows, the arms differ in cases, repeats, suite, host or listing condition, an arm mixes plugin trees, the two baseline arms are different plugin trees, or a trial is counted twice, because an absent case must not read as no regression. It states how many of the existing cases were conclusive in all three arms, and says "not evaluated" if none were.
  - **Limit.** At `max_turns`, a positive case passes if its skill activated and is otherwise inconclusive. A negative case is decided by its first activation, and is inconclusive if no skill activated.
  - **Errors.** A run error, an unreadable trace or an unclassified command is inconclusive even after an activation, unless a mutation came first.

- **R-RUN-11. Listing validity.** The scorer reads the `skill_listing` attachment from each fresh run's session log. A run where any first-class skill under test appears without its description is invalid and is excluded and reported, because it did not test the description. Resumed runs keep no session log, so each batch with resumed cases adds one authorized listing probe per arm, model and listing condition: a resumed case asking the model to quote a description, compared with the source text. A failed probe invalidates that batch's resumed runs, so the runner collects the probe first and stops if it fails. This applies in the isolated condition. In the crowded condition, a missing description is the R-DESC-7 finding itself. On a model whose window the host does not recognize, the run plan states the listing budget it sets.
- **R-RUN-12. Guidance delivery.** `claude plugin eval` does not load `CLAUDE.md`, so every arm delivers the installed Skills guidance through a generated plugin `SessionStart` hook. The R-EVAL-8 control and the wording arm change only that text. This approximates, and does not equal, a real `CLAUDE.md`.

### Feasibility results

Probes of 2026-11-03: 17 authorized runs (6, then 11), one per case, on DeepSeek Flash through Claude Code 2.1.309, plus read-only checks of local session logs. One run per case shows whether a mechanism works, not an activation rate.

| R-RUN-9 question | Result | Evidence |
|---|---|---|
| Collector | **Use `claude plugin eval`**, wrapping installer output as a generated plugin | All runs completed; skills appear as `af:assistant-*` |
| Ordered tool calls | **Yes**, including subagent calls | `out/trace.jsonl` in each run's kept directory |
| Replay | **Yes, with a fixture and write tools.** `context.history_file` and `scaffold_script` work together, plain and compacted. The `SessionStart` hook fires with source `resume` | Runs acted on the plan in history against the fixture |
| Containment | **Confirmed for Edit and Write; not tested with Bash granted.** A run told to write outside its workspace was refused at all three paths, including inside the loaded plugin, and no file appeared. Other runs' writes stayed in the workspace, and an ungranted Bash call was refused as "No such tool available". The eval documentation promises OS-level confinement only for Bash, so this rests on the permission layer and on these observations | Tool results; files absent on disk; `git status` before and after |
| Mutation interception | **Not available.** Grant Edit and Write inside the workspace. See R-RUN-6 | Eval documentation |
| Listing capture | **Fresh runs only.** Resumed runs keep no session log, so R-RUN-11 uses a listing probe for them | `skill_listing` attachment in fresh runs; no session log in resumed runs |
| Listing delivery on resume | **Yes**, plain and compacted | The model quoted the `assistant-workflow` description word for word when asked |
| Guidance | **Hook fires** and its context is delivered | Trace `hook_response` for `SessionStart` |
| `paths` load | Not tested | |

These findings affect later stages:

- **The listing budget fix works.** `deepseek-flash` is an unrecognized model, so Claude Code assumes a 200k window and lists every plugin skill by name only. With `SLASH_COMMAND_TOOL_CHAR_BUDGET=40000`, all 16 framework skills keep their descriptions, both isolated (29 skills, 13 of them added by the host, 8,505 listing characters) and crowded (69 skills, 14,301 characters). The value is the probe's, and this setting makes both listing conditions fit, so a DeepSeek crowded run does not test overflow.
- **Overflow did not cause the original misses.** All six local session logs for this repository list every framework skill with its description, including the "Review process improvements" session, at about 23,000 listing characters.
- **Complete mid-flow misses reproduced only without guidance.** On a fixture with readable descriptions, the approval and post-compaction turns mutated files with no skill in the arm without guidance, and activated `assistant-workflow` first in the arm with the current Skills bullet. Under the routing oracle, which also requires `assistant-verification`, that is 0 of 2 against 1 of 2: the guided compaction run edited after `assistant-workflow` alone, and the guided approval run passes under the R-RUN-6 turn-limit rule, having activated both skills and reached `max_turns` without mutating. These are single runs on one model, so this is a signal for the R-EVAL-8 sensitivity check, not a measured effect. The arm without guidance is not an R-RUN-12 arm, and its guidance was the probe's copy of the Skills bullet.
- **Grading needs the whole mutation set.** Several runs wrote with `Write`, one of them before any `Edit`, and a `tool_order` grader against `Edit` cannot see a skill that arrives between the two. The scorer computes first activation and first mutation from the trace, as R-RUN-5 defines them, so the built-in graders are only a cross-check.
- **Runs often end at `max_turns`.** The built-in score and the run's error are independent, and activation is usually decided in the first calls. R-RUN-6 scores the prefix, so reaching `max_turns` is not by itself a failed run.
- **`--allow-tools` applies to a whole run.** A case's `allowed_tools` cannot widen it, so per-case commands in R-RUN-5 and R-RUN-10 need separate runs or a shared grant.
- **The plugin has to carry shared files.** Skills link to `tools/progress`, and those reads were denied until the generated plugin included it.
- **Empty workspaces waste runs.** Models spent their turns looking for code. Cases need a `scaffold_script` fixture.

The user prefers DeepSeek for testing. Results apply to the model tested. On 2026-11-05 the user decided adoption needs a Claude listing check under R-DESC-7 and no Claude trial run.

### Scoring

- **R-SCORE-1.** A trial passes when all required skills are satisfied before the first mutation or final answer, and no Forbidden skill activated.
- **R-SCORE-2.** Reports show counts with denominators, per skill, phase, model and listing condition:
  - recall and precision;
  - set completeness for cases requiring several skills;
  - activation before mutation;
  - both kinds of compaction case;
  - inconclusive trials;
  - tokens and time.
- **R-SCORE-3.** Scores are diagnostic, as in [the operating guidance](../../tools/progress/operating-guidance.md). A claim of benefit needs the matched observation that guidance defines.

### Promotion

Arms are the baseline twice, then candidate descriptions. Arms interleave on the same host version and model identity, and the baseline reruns if either changes. There are two optional arms. The `paths` frontmatter on `assistant-skill-creator` runs only if R-RUN-9 shows its load can be observed. Installer wording that extends "matches the request" to work in progress runs only after the user approves changes to the contracts that pin that phrase, with matching changes to both installers.

These terms apply per model and listing condition:

- **Baseline value:** the mean of the two baseline arms.
- **Drift:** the absolute difference in percentage points between the two baseline arms on the same measure.
- **Pass rate:** the R-SCORE-1 rate on conclusive trials of cases with at least one required skill, including neighbour-must-win cases. Compaction cases whose whole requirement activated before compaction are left out, because [R-EVAL-9](#eval-suite) reports them by re-invocation.
- **False activation rate:** the share of conclusive trials on no-skill cases where any skill activated, plus trials on any case where a Forbidden skill activated, over those cases' conclusive trials. Extra skills under R-ROUTE-2 are reported separately.

- **R-GATE-1.** A candidate is adopted only if, on held-out cases, for each model in the isolated condition, against the baseline value:
  - the pass rate gains by more than twice the drift, and by at least the [OD-2](#accepted-defaults) floor;
  - the false activation rate and the inconclusive rate do not rise beyond their drift;
  - no skill with at least 15 trials loses recall beyond the drift. Skills under 15 trials are reported but not gated.

  In the crowded condition, the pass rate must not fall below the baseline value by more than the drift.
- **R-GATE-2.** R-DESC-5, R-DESC-6, R-DESC-7 and R-LED-2 hold for the adopted candidate.
- **R-GATE-3.** Any gap between the two models is reported.
- **R-GATE-4.** If no candidate meets R-GATE-1, the result goes back to the user with the deferred forced-decision and hook options. Neither is added without that decision.

### Documentation

- **R-DOC-1.** The change that adopts descriptions updates the contract design guide, the per-skill fixtures guide and this spec's status.
- **R-DOC-2.** Tracked regression tests cover the routing table's decisive cases where they can be checked without a model. The docs must state that such tests do not prove native activation.

## Dependencies

The order is the ledger and the feasibility check (R-LED, R-RUN-9), then the eval suite and sensitivity check (R-EVAL), then candidates (R-DESC), then promotion (R-GATE), then composition documentation (R-ROUTE-4). The baseline source can be reinstalled from a commit later, but host and model identity cannot, so baseline arms always run alongside candidates.

## Accepted defaults

The user accepted these on 2026-11-03.

- **OD-1. One-word typo.** The installed instructions now say not to skip a skill because work is small, the workflow's framework fixture sends a typo down its light path, and the workflow body lets trivial safe work "proceed directly". The research note listed a typo as a case where no skill should fire, which conflicts with this. Decision: `assistant-workflow` is optional here, counted as neither a miss nor a false activation.
- **OD-2. Numeric thresholds.** These are initial values with no measured basis: a 10-point floor in R-GATE-1, so a small noisy gain cannot pass, and a 30% miss rate over at least 5 repeats for the R-EVAL-8 control. Decision: use them as starting values, and confirm or adjust them with the user after the first control run. The user confirmed the 30% rate on 2026-11-04, measured across all seeds in the batch.
- **OD-3. Models.** Anthropic's guidance names Haiku, Sonnet and Opus. Decision: run the pilot on the model the user uses most, then use two for the full stage.
- **OD-4. Review of skill changes.** The user's earlier decision assigns skill review to `assistant-skill-creator`, and also asks to keep skill-review guidance out of `assistant-review`. But `skills/assistant-review/references/review-checklists.md` has a checklist for changes to skills, and the workflow's Review phase applies to skill diffs. `assistant-skill-creator`'s assess operation is also read-only. Decision, as in the routing table: assessing a skill goes to skill-creator, a delivered diff keeps its formal review in `assistant-review`, and review-and-fix uses skill-creator with workflow. The checklist stays where it is.

## Current state

| Item | State |
|---|---|
| Installer Skills bullet ("Direct implementation means no delegation, not no skill") | Implemented in `install.sh` and `install.ps1`; effect unmeasured |
| Existing `activation_cases` and `--activation-results` grading | Implemented; do not cover this failure |
| Use-case ledger | Built locally. Candidate c1's rationale maps the existing clauses and positive cases of the seven skills it changes |
| Feasibility probe | Run; see [Feasibility results](#feasibility-results) |
| Plugin generator, per-trial scorer, report aggregation | Implemented in `tools/evals/skill-activation/`, with offline tests; real batches are in [Adoption result](#adoption-result). Reports group by arm, model and listing condition; gate comparisons between arms are not computed |
| Stateful suite and trial runner | Implemented. One 5-call smoke batch on development cases passed its validity checks on 2026-11-03; it tested the pipeline, not activation rates, and did not cover repeats above 1. A 61-call development batch the same day hit its $15 cap after 48 of 60 cases, so it is invalid and only diagnostic. A valid 13-call batch ran the other 12 cases on the same plugin tree and suite. Cases cost about $0.31 each by the host's estimate, and the host can overrun a cap slightly. Those batches predate later case edits, so their results don't compare with later runs. The held-out set is frozen provisionally after two independent agent reviews; the human review R-EVAL-3 requires before commit is still open, and changes from it go in with `suite.py freeze --refreeze`. Held-out ran for c1; see [Adoption result](#adoption-result) |
| R-EVAL-8 sensitivity check | Run 2026-11-04 on 12 development seeds × 5 repeats on `deepseek-flash`, isolated: both arms valid, 122 calls, about $38.85. Control missed 39 of 51 conclusive trials and current 40 of 53, so both miss. The misses are almost all `assistant-verification`; `assistant-workflow` was missing in 10 of 51 and 7 of 53, below the OD-2 30% rate, though the rate as confirmed applies across all seeds, so the check passes |
| R-RUN-10 collection of existing `activation_cases` | Implemented in `activation.py`, `run_trials.py --set activation` and `report.py --baselines --candidate`, and run once for candidate c1. Trials grant no Bash, so there is no runner table and the two run-only cases cannot run their command; the report counts those trials |
| Description candidates | Candidate c1 is adopted in `skills/`; see [Adoption result](#adoption-result). The gain is measured on `deepseek-flash` only, and the user's case review is still open |
| Forced-decision line, hook backstop | Deferred |

## Adoption result

Candidate c1 was written by a fresh actor that did not read held-out cases. It changes 7 of 16 descriptions, 2,193 to 3,536 characters, and a plugin generated from `skills/` has the tested `description_sha256`. All results are on `deepseek-flash`, host 2.1.317, from valid batches with no listing-invalid trials. Baseline values are the mean of two arms of the same tree.

| Held-out, 80 cases × 3 | Isolated baseline | Isolated c1 | Crowded baseline | Crowded c1 |
|---|---|---|---|---|
| Pass rate, R-GATE-1 | 72.3% | **87.3%** | 70.5% | **85.3%** |
| Drift | 2.2 points | | 1.8 points | |
| False activation | 3.9% | 3.8% | 3.8% | 3.9% |
| Inconclusive | 6.7% | 5.0% | 5.2% | 5.0% |
| `assistant-verification` recall | 29% | 70% | 30% | 65% |
| `assistant-workflow` recall | 77% | 95% | 77% | 97% |
| `assistant-review` recall | 41% | 53% | 33% | 64% |
| `assistant-skill-creator` recall | 100% | 100% | 100% | 100% |

- **R-DESC-5.** Run on a temporary copy with c1 applied before trials, then on the applied tree: all 1,283 contract checks pass, with no contract edited. One signal test, in `tests/p0-p4/codex-behavioral-eval-contracts.sh`, fails when the suite is started as a shell background job, which ignores SIGINT. It passes with SIGINT restored.
- **R-DESC-6.** 61 existing cases × 3 on three arms, 549 interleaved calls, about $145.31. No regressions over the 59 cases conclusive in all three arms. `a-research-02` is not gated because the baselines disagree, `a-skill-creator-02` is inconclusive in both baselines, and `a-clarify-02` fails in all arms.
- **R-DESC-7.** The crowded listing keeps all 16 descriptions word for word for `claude-opus-5-5`, `claude-sonnet-5-5`, `claude-haiku-5-5`, `claude-fable-5-1` and the two `[1m]` variants at the default budget, in a fresh home. The listing is 15,842 characters against 14,499, against a limit of about 30,000. The check made no model call: the session log records the listing even when the API base URL is a closed local port and the key is a placeholder, and the same check on `deepseek-flash` correctly reports name-only entries.
- **R-LED-2.** On 2026-11-05 the user approved "explicit" removed from `assistant-review`, `assistant-security` and `assistant-research`, "input" changed to "external input" in `assistant-security`, the `assistant-skill-creator` sentence naming `assistant-workflow` and `assistant-verification`, and the longer total. The reason is the measured recall gain, accepted with the over-firing below.
- **Development set.** 60 cases × 3 on three arms, 543 calls, about $150.55: pass rate 87% against 61% and 65%, false activation 0 in all arms. Five cases fail in all arms: `c-review-keyword`, `d-security-change`, `d-seed-bot-comment`, `d-seed-go-step` and `d-seed-resume-compacted`. c1 adds `assistant-skill-creator` in all 6 trials of the two typo-fix cases.
- **Held-out cost and misses.** Isolated 723 calls, about $187.18; crowded 723 calls, about $198.70. Eight cases fail in all arms isolated and nine crowded, so short review-feedback and CI turns stay weak. Under c1, `assistant-review` has the lowest recall of the skills listed.

Departures from the plan, all accepted by the user's authorization of exact counts or stated decision:

- The development and held-out stages ran one arm after another, c1 last, not interleaved, because three batches per arm would exceed the authorized calls. Host and model identity did not change.
- Held-out ran 3 repeats on one model, not the R-RUN-7 Full default of 5 repeats on 2 models. On 2026-11-05 the user decided adoption needs a Claude listing check and no Claude trial run, so R-GATE-3 has no gap to report.
- Held-out ran before the user's case review. A held-out case the review changes needs rerunning in both conditions.

R-ROUTE-4 and R-DOC-1 followed adoption, so the composition text in the workflow and skill-creator bodies was not measured.

## Known limits

- `assistant-verification` stays required before the first edit on implementation rows; the user confirmed this on 2026-11-03. Across the two diagnostic development batches it activated in time in 3 of 15 conclusive trials, usually after `assistant-workflow` had loaded. c1 raises its held-out recall to 70% against 29%, so about 30–35% of conclusive trials still miss it.
- The evidence for this failure is one session, and the activation figures in the research note come from informal external tests.
- Passing activation evals would not show that a skill was then followed correctly.
- Claude Code's listing limits are documented host behavior and can change. Codex and Gemini limits were not checked.
- Containment with Bash granted is unproven, and cases that run commands depend on it. That includes the two run-only `activation_cases`.
- R-DESC-7 cannot be assessed on DeepSeek at the probe's listing budget, so it was checked with no model call on Claude model names. That check used a fresh home, so usage history is untested. Past about 30,000 listing characters the host reduces entries to names. Framework skills stayed intact in that test, but they also sorted first, so that doesn't show they would survive overflow in a real environment.
- No Claude model ran the trials, so the measured gain is shown on `deepseek-flash` only.
- The scorer's shell classifier is an approximation of bash. Anything it cannot follow becomes inconclusive, but an unquoted glob that expands to a writing option is not detected, and an unusual form can still be misread.
- Compaction replay uses a synthetic boundary and summary, which approximates a real compaction.

Return to the [specification index](README.md).
