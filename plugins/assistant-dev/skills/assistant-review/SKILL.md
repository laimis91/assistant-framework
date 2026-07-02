---
name: assistant-review
description: "This skill runs an autonomous code review loop and optional independent QA evaluation loop: review, fix, re-review until clean (max 20 rounds), then evaluate acceptance when QA is required. Use when the user says 'review', 'fresh review', 'code review', 'review this', 'check the code'. Also activates when the workflow's Review phase requires quality review or QA evaluation dispatch."
effort: high
triggers:
  - pattern: "fix (all |the |review |reported )?issues|fix (all |the )?findings|apply (all )?fixes"
    priority: 90
    reminder: "This request to fix review issues matches assistant-review. You MUST load and follow this SKILL.md and its contracts before editing code. The skill includes fix -> validation -> re-review steps that run before the final summary."
  - pattern: "review|fresh review|code review|review this|check the code|/review"
    priority: 80
    reminder: "This request matches assistant-review. You MUST load and follow this SKILL.md and its contracts before doing anything else. Run the autonomous review-fix loop to its exit condition before reporting."
---

# Autonomous Review And QA Evaluation

## Contracts

This skill enforces strict contracts on inputs, outputs, loop gates, reviewer handoffs, and QA evaluator handoffs. Read the contract files in `contracts/` before executing.

| Contract | File | Purpose |
|---|---|---|
| **Input** | `contracts/input.yaml` | Scope, mode, and review material snapshot to resolve before entering the loop |
| **Output** | `contracts/output.yaml` | Final summary and verification artifacts |
| **Phase Gates** | `contracts/phase-gates.yaml` | Per-round step assertions and loop invariants |
| **Handoffs** | `contracts/handoffs.yaml` | Reviewer and QAEvaluator subagent dispatch and return schemas |

**Rules:**
- Resolve all input contract fields before entering the loop
- Check phase gate assertions at every step transition within each round
- Include all required context fields when dispatching Reviewer or QAEvaluator subagents, and record direct-fallback evidence when subagents are not authorized/available/allowed
- Validate all required return fields when Reviewer or QAEvaluator completes
- Verify all output contract artifacts before presenting the final summary

Run the code review loop autonomously from start to finish. Continue rounds until clean or max rounds reached, keep intermediate results inside the loop, and present one final result after exit. When QA is required, run the QA evaluation loop after build/test evidence and code-review evidence are available.

## Goal

Find concrete defects, risks, regressions, and test gaps; fix them when in review-fix mode; and return one evidence-backed final review result. When QA is required, independently evaluate the Done Contract, acceptance criteria, verification evidence, scoped UI/visual/product/UX/docs/DX/domain quality, score progression, and final acceptance result. Reviews must be useful in company environments: local-first, policy-safe, and focused on actionable engineering risk or acceptance evidence rather than generic style preferences.

## Success Criteria

- Review scope and mode are resolved before the loop starts.
- Findings are severity-ranked with file evidence and confidence.
- Every review applies the SOLID, KISS, DRY, YAGNI, and readability lens from `references/review-principles.md`.
- In review-fix mode, must-fix and should-fix findings are addressed or explicitly deferred.
- Validation runs after fixes, and a fresh review confirms the final state.
- QA evaluation runs after code-review/build evidence when `qa_evaluation_mode=required`, returns score progression and a final acceptance verdict, and does not replace code-reviewer.
- QA evaluation loads `references/domain-rubrics.md` only when `domain_context`, explicit `rubric_refs`, or subjective/UI/visual/product/UX/docs/DX/domain acceptance criteria require scoped domain-quality scoring.

## Constraints

- Default to audit mode when the user asks to provide, report, list, or summarize findings.
- Do not emit intermediate review summaries; present one final summary after loop exit.
- Use concrete risk categories for refactor-related findings.
- Treat clean-code principles as evidence lenses, not acronym-driven style rules.
- Keep QA evaluation separate from code review: QA focuses on acceptance criteria, Done Contract, verification evidence, UI/visual/product/UX/docs/DX/domain quality, score progression, and final result. Code Reviewer continues to own code defects, security, architecture, and test-coverage review.

## Entry

Determine the review scope:
- If the user specified files, pasted content, or a diff -> review that material
- If there are uncommitted changes -> review those (`git diff`)
- If there's an active configured task journal, agent-state task file (`{agent_state_dir}/task.md`), or carried-forward task packet -> review all changes from that task
- If the user requests an audit of current file contents -> review the relevant files even without a diff
- Otherwise -> ask the user what to review

## Review Modes

Use the smallest mode that answers the request; combine modes when reviewing implementation work.

- **Spec review**: compare the diff/code to the stated goal and acceptance criteria. Report missing behavior, scope creep, and mismatched semantics.
- **Behavioral contract review**: for code changes, check preserved behavior/invariants, interface-implementation alignment, inherited test coverage, protocol/algorithm fidelity, high-impact operation guards, and runtime-surface sync.
- **Agentic loop safety review**: for agent/workflow/tool loops, check max steps/time budget, stop condition, retry/empty-result handling, tool-error handling, low-confidence escalation, and cost/token guardrails.
- **Review finding distillation**: for blocker/must-fix findings, classify whether the issue is a one-off fix or a permanent rule candidate using `references/review-finding-permanent-rule.md`.
- **Regression review**: identify likely breakage of existing behavior, public API contracts, migrations, configs, or compatibility assumptions.
- **Test review**: verify that tests would fail without the implementation, cover meaningful edge cases, and are not only happy-path snapshots.
- **Bugfix evidence review**: for bugfixes, verify the review material includes reproduction/root-cause evidence from `assistant-debugging` or an explicit not-applicable/blocker rationale; the regression test must trace to the isolated failure mechanism.
- **Semantic contract review**: for skill/workflow/framework changes, check contract inheritance, method-template alignment, eval coverage, method-signature fidelity, and high-stakes recommendation guards before judging the change clean.
- **Maintainability review**: apply SOLID/KISS/DRY/YAGNI/readability only when a concrete risk exists.
- **Security handoff**: invoke `assistant-security` when the reviewed surface touches auth, permissions, secrets, input handling, persistence, shell commands, dependency/config changes, network calls, or external integrations.
- **QA evaluation**: after code-review/build evidence exists, dispatch QAEvaluator when `qa_evaluation_mode=required` for medium+ harness-capable, domain-scored, UI/visual/product/UX/docs/DX-facing, or explicitly requested QA work. Load `references/qa-evaluation-loop.md`.
- **Domain rubric QA**: within QA evaluation, load `references/domain-rubrics.md` only when scoped by acceptance criteria, Done Contract, `domain_context`, or explicit `rubric_refs`. QAEvaluator selects rubric families and returns domain-quality scores; Code Reviewer still owns code defects, security, architecture, and test coverage.

Finding format:

```markdown
- Severity: must-fix | should-fix | nit
- Evidence: file:line or diff hunk plus observed behavior
- Impact: what can break, leak, regress, or become hard to maintain
- Recommendation: smallest useful fix
- Confidence: evidence-calibrated percentage; speculative concerns belong in Observations and do not block completion
```

Severity mapping:
- **must-fix**: correctness/security/regression issue that should block completion or release.
- **should-fix**: concrete risk that should be resolved in the review-fix loop but may not block an audit report.
- **nit**: low-priority observation with limited impact.

## Company-Safe Review Rules

- Prefer local diffs, local commands, and repo-native checks.
- Do not require external SaaS scanners, remote LLM review, or unapproved package installs.
- Do not quote secrets or proprietary data in review output; identify the file/location and redact sensitive values.
- If an external scan would be useful but policy may block it, suggest a local/manual equivalent instead.

## Mandatory Review Checklists

Load and apply `references/review-checklists.md` before declaring clean whenever a corresponding review mode is applicable. Checklist headings alone are not evidence; each applicable area must produce concrete findings or an explicit "no concrete risk found" check.

- **Agentic loop safety review**: apply the Agentic Loop Safety Checklist for agent/workflow/tool loops and return `agentic_loop_safety_checks` covering bounded execution, stop condition, retry/empty-result handling, tool-error handling, progress/stagnation detection, cost/token guardrails, and low-confidence escalation.
- **Behavioral contract review**: apply the Behavioral Contract Review Checklist for behavior-bearing code and return `behavioral_contract_checks` covering existing invariants, interface-implementation alignment, test inheritance coverage, protocol/algorithm fidelity, high-impact operation guards, and runtime-surface sync.
- **Semantic contract review**: apply the Semantic Contract Review Checklist for skill/workflow/framework changes and return `semantic_contract_checks` covering inherited contract obligations, template-contract alignment, eval inheritance coverage, external-method signature fidelity, high-stakes recommendation guards, and mirror-surface sync.

## Refactor-Related Findings

Use refactor-related findings only for concrete actionable risk. Allowed risk categories:
- correctness
- security
- unsafe change surface
- branching/responsibility growth
- hidden dependency/ownership
- brittle testing
- poor extension seam
- readability/maintainability drag

Every refactor-related finding MUST state the risk category, affected surface, evidence from the review material, and the smallest durable fix that addresses the risk within the normal finding text.

Use concrete risk framing instead of generic convention, style, cleanliness, or improvement language. Request broad cleanup only when a smaller durable fix cannot remove the risk.

## Principle and Readability Lens

Load `references/review-principles.md` before each REVIEW step. Apply SOLID, KISS, DRY, YAGNI, and readability checks to the review material. Report a principle finding only when the evidence shows concrete risk, such as duplicated knowledge that will diverge, speculative abstraction, hidden coupling, substitution breakage, needless branching, or code whose intent is hard to recover.

For each principle/readability finding, include the violated lens, affected surface, concrete evidence, risk category, and smallest durable fix. Do not report acronym-only findings such as "violates SOLID" without naming the observed behavior and the user-facing or maintainer risk.

## The Code Review Loop

```
round = 1
previously_fixed = []
score_history = []

while round <= 20:

  1. REVIEW
     - Dispatch a fresh Reviewer subagent when `subagent_execution_mode=delegated`
     - Use fresh direct-fallback review context when `subagent_execution_mode=direct_fallback`
     - Use self-review only for trivial/small scope or direct fallback mode with recorded fresh-context evidence
     - Provide: review material snapshot, previously_fixed list, round number
     - First run Spec Review against the user request and acceptance criteria
     - For agent/workflow/tool loop changes: apply the Agentic Loop Safety Checklist before declaring clean
     - For behavior-bearing code changes: apply the Behavioral Contract Review Checklist before declaring clean
     - Then run Regression/Test/Maintainability modes as applicable
     - If security-sensitive surfaces are present, hand off to `assistant-security`
     - Load and apply references/review-principles.md as the clean-code lens
     - Load and apply references/review-checklists.md when agentic loop safety, behavioral contract, or semantic contract review is applicable
     - For skill/workflow/framework changes: apply the Semantic Contract Review Checklist before declaring clean
     - For medium+ scope: set rubric_required=true (see references/review-rubric.md)
     - Reviewer prompt must include:
       "This is review round {round}. The following items were already
       fixed — do NOT re-report them:
       {previously_fixed}
       If the current review material shows a residual or related risk, report it
       only as a distinct new finding with new evidence; do not re-report the fixed item.
       Finding filter policy:
       - Report only evidence-backed findings with file/line evidence, concrete impact, and the smallest useful fix.
       - Put speculative or low-evidence concerns in Observations; they do not block completion.
       - In rounds 16-20, only must-fix or high-confidence should-fix findings count as blockers; round 20 is terminal and exits with remaining items instead of starting round 21.
       Apply the SOLID, KISS, DRY, YAGNI, and readability lens from
       references/review-principles.md. Report principle issues only when tied
       to concrete evidence, concrete risk, and the smallest durable fix.
       Load and apply references/review-checklists.md before declaring clean
       when any checklist mode below is applicable.
       For agent/workflow/tool loop changes, apply the Agentic Loop Safety Checklist:
       max steps/time budget, stop condition, retry/empty-result handling,
       tool-error handling, progress/stagnation detection, and cost/token guardrails.
       For behavior-bearing code changes, apply the Behavioral Contract Review Checklist:
       existing invariants, interface-implementation alignment, inherited test coverage,
       protocol/algorithm fidelity, high-impact operation guards, and runtime-surface sync.
       For skill/workflow/framework changes, also apply the Semantic Contract Review Checklist:
       inherited contract obligations, template-contract alignment, eval inheritance,
       external-method signature fidelity, high-stakes recommendation guards, and mirror-surface sync.
       Score against the rubric (5 dimensions) per references/review-rubric.md."

  2. EVALUATE
     a. Check rubric score (medium+ scope):
        - PASS (weighted >= 4.0) AND no must-fix AND no should-fix -> EXIT CLEAN
        - PIVOT (weighted < threshold for round) -> escalate to orchestrator-owned pivot_restart_decision
        - REFINE (weighted below 4.0 but not PIVOT), including zero findings -> continue to step 3
          using lowest-scoring rubric dimensions as the improvement targets
        - Medium+ CLEAN and ISSUES_FIXED require weighted >= 4.0 and zero
          must-fix/should-fix findings
     b. No rubric (small scope): use findings-based exit:
        - No must-fix AND no should-fix -> EXIT CLEAN
        - Only nits -> EXIT CLEAN (note nits in final report)
     c. round == 20 with remaining must-fix or should-fix -> EXIT WITH REMAINING ITEMS
     d. round == 20 with issues fixed and now clean -> EXIT ISSUES FIXED
     e. Otherwise -> continue to step 3

     Record in score_history: { round, weighted_score, finding_count, drift_status }
     (see references/score-tracking.md for drift detection rules)
     If score tracking reports STAGNATION, repeated DRIFT, repeated REGRESSION,
     or rubric action PIVOT, pause the loop and return a pivot_restart_signal to
     the orchestrator. The orchestrator records pivot_restart_decision with
     trigger, evidence, affected_slice_or_round, options_considered,
     selected_action, reapproval_required, next_agent, recovery_pointer, and
     exact_next_action before another fix/review dispatch. If the selected action
     changes scope, files, behavior, risk, verification, or acceptance criteria,
     reapproval is required. Round 20 remains terminal and never starts round 21.

  3. FIX
     - Fix ALL must-fix and should-fix items (not just must-fix)
     - Prioritize lowest-scoring rubric dimensions first
     - Add each fixed item to previously_fixed with description

  4. VALIDATE
     - Run build + tests if applicable
     - If build/tests fail -> fix and re-verify before continuing
     - For C# projects: run the configured local cognitive-complexity check when available and policy-allowed, then flag methods exceeding threshold; if unavailable/disallowed, record that explicitly and use equivalent review evidence from source inspection, tests, and focused complexity reasoning.

  5. round += 1 -> go to step 1
```

## The QA Evaluation Loop

Run this loop only when `qa_evaluation_mode=required` or the workflow Review phase requests QA evidence. Load `references/qa-evaluation-loop.md` before dispatching QAEvaluator.

QA evaluation runs after code-review/build evidence. It is not an alternate path around the Code Reviewer loop.

QA runs after build/test evidence and the Code Reviewer loop result exist. It must receive the Done Contract, acceptance criteria, verification evidence, domain_context/rubric_refs when applicable, round number, previously_failed_acceptance_items, and qa_filter_policy. It conditionally loads `references/domain-rubrics.md` only for scoped subjective/UI/visual/product/UX/docs/DX/domain acceptance. It returns status, round, acceptance_findings, qa_scorecard, selected_domain_rubrics/domain_quality_scores when used, final_verdict/result, evidence, score_progression or score_entry, and open_questions when blocked.

The QA loop supports rounds 1-20. In rounds 16-20, only unresolved acceptance blockers or high-confidence acceptance risks keep the loop open. Round 20 is terminal: return the final verdict and remaining failed acceptance items instead of starting round 21.

QA findings do not replace code-review findings. Do not use QAEvaluator to review general bugs, security, architecture, or test coverage unless that issue directly blocks an acceptance criterion or Done Contract item.

If QA score progression reports STAGNATION, repeated DRIFT, repeated REGRESSION,
or a scoped domain rubric returns action `pivot`, pause QA and return a
pivot_restart_signal to the orchestrator. The orchestrator records
pivot_restart_decision before another QA/build dispatch, updates trace/replay/run
state when the workflow is harness-capable, and obtains reapproval when the
selected restart or pivot changes scope, files, behavior, risk, verification, or
acceptance criteria.

## Exit: Present Final Result

After the loop completes, present ONE summary to the user:

```
## Review Complete

**Rounds:** {N}
**Result:** CLEAN | ISSUES_FIXED | HAS_REMAINING_ITEMS

### Rubric Score (medium+ scope)
| Dimension | Score | Justification |
|---|---|---|
| Correctness (0.30) | {score} | {one-line justification} |
| Code Quality (0.20) | {score} | {one-line justification} |
| Architecture (0.20) | {score} | {one-line justification} |
| Security (0.15) | {score} | {one-line justification} |
| Test Coverage (0.15) | {score} | {one-line justification} |
| **Weighted** | **{score}** | **{PASS/REFINE/PIVOT}** |

### Score Progression (if multiple rounds)
| Round | Score | Findings | Delta | Drift |
|---|---|---|---|---|
| 1 | {score} | {count} | - | - |
| 2 | {score} | {count} | {+/-} | {drift_status} |

### Fixed in this review
- [list of all items fixed across all rounds, grouped by severity]

### Remaining (if any)
- [items that could not be resolved]

### Nits noted (not fixed)
- [low-priority observations]
```

## Rules

- **Single final summary**: keep round results internal and report after the loop exits.
- **Autonomous continuation**: advance to the next round while exit criteria are unmet.
- **Fresh Reviewer each round** on medium+ scope: stale context weakens reviews.
- **Previously-fixed list prevents re-reporting**: each round should find fewer issues.
- **Evidence-backed filtering**: findings need file/line evidence, concrete impact, and the smallest useful fix; late rounds only stay open before the hard max for must-fix or high-confidence should-fix findings, and round 20 is terminal.
- If scope is trivial (single small file, obvious change) -> one clean round can exit. If findings exist, continue looping.

## Output

Return:
- **Rounds** - number of review rounds completed.
- **Result** - CLEAN, ISSUES_FIXED, or HAS_REMAINING_ITEMS.
- **Findings/fixed items** - severity, file, evidence, action, and round.
- **Verification** - build/test commands or not-applicable reason.
- **Bugfix evidence review** - when applicable, whether reproduction/root-cause evidence and regression linkage were reviewed.
- **Agentic loop safety review** - when applicable, whether bounds, stop conditions, retry/empty handling, tool-error routing, progress checks, and cost/token guards were checked.
- **Behavioral contract review** - when applicable, whether existing invariants, interface alignment, inherited tests, protocol fidelity, high-impact guards, and runtime surfaces were checked.
- **Semantic contract review** - when applicable, whether inherited contracts, method signatures, eval coverage, high-stakes guards, and mirror surfaces were checked.
- **QA evaluation result** - when applicable, final_verdict/result, acceptance_findings, qa_scorecard, selected_domain_rubrics/domain_quality_scores when scoped, score_progression, and blocked open questions.
- **Residual risk** - remaining items, nits, or scope gaps.

## Stop Rules

- In audit mode, stop after the first review round and report findings without edits.
- In review-fix mode, stop only when clean, blocked, or max rounds is reached.
- Stop and report a blocker if required review material is unavailable or empty.

### Drift detection (medium+ scope)

After each round, compare rubric scores to the previous round per `references/score-tracking.md`:

- **GENUINE**: Score up, findings down -> continue normally
- **SUSPICIOUS**: Score jumped > 1.0 in one round -> log warning, continue
- **DRIFT**: Score up but findings didn't decrease -> **reset evaluator** (fresh agent, stricter prompt)
- **REGRESSION**: Score down -> investigate; 2+ consecutive regressions trigger pivot_restart_signal
- **NEUTRAL**: Score unchanged for 1 round with findings present -> log, no action yet
- **STAGNATION**: Score unchanged for 2+ rounds with findings present -> return pivot_restart_signal to orchestrator

On DRIFT, the next Reviewer dispatch MUST include this addition to its prompt:
> "Previous rounds showed score inflation without corresponding quality improvement.
> Apply maximum skepticism. Score conservatively; when uncertain, round DOWN."

On repeated DRIFT after the reset, stop the current review dispatch path and
return pivot_restart_signal. The orchestrator owns the pivot_restart_decision and
selects reset, candidate search, replan, restart, or a blocked/user path without
creating round 21 behavior.


## Review Finding Rule Distillation

At the end of review, load `references/review-finding-permanent-rule.md` for every blocker or must-fix finding. Classify each as `one_off_fix`, `permanent_rule_candidate`, or `no_action`. Promote only recurring process gaps, fake-pass eval gaps, missing contracts, missing checklists, or high-impact repeatable failure modes; do not promote style nits or one-off file-specific issues into broad rules.
