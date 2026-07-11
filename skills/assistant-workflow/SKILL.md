---
name: assistant-workflow
description: "Run proportional development phases. Use to plan, build, implement, fix, migrate, or refactor project artifacts."
effort: high
triggers:
  - pattern: "rewrite|implement|fix|migrate|refactor|build feature|build the|build a|build an|create feature|add feature|(create|make) (a |an |the |new )*(rest |api )?(endpoint|dashboard|screen|page|component|service|tool|app|feature)|idea into (an |a )?(implementation plan|implementation|plan|code|feature)|how should i approach|break this down|start working on|let.s (build|create|implement|add|make|fix|migrate|refactor|rewrite)|phase [0-9]|code (this|that|it|the|a|an|up)"
    priority: 40
    min_words: 2
    reminder: "This matches assistant-workflow. Read this SKILL.md and contracts/index.yaml first, then load the selector. Triage task size and include tests in Build; do not skip phases."
---

# Development Workflow

Public routing contract; detailed mechanics live in references and contracts.

## Goal

Move work to verified outcome through right-sized phases, gates, tests, review, and company-safe execution.

## Success Criteria

- Core phases run at smallest useful depth; Decompose and Design run only when needed.
- No phase is skipped; small work scales down and durable state is used only when its mode triggers.
- Medium+ work has an approved plan before Build; small work has an inline plan and proceeds without ceremony unless risk requires approval.
- `references/workflow-controller.md` is the canonical source for controller intensity, workflow state, manual verification, learning capture, harness/QA routing, and review-role separation.
- Ordinary medium+ workflow tasks stay standard, non-harness, and non-QA unless explicit controller criteria apply.
- Harness-capable work carries the Done Contract, Harness Recipe, and trace/replay artifacts required by the controller.
- Candidate Search is reserved for explicit alternatives, open-ended architecture/design, optimization, high uncertainty, repeated failures, unclear/flaky bugs, or reviewer-requested pivots.
- Behavior changes default tests-first or carry explicit validation in the same Build step.
- Review, QA, and security routing apply when triggered.
- Final output gives changed files, evidence, review status, risks, next steps.

## Constraints

- Do not skip phases; scale them down for small work instead.
- Do not ask ritual questions when code/context makes the next safe action clear.
- Ask bounded clarification before planning only when an undiscoverable implementation-shaping unknown lacks a safe default and affects correctness, scope, behavior, data, public contract, security, migration safety, or verification.
- Keep scope changes explicit and tied to correctness, security, safety, or verification.
- Do not install tools, upload code, call external services, or paste proprietary content into third-party systems unless the user explicitly approved that path.
- Prefer repo-native commands over new tooling.
- When external services, installs, or sensitive-data handling are in scope, load `references/ai-usage-policy.md` for company-safe detail. It is not an entry dependency.

## Contracts

Canonical files stay authoritative; validate applicable rules at enforcement points. Read `contracts/index.yaml` first; do not load every contract at entry. Load only the contract selector applicable to current boundary:

- `entry`: select `task_description`, `task_type`, `scope_hint`, `target_files`, `constraints`, and `acceptance_criteria` from `contracts/input.yaml`; `references/triage-rubric.md` is the only declared entry reference.
- `current_phase`: active `contracts/phase-gates.yaml` at transition.
- `selected_handoff`: `contracts/handoffs.yaml` before dispatch and return validation.
- `completion`: `contracts/output.yaml` at completion before final exit.

Selectors resolve by unique id plus canonical path, exact section, key, and explicit names. Runtime selectors resolve `name_from` only through their declared `allowed_names`.

Missing or invalid selector: `load_full_authoritative_file`; validate the full named canonical file and record recovery.

Migration note: `contracts/handoffs.yaml` v2 removes the retired lifecycle-script
reference kind. Use `runtime` for executable integrations and identify generic automation
in descriptive evidence fields.

## Visible Checkpoints

Phase markers are required only for `controller_intensity=strict`, explicit
project policy, or a user request. Light and standard work still follows every
logical phase and gate, but reports progress with concise natural updates
without exact marker ceremony.

When exact markers are required, use this instruction: `Use this exact format:`

```
--- PHASE: [name] ---
```

For steps within a phase:

```
>> [step description]
```

For completion:

```
--- PHASE: [name] COMPLETE ---
```

These examples are conditional on the exact-marker triggers above.

## Refactor Guidance

- Justify it with a concrete risk only: correctness, security, unsafe change surface, ownership, brittle testing, or poor extension seam.
- Tie incidental or scope-expanding refactors to concrete risk instead of vague framing such as generic convention language, style, cleanliness, or generic improvement.
- Choose the smallest useful, durable fix that removes the identified risk. Keep cleanup scoped unless the user explicitly requested cleanup, reorganization, or refactor work.

## Triage

Start Triage with a concise progress update. When exact markers are required,
use `--- PHASE: TRIAGE ---`.

Load `references/triage-rubric.md`. Perform a quick read-only Candidate scope scan, then assess task type, risk tier, size, gates, agents, `controller_intensity`, subagent state, and `search_mode`. For ideas, create binary observable criteria before planning.

| Size | Phases |
|---|---|
| **Small** | Discover quick -> Plan inline/no-wait unless risk/ambiguity -> Build -> Review -> Document |
| **Medium** | Discover -> Decompose -> Plan -> [Design] -> Build -> Review -> Document |
| **Large** | Discover -> Decompose -> Plan -> Design -> Build -> Review -> Document |
| **Mega** | Discover -> Decompose -> Plan -> Design -> Build -> Review -> Document |

[Design] = UI only.

Print: `>> Triaged as: [SIZE] — phases: [list]`
Print: `>> Triage metadata: type=[TASK_TYPE] | risk=[RISK_TIER] | intensity=[controller_intensity] | gates=[count] | agents=[count] | search=[search_mode] | scope_confidence=[low|medium|high]`

If scope exceeds initial triage during any phase, stop and re-triage. Use `references/candidate-search.md` only when `search_mode: candidate_search` is selected.

## Phase Routing

Load `references/phases.md` for the current phase. Load `references/workflow-controller.md` only when resolving shared routing/default, movement, harness, review, QA, or subagent-separation decisions. Use `references/context-budget-and-pattern-retrieval.md` for large material or framework patterns, `references/artifact-first-output-contract.md` before Plan, `references/decomposition-plan-review.md` before medium+ Decompose exits, `references/plan-template.md` during Plan, and `references/context-handoff-templates.md` for non-standard continuations.

| Phase | When | Key Actions |
|---|---|---|
| Discover | All | Read repo, resolve unknowns, restate requirements. Medium+: Code Mapper map. Unknown-cause bugfixes: load `assistant-debugging`. |
| Decompose | Medium+ | Smallest iterable slices with acceptance and verification fields. |
| Plan | All | Small: inline no-wait plan unless risk/ambiguity requires approval. Medium+: WAIT for approved scope, slices, packets, files, verification, and risks before Build. |
| Design | UI only | Direction, mockup, checklist, approval gate. |
| Build | All | Light may use `workflow_state_mode=inline`, `subagent_policy_state=not_required`, and `subagent_execution_mode=not_applicable` for direct implementation; standard/strict use Code Writer -> Builder/Tester. Tests or relevant validation travel with code. |
| Review | All | Light gets a fresh self-review without worker/reviewer dispatch evidence; standard/strict use Spec Review then independent `assistant-review`; QA only when required. |
| Document | All | Apply the state/manual/learning modes; metrics, reflexion, and memory are optional/non-blocking. |

For subagent rules, load `references/subagent-dispatch.md` and resolve `subagent_policy_state`, `subagent_execution_mode`, and `subagent_authorization_scope` before spawning. Light small low-risk localized work may select `not_required` plus `not_applicable` and does not ask for delegation. For standard/strict development work, Assistant Framework policy requires explicit user authorization before spawning subagents unless the current prompt already authorizes them. Ask once for the needed delegation scope and wait before continuing phases that require subagents. After authorization, use `delegated` mode and spawn the configured role agents. Use direct fallback only when authorization is denied, policy disallows spawning, or a real spawn attempt fails because subagents/custom agents are unavailable; do not infer unavailability merely because no visible tool is named `Task`, `delegate`, or `subagent`.

Load `references/harness-controller.md` only after `references/workflow-controller.md` or carried-forward phase state establishes `harness_capable=true`.
Load `assistant-security` when touching auth, user input, secrets, persistence, network calls, shell commands, dependency/config changes, or external integrations.

## Output

Return:
- Status: complete, partially complete, blocked, or plan ready.
- Changed files: paths and purpose.
- Verification: commands, pass/fail, skipped checks with reasons.
- Review result: spec, quality, QA, and security when applicable.
- Residual risk: blockers, assumptions, policy constraints, or follow-up.
- Next step: one practical recommendation.

Do not use phrases like "should work", "probably fixed", or "looks good" unless immediately qualified with evidence or uncertainty.

## Stop Rules

- Stop and ask when an implementation-shaping field is material, undiscoverable, and has no safe default.
- Stop before medium+ Build until plan approval.
- Stop before final response if build, tests, required review, or output contract evidence is missing.
- Stop when a plan deviation changes approved scope, files, behavior, risk, verification, or acceptance criteria; record the deviation and get approval before continuing.
