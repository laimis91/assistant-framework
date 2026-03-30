# Harness Patterns for Loop-Based Skills

Reference pack for the skill creator. Load this when designing a **Process** skill that includes an evaluation loop, multi-round refinement, or autonomous fix-verify cycles.

**When to load:** The skill being created has any of these characteristics:
- Multi-round loop (review, refinement, optimization)
- Separate generator and evaluator roles
- Quality scoring against criteria
- Autonomous fix → re-check cycles

**When to skip:** Single-pass skills, analysis pipelines without loops, utility skills.

---

## Pattern 1: Rubric Scoring

Replace open-ended evaluation ("is this good?") with weighted dimensions scored 1-5.

### How to apply

1. **Identify 3-6 evaluation dimensions** specific to the skill's domain
2. **Assign weights** that sum to 1.0 — weight subjective dimensions higher to push beyond generic output
3. **Write anchor examples** for each dimension at scores 1, 3, and 5
4. **Define threshold actions** that map score ranges to loop decisions

### Template

```yaml
# In the skill's references/rubric.md or inline in SKILL.md

dimensions:
  - name: [dimension_name]
    weight: [0.10-0.40]
    measures: "[what this dimension evaluates]"
    anchors:
      5: "[concrete description of excellent]"
      3: "[concrete description of acceptable]"
      1: "[concrete description of poor]"

thresholds:
  pass: 4.0      # Exit loop — quality sufficient
  refine: 3.0    # Continue loop — specific improvements needed
  pivot: 2.5     # Escalate — approach may be fundamentally wrong
```

### Scoring rules to include in the evaluator's prompt

- Score each dimension independently (no halo effect)
- Cite specific evidence for each score
- When uncertain, round down
- Critical findings can cap the total score (define what's critical for your domain)

### Contract integration

Add to the evaluator's **return_fields** in `handoffs.yaml`:

```yaml
- name: rubric_scores
  type: object
  required: true
  condition: "scope warrants scoring"
  object_fields:
    - name: [dimension_name]
      type: float
      required: true
      validation: "1.0 to 5.0 in 0.5 increments"
    # ... one per dimension
    - name: weighted_score
      type: float
      required: true
    - name: action
      type: enum
      required: true
      enum_values: [PASS, REFINE, PIVOT]
```

### Example: applying to a content generation skill

```yaml
dimensions:
  - name: accuracy
    weight: 0.35
    measures: "Factual correctness, no hallucination, citations where needed"
  - name: clarity
    weight: 0.25
    measures: "Clear structure, audience-appropriate language, logical flow"
  - name: completeness
    weight: 0.20
    measures: "All requested topics covered, no significant gaps"
  - name: tone
    weight: 0.20
    measures: "Matches requested style, consistent voice throughout"
```

**Reference implementation:** `skills/assistant-review/references/review-rubric.md`

---

## Pattern 2: Drift Detection

Track evaluator scores across loop rounds to ensure genuine improvement, not evaluator fatigue.

### How to apply

1. **Record score + finding count per round** in a score history
2. **Compare round N to round N-1** using score delta and finding count
3. **Classify the change** and take appropriate action

### Drift classification

| Score Delta | Finding Condition | Status | Action |
|---|---|---|---|
| +, ≤ 1.0 | count decreased | **GENUINE** | Continue |
| +, > 1.0 | count decreased | **SUSPICIOUS** | Log warning |
| +, any | count same or increased | **DRIFT** | Reset evaluator |
| − | any | **REGRESSION** | Investigate |
| 0 | findings remain, 2+ rounds | **STAGNATION** | Escalate |
| 0 | findings remain, 1 round | **NEUTRAL** | Log only |

### On DRIFT: evaluator reset

Dispatch a fresh evaluator with an explicitly stricter prompt:

> "Previous rounds showed score inflation without quality improvement. Apply maximum skepticism. When uncertain, score DOWN."

### Contract integration

Add to **phase-gates.yaml** as loop invariants:

```yaml
invariants:
  - id: INV_DRIFT
    check: "Rubric score increases correlate with finding count decreases"
    scope: all_rounds
    condition: "round >= 2"
    on_fail: "Drift detected. Reset evaluator with stricter prompt."

  - id: INV_STAGNATION
    check: "Score does not stagnate (unchanged 2+ rounds with findings present)"
    scope: all_rounds
    condition: "round >= 3"
    on_fail: "Escalate to orchestrator — loop churning without progress."
```

Add to **output.yaml** as score progression:

```yaml
- name: score_progression
  type: object[]
  required: true
  condition: "loop ran 2+ rounds"
  object_fields:
    - name: round
      type: int
    - name: weighted_score
      type: float
    - name: finding_count
      type: int
    - name: drift_status
      type: enum
      enum_values: [GENUINE, SUSPICIOUS, DRIFT, REGRESSION, STAGNATION, NEUTRAL]
```

**Reference implementation:** `skills/assistant-review/references/score-tracking.md`

---

## Pattern 3: Harness Gates

Structural enforcement that blocks loop completion without required artifacts.

### How to apply

1. **Identify the artifacts** that must exist before the loop can exit (rubric scores, passing threshold, all items addressed)
2. **Add phase-gate assertions** that check for these artifacts
3. **Optionally add a Stop hook** for hard enforcement (shell script that parses the task journal)

### Phase-gate assertions for loop exit

```yaml
- id: EXIT_SCORE
  check: "Rubric weighted score meets pass threshold"
  on_fail: "Score below threshold — continue loop or escalate"

- id: EXIT_FINDINGS
  check: "No must-fix or should-fix findings remain"
  on_fail: "Findings remain — fix all before exiting"

- id: EXIT_VERIFICATION
  check: "Build and tests pass after all fixes"
  on_fail: "Verification failed — fix before exiting"
```

### Stop hook pattern (optional, for hard enforcement)

If the skill runs within the workflow (task journal exists), you can add a Stop hook that:
1. Reads the task journal
2. Checks for required artifacts (rubric lines, score threshold, final result)
3. Blocks stop if missing

Follow the pattern in `hooks/scripts/harness-gate.sh`:
- Use `set -euo pipefail`
- Check `stop_hook_active` to prevent infinite loops
- Use `jq` for JSON output
- Exit 0 (allow) or output `{"decision": "block", "reason": "..."}` (block)

**Reference implementation:** `hooks/scripts/harness-gate.sh`

---

## Pattern 4: Separation of Generation and Evaluation

The evaluator must never review its own fixes.

### How to apply

1. **Evaluator is read-only** — tools limited to Read, Grep, Glob, LS (no Edit, Write, Bash)
2. **Fresh evaluator per round** — no context contamination from previous evaluations
3. **Previously-fixed list** — each round receives what was already fixed, must not re-report
4. **Fixer is a separate agent** — the orchestrator or a dedicated implementer applies fixes

### Handoff contract for evaluator

```yaml
handoffs:
  - name: orchestrator_to_evaluator
    from: Orchestrator
    to: Evaluator
    context_fields:
      - name: content_to_evaluate
        type: string
        required: true
      - name: round
        type: int
        required: true
      - name: previously_fixed
        type: object[]
        required: true
        description: "Items fixed in prior rounds — do NOT re-report"
      - name: confidence_threshold
        type: int
        required: true
        description: "Minimum confidence for this round (increases per round)"
    return_fields:
      - name: findings
        type: object[]
        required: true
      - name: rubric_scores
        type: object
        required: true
      - name: verdict
        type: enum
        required: true
```

### Confidence progression

| Rounds | Threshold | Rationale |
|---|---|---|
| 1–2 | 80% | Cast wide net |
| 3–4 | 85% | Higher certainty required |
| 5 | 90% | Only near-certain findings |

**Reference implementation:** `skills/assistant-review/contracts/handoffs.yaml`

---

## Decision Checklist

When creating a Process skill with a loop, check which patterns apply:

| Question | If Yes → Apply |
|---|---|
| Does the loop evaluate quality? | Pattern 1 (Rubric) |
| Does the loop run 2+ rounds? | Pattern 2 (Drift Detection) |
| Must the loop complete before the task finishes? | Pattern 3 (Harness Gates) |
| Does one agent create and another evaluate? | Pattern 4 (Separation) |

Most loop-based skills will use all four. Simple refinement loops (e.g., "retry until build passes") may only need Pattern 3.

---

## Full reference

See `docs/harness-design-guide.md` for the complete design guide with architecture rationale, research references, and evolution principles.
