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
- `../../tools/evals/run-framework-instruction-evals.sh` - offline helper for
  validating the fixture, listing cases, emitting prompt packets, and grading
  captured responses locally.

## How To Use

Validate the fixture before using it:

```bash
tools/evals/run-framework-instruction-evals.sh --validate-fixture
```

List the available cases:

```bash
tools/evals/run-framework-instruction-evals.sh --list
```

Emit provider-neutral prompt packets for manual or adapter-driven execution:

```bash
tools/evals/run-framework-instruction-evals.sh --emit-prompts /tmp/framework-eval-prompts
```

Run each prompt packet with any model or provider, then save the captured
assistant responses as `<case-id>.txt` or `<case-id>.md` in a response directory.
Grade those saved responses locally:

```bash
tools/evals/run-framework-instruction-evals.sh --responses /tmp/framework-eval-responses
```

The response grader is intentionally heuristic/local grading. It checks for
missing files, empty responses, and exact fail-signal phrase hits where useful.
It complements human review or a separate LLM judge; it does not replace natural
language judgment.

The cases are intended for prompt/instruction behavior comparisons. They should
be useful whether the evaluated assistant is backed by GPT 5.4, GPT 5.5, Claude,
Gemini, or another provider.

The eval flow is provider-neutral: the helper only reads local fixture and
response files. It does not invoke provider APIs, provider SDKs, or network
services.
