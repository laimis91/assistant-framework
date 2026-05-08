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

## Framework Instruction Fixtures

### Files

- `framework-instruction-cases.json` - machine-readable eval cases with prompts,
  setup context, expected behavior, pass criteria, failure signals, and local
  machine expectations.
- `../../tools/evals/run-framework-instruction-evals.sh` - offline helper for
  validating the fixture, listing cases, emitting prompt packets, and grading
  captured responses locally.

### How To Use

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

Each case includes `machine_expectations.required_substrings` and
`machine_expectations.forbidden_substrings`. These arrays contain literal
observable substrings for deterministic local checks. Required substrings must
appear in the captured response, and forbidden substrings must not appear.

The response grader is intentionally heuristic/local grading. It checks for
missing files, empty responses, exact fail-signal phrase hits where useful,
missing required substrings, and forbidden substring hits. These deterministic
substring checks are proxies that complement human review or a separate LLM
judge; they do not replace natural language judgment.

The cases are intended for prompt/instruction behavior comparisons. They should
be useful whether the evaluated assistant is backed by GPT 5.4, GPT 5.5, Claude,
Gemini, or another provider.

The eval flow is provider-neutral: the helper only reads local fixture and
response files. It does not invoke provider APIs, provider SDKs, or network
services.

## Per-Skill Eval Fixtures

Skill-local eval fixtures live beside the skill they exercise:

```text
skills/<skill>/evals/cases.json
```

`tools/evals/run-skill-evals.sh` validates, lists, emits, and locally grades
those skill fixtures with the same provider-neutral constraints as the framework
instruction eval runner. It uses local shell and `jq` only; it does not call
provider SDKs, model APIs, or network services.

This slice is a pilot, not complete coverage for all 15 first-class skills. The
current tracked fixtures cover:

- `skills/assistant-clarify/evals/cases.json`
- `skills/assistant-thinking/evals/cases.json`

By default, the runner discovers first-class `skills/assistant-*/SKILL.md`
skills that have `evals/cases.json` fixtures. Local-only `skills/unity-*`
skills are excluded from the default inventory. Use `--include-local` only when
you explicitly want to include local skill experiments that also have eval
fixtures.

### How To Use

Validate all default per-skill fixtures:

```bash
tools/evals/run-skill-evals.sh --validate-fixture
```

Validate one skill by name, directory, or `SKILL.md` path:

```bash
tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-clarify
tools/evals/run-skill-evals.sh --validate-fixture --skill skills/assistant-thinking
tools/evals/run-skill-evals.sh --validate-fixture --skill skills/assistant-thinking/SKILL.md
```

List available cases as tab-separated `skill`, `case id`, `category`, and
`title` rows:

```bash
tools/evals/run-skill-evals.sh --list
tools/evals/run-skill-evals.sh --list --skill assistant-clarify
```

Emit provider-neutral prompt packets for manual or adapter-driven execution:

```bash
tools/evals/run-skill-evals.sh --emit-prompts /tmp/skill-eval-prompts
tools/evals/run-skill-evals.sh --emit-prompts /tmp/clarify-eval-prompts --skill assistant-clarify
```

Prompt packets are written under `<output>/<skill>/<case-id>.md` and include the
setup context, prompt, expected behavior, pass criteria, fail signals, and
machine expectations.

Run each prompt packet with the target assistant and save captured responses as
`<response-dir>/<skill>/<case-id>.txt` or `<response-dir>/<skill>/<case-id>.md`.
When a single fixture is selected, the runner also accepts flat
`<response-dir>/<case-id>.txt` or `<response-dir>/<case-id>.md` files.

Grade saved responses locally:

```bash
tools/evals/run-skill-evals.sh --responses /tmp/skill-eval-responses
tools/evals/run-skill-evals.sh --responses /tmp/clarify-eval-responses --skill assistant-clarify
```

Include local-only skill experiments explicitly:

```bash
tools/evals/run-skill-evals.sh --validate-fixture --include-local
tools/evals/run-skill-evals.sh --list --include-local
```

The response grader is heuristic/local grading. It checks missing files, empty
responses, exact fail-signal phrase hits where useful, missing required
substrings, and forbidden substring hits. These deterministic checks are proxies
for behavior conformance; they complement human review or a separate LLM judge
and do not replace semantic judgment.

Per-skill evals complement `tools/skills/validate-skills.sh`. The source
validator checks skill metadata and contract structure; per-skill eval fixtures
exercise observable skill behavior. Together they are the next step toward Level
4 per-skill conformance, with broader fixture coverage still future work.
