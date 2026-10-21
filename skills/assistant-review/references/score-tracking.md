# Score tracking

Record the current final snapshot's aggregated score and finding count after the
complete response barrier. Preserve historical entries and source/finding
identities. Scores, counts and their GENUINE/SUSPICIOUS/DRIFT/REGRESSION/STAGNATION
labels are diagnostics only; they cannot reset or stop work, change severity or
confidence by round, force another review, or certify completion. In particular,
a numeric STAGNATION label is not a semantic guard decision.

Use [the shared task policy](../../../tools/progress/operating-guidance.md) for
repeated work. Assess each correction plus due executable verification/review
as one semantic cycle. A durable acceptance gain or useful novel evidence resets
the consecutive count; otherwise increment it. The source-bound effective window (default three consecutive unproductive
cycles) stops corrective work. Productive trajectories can pass round 10. New
findings, including an increased count, may be useful evidence; decreasing counts
or score inflation alone prove no gain. A/B oscillation and its fresh rechecks
retain one net disposition per cycle under the same guard.

A score entry retains positive round ordinal, weighted_score, aggregated finding
count, dimension scores, adjacent delta and diagnostic status. Never reinterpret
historical score data as progress evidence. Current final-snapshot coverage,
immutable finding provenance and acceptance obligations still govern completion.
Audit remains one read-only batch.

When genuinely stalled, retain evidence and report the specific blocker and next
useful action. A pivot/restart decision is required for a material scope, access,
cost, risk or acceptance change under existing authority rules. An equivalent
routine correction needs no repeated approval. Generic continuation cannot erase
a stall. A validated material unblock permits only its bound newly feasible
action, consumed once after all gates, without resetting count/history.

Diagnostic arithmetic preserves the aggregated union finding count. For adjacent
entries, DRIFT takes precedence whenever finding count is unchanged or increased;
SUSPICIOUS requires a score delta greater than +1.0 AND count decrease. A negative
delta is REGRESSION; positive delta plus count decrease is otherwise GENUINE.
A zero-delta plateau with the same positive count across two transitions is the
numeric STAGNATION diagnostic. Example: correctness=4, quality=3.5,
architecture=4, security=5, coverage=3 yields weighted_score: 3.90:
(4.0 * 0.30) + (3.5 * 0.20) + (4 * 0.20) + (5 * 0.15) + (3 * 0.15).
These arithmetic checks retain data integrity; score diagnostics alone do not
trigger pivot_restart_decision. On genuine shared semantic stagnation or material
change, preserve pivot_restart_signal and route the Pivot/Restart Decision Packet
through the orchestrator with the retained guard and concrete unblock condition.

Diagnostic formula: score_delta > 1.0 AND aggregated_finding_count_delta < 0 → SUSPICIOUS.
