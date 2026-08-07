# Review Checklists

Use these checklists when the matching assistant-review mode is applicable. Report findings with normal severity, file evidence, impact, smallest useful fix, and confidence. If a checklist area has no concrete issue, record the checked area and state that no concrete risk was found.

## Agentic Loop Safety Checklist

Use this checklist when reviewing changes that add or modify autonomous loops: agent loops, review/fix loops, research/search loops, retry loops, tool-calling loops, multi-agent orchestration, background jobs, or any workflow that repeatedly calls models, tools, APIs, or subagents.

1. **Bounded execution**
   - Require an explicit max step/round count, timeout, or budget.
   - The bound must be low enough to prevent runaway cost/time while still allowing expected completion.

2. **Stop condition**
   - Require a concrete success/exit condition, not only "until done".
   - The loop should stop on clean success, max budget, unrecoverable blocker, or explicit escalation.

3. **Retry and empty-result handling**
   - Retries must be capped and scoped to transient failures.
   - Empty search/retrieval/tool results must have a defined fallback: broaden query once, report no evidence, ask/escalate, or exit; never infinite retry.

4. **Tool-error handling**
   - Tool/API failures must be observed and routed to retry, fallback, blocker, or degraded result.
   - Silent failures must not produce confident final answers.

5. **Progress/stagnation detection**
   - Repeated iterations should show new evidence, fewer findings, better score, or another progress signal.
   - If progress stalls, reset context/evaluator, pivot, or escalate instead of continuing.

6. **Cost/token guardrails**
   - Loops that call paid APIs, large models, web search, subagents, or large-context prompts need cost/time/token awareness.
   - Prefer summaries, batching, narrowed scope, or early exit when budget risk grows.

7. **Low-confidence escalation**
   - When the loop cannot prove progress, evidence quality, or reliable completion, require a blocker, conservative result, or human/user escalation.
   - Uncertain outcomes must not be hidden behind confident final language.

Treat missing stop conditions, unbounded retries, ignored empty results, silent tool failures, paid-API loops without budgets, or missing low-confidence escalation as must-fix or should-fix depending on risk.

## Behavioral Contract Review Checklist

Use this checklist when reviewing code changes that affect public APIs, domain/business logic, persistence/migrations, auth/permissions, money/payments/trading, config/feature flags, external protocols/SDKs, algorithms, infrastructure/deployment, generated schemas/clients, or other behavior-bearing surfaces.

1. **Existing behavior and invariants**
   - Identify the existing behavior, invariants, compatibility assumptions, and edge cases that the code must preserve.
   - Check whether a new specialized path bypasses shared validation, authorization, transactions, rate limits, logging, error handling, cancellation, idempotency, or cleanup.

2. **Interface-implementation alignment**
   - Verify public methods, DTOs, API schemas/OpenAPI, CLI help, config names/defaults, docs/examples, generated clients, and implementation behavior agree.
   - If one surface changed, check every consumer-visible mirror surface that can still describe or drive the old behavior.

3. **Test inheritance coverage**
   - Tests must cover inherited behavior plus new behavior, not only the happy path of the new feature.
   - Ask whether a fake or incomplete implementation could still pass the tests; if yes, report the missing assertion or fixture.

4. **External protocol / algorithm fidelity**
   - When implementing or adapting a known protocol, SDK flow, RFC, algorithm, or business rule, identify its defining semantic steps before approving.
   - Examples: OAuth state/redirect validation, retry backoff plus max attempts plus idempotency, cache invalidation, payment authorization/capture/refund semantics, migration rollback/safety steps.

5. **High-impact operation guards**
   - For code that can affect money, auth, permissions, personal data, deletion, production deploys, safety, or irreversible actions, require appropriate guardrails: validation, explicit approval, dry-run, limits, audit logs, rollback/compensation, and failure-mode handling.

6. **Runtime surface sync**
   - Check code, tests, docs, config, migrations, generated clients, examples, CLI help, API schemas, deployment manifests, feature flags, telemetry, and runbooks when they can affect or describe runtime behavior.

Treat bypassed invariants, public-contract drift, weak inherited tests, protocol safety-step omissions, missing high-impact guards, or runtime-surface drift as must-fix or should-fix depending on release risk.

## Semantic Contract Review Checklist

Use this checklist when reviewing changes to skills, workflow docs, contracts, evals, prompts, generated instructions, agent frameworks, or named-method adaptations. This is a semantic review, not just a YAML/Markdown syntax check.

1. **Inherited contract obligations**
   - If a specialized method/template is added inside an existing skill, confirm it still satisfies every base input/output artifact required by that skill.
   - If the method intentionally does not satisfy a base artifact, the base contract must be explicitly made conditional and evals must cover both paths.

2. **Template-contract alignment**
   - Check that method templates, `SKILL.md`, `contracts/output.yaml`, `contracts/input.yaml`, phase gates, handoffs, and references name the same artifacts and fields.
   - Required artifacts must include recovery guidance (`on_fail` or equivalent) where the contract design guide expects it.

3. **Eval coverage inheritance**
   - Evals for a new method must require both the new behavior and inherited base artifacts.
   - Machine expectations should fail on plausible incomplete responses, not only confirm the new section headings.

4. **External-method signature fidelity**
   - When adapting a named paper/tool/framework method, identify its defining loop before approving. Do not preserve only the visible surface shape.
   - Require a testable artifact proving the defining loop happened. Example: STORM requires perspective-guided questions, source-grounded answers, follow-up questions, then synthesis, not just fixed perspectives.

5. **High-stakes recommendation guard**
   - If the workflow can emit `do`, `wait`, `avoid`, approval, trade, legal, medical, security, safety, or other high-impact recommendations, require domain guardrails.
   - Guardrails should include educational/due-diligence framing where appropriate, risk/user-context caveats, verification requirements, and conservative defaults such as `investigate_further` unless stronger action is justified.

6. **Mirror surfaces**
   - Root skill and plugin-local copies must be synced.
   - Generated installer/global instruction templates, automation, docs, references, and eval contract tests must be updated when they can drive the old behavior.

Treat missing inherited artifacts, template-contract drift, evals that pass incomplete outputs, method-signature drift, high-stakes recommendation guard gaps, or mirror-surface drift as must-fix or should-fix depending on release risk.

## Architecture Decision Pack Review Checklist

Use this checklist only when a workflow Architecture Decision Pack or equivalent architecture decision record is carried into review. The Pack is a compact decision record for the current goal or file boundary, not a standing architect agent or global memory store.

1. **Freshness, facts, and material questions**
   - Verify the Pack binds its repository facts to a revision/branch/path or its greenfield facts to a stated context, and that changed requirements or source evidence invalidate it.
   - Ensure facts and assumptions are distinct. Ask or record every material question that changes the architecture choice; group it by topic, why it matters, risk if guessed, and safe default where one exists.

2. **Ownership, dependency, and lifecycle boundary**
   - Check ownership, data/resource lifecycle, dependency direction, failure/cancellation behavior, and public boundary against the actual changed code and consumers.
   - Treat an unowned resource, ambiguous lifecycle, or a dependency direction that conflicts with the stated boundary as a concrete risk.

3. **Design-pressure checks**
   - Verify whether a consumer needs early exit, cancellation, seek, retry, or pull control before approving a push-based loop or outer engine.
   - Verify buffer, stream, handle, cancellation, and disposal ownership; resource claims must name bounded item/buffer/concurrency envelopes.
   - Require an actual extension registration/selection seam when implementations must grow, and a representative producer-consumer path before approving a generic interface, callback, collection, or engine.

4. **Semantic type ledger and primitive exceptions**
   - Require named semantic/domain types when parameter, return, collection, callback, or public-contract primitives erase a meaningful identity, unit, state, lifecycle, or extension seam.
   - A primitive is acceptable only at an explicit local temporary, wire/storage, foreign/framework, or no-domain-semantics boundary, with conversion/validation near that boundary. Cohesive request/command types may evolve; public/serialized contracts need a compatibility/versioning/adaptor or migration plan.

5. **Falsifiable quality scenarios**
   - A memory, performance, or extensibility claim must state workload, budget/threshold (or explicit unknown), measurement method, and failure condition.
   - Do not approve a qualitative benefit merely because an architecture sounds clean. If evidence is unavailable, report a verification task or unknown rather than a confirmed benefit.

6. **Compatibility, extension, and verification handoff**
   - Check the selected alternative’s compatibility/migration/rollback path, predicted extension seam (or explicit none), and the tests, benchmark, inspection, or manual method that could falsify it.
   - Confirm the Pack reference and its unresolved risks reach the implementation packet, tests, review result, and final handoff without duplicating unrelated task memory.

Treat stale source facts, hidden primitive leakage, undocumented exceptions, unmeasured quality claims, public-contract evolution gaps, and missing verification/rollback paths as must-fix or should-fix depending on affected risk.
