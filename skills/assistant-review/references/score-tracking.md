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

Action: **Reset evaluator context.** Dispatch a fresh reviewer agent with an explicitly stricter prompt:

> "Previous rounds showed score inflation without corresponding quality improvement.
> Apply maximum skepticism. Score conservatively — when uncertain, round DOWN.
> Do not give benefit of the doubt on any dimension."

Also add to the final summary: "Drift detected in round N — evaluator was reset."

### Rule 4: REGRESSION

Score went down. Fixes may have introduced new problems, or the evaluator is catching things it previously missed.

```
score_delta < 0 → REGRESSION
```

Action: This is not necessarily bad — a fresh evaluator may legitimately find more issues. Log it but don't escalate unless regression persists for 2+ consecutive rounds.

### Rule 5: STAGNATION

Score unchanged for 2+ consecutive rounds with findings still present.

```
score_delta == 0 for 2 consecutive rounds AND finding_count > 0 → STAGNATION
```

Action: Flag to orchestrator. The loop is churning without progress. Consider:
- Fixes are introducing new issues at the same rate as resolving old ones
- The remaining issues may be architectural (can't fix without broader changes)
- May need to PIVOT or accept current state with documented limitations

## Decision Matrix

| Score Delta | Finding Condition | Status | Action |
|---|---|---|---|
| +, magnitude ≤ 1.0 | count decreased | **GENUINE** | Continue normally |
| +, magnitude > 1.0 | count decreased | **SUSPICIOUS** | Log warning, continue |
| +, any | count same or increased | **DRIFT** | Reset evaluator, stricter prompt |
| − | any | **REGRESSION** | Log, investigate if 2+ rounds |
| 0 | any, findings > 0 remain, 2+ consecutive rounds | **STAGNATION** | Escalate to orchestrator |
| 0 | any, findings > 0 remain, 1 round only | **NEUTRAL** | Log, no action yet |
| 0 | findings == 0 | *(exit as CLEAN)* | Should not reach drift check |

Note: STAGNATION checks absolute finding count (> 0), not finding delta. A score unchanged at 3.5 with findings dropping 5→3→1 across rounds is NEUTRAL (findings still moving), not STAGNATION. STAGNATION triggers when the score plateaus AND findings persist for 2+ consecutive rounds — the loop is churning without measurable progress.

## Task Journal Format

Record scores in each Quality Review entry:

```markdown
### Quality Review #N
- Round: N of 5
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
| 2 occurrences | Flag to orchestrator, consider different model for evaluation |
| 3+ occurrences | Stop loop, present findings to user for manual review |

The goal is not to prevent the loop from exiting — it's to ensure that when it exits, the code genuinely earned its passing score.
