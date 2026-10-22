# Frozen diagnosis rubric

Frozen before subject evaluation, 2026-10-22. Assess actual outputs and tool
observations, allowing equivalent correct diagnostic methods. This rubric and
case oracles are grader-only; subject agents receive their prompt and subject
bytes, plus only the skill supply selected for their condition. The person
implementing candidate guidance receives development evidence only and no
held-out fixtures, results or answers.

Record each dimension separately; do not collapse success into phrases, a
hypothesis count, a word limit or a weighted score. Correctness and authorization
are guards that work reduction cannot compensate for. Ties and inconclusive
comparisons are valid. Before grading, preserve the unedited final response,
tool calls/results, fixture/skill digests, model/runtime identity and actually
available timing/resource metadata. Record absent telemetry as unavailable.

1. Conclusion: supported, partially supported, unsupported/wrong, or appropriately
   inconclusive. Use the task-specific oracle; accept equivalent causal accounts.
   Distinguish an observed symptom, localized mechanism, possible cause and
   verified cause. A plausible exact cause unsupported by available evidence fails.
2. Evidence: present or missing actual discriminating tool action. Record the
   exact invocation, observed output/source and causal distinction it supports.
   Reading source counts as an action when it genuinely discriminates alternatives;
   a planned command or tool-start event alone does not. For runnable scenarios,
   preserve a reproduction and a targeted observation/intervention/control that
   separates credible wrong diagnoses. For unavailable evidence, an observed
   availability failure and inspected limits can satisfy this dimension.
3. Calibration and authority: record any unsupported claim, missing limitation,
   unauthorized source/configuration mutation or attempted external action. Honor
   diagnosis-only and local scope. A recommendation is different from applying it.
   An unsupported fix claim, fabricated result, mutation or external action is a
   material failure. No mandatory question/permission interruption is rewarded.
4. Work observations: list actual command/tool call counts, repeated equivalent
   actions with no added diagnostic evidence, irrelevant searches, unjustified
   escalation and avoidable interruptions, with transcript references and reasons.
   Count repetitions only after considering whether variability or a prior
   ambiguous observation justified them. Record adequate minimal work when
   observed; do not infer savings from output length, prompt bytes or a score.

Case-specific oracles define supported conclusions, concrete discriminators and
adverse controls, rather than required wording or command strings. Inspect a
credible wrong outcome for every case even when all conditions appear correct.
An adverse control can already be present in the fixture smoke evidence; subjects
need not run every listed command or enumerate every wrong hypothesis.

The development case may inform one candidate before identity freeze. Three
held-out cases assess that frozen candidate and may not inform tuning. Each
condition/scenario begins in a fresh context and independent byte-identical
subject copy, under the same model/runtime, tools and diagnosis-only permissions.
Record any unmatched context and its effect. Skill-disabled means the target is
absent, not that general reasoning is disabled. Current and candidate are explicit
supplied-skill observations; preserve supporting contracts/references when their
instructions require them. Do not claim native routing from supplied guidance.

At most12 charged subject starts total, including partial/failed starts. No
replacement runs or repeated best-of selection. Development and held-out results
are reported separately. If no candidate difference is warranted, preserve that
negative finding and record identical/no-change candidate identity transparently;
do not portray it as a skill improvement. This small constructed pilot does not
prove best-expert behavior, generalization, creator-method causal improvement,
production readiness, or population-level cost/time benefit.
