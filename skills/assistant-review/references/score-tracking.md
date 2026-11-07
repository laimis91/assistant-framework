# Score tracking

Record the current final snapshot's aggregated score and finding count after the
complete response barrier. Preserve historical entries and source/finding
identities. Scores, counts and their GENUINE/SUSPICIOUS/DRIFT/REGRESSION/STAGNATION
labels are diagnostics only; they cannot reset or stop work, change severity or
confidence by round, force another review, or certify completion. In particular,
a numeric STAGNATION label is not a semantic guard decision.

Repeated work follows the [shared task policy](../../../tools/progress/operating-guidance.md).

A score entry retains positive round ordinal, weighted_score, aggregated finding
count, dimension scores, adjacent delta and diagnostic status. Never reinterpret
historical score data as progress evidence. Current final-snapshot coverage,
immutable finding provenance and acceptance obligations still govern completion.
Audit remains one read-only batch.

Diagnostic arithmetic preserves the aggregated union finding count. For adjacent
entries, DRIFT takes precedence whenever finding count is unchanged or increased;
SUSPICIOUS requires a score delta greater than +1.0 AND count decrease. A negative
delta is REGRESSION; positive delta plus count decrease is otherwise GENUINE.
A zero-delta plateau with the same positive count across two transitions is the
numeric STAGNATION diagnostic. Example: correctness=4, quality=3.5,
architecture=4, security=5, coverage=3 yields weighted_score: 3.90:
(4.0 * 0.30) + (3.5 * 0.20) + (4 * 0.20) + (5 * 0.15) + (3 * 0.15).
These arithmetic checks retain data integrity. Pivot and restart routing lives in
[review-loop.md](review-loop.md) EVALUATE.

Diagnostic formula: score_delta > 1.0 AND aggregated_finding_count_delta < 0 → SUSPICIOUS.
