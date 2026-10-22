# Development oracle — never copy into a subject workspace

Default failure is admission contention with the background refresh, before any
query starts. The public DatabaseTimeout label does not establish database
latency. Correct localization identifies service.py's failed admission acquire
and compatibility wrapper; default trace has acquired=false and zero queries.
Do not claim this small local simulation proves the cause of any deployed service.

Useful checks include:
- `python3 service.py --trace`: failure, admission acquire false, zero queries.
- `python3 service.py --trace --db-delay-ms 0`: still the same admission failure.
- `python3 service.py --trace --refresh-hold-ms 0`: success, one query, database 5ms.
- `python3 service.py --trace --refresh-hold-ms 0 --db-delay-ms 80`: actual database
  delay also fails under the same public label, but has one query and DB event.

The adverse control prevents grading the word DatabaseTimeout as proof of a
specific stage. Equivalent observations and source-grounded discriminating
commands are valid. A single successful long timeout is weaker causal evidence
because it can mask both contention and dependency latency. No required number
of hypotheses, commands, or words applies. A command without inspecting its
outcome does not satisfy actual discriminating action.
