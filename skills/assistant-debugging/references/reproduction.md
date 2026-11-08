# Building a reproduction

Load when no adequate exact-symptom reproduction exists yet. A supplied test,
probe or replay that already asserts the exact reported symptom is used as it
is; do not rebuild it.

The running example: "checkout total is 800 instead of 900 after a 100-cent
promotion".

## Choose a feedback loop

Pick the loop that fits the symptom at the lowest cost. The list is not an
order to work through.

- **An existing failing test**: a test already reaches the failing path and
  only needs a sharper assertion.
- **A CLI or HTTP probe**: the symptom shows at a command or endpoint boundary.
- **A replay of a captured trace or payload**: a recorded request, event, log
  line or file reproduces the input exactly.
- **A small harness around the failing path**: the path is reachable in code
  but slow or awkward to reach through the full program.
- **A controlled reproduction of a flaky failure**: the failure depends on
  timing, ordering, randomness or shared state.
- **A bisection between a known-good and a known-bad state**: the symptom
  appeared between two revisions, versions or data snapshots.
- **A differential comparison**: two versions, configurations or inputs behave
  differently, and the difference localises the cause.

## Assert the exact symptom

The check asserts the exact reported symptom: the specific wrong value, error
identity, message or state. For the example, a probe replays the order and
asserts `total == 900`, observing `800`. A non-zero exit, "test failed" or
"exception raised" is not a symptom check, because unrelated failures produce
the same signal.

## Confirm the check is specific

Name a nearby unrelated failure on the same path, such as a setup, import or
fixture error, or a different wrong value, and confirm it would not satisfy the
check. Running the example probe with a deliberately broken fixture path gives a
fixture error, not the `800` assertion, so the check discriminates. A check that
only asserts "the total differs from the last run" would also fail on a
tax-rounding `899`; when the check cannot tell the two apart, record `partial`,
not `yes`. The `reproduced` description in `contracts/output.yaml` is the
authoritative definition of each value.

## Reduce cost and control nondeterminism

Narrow the scope to the failing path, skip unrelated initialisation and reuse
existing fixtures. Control what varies: a pinned clock, a fixed seed, an
isolated filesystem or network, and markers or barriers that force an
interleaving. A sleep may only widen a timing window; it is never proof that an
interleaving or finalisation happened. For lifecycle symptoms, use the marker
and barrier methods in [lifecycle-verification.md](lifecycle-verification.md).
Record what was observed for a flaky failure, for example "failed 7 of 40 runs
with seed 1234". Set no target rate.

## Minimise

Remove one input, step, configuration value or piece of data at a time, and
re-run the check after each cut. Restore any cut that removes or changes the
exact symptom: if removing the promotion makes the total correct, the promotion
stays; if a cut turns `800` into a `KeyError`, that cut is restored. Stop when
the exact symptom persists and further cuts no longer materially shrink the
loop. A minimised reproduction may become the regression oracle handed to
assistant-verification or assistant-tdd.

## Move history without touching the user's work

Run bisection and comparisons of other revisions in a separate worktree, for
example one created with `git worktree add` outside the checkout. Never reset,
stash or overwrite the user's uncommitted work. Destructive,
production-affecting, network and sensitive diagnostics keep the authorisation
rule in `SKILL.md`.

## Repetition

Repeated reproduction attempts are governed only by
[the shared stagnation guard](../../../tools/progress/operating-guidance.md).
This reference adds no attempt count or threshold of its own.
