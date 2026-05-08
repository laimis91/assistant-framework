# Skill Contract Design Guide

Enforcements and best practices for designing strict, well-defined skills with typed inputs, validated outputs, and structural gates. Based on research across DSPy, CrewAI, Guardrails AI, RAIL spec, OpenAI Agents SDK, Google A2A, and Addy Osmani's agent spec work.

## Core Principle

A skill without contracts is a suggestion. A skill with contracts is a specification.

Every skill MUST define what it accepts, what it produces, and what must be true at every transition point. Agents treat prose instructions as guidance; they treat typed schemas as constraints.

---

## Research Findings

### 1. DSPy Signatures — Typed I/O as Contracts

**Source:** [DSPy Signatures](https://dspy.ai/learn/programming/signatures/)

DSPy replaces hand-written prompts with **signatures** — typed declarations of inputs and outputs. Instead of "write me a summary," you declare fields with types, descriptions, and constraints.

**Key patterns:**
- Every input and output is a named, typed field
- Output fields can have `Literal` type constraints (enum values)
- `InputField(desc=...)` and `OutputField(desc=...)` carry semantic descriptions
- TypedPredictors enforce type constraints at runtime — mismatches trigger warnings
- Assertions validate LLM output after generation, enabling re-ask loops

**Enforcement for skills:**
- Every skill MUST declare typed `InputField` and `OutputField` equivalents in YAML
- Field types: `string`, `int`, `boolean`, `enum`, `string[]`, `object`, `object[]`
- Enum fields MUST list all valid values — no open-ended enums
- Descriptions are not optional — they scope what the agent should produce

### 2. CrewAI — Pydantic Output Models and Task Chaining

**Source:** [CrewAI Tasks](https://docs.crewai.com/en/concepts/tasks)

CrewAI requires `expected_output` as a Pydantic model on every task. The output of Task 1 becomes the typed input of Task 2 — like Unix pipes, but schema-validated.

**Key patterns:**
- `output_pydantic` property defines the exact shape of task output
- Output is validated against the Pydantic model — type mismatches fail
- In Sequential Process, one task's output automatically becomes the next task's context
- Structured fields are accessible via `result["field_name"]` or `result.pydantic`

**Enforcement for skills:**
- Subagent returns MUST define `return_fields` with typed schemas
- When one subagent feeds another, the producer's `return_fields` must satisfy the consumer's `context_fields`
- Missing required return fields trigger re-dispatch, not silent continuation

### 3. Guardrails AI — RAIL Spec (Schema + Validators + Corrective Actions)

**Source:** [Guardrails AI RAIL](https://github.com/guardrails-ai/guardrails/blob/main/docs/how_to_guides/rail.md)

RAIL (Reliable AI markup Language) defines fields, types, validators, and corrective actions in XML. If the LLM output doesn't match, it re-asks automatically.

**Key patterns:**
- Every output field has: `name`, `description`, `type`, and `validators`
- Validators are composable rules (e.g., length checks, format checks, content checks)
- Corrective actions on failure: `reask` (re-prompt the LLM), `filter` (remove invalid), `fix` (auto-correct)
- Guard objects compile the schema and inject it into the prompt automatically
- Re-ask loops run until output passes validation or max retries

**Enforcement for skills:**
- Every field MUST have an `on_missing` or `on_fail` action — never silently skip
- Valid actions: `ask` (prompt user), `infer` (state inference), `skip` (use default), `fail` (block), `re-dispatch` (retry subagent)
- Validation rules are plain-English predicates, not code — agent-portable

### 4. Addy Osmani — Conformance Suites as Agent Contracts

**Source:** [How to Write a Good Spec for AI Agents](https://addyosmani.com/blog/good-spec/) (O'Reilly)

Treating specs as formal contracts between you and the AI agent. Conformance suites — language-independent tests that any implementation must pass — act as a contract specifying expected inputs/outputs.

**Key patterns:**
- Specs should cover: commands, testing, project structure, code style, git workflow, boundaries
- Organize prompts into distinct sections (`<background>`, `<instructions>`, `<tools>`, `<output_format>`)
- Use "LLM-as-a-Judge" for subjective criteria — a second agent reviews the first agent's output against quality guidelines
- Conformance suites are YAML-based, reusable across implementations

**Enforcement for skills:**
- Phase gate assertions are conformance tests — checkable conditions that must pass
- Anti-patterns lists are negative conformance tests — things that must NOT happen
- Output contracts define what "done" looks like — the agent cannot claim completion without meeting them

### 5. OpenAI Agents SDK — Declared Handoff Targets

**Source:** [OpenAI Agents SDK Handoffs](https://openai.github.io/openai-agents-python/handoffs/)

Each agent declares its handoff targets, and the framework enforces that handoffs follow declared paths. Agents cannot hand off to undeclared targets.

**Key patterns:**
- Handoff targets are declared at agent creation time — not ad-hoc
- Handoff behavior is controlled by parameters determining how much context flows
- The framework enforces that handoffs follow declared paths

**Enforcement for skills:**
- Subagent dispatch MUST follow the handoffs contract — no ad-hoc agent creation
- Context fields are explicit — the orchestrator decides what context flows, not the subagent
- Return fields are validated — the orchestrator checks the return before using it

### 6. Agent Interoperability Protocols (A2A, ACP, ANP)

**Source:** [Agent Interoperability Survey](https://arxiv.org/html/2505.02279v1)

Multiple open protocols define structured metadata for agent discovery, capability declaration, and task handoff.

**Key patterns:**
- Agents declare capabilities as structured metadata — not free-form descriptions
- Task requests include structured fields, not prose
- Responses are multimodal but schema-validated
- Handoff requires structured, queryable memory rather than raw text transfer

**Enforcement for skills:**
- Skill descriptions in frontmatter are capability declarations — keep them precise
- Trigger patterns are capability matching — keep them specific to avoid false matches
- Subagent prompts include structured context blocks with required fields, not free-form prose

### 7. LLM Guardrails — Drift Prevention

**Sources:** [Datadog](https://www.datadoghq.com/blog/llm-guardrails-best-practices/), [Orq.ai](https://orq.ai/blog/llm-guardrails), [CSA](https://cloudsecurityalliance.org/blog/2025/12/10/how-to-build-ai-prompt-guardrails-an-in-depth-guide-for-securing-enterprise-genai)

Without source-of-truth validation, outputs slowly become inaccurate or inconsistent (model drift). Guardrails enforce deterministic formatting by schema enforcement.

**Key patterns:**
- Output guardrails perform filtering and relevancy checks for domain drift
- Format validation ensures structured outputs via schema enforcement
- Confidence thresholds block low-certainty responses
- Prompt construction guardrails inject structured metadata (roles, permissions) into system prompts
- Automated policy trees compiled into lightweight classifiers audit agent behavior at runtime

**Enforcement for skills:**
- Phase gate assertions prevent drift — the agent must prove it's on track before continuing
- Cross-phase invariants catch slow drift (e.g., constraints list only grows, never shrinks)
- Confidence thresholds in review contracts increase with each round (80% → 85% → 90%)

---

## Contract Schema Format

### Design principles
- **Agent-portable**: Plain YAML — no Python, JavaScript, or framework-specific syntax
- **Human-readable**: Any developer can read and understand the contracts
- **Self-documenting**: Descriptions and validation rules explain intent
- **Recoverable**: Every failure has a defined corrective action

### Field schema

```yaml
fields:
  - name: field_name            # identifier (snake_case)
    type: string                # string | int | boolean | enum | string[] | object | object[]
    required: true              # true | false | conditional
    condition: "when..."        # only when required=conditional
    description: "what this is" # human-readable purpose
    validation: "rule"          # plain-English validation predicate
    default: value              # when required=false, the default value
    on_missing: ask             # ask | infer | skip | fail | re-dispatch
    enum_values: [a, b, c]      # when type=enum
    min_items: 1                # when type=array, minimum entries
    object_fields: [...]        # when type=object or object[], nested field definitions
    examples: [...]             # optional example values
    infer_from: "rule"          # when on_missing=infer, how to infer
    ask_prompt: "question"      # when on_missing=ask, what to ask
    notes: "context"            # additional context for the agent
```

### Phase gate schema

```yaml
gates:
  - phase: PHASE_NAME
    checkpoint_start: "--- PHASE: NAME ---"
    checkpoint_end: "--- PHASE: NAME COMPLETE ---"
    condition: "when this phase runs"  # optional
    exit_assertions:
      - id: XX1                        # unique ID for referencing
        check: "what must be true"     # plain-English assertion
        condition: "when applicable"   # optional — scopes the assertion
        on_fail: "corrective action"   # what to do if assertion fails

invariants:
  - id: INV1
    check: "what must always be true"
    scope: all_phases
    on_fail: "corrective action"
```

### Handoff schema

```yaml
handoffs:
  - name: producer_to_consumer
    from: ProducerRole
    to: ConsumerRole
    phase: PHASE_NAME
    context_fields: [...]   # what the orchestrator sends (uses field schema)
    return_fields: [...]    # what the subagent must return (uses field schema)
    on_missing_field: "corrective action"
```

---

## Contract Tiers by Skill Category

| Category | Skills | Contract files | Rationale |
|---|---|---|---|
| **Process** (multi-phase, subagents) | workflow, review, tdd, security | input + output + phase-gates + handoffs | Full pipeline with transitions and delegation |
| **Analysis** (structured reasoning) | thinking, research, ideate | input + output + phase-gates | Multi-step pipeline but no subagent delegation |
| **Utility** (single-purpose) | memory, docs, diagrams, onboard, reflexion, telos | input + output | Single-pass execution, no phases to gate |

### Process skills (4 files)
- Most complex — multiple phases, subagent dispatch, approval gates
- Phase gates enforce sequencing (can't skip steps)
- Handoff schemas ensure subagents get proper context and return structured data
- Example: assistant-workflow, assistant-review

### Analysis skills (3 files)
- Multi-step pipeline (e.g., diverge → converge → refine)
- Phase gates enforce pipeline ordering
- No subagent delegation — the main agent does all work
- Example: assistant-ideate (8+ ideas in DIVERGE before CONVERGE can score)

### Utility skills (2 files)
- Single-pass: accept input, produce output
- Input contract prevents "what do you want me to do?" confusion
- Output contract prevents incomplete or missing artifacts
- Example: assistant-docs (must specify doc type, must produce a file)

---

## Enforcement Mechanisms

### Source validation foundation

Run the source validator before changing first-class skill contracts:

```bash
tools/skills/validate-skills.sh
```

The default inventory is the tracked first-class release set: `skills/assistant-*/SKILL.md`. Local-only `skills/unity-*` directories are excluded by default. Use targeted validation when working on one skill:

```bash
tools/skills/validate-skills.sh --skill assistant-thinking
tools/skills/validate-skills.sh --skill skills/assistant-thinking/SKILL.md
```

Use `--include-local` only for local experiments:

```bash
tools/skills/validate-skills.sh --include-local
```

This validator checks source skill metadata and contract structure: frontmatter, required contract tier files, contract headers, required-field recovery behavior, and enum value declarations. It intentionally stays on the source side. Canonical source paths such as `.claude` remain valid in source skills; installed-agent path substitution for `.codex` and `.gemini` stays covered by installer tests.

### Level 1: Contract files exist (passive)
The contracts are YAML files in the skill directory. Agents read them as part of skill execution. This relies on the agent following instructions — the same trust model as the existing SKILL.md.

### Level 2: SKILL.md references contracts (active)
The SKILL.md explicitly says "read and follow contracts/". The Contracts section lists the files and summarizes the rules. This makes contracts visible and hard to miss.

### Level 3: Hook-based validation (structural)
Shell scripts in hooks can validate contract compliance:
- Pre-phase hooks check input contract resolution
- Post-phase hooks check phase gate assertions
- Stop hooks check output contract completeness
- Example: `stop-review.sh` already enforces that the review cycle completes

The source validator is the Level 3 foundation: it gives hooks a consistent, checked contract shape to rely on before runtime enforcement expands.

### Level 4: Conformance test suite (automated)
YAML test cases define "given this input, skill must produce output matching this schema." Can be run as a verification step after skill modifications.

The validator is also the Level 4 foundation because it provides the inventory and structural checks that per-skill conformance suites build on. Provider-neutral per-skill eval fixtures now live at `skills/<skill>/evals/cases.json` and run through `tools/evals/run-skill-evals.sh`.

```bash
tools/evals/run-skill-evals.sh --validate-fixture
tools/evals/run-skill-evals.sh --list
tools/evals/run-skill-evals.sh --emit-prompts /tmp/skill-eval-prompts
tools/evals/run-skill-evals.sh --responses /tmp/skill-eval-responses
```

The default per-skill eval inventory is first-class `skills/assistant-*` skills with fixtures. Local-only `skills/unity-*` fixtures are excluded unless `--include-local` is passed. The current eval slice is a pilot covering `assistant-clarify` and `assistant-thinking`; it is not full coverage for all 15 first-class skills.

Local response grading is deterministic and heuristic: missing files, empty responses, fail-signal phrase hits, required substrings, and forbidden substrings. It is a provider-neutral proxy for behavior conformance and does not replace human or LLM semantic judgment.

**Current implementation: Level 2 plus source structural validation and pilot per-skill eval fixtures.** Level 3 already exists for review (`stop-review.sh`). Broader runtime enforcement and wider Level 4 per-skill coverage are next slices built on the validator.

---

## Rules for Writing Contracts

1. **Required fields must have `on_missing` actions** — never leave the agent guessing what to do when data is absent
2. **Enum types must list all values** — open-ended enums defeat the purpose of typing
3. **Validation rules are plain English** — no regex, no code, no framework syntax
4. **Phase gates are binary assertions** — "X is true" or "X is false", nothing subjective
5. **Handoff schemas match producer output to consumer input** — if the Architect returns `implementation_steps`, the CodeWriter must accept `implementation_steps`
6. **Corrective actions are actionable** — "fix it" is not a corrective action; "re-dispatch CodeMapper requesting the missing field" is
7. **Contracts only grow** — adding fields is safe, removing required fields is a breaking change
8. **Conditional fields use `condition:`** — don't make everything required; scope to when it matters
9. **Examples clarify ambiguous fields** — when `description` alone isn't enough, add `examples:`
10. **Cross-phase invariants catch slow drift** — things that must ALWAYS be true, not just at gates
