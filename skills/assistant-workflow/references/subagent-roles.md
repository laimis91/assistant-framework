# Subagent Role Definitions

Reference for dispatching subagents through the active runtime's agent mechanism. When the framework's custom agents are installed (`~/{agent_state_dir}/agents/`), dispatch by the configured agent name — each agent carries its own system prompt, tool restrictions, and provider-specific model settings when that runtime supports them.

## Model selection guidance

Use **capability tiers**, not provider-specific model names, when deciding which model a role should use. Different runtimes name models differently, and some (for example Gemini CLI today) may not support custom per-role model files yet.

| Tier | Use for | Selection rule |
|---|---|---|
| **Fast / economical** | Shallow mapping, file inventory, locating entry points | Cheapest/fastest model that can follow structured output reliably |
| **Balanced / standard** | Deep reading, build/test loops, noisy output summarization | Default strong coding model for day-to-day reasoning and tool use |
| **Strongest / deep reasoning** | Architecture, implementation, high-confidence review | Best available coding/reasoning model; spend tokens here when mistakes are expensive |

Provider examples are only examples, not requirements:

- Claude: fast ≈ Haiku, balanced ≈ Sonnet, strongest ≈ Opus.
- Codex/OpenAI: fast ≈ the configured lightweight coding model, balanced ≈ the default coding model, strongest ≈ the highest-reasoning coding model available in the environment.
- Gemini: fast ≈ Flash-class, balanced ≈ Pro-class/default coding model, strongest ≈ highest-reasoning Pro/Ultra-class model available.

If the runtime does not expose model overrides for subagents, keep the role separation and tool-access constraints; use the default model and include the tier as guidance in the dispatch prompt.

## Installed agents

Dispatch the configured role through the active runtime's supported delegation mechanism. Resolve triggers through [Execution policy](subagent-dispatch.md#execution-policy); evidenced fallback applies only to optional Build/execution roles, never to formal review, QA/acceptance, or research lens isolation.

The prompt you provide is the **task context** — what to do, not how to do it. The agent's built-in system prompt handles the "how."

## Agent summary

| Agent | Recommended tier | Access | Phase(s) | Purpose |
|---|---|---|---|---|
| `code-mapper` | Fast / economical | Read-only | Discover | Produces context map (`{agent_state_dir}/context-map.md`) — entry points, interfaces, data flow, conventions |
| `explorer` | Balanced / standard | Read-only | Discover | Deep analysis: execution paths, design decisions, hidden dependencies |
| `architect` | Strongest / deep reasoning | Read-only | Decompose, Plan, Design | Strict slice decomposition, implementation blueprints, design direction |
| Logical CodeWriter: Claude and Codex `intelligent-writer` / eligible `mechanical-writer` | Approved provider configuration | Write | Build | Owns selected tests plus implementation and follows its unchanged verification decision and worker_stage; RED only when TDD is active; no independent review |
| `builder-tester` | Balanced / standard | Write | Build | Execution-only separated verifier for selected checks and binding suites; observes writer-authored RED only when TDD is active; writes only designated generated outputs/evidence logs |
| `code-reviewer` | Strongest / deep reasoning | Read-only | Review | Canonical code review for bugs, security issues, architecture violations, test coverage gaps, and structural problems |
| `reviewer` | Strongest / deep reasoning | Read-only | Review compatibility | Compatibility route for existing reviewer handoffs; prefer `code-reviewer` for new code review dispatches |
| `qa-evaluator` | Strongest / deep reasoning | Read-only | Review QA | Independent acceptance, Done Contract, verification evidence, UI/visual/product/UX/docs/DX/domain quality, score progression, and final result evaluation |

## Dispatch rules by task size (`execution_intent != prepare_only`)

| Size | Execution options | Required judgments and boundaries |
|---|---|---|
| **Small** | Direct main implementation/verification or optional selected Build lane | Fresh independent formal review; no Decompose; expanded impact retains canonical review evidence; QA only when required |
| **Medium** | Direct main or optional bounded_executor/separated_workers; mapping/design roles only for concrete uncertainty | Approved plan, selected verification and fresh independent review; QA only when required |
| **Large** | Direct main or optional selected Build lane; mapping/lifecycle/Pack specialists only for concrete benefit | Preserve slice verification, approval and fresh independent review; Reviewer remains compatibility routing |
| **Mega** | Direct main or optional selected Build lane and specialists for concrete mapping/lifecycle/Pack uncertainty | Preserve integration review and required QA. Shared/unknown source writers serialize; parallel writers need runtime-proven workspace isolation. Independent read-only analysis may run in parallel. |

At every size/risk, direct main execution records its actual identity without
fabricated worker records or a fallback exemption. Formal plan, code, closure and
acceptance reviews use newly created independent actors with fresh self-contained
context (Codex `fork_turns=none`); selected research lenses remain sibling-blind.

For `prepare_only`, dispatch only concretely triggered Discover or preparation roles,
such as mapping, research, security, thinking, documentation, or diagrams. Size alone
requires no agent. Requested/required readiness plans retain fresh independent review,
and selected research lenses/peer retain isolation. Preparation creates no executable
slices, Build, post-Build code/QA Review or developer handoff; a plan-review PASS grants
no implementation approval.

## Reviewer dispatch (review rounds)

**Round 1:**
```
Use the code-reviewer agent to review all code changes. Find real issues, not nitpicks.
Review for: bugs, logic errors, edge cases, security vulnerabilities, architecture violations,
code quality, test coverage, and structural organization.
Report at 80%+ confidence only.
```

**Round N > 1:**
```
Use the code-reviewer agent. This is review round {N}.
Discovery passes receive the current snapshot and assigned scope with no prior findings.
Only the designated closure_verification pass receives the immutable pre-fix ledger
as previously_fixed and verifies those findings against the current snapshot.
Keep discovery passes isolated from sibling results and return the canonical Reviewer schema.
Confidence standards remain evidence-based and unchanged across round ordinals.
```

Follow the [review loop](../../assistant-review/references/review-loop.md) and
[review handoffs](../../assistant-review/contracts/handoffs.yaml) for discovery,
closure, additional-round evidence, and return fields.

## QA Evaluator dispatch (QA rounds)

Use QA Evaluator only after build/test evidence and Code Reviewer or Reviewer compatibility result exist. It evaluates acceptance, not general code defects.

**QA Round 1:**
```
Use the qa-evaluator agent to evaluate acceptance for {task}.
Review: Done Contract, acceptance criteria, verification evidence, code review result,
domain_context/rubric_refs when applicable, and final result requirements.
Load assistant-review references/domain-rubrics.md only when the acceptance
criteria, Done Contract, domain_context, or explicit rubric_refs scope subjective,
product, UX, docs, DX, UI/visual, or domain craft scoring. Return selected_domain_rubrics
and domain_quality_scores when scoped; do not invent rubrics when not scoped.
Do not replace Code Reviewer. Report only acceptance findings backed by evidence.
```

**QA Round N > 1:**
```
Use the qa-evaluator agent. This is QA round {N}.
Previously failed acceptance items:
{previously_failed_acceptance_items}
Do not re-report resolved items. Keep the same acceptance and confidence
standards at every ordinal. Use the shared semantic task guard for correction.
```

## Fallback: agents not installed

For missing new Claude or Codex writer definitions, report a deployment mismatch and stop; never silently use a nearest generic worker. Explicit legacy `code-writer` requests and separately authorized bootstrap execution record their real runtime identity. For other supported provider fallbacks, use the nearest available built-in subagent type and choose by capability tier rather than by provider-specific model name:

| Role | Supported fallback role | Recommended tier |
|---|---|---|
| Code Mapper | `Explore` or nearest read-only explorer | Fast / economical |
| Explorer | `Explore` or nearest read-only explorer | Balanced / standard |
| Architect | `general-purpose` or nearest planning agent | Strongest / deep reasoning |
| Code Writer (Gemini supported fallback only) | `general-purpose` or nearest coding agent | Strongest / deep reasoning |
| Builder/Tester | `general-purpose` or nearest coding agent with shell/test access | Balanced / standard |
| Code Reviewer | `general-purpose` or nearest read-only reviewer | Strongest / deep reasoning |
| Reviewer compatibility | `general-purpose` or nearest read-only reviewer | Strongest / deep reasoning |
| QA Evaluator | `general-purpose` or nearest read-only evaluator | Strongest / deep reasoning |

When using fallback types, include the full role instructions in the dispatch prompt (the agent won't have a built-in system prompt for the role). Prefer the matching role definition for the active runtime under the framework's `agents/` directory when available; otherwise adapt the closest provider-neutral role prompt.

Writer selection is owned by the Orchestrator; load `subagent-dispatch.md#concrete-writer-selection` for the four actual-evidence conditions, intelligent default, provider mapping, stale evidence stop, and compatibility rules. CodeWriter remains a logical role; concrete names do not weaken its verification, TDD, status, partial-work or independent-review contract.
