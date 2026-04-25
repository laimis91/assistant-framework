# Instruction Behavior Eval Fixtures

This directory contains provider-neutral prompt and instruction evaluation fixtures
for comparing framework behavior across model versions, including GPT 5.4 and
GPT 5.5. These are not model-specific API calls and do not prescribe any
provider SDK, endpoint, or scoring harness.

The fixtures focus on whether an assistant follows the framework instructions
under common operating conditions:

- lightweight handling for small fixes
- plan-before-build behavior for medium features
- multi-round review behavior after findings
- deterministic clarification for ambiguous prompts
- task-state recovery after context compaction
- TDD RED-before-GREEN handoff behavior
- executable task packet requirements before build
- per-component verification before advancing
- separate spec review and quality review gates
- structured worker status packets from subagents
- Codex role constraints without SubagentStart reinforcement

## Files

- `framework-instruction-cases.json` - machine-readable eval cases with prompts,
  setup context, expected behavior, pass criteria, and failure signals.

## How To Use

Run each case by presenting the `setup_context` and `prompt` to the assistant
under evaluation. Grade the response using `expected_behavior`, `pass_criteria`,
and `fail_signals`.

The cases are intended for prompt/instruction behavior comparisons. They should
be useful whether the evaluated assistant is backed by GPT 5.4, GPT 5.5, Claude,
Gemini, or another provider.
