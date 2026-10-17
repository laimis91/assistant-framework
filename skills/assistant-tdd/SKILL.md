---
name: assistant-tdd
description: "Use for tests-first TDD requests, project TDD rules, or workflow-selected TDD checks."
---

# Test-Driven Development

## Goal

For an active TDD decision, protect each selected behavior with meaningful RED,
minimal GREEN, and behavior-neutral REFACTOR evidence before production code is
trusted. TDD is independent of test scope and does not activate by default.

## Success Criteria

- Each behavior starts with a test assertion that fails for the intended reason; extend an existing test when that is the smallest useful change.
- Production code is limited to the smallest change that makes that test pass.
- The target and relevant regression checks pass before the next cycle; run binding project suites when required.
- RED/GREEN/REFACTOR evidence is recorded in the task journal or output.
- When a workflow Architecture Decision Pack carries semantic type, primitive-boundary, public compatibility, or quality-scenario obligations, tests prove those obligations rather than merely compiling wrappers.

## Constraints

- Never treat syntax, import, environment, or flaky failures as valid RED.
- Do not write production code before RED evidence exists.
- Ask every material question when behavior or acceptable test scope changes the test; group questions by topic with why, risk if guessed, and a safe default where available rather than enforcing a numeric quota.

## Progressive Contract Loading

Canonical tier files are `contracts/input.yaml`, `contracts/output.yaml`,
`contracts/phase-gates.yaml`, and `contracts/handoffs.yaml`.

Read `contracts/index.yaml` first and load only the active enforcement boundary:

- `entry` for activation, behaviors, debugging evidence, framework, and exceptions;
- `current_phase` for RED, GREEN, or REFACTOR; and
- `completion` for the returned cycle artifact.

The handoffs contract remains canonical but empty because `assistant-workflow`
owns cross-role dispatch. Missing or invalid selectors fall back to the full
named canonical contract; do not load every contract at entry.

## Ownership

assistant-tdd owns RED-GREEN-REFACTOR correctness. Generic workflow coordinates
task packets and role dispatch, but specialist gates are authoritative.

When workflow delegates, ownership follows `execution_lane`; preserve carried
decision and phase boundary:

- Run RED only for selected IDs intersecting `tdd_choice.applicable_check_ids`;
  split active workflow packets until one ID intersects, and preserve the
  decision unchanged.

- `verification_selection` uses unchanged `selected_technique` and current ID
  intersection; preserve its source.

- In `bounded_executor`, one bounded executor owns RED, production, GREEN, and REFACTOR verification; production starts only after valid RED.
- Separated_workers: SAME writer authors tests (`test_authoring`, no incoming RED), implements after current RED (`production`), and refactors after current GREEN (`refactor`). Builder/Tester only executes RED/GREEN/REFACTOR. Stage-only DONE cannot complete Build or Review.

Reused checks force no new tests/stages. Changed authorizing inputs require fresh RED; preserve history.

Required RED evidence before production implementation:

- Test file and test name
- For authorizing RED, the sole applicable selected CheckSpec ID, exact argv/cwd,
  and matching oracle; standalone/no-decision TDD may omit the ID.
- Failure summary
- Why the failure proves the intended missing behaviour

Keep actual RED outcomes/counts failed. Only matching authorizing RED completes
`pre_production_red` with aggregate `partial` and pending GREEN; it is not final
Build evidence. Run `final_verification` after Code Writer before Review.

For a carried Architecture Decision Pack, test semantic type, primitive-boundary, public-compatibility, quality-scenario, and applicable design-pressure obligations (control/early exit, ownership/disposal, resources, extension registration, representative path). Do not invent Packs or benchmarks. Quality claims remain unknown until workload, budget, measurement, and failure condition are testable.

If TDD is active and RED evidence is missing, the selected production owner
must return `NEEDS_CONTEXT` and make no production changes.

## Cycle

1. **RED** — writer adds or extends one behavior assertion; the verification owner runs it for the right failure. If it passes unexpectedly, inspect existing behavior and test validity; use current regression/characterization evidence instead of fabricating RED.
2. **GREEN** — write the simplest passing code, rerun the target and relevant
   regressions, plus any binding suite. Repair regressions before continuing.
3. **REFACTOR** — remove duplication or improve names without new behavior; keep
   tests green after each change.
4. Repeat for the next behavior.

For unknown-cause bugs, use `assistant-debugging` first. Start TDD only after
reproduction/root-cause evidence can define a meaningful regression test.

Allowed exceptions require recorded approval/reason when TDD is active:
throwaway spikes, generated code, docs-only work, behavior-free config, and
layout-only styling. Do not claim TDD completion for an exception.

## Output

Return status, cycle log with commands/outcomes, test and production files,
targeted/regression verification, approved exceptions, and blockers.

## Stop Rules

- Stop before production edits when active TDD requires RED and its evidence is absent or invalid.
- Stop and repair the test when RED passes or fails for the wrong reason.
- Stop and repair regressions before the next behavior.
