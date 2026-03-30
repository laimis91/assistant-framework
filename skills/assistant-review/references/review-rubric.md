# Review Rubric

Structured scoring system for evaluator calibration. Replaces open-ended "find issues" with weighted dimensions and anchored examples.

## When to Use

- **Medium+ scope**: Full rubric scoring required — reviewer scores all 5 dimensions
- **Trivial/small scope**: Rubric scoring optional — reviewer may skip if review is a single-round clean pass
- **Audit mode**: Score but do not act on thresholds (report only)

## Dimensions

| Dimension | Weight | What It Measures |
|---|---|---|
| **Correctness** | 0.30 | Bugs, logic errors, edge cases, acceptance criteria met |
| **Code Quality** | 0.20 | Readability, naming, maintainability, SOLID adherence |
| **Architecture** | 0.20 | Layer boundaries, dependency direction, pattern consistency |
| **Security** | 0.15 | Injection, auth bypass, data exposure, OWASP top 10 |
| **Test Coverage** | 0.15 | New behavior tested, edge cases covered, test quality |

## Score Anchors

Each dimension is scored 1-5. Use these anchors to calibrate:

### Correctness (weight: 0.30)

| Score | Anchor |
|---|---|
| **5** | All acceptance criteria met. Edge cases handled. No bugs found. Error paths are correct. |
| **4** | Core logic correct. Minor edge case missed but no user-facing impact. |
| **3** | Happy path works. 1-2 edge cases unhandled that could cause issues under specific conditions. |
| **2** | Core logic has a flaw that would manifest in normal usage. Regression risk. |
| **1** | Fundamental logic error. Would fail basic smoke testing. |

### Code Quality (weight: 0.20)

| Score | Anchor |
|---|---|
| **5** | Clean, self-documenting code. Consistent with repo conventions. No code smells. |
| **4** | Readable and maintainable. Minor inconsistency (e.g., one method slightly too long). |
| **3** | Works but some areas hard to follow. Mixed naming conventions or unclear intent. |
| **2** | Multiple code smells. God method, unclear responsibilities, copy-paste patterns. |
| **1** | Unmaintainable. No structure, magic numbers, misleading names, tangled logic. |

### Architecture (weight: 0.20)

| Score | Anchor |
|---|---|
| **5** | Follows existing patterns exactly. Correct layer placement. Dependencies point inward. |
| **4** | Mostly aligned. One minor boundary concern (e.g., a helper in the wrong layer but low impact). |
| **3** | Works but introduces a new pattern where existing one applies. Or bypasses a layer for convenience. |
| **2** | Layer violation that will cause coupling issues. Domain depends on infrastructure. |
| **1** | Ignores project architecture entirely. Business logic in UI, SQL in controllers, circular deps. |

### Security (weight: 0.15)

| Score | Anchor |
|---|---|
| **5** | No security concerns. Inputs validated. Auth checked. Sensitive data handled correctly. |
| **4** | Secure by default. Minor hardening opportunity (e.g., could add rate limiting, not critical). |
| **3** | No active vulnerability but missing defense-in-depth (e.g., no input validation on internal API). |
| **2** | Exploitable vulnerability under specific conditions (e.g., SQL injection via crafted input). |
| **1** | Open vulnerability. Auth bypass, credential exposure, injection with no mitigation. |

### Test Coverage (weight: 0.15)

| Score | Anchor |
|---|---|
| **5** | All new behavior tested. Edge cases covered. Tests are readable and maintainable. |
| **4** | Happy path tested well. One edge case could use a test but isn't critical. |
| **3** | Some tests exist but gaps in coverage. Missing negative cases or boundary tests. |
| **2** | Minimal testing. Only trivial assertions. Would not catch regression. |
| **1** | No tests for new/changed behavior. Or tests exist but don't assert meaningful behavior. |

## Calculating the Weighted Score

```
weighted_score = (correctness * 0.30) + (quality * 0.20) + (architecture * 0.20)
               + (security * 0.15) + (coverage * 0.15)
```

Example: correctness=4, quality=4, architecture=3, security=5, coverage=3
```
= (4 * 0.30) + (4 * 0.20) + (3 * 0.20) + (5 * 0.15) + (3 * 0.15)
= 1.20 + 0.80 + 0.60 + 0.75 + 0.45
= 3.80 → REFINE
```

## Threshold Actions

| Weighted Score | Action | What Happens |
|---|---|---|
| **4.0+** | **PASS** | Exit clean. Ship it. Minor nits noted but not blocking. |
| **3.0–3.9** | **REFINE** | Continue loop. Reviewer provides specific feedback per dimension. Generator iterates on lowest-scoring dimensions. |
| **< 3.0** | **PIVOT** | Current approach has fundamental issues. Flag to orchestrator. Consider whether the implementation strategy needs to change, not just the code. |

### Threshold adjustment by round

As the loop progresses, the bar rises — like a tightening ratchet:

| Round | Pass Threshold | Refine Range | Pivot Threshold |
|---|---|---|---|
| 1 | 4.0+ | 2.5–3.9 | < 2.5 |
| 2 | 4.0+ | 2.75–3.9 | < 2.75 |
| 3 | 4.0+ | 3.0–3.9 | < 3.0 |
| 4-5 | 4.0+ | 3.25–3.9 | < 3.25 |

Rationale: If the code hasn't reached 3.25 by round 4, the approach likely needs rethinking, not more polish.

## Reviewer Scoring Instructions

When scoring, the reviewer MUST:

1. **Score each dimension independently** — do not let one dimension's score influence another
2. **Reference specific code** — each score must cite at least one example from the diff
3. **Use the anchors** — pick the anchor that most closely matches, then adjust +/- 0.5 if between anchors
4. **Never score higher than evidence supports** — when uncertain, round down
5. **Weight security appropriately** — a single critical vulnerability caps the weighted score at 2.0 regardless of other dimensions

## Rubric Override: Critical Findings

Certain findings override the rubric score regardless of dimension scores:

| Finding Type | Effect |
|---|---|
| Active security vulnerability (exploitable) | Weighted score capped at 2.0 |
| Data loss risk | Weighted score capped at 2.0 |
| Build-breaking change | Weighted score capped at 1.0 |
| Test suite broken by changes | Weighted score capped at 2.5 |

## Output Format

The reviewer returns rubric scores in this structure:

```yaml
rubric_scores:
  correctness: 4.0
  code_quality: 3.5
  architecture: 4.0
  security: 5.0
  test_coverage: 3.0
  weighted_score: 3.85
  action: REFINE
  score_justification:
    correctness: "All CRUD operations correct. Edge case: bulk delete with empty list not handled (line 45)."
    code_quality: "Consistent naming. OrderService.Process() at 85 lines is borderline but acceptable."
    architecture: "Clean layer separation. Repository pattern matches existing conventions."
    security: "No user input reaches SQL. Auth middleware correctly applied to all new endpoints."
    test_coverage: "Happy path tested. Missing: concurrent access test for shared state in OrderCache."
  critical_override: null  # or: "Active SQL injection in SearchController:92 — caps score at 2.0"
```
