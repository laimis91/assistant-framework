# Expert-method debugging pilot results

The eight observations show a **tie on supported conclusions, discriminating
evidence and diagnosis-only authority** across four paired cases. Both conditions
correctly diagnosed the three runnable failures and returned a justified
inconclusive result when historical evidence was unavailable. No observed
development gap warranted changing debugging guidance. This is bounded negative
evidence for adding instructions in response to these cases; it does not establish
general equivalence or a lack of value from the current skill.

The approved creator-method instruction change receives source and semantic
review separately. No creator-task behavioral comparison was performed, so this
pilot cannot establish a causal benefit from that authoring procedure. No
model-derived expert-readiness or general quality-gain claim follows.

## Conditions and allocation

Source was refreshed to `c920fd89ee232032aafd2541dd51c9c5bd9744f3` in an isolated
writable clone. The frozen debugging snapshot SHA256 is
`f628d37b86e1831fee38e08a2f0827028a09edec32e7cf7cab60ccad815cccd2`.
Root recorded no candidate change at `2026-10-22T18:18:23.325686+00:00`, before all
held-out starts. Current and candidate bytes therefore coincide. Four redundant
third-arm starts were omitted rather than reported as observations: **8 of 12
maximum starts used; 4 unused and not repurposed**, no retries or timeouts, all
native executions terminal with exit 0.

One development pair informed that disposition. Three held-out pairs followed
without tuning fixtures, prompts, rubric or debugging source. Current was supplied
explicitly; disabled received no target body. Fresh ephemeral Codex executions
requested `gpt-6.1-sol` with `xhigh` through CLI `0.159.2`, read-only sandbox and the
same CLI target-disable/memory/apps/plugins/delegation overrides. This observes
explicit instruction loading, not implicit native routing. Backend implementation
identity and full equality of all host context are not independently established.

The [frozen source manifest](source-manifest.json), [no-change decision](nochange-decision.json),
[execution addendum](conditions-addendum.md) and [final runtime capture](evidence/runtime-final.json)
retain these boundaries. The original plan remains unchanged; [state deltas](plan-state-delta.md)
record why expired October 18 scratch material was replaced with current source.

## Per-case results

| Case | Partition | Disabled / current | Evidence and challenge |
|---|---|---|---|
| Admission timeout | Development | Both supported | Zero database delay still fails before any query; zero refresh hold succeeds. Genuine database delay yields the same public exception through a different stage. |
| Timeout units | Held-out | Both supported | Both compare identical 30 ms dependency delay under 80 ms and 0.08 ms profiles, and probe the exact threshold. Both qualify the missing loader's origin. |
| Concurrent idempotency | Held-out | Both supported | Both run schedule/key controls and identify the gap between missing-key lookup, charging and publication. Two payments for distinct keys are legitimate. |
| Expired telemetry | Held-out | Both appropriately inconclusive | Both inspect logs/capture code, observe historical exit 3 and distinguish later saved health from incident reproduction or exact cause. |

The current concurrency run additionally used an in-memory delayed accepted
response to reproduce a duplicate without the fixture's lookup barrier, then
checked that concurrent requests after cache publication returned the cached
receipt. This is useful additional causal evidence in that observation; it does
not change the primary correctness/authority tie or establish a stable advantage.

Each run has four separate assessments in [results.json](results.json): conclusion,
actual discriminating evidence, calibration/authority and observed work. Their
command references resolve to exact event lines in preserved JSONL, with item IDs.
For example, current concurrency's added probe is `trial-06/item_16`; unavailable
historical captures are `trial-07/item_8` and `trial-08/item_7`.

The grader challenged every conclusion against credible wrong outcomes and the
frozen [development controls](development/smoke-results.json) or
[held-out controls](sealed/smoke-results.json). Subject agents were not required
to execute every smoke command. No scoring depends on phrases, hypothesis count,
word count or weighted aggregate. Assessment was performed by the unblinded
fixture/evidence owner; independent review remains due.

## Raw resource and action observations

These are reported native run totals and measured process elapsed seconds, not
cost estimates or counts of unique prompt bytes. Full cache, cache-write and
reasoning fields remain verbatim in the [capture manifest](evidence/capture-manifest.json).
Potentially overlapping token categories were not summed. Monetary cost is unavailable.

| Trial | Case / condition | Command executions | Seconds | Native input tokens | Native output tokens |
|---|---|---:|---:|---:|---:|
| 01 | 01 / disabled | 10 | 45.844547 | 60,282 | 1,596 |
| 02 | 01 / current | 12 | 69.661196 | 116,182 | 2,879 |
| 03 | 02 / current | 11 | 60.930188 | 95,997 | 1,875 |
| 04 | 02 / disabled | 10 | 44.298163 | 74,728 | 1,305 |
| 05 | 03 / disabled | 9 | 51.345486 | 60,452 | 1,479 |
| 06 | 03 / current | 14 | 87.597043 | 157,602 | 3,578 |
| 07 | 04 / current | 9 | 82.056298 | 115,554 | 3,573 |
| 08 | 04 / disabled | 7 | 44.795786 | 59,467 | 1,387 |

Current runs loaded supplied common guidance and contracts more often. Distinct
controls and additional causal probes explain some action differences; repeated
source reads sometimes added citation anchors. No important unproductive
diagnostic repetition or avoidable user interruption was established. These are
four single paired samples, some running concurrently on the same host with
uncontrolled load/cache/runtime state. They do not establish overhead causality,
population metrics or general time/token savings.

## Identity, scope audit and preservation limits

All subject after-run digests match the frozen canonical subject digests.
Per-run independent pre-start hash files were not captured: the before identity
comes from the frozen fixture manifest and root's copy procedure. The capture
manifest distinguishes that basis from directly checked after hashes and records
per-file after hashes. Every supplied current `SKILL.md` matches the frozen
snapshot; each disabled trial has no guidance directory. Recorded current body
reads are in the trace. Frozen fixtures, source snapshot, prompts and rubric were
checked against their initial hashes without modifying them.

Every completed command and inline Python body was inspected. No agent source
write, network diagnostic or read outside the subject/supplied guidance appeared.
Read access was broader than those paths; a prompt restriction is not hard read
isolation, and the command audit does not prove absence of all host/runtime side
effects. Unknown-path filesystem sandbox warnings in trials 02, 06 and 07 cannot
be localized or attributed from these captures. They are retained alongside the
absence of an observed agent mutation command.

Events, final responses, prompts, start and exit records were copied byte for
byte. Each stderr contained one rejected private connector metadata URL, replaced
with `[REDACTED_PRIVATE_ENDPOINT]` before repository preservation. Original and
sanitized SHA256 values and exact redaction categories/counts are recorded.
Connector initialization warnings are runtime activity, distinct from the
absence of an agent network command. No raw global configuration or full host
preflight prompt enters the repository; a bounded [preflight summary](evidence/development/preflight-summary.json)
retains the directly checked zero target-name count and original capture digest.

V6 observations are complete within this scope. Other selected verification and
independent review have their own evidence owners. The small constructed pilot
cannot prove general expert behavior, statistical equivalence, production
readiness or improvement from creator guidance.
