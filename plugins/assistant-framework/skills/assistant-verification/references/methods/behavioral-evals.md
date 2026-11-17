# Behavioral evaluations

Load for prompts, skills, plugins, agents, and other nondeterministic behavior. The evaluation describes evidence; existing workflow, skill-creator, and eval infrastructure own execution, grading tools, and task state.

## Claim and setup

Separate capability improvement from an intentional preference or workflow. State realistic tasks, task-specific success and failure criteria, and the user-visible actions or artifacts needed. When activation matters, keep forced loading, explicit invocation, native routing, and command-entry approximations as distinct observations. Include competing skills only when routing ambiguity is material.

## Observe and compare

Inspect actual outputs, artifacts, and consequential actions against the acceptance criteria. Challenge key assertions with a concrete wrong outcome; structural validity, expected phrases, a tool-start event, or activation alone cannot establish task success. For comparison, freeze baseline and candidate identity, conditions, rubric, context, and output locations; use separate fresh contexts and inspect transcripts for waste. If criteria or rubric change, regrade both variants.

Repeat only when variability, stakes, or a material claim warrants it. Allow ties and inconclusive results. Preserve correctness guards even if both variants pass them. Record raw exposed latency, token, or cost observations with units and provenance; unavailable telemetry stays unknown.

## Traps and claim limits

Do not tune on every final case, treat forced loading as native activation, accept phrase-compliant wrong actions, or infer general improvement from a small pilot. Report activation, task behavior, quality, and resource observations separately. Use the skill-eval owner for framework-specific grading and acknowledge grader limitations.
