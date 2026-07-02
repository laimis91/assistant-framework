# Score Tracking & Drift Detection

Tracks rubric scores across review rounds to ensure the loop makes genuine progress — not just an evaluator getting tired and passing things it shouldn't.

Think of it like a speedometer with a lie detector: the score can go up, but only if the code actually got better.

## Score History Format

After each review round, record an entry in the score history:

```
score_history.append({
  round: N,
  weighted_score: 3.85,
  finding_count: 5,        # must-fix + should-fix (not nits)
  dimension_scores: { correctness: 4.0, code_quality: 3.5, ... },
  drift_status: GENUINE    # computed from rules below
})
```

## Drift Detection Rules

Compare each round to the previous round using two signals: **score delta** and **finding count delta**.

### Rule 1: GENUINE improvement

Score went up AND finding count went down.

```
score_delta > 0 AND finding_count_delta < 0 → GENUINE
```

This is the expected pattern: fixes improve the code, fewer issues found.

### Rule 2: SUSPICIOUS improvement

Score went up significantly (> 1.0) in a single round. Even if findings decreased, this magnitude of jump warrants verification.

```
score_delta > 1.0 → SUSPICIOUS (regardless of finding count)
```

Action: Log a warning in the final summary. The improvement may be real (e.g., a single critical fix that uncapped the score), but it should be noted.

### Rule 3: DRIFT (evaluator leniency)

Score went up BUT finding count didn't decrease. The evaluator is scoring higher without the code actually improving.

```
score_delta > 0 AND finding_count_delta >= 0 → DRIFT
```

Action: **Reset evaluator context once.** Dispatch a fresh reviewer agent with an explicitly stricter prompt:

> "Previous rounds showed score inflation without corresponding quality improvement.
> Apply maximum skepticism. Score conservatively — when uncertain, round DOWN.
> Do not give benefit of the doubt on any dimension."

Also add to the final summary: "Drift detected in round N — evaluator was reset."
Repeated DRIFT after the reset triggers `pivot_restart_signal` and requires an
orchestrator-owned `pivot_restart_decision` before another review dispatch.

### Rule 4: REGRESSION

Score went down. Fixes may have introduced new problems, or the evaluator is catching things it previously missed.

```
score_delta < 0 → REGRESSION
```

Action: This is not necessarily bad — a fresh evaluator may legitimately find more issues. Log it, but 2+ consecutive REGRESSION entries trigger `pivot_restart_signal` and require an orchestrator-owned `pivot_restart_decision` before another fix/review dispatch.

### Rule 5: STAGNATION

Score unchanged for 2+ consecutive rounds with findings still present.

```
score_delta == 0 for 2 consecutive rounds AND finding_count > 0 → STAGNATION
```

Action: Return `pivot_restart_signal` to the orchestrator. The loop is churning
without progress. The orchestrator must record `pivot_restart_decision` before
another fix/review dispatch and consider:
- Fixes are introducing new issues at the same rate as resolving old ones
- The remaining issues may be architectural (can't fix without broader changes)
- The selected recovery may need reset, candidate search, replan, restart, or a
  blocked/user path

## Decision Matrix

| Score Delta | Finding Condition | Status | Action |
|---|---|---|---|
| +, magnitude ≤ 1.0 | count decreased | **GENUINE** | Continue normally |
| +, magnitude > 1.0 | count decreased | **SUSPICIOUS** | Log warning, continue |
| +, any | count same or increased | **DRIFT** | Reset evaluator once; repeated DRIFT triggers pivot_restart_decision |
| − | any | **REGRESSION** | Log; 2+ consecutive regressions trigger pivot_restart_decision |
| 0 | any, findings > 0 remain, 2+ consecutive rounds | **STAGNATION** | Return pivot_restart_signal and require pivot_restart_decision |
| 0 | any, findings > 0 remain, 1 round only | **NEUTRAL** | Log, no action yet |
| 0 | findings == 0 | *(exit as CLEAN)* | Should not reach drift check |

Note: STAGNATION checks absolute finding count (> 0), not finding delta. A score unchanged at 3.5 with findings dropping 5→3→1 across rounds is NEUTRAL (findings still moving), not STAGNATION. STAGNATION triggers when the score plateaus AND findings persist for 2+ consecutive rounds — the loop is churning without measurable progress.

## Task Journal Format

Record scores in each Quality Review entry:

```markdown
### Quality Review #N
- Round: N of 10
- Previously fixed: M items from prior rounds
- Found this round: X must-fix, Y should-fix, Z nits
- Rubric: correctness=4.0 quality=3.5 architecture=4.0 security=5.0 coverage=3.0
- Weighted: 3.85
- Delta from previous: +0.35
- Drift check: GENUINE (findings decreased 5→3)
```

## Final Summary Score Progression

Include in the review exit summary:

```markdown
### Score Progression
| Round | Score | Findings | Delta | Drift |
|---|---|---|---|---|
| 1 | 3.50 | 5 | — | — |
| 2 | 3.85 | 3 | +0.35 | GENUINE |
| 3 | 4.10 | 0 | +0.25 | GENUINE |
```

## Drift Response Escalation

| Drift Count | Response |
|---|---|
| 1 occurrence | Reset evaluator, stricter prompt |
| 2 occurrences | Return pivot_restart_signal; orchestrator records pivot_restart_decision |
| 3+ occurrences | Stop current review path until pivot_restart_decision selects reset, candidate search, replan, restart, or blocked/user path |

The goal is not to prevent the loop from exiting — it's to ensure that when it exits, the code genuinely earned its passing score.

## Pivot/Restart Decision Packet

When STAGNATION, repeated DRIFT, repeated REGRESSION, or rubric action PIVOT
fires, the review loop does not silently continue. It returns
`pivot_restart_signal`; the orchestrator records `pivot_restart_decision` with:

- `trigger`
- `evidence`
- `affected_slice_or_round`
- `options_considered`
- `selected_action`
- `reapproval_required`
- `next_agent`
- `recovery_pointer`
- `exact_next_action`

If the selected action changes approved scope, files, behavior, risk,
verification, or acceptance criteria, `reapproval_required` is true and the
workflow waits for approval before Build or Review continues. Round 10 remains
terminal; do not start round 11.
