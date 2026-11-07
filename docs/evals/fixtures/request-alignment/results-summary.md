# S01 request-alignment matched evaluation — result summary

Run 2026-11-07 under the frozen procedure in the S01 plan (tasks T7–T9) and
[S01 specification](../../../specs/framework-value-improvements/S01-request-alignment.md),
"Bounded matched evaluation". Full per-run records stay in local Git-ignored
evaluation state.

## Conditions

- **current**: main `d11756d` — the shared guide plus the target skill tree and
  its declared dependencies.
- **changed**: the frozen candidate `7d5765e` (tag `fvi-s01-candidate`), the S01
  change later merged as `b77a1e8`.

Both conditions were supplied by explicit controlled loading: the guide and the
target `SKILL.md` were appended to the system prompt, and every referenced file
resolved inside that condition's exported tree. Before the first start, every
subject manifest, oracle and rubric hash, guide hash and skill tree id was
compared with its frozen value and matched; the local record keeps those
values. Each start's log entry records the subject manifest and guide hash but
not the skill tree id, which the frozen procedure asked for per start.

## Runtime

- Subjects: DeepSeek Flash (`deepseek-flash`), run through Claude Code 2.1.317
  headless (`-p`) against the DeepSeek Anthropic-compatible endpoint, with
  default reasoning settings.
- Isolation:
  - each start had a fresh process and context, in a fresh byte-identical copy
    of the case subject;
  - an isolated configuration directory, with no skills, `CLAUDE.md`, hooks or
    MCP servers;
  - no filesystem sandbox: reads could reach paths outside the workspace.
- Tools: Read, Grep and Glob for cases 01–04; Read, Grep, Glob, Edit and Write
  for cases 05 and 06. No shell for any case, so no subject ran tests. Both
  conditions of a case had identical tools.
- Starts: 12 of 12 used, single trial. All completed, with no retries or
  replacements.
- Grading: one fresh, read-only DeepSeek Flash grader per response, applying
  the frozen rubric and case oracle. Packets had random identifiers and no
  condition labels.
- Grader output: graders added prose after the JSON verdict. One grader also
  left unescaped quotes inside an evidence string; these were repaired
  mechanically, and no verdict was changed.
- Trace files: not written, because the trace schema's required timing and
  rework metrics were not observed. `--compare-traces` was not used.

## Results

Results are per case. Notes summarise the deciding items; full per-dimension
grades are in the local record.

| Case | Partition | current | changed | Notes |
|---|---|---|---|---|
| case-01-research | development | pass | pass | All outcomes direct, all support retained in both. |
| case-04-plan | development | pass | pass | All outcomes direct, all support retained in both. |
| case-02-ticket | held-out | pass | pass | All outcomes direct, all support retained in both. |
| case-03-spec | held-out | pass | pass | All outcomes direct, all support retained in both. |
| case-05-docs | held-out | fail | fail | Both kept "Tested on macOS and Linux" as fact: M2 lost and calibration trap F1, although CI runs only on `ubuntu-latest`. Coverage O1–O3 was direct in both. The grader also flagged other unsupported claims: an invented `node` extra (current); "silently skips" and a Homebrew pip claim (changed). |
| case-06-handoff | held-out | pass | pass | Both named `render_invoice` as the other affected caller, left it unedited and said tests were not run. |

Held-out cases passed: 3 of 4 in both conditions. Development cases passed: 2
of 2 in both conditions. No coverage or material-support verdict differed
between conditions in any case. Tangent counts in the main answer were
similar: the changed condition had fewer in cases 01 and 06, and the same
number elsewhere. Tangents do not affect pass or fail.

## Claim rule

The changed tree is supported if it has no held-out case where it loses a
coverage or material-support item that current had, and it passes at least as
many held-out cases as current. Both conditions hold, so the change is
**supported as a tie**. This run observed no improvement over current, and no
regression.

## Limits

- Six constructed cases, one model and single trials, with explicit loading.
- Both subjects and grader were DeepSeek Flash, not the models the framework
  normally runs on, and the grader was not a separate model family.
- No subject had a shell, so the test-running behaviour in cases 05 and 06 was
  not exercised.
- No claim about native activation, generalization, population-level quality,
  or token or time savings.
- The case-05 failure is shared, so it shows a gap neither instruction tree
  closes for this model. It is not a difference between the trees.

Held-out oracles are committed under [`oracles/`](oracles/) now that the
result exists. Never copy them into a subject workspace.
