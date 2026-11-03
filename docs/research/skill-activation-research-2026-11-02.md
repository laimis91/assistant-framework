# Skill activation: why skills were skipped, how to improve it, and which skill fits when

Date: 2026-11-02. Status: **research and proposal; one wording change implemented (installer Skills bullet).** Method: transcript analysis of one
session, a read of the repository's skill descriptions and eval fixtures, and a small amount of web research. Nothing
here establishes implemented behavior or a measured benefit; see [Limits](#limits).

Motivating case: the local session titled "Review process improvements" (work on PRs 77, 79 and 80). The assistant
skipped several skills that apply to the repository's work.

## Evidence labels

- **read locally**: a repo file or session transcript read in this analysis.
- **fetched**: a web page opened here; the cited point was seen (via the fetch tool's summary for the Spence page).
- **excerpt / secondary**: seen only in search results or a blog. It carries no weight alone.
- **inference**: reasoning from the above, not observed.

## 1. What happened in the session (read locally)

Session transcript, user turns, Skill and Agent calls, and the two Q&A exchanges about skills.

| Phase | Skill that applied | Observed |
|---|---|---|
| Research on review techniques | `assistant-research` | Invoked, then followed partly: no URL verification, support files unread, no counter-evidence search. The user had to ask whether it was used. |
| 22 review-fix rounds on the catalog | `assistant-review` | Used. |
| Implementing P0-P5, the CI fix on PR 79, PR 80 | `assistant-workflow` | Not used. PR 80 had no fresh-agent review. PR 79's CI failure was attributed by the assistant to this gap. |
| Editing `skills/assistant-review/**` | `assistant-skill-creator` | Not used. |
| Test planning | `assistant-verification` | Not used. |

Assistant's own explanation when asked: it "never weighed the question", treated plan approval as the end of process,
and judged later steps "too small to need a process".

Self-reports are unreliable. The later answer says `assistant-research` was run only after the user asked. The
transcript shows the Skill call right after the research request and well before the user's question. Audit
skill use by counting `Skill` tool calls, not by asking the model.

## 2. Why it happens

1. **No deterministic backstop (read locally).** PR #42 "Retire Assistant Framework hooks" removed `skill-router.sh`,
   `workflow-enforcer.sh`, `stop-review.sh` and the rest. Routing now depends on the model's judgment.
2. **Contradictory global wording (read locally, `~/.claude/CLAUDE.md`).** "Implement and verify directly when
   useful, at every size/risk" sits beside "Do not skip a matched skill's gates." The assistant read the first as
   making the workflow optional.
3. **Per-request matching (inference).** `CLAUDE.md` says to use a skill "when a skill's description matches the
   request". Mid-flow turns such as "Approve P0-P5", "CI failing", "create pr" and a pasted bot review comment do not
   read as matching any description. The session also crossed a context compaction.
4. **Descriptions that undertrigger (read locally).**
   - "explicit" appears in the descriptions of review, research, thinking, ideate, docs, diagrams, onboard, security
     and telos. It reads as "only when asked by name".
   - `assistant-workflow` and `assistant-skill-creator` have no path or state cues (`skills/**`, `SKILL.md`, plan
     approved, CI failing, PR created).
   - `assistant-ci-audit` has no "Use when" clause in its description; its trigger examples sit only in the body.
5. **Existing activation evals do not cover the failure (read locally).** Section 5 gives details.

## 3. Research findings

### Anthropic's authoring guidance (fetched)

Source: [Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices).

- Description states what the skill does and when to use it, in third person, with specific key terms. Maximum 1,024
  characters. It is the field Claude uses to choose among 100+ skills.
- Vague descriptions ("helps with documents") are the named anti-pattern.
- Build at least three evaluations before extensive documentation, test with Haiku, Sonnet and Opus, and observe real
  use for missed triggers. The page says no built-in way to run evaluations exists.
- Keep `SKILL.md` under 500 lines and references one level deep.

### Measured activation (fetched, informal)

Source: [Scott Spence, sandboxed activation evals](https://scottspence.com/posts/measuring-claude-code-skill-activation-with-sandboxed-evals).
Sonnet 4.5 through `claude -p`, 22 prompts, four Svelte skills, two runs.

| Approach | Activation on standard prompts |
|---|---|
| No hook | 55% and 50% |
| Simple reminder hook | 59% and 50% |
| Forced-evaluation hook | 100% and 100%; 75% on 24 harder prompts, no false positives on the 5 no-skill prompts |
| Pre-classifier hook (Haiku) | 100% and 100%; 4 false positives on the same 5 no-skill prompts |
| Prompt-type hook | 55% and 41% |

When a skill fired it was always the right one: the failure is activation, not selection. Keyword-heavy prompts fired
without help; conceptual wording often did not. Caveats: one model, small sample, 5-point baseline drift, a
20-second window that checks only whether a skill was called.

A second write-up ([Seleznov, 650 trials](https://medium.com/@ivan.seleznov1/why-claude-code-skills-dont-activate-and-how-to-fix-it-86f679409af1),
excerpt/secondary) reports directive descriptions activating far more reliably than passive ones. Unverified.

## 4. Decisions so far (2026-11-02, from the user)

| Proposal | Decision |
|---|---|
| Forced decision line in `CLAUDE.md` ("name the skill or state why none applies" before the first edit) | **Deferred.** It matches the best-measured fix and costs nothing; revisit after the description and eval work. |
| Thin hook as a backstop, for example a Bash matcher on `gh pr create` | **Deferred.** It would partly reverse #42, and whether hooks fire in the desktop app is untested. |
| Remove the contradiction in global `CLAUDE.md` wording | **Done.** The Skills bullet now reads "...to save time or because work is small. Direct implementation means no delegation, not no skill." The Operating stance bullet is unchanged because contract tests pin its wording and a 32-word bullet limit. Changed in `install.sh`, `install.ps1` and the installed `~/.claude/CLAUDE.md`. Effect on activation is unmeasured. |
| Rewrite descriptions, preserving every current use case | Wanted; see section 6. |
| Activation evals | Wanted, and better than the single short prompts first suggested; see section 5. |
| `deepseek-delegate` | **Out of scope.** It is a local skill under `~/.claude`, not a project skill, and `skills/` has no such directory. Its routing is owned by the global `CLAUDE.md`. |

## 5. Better activation evals (proposal)

### What exists (read locally)

`docs/evals/skill-fixtures.md` requires each first-class skill's fixture to declare `activation_cases`: entries of
`{ user_request, should_activate }`, with at least two distinct positives and one nearby negative. A runner grades
externally collected `selected_skills` against them. It never invokes a model. The 16 fixtures hold 3 to 6 such cases
each.

Gaps against the failure seen here:

- Every case is a single short turn, many of them near-restatements of the description ("Update the README
  documentation", "Create a Mermaid sequence diagram"). The assistant did not skip a skill on prompts like these.
- No case carries conversation state: plan just approved, post-compaction, a pasted review comment, a CI log, a
  PR just opened.
- Grading checks only that the skill was selected. It does not check that it was invoked **before the first edit,
  commit or PR**, or that a required set was invoked together.
- No sibling-confusion pairs where two skills are plausible (review vs skill-creator for a skill review,
  verification vs tdd, debugging vs ci-audit, research vs thinking vs ideate).
- One run per case, no variance, no model comparison, no held-out split.

### Proposed design

1. **Seed from real misses, then generalize.** Mine local session transcripts (this one and the earlier "Sessions
   not delegating to Deepseek" and similar sessions) for turns where a skill should have fired and did not. Keep
   the raw turn plus paraphrases, and hold out a split that is never used while editing descriptions.
2. **Stateful fixtures.** Each case is a replayable conversation prefix plus a final user turn: approved plan,
   compaction summary, bot review comment, failing CI output, PR created, mid-task pivot.
3. **Trace-based oracle.** Capture the ordered tool calls per run. Pass requires: required skills invoked, forbidden
   skills not invoked, and the first `Skill` call before the first `Edit`, `Write`, commit or `gh pr create`. A
   scorer that is separate from model execution fits the existing "ingest observations" runner design.
4. **Axes covered by a matrix**, not hand-picked prompts:
   - request size: typo, small fix, medium change, large change;
   - phase: request, approval, mid-build, CI failure, review feedback, PR, resume after compaction;
   - input form: terse, conceptual, keyword-heavy, pasted artifact, multi-intent;
   - authority wording: explicit skill name, implicit task, no process words;
   - target: repo code, skill files, docs/specs/plans, tests/CI.
5. **Negatives and near-misses.** Cases where no skill should fire (a question about existing code, a typo, run an
   existing test) and cases where the neighbour skill must win. Report false positives separately.
6. **Trials and models.** Repeat each case several times per model (Anthropic names Haiku, Sonnet and Opus), report
   rates with the denominator, and compare description variants against the current baseline on the same frozen
   cases. This is the evidence standard in `tools/progress/operating-guidance.md`: frozen oracles, current
   source and host identity, call counts and explicit limits.
7. **Metrics:** per-skill recall and precision; set completeness for co-activation (for example workflow with
   skill-creator and verification); activation-before-edit rate; skip rate after compaction; tokens and latency.
8. **Collection method to verify before relying on it:** headless `claude -p` with structured output to read tool
   order (the Spence method used `claude -p`; ordering output and hook behavior in headless mode were not checked
   here).

## 6. Rewriting descriptions without losing use cases

Procedure so no current use case is lost:

1. **Build a use-case ledger per skill** from four sources: current description clauses, `activation_cases`, the body's
   scope and boundary statements, and the skill's eval cases.
2. **Map every ledger line** to the new description, or record an explicit reason for dropping it.
3. **Check** that all existing `activation_cases` still pass and that new stateful cases improve.
4. **Keep each description within 1,024 characters**, third person, "what" plus "Use when" with concrete triggers.

Use cases found in the bodies that the descriptions must keep or that are easy to lose (read locally):

| Skill | Use cases to preserve |
|---|---|
| `assistant-workflow` | Feature, epic and story **technical preparation without implementing**; implementation, fixes, migrations, refactors; resuming task state; backlog items; intended-change ideas; small changes via the ordinary path. |
| `assistant-review` | Review-fix as well as report-only audit; being the workflow Review phase; QA only when required; spec, plan, C# and test review (the user's stated assignment). |
| `assistant-skill-creator` | Create, update, assess, review skills; compliance; **read-only check of registered upstream guidance**; skill review is owned here (user's stated assignment). |
| `assistant-verification` | Proportionate check selection; judging whether existing evidence is sufficient; scope across code, skills, plugins and non-code artifacts. |
| `assistant-research` | Source-backed research, topic investigation, option comparison; five-lens only for contested decisions, not for breadth or stakes alone. |
| `assistant-tdd` | Tests-first requests, project TDD rules, workflow-selected TDD checks. |
| `assistant-security` | Threat modeling, vulnerabilities, dependencies, attack surfaces, **and implicit triggers**: changes to auth, input handling and sensitive data. |
| `assistant-debugging` | Unknown failures, root causes, flaky tests, unexplained breakage; not the known one-line fix. |
| `assistant-ci-audit` | False passes, discovery gaps, stale fixtures, brittle or duplicate tests, cost; description lacks any "Use when". |
| `assistant-ideate` | Light mode for quick improvement scans, deep mode for brainstorming. |
| `assistant-thinking` | Stress tests, debate, first principles, hypotheses, architecture trade-offs. |
| `assistant-clarify`, `-docs`, `-diagrams`, `-onboard`, `-telos` | Keep their current clauses; replace "explicit" with the concrete triggers it was standing in for. |

Removing "explicit" is the highest-leverage edit, but it also removes a guard against over-triggering on skills such as
`assistant-telos` and `assistant-ideate`. The negative and near-miss cases in section 5 are what make that safe to
change.

## 7. Which skill when (repository skills)

| Situation | Skill |
|---|---|
| Any repository change: feature, fix, refactor, migration, CI fix, applying review comments | `assistant-workflow` (pulls in review and verification) |
| Editing `skills/**`, contracts, evals, or checking upstream skill guidance | `assistant-skill-creator` |
| Review of code, spec, plan, docs or tests | `assistant-review` |
| Unknown failure, flaky test, unexplained breakage | `assistant-debugging` |
| Weak, slow or false-passing CI and test suites | `assistant-ci-audit` |
| Source-backed research or option comparison | `assistant-research` |
| Choosing proportionate checks, or judging evidence sufficiency | `assistant-verification` |
| Tests-first request | `assistant-tdd` |
| Ambiguous or multi-intent request | `assistant-clarify` |
| Architecture trade-off or stress test | `assistant-thinking` |
| Generating and ranking options | `assistant-ideate` |
| Auth, input or sensitive-data change; threat model | `assistant-security` |
| README, API, architecture, changelog or migration docs | `assistant-docs` |
| Mermaid diagrams | `assistant-diagrams` |
| Unfamiliar codebase | `assistant-onboard` |
| Purpose, mission and goals | `assistant-telos` |

Applied to the session studied: research used `assistant-research`; the catalog review used `assistant-review`;
P0-P5 and both PRs belonged under `assistant-workflow` with `assistant-skill-creator` for the skill edits and
`assistant-verification` for check selection.

## Limits

- The transcript was read through user turns, Skill and Agent calls, and two Q&A exchanges, not in full.
- Activation figures come from one informal test and one secondary write-up. No test was run here.
- No description was rewritten, no eval was run, and no skill description was rewritten.
- Whether Claude Code truncates or budgets long skill descriptions in the listing was not checked.
- Hook behavior in the desktop app and in headless mode was not tested.

## Suggested order for implementation

1. Build the use-case ledger and the stateful, trace-graded eval set (section 5), with a baseline run on the
   current descriptions.
2. Rewrite descriptions against the ledger (section 6) and compare against the baseline on held-out cases.
3. Global `CLAUDE.md` contradiction: decided and done (installer Skills bullet).
4. Only if rates remain low, revisit the deferred forced-decision line and the hook backstop (section 4).
