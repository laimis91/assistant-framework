---
name: assistant-review
description: "This skill runs an autonomous code review loop: review, fix, re-review until clean (max 5 rounds). Use when the user says 'review', 'fresh review', 'code review', 'review this', 'check the code'. Also activates when the workflow's Review phase requires quality review dispatch."
effort: high
triggers:
  - pattern: "fix (all |the |review |reported )?issues|fix (all |the )?findings|apply (all )?fixes"
    priority: 90
    reminder: "This request to fix review issues matches assistant-review. You MUST load and follow this SKILL.md and its contracts before editing code. The skill includes fix -> validation -> re-review steps that run before the final summary."
  - pattern: "review|fresh review|code review|review this|check the code|/review"
    priority: 80
    reminder: "This request matches assistant-review. You MUST load and follow this SKILL.md and its contracts before doing anything else. Run the autonomous review-fix loop to its exit condition before reporting."
---

# Autonomous Review Loop

## Contracts

This skill enforces strict contracts on inputs, outputs, loop gates, and reviewer handoffs. Read the contract files in `contracts/` before executing.

| Contract | File | Purpose |
|---|---|---|
| **Input** | `contracts/input.yaml` | Scope, mode, and review material snapshot to resolve before entering the loop |
| **Output** | `contracts/output.yaml` | Final summary and verification artifacts |
| **Phase Gates** | `contracts/phase-gates.yaml` | Per-round step assertions and loop invariants |
| **Handoffs** | `contracts/handoffs.yaml` | Reviewer subagent dispatch and return schema |

**Rules:**
- Resolve all input contract fields before entering the loop
- Check phase gate assertions at every step transition within each round
- Include all required context fields when dispatching Reviewer subagents, and record direct-fallback review evidence when subagents are not authorized/available/allowed
- Validate all required return fields when Reviewer completes
- Verify all output contract artifacts before presenting the final summary

Run this loop autonomously from start to finish. Continue rounds until clean or max rounds reached, keep intermediate results inside the loop, and present one final result after exit.

## Goal

Find concrete defects, risks, regressions, and test gaps; fix them when in review-fix mode; and return one evidence-backed final review result. Reviews must be useful in company environments: local-first, policy-safe, and focused on actionable engineering risk rather than generic style preferences.

## Success Criteria

- Review scope and mode are resolved before the loop starts.
- Findings are severity-ranked with file evidence and confidence.
- Every review applies the SOLID, KISS, DRY, YAGNI, and readability lens from `references/review-principles.md`.
- In review-fix mode, must-fix and should-fix findings are addressed or explicitly deferred.
- Validation runs after fixes, and a fresh review confirms the final state.

## Constraints

- Default to audit mode when the user asks to provide, report, list, or summarize findings.
- Do not emit intermediate review summaries; present one final summary after loop exit.
- Use concrete risk categories for refactor-related findings.
- Treat clean-code principles as evidence lenses, not acronym-driven style rules.

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

Finding format:

```markdown
- Severity: must-fix | should-fix | nit
- Evidence: file:line or diff hunk plus observed behavior
- Impact: what can break, leak, regress, or become hard to maintain
- Recommendation: smallest useful fix
- Confidence: percentage matching the active review-round threshold
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

## The Loop

```
round = 1
previously_fixed = []
score_history = []

while round <= 5:

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
       Confidence threshold:
       - Round 1-2: 80%+
       - Round 3-4: 85%+
       - Round 5: 90%+
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
        - PIVOT (weighted < threshold for round) -> escalate to orchestrator
        - REFINE with findings -> continue to step 3
        - REFINE with zero findings -> EXIT CLEAN with advisory:
          "Rubric score {score} is below target, but no concrete
          actionable risk was found in scope. Low-scoring dimensions
          are noted as watch areas for future work."
          Include rubric scores and low-dimension details in final report.
     b. No rubric (small scope): use findings-based exit:
        - No must-fix AND no should-fix -> EXIT CLEAN
        - Only nits -> EXIT CLEAN (note nits in final report)
     c. round == 5 with remaining must-fix -> EXIT WITH REMAINING ITEMS
     d. round == 5 with issues fixed and now clean -> EXIT ISSUES FIXED
     e. Otherwise -> continue to step 3

     Record in score_history: { round, weighted_score, finding_count, drift_status }
     (see references/score-tracking.md for drift detection rules)

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
- **Higher confidence each round**: early rounds catch obvious issues, later rounds require higher certainty.
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
- **REGRESSION**: Score down -> investigate, escalate if 2+ consecutive rounds
- **NEUTRAL**: Score unchanged for 1 round with findings present -> log, no action yet
- **STAGNATION**: Score unchanged for 2+ rounds with findings present -> escalate to orchestrator

On DRIFT, the next Reviewer dispatch MUST include this addition to its prompt:
> "Previous rounds showed score inflation without corresponding quality improvement.
> Apply maximum skepticism. Score conservatively; when uncertain, round DOWN."

On 3+ DRIFT occurrences: stop the loop and present findings for manual review.


## Review Finding Rule Distillation

At the end of review, load `references/review-finding-permanent-rule.md` for every blocker or must-fix finding. Classify each as `one_off_fix`, `permanent_rule_candidate`, or `no_action`. Promote only recurring process gaps, fake-pass eval gaps, missing contracts, missing checklists, or high-impact repeatable failure modes; do not promote style nits or one-off file-specific issues into broad rules.
