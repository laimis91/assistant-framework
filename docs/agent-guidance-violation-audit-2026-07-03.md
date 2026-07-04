# Agent Guidance Violation Audit - 2026-07-03

Note: This is the original pre-fix audit snapshot. It may describe violations that were later remediated during the follow-up workflow, and should not be read as the final clean report.

## Scope

Audit-only review of Assistant Framework guidance and enforcement surfaces against current OpenAI and Anthropic/Claude recommendations for agents, skills, loops, approvals, guardrails, hooks, and evals.

Reviewed local surfaces:

- Root instructions: `AGENTS.md`, `CLAUDE.md`
- Skills: 16 root `skills/*/SKILL.md` entrypoints
- Skill contracts: 46 root `skills/*/contracts/*` files
- Agents: 8 Claude agents and 8 Codex agents
- Hooks/settings: 16 hook scripts plus agent settings JSON
- Tests/evals: P0/P4 contract suites, hook tests, skill eval fixtures, framework instruction evals
- Mirrors: generated plugin skill mirrors checked with `tools/plugins/sync-plugin-skills.sh --check`

## Official Guidance Baseline

Sources used:

- OpenAI Codex AGENTS.md: <https://developers.openai.com/codex/guides/agents-md>
- OpenAI Codex skills: <https://developers.openai.com/codex/skills>
- OpenAI Codex subagents: <https://developers.openai.com/codex/subagents>
- OpenAI Codex best practices: <https://developers.openai.com/codex/learn/best-practices>
- OpenAI agents orchestration: <https://developers.openai.com/api/docs/guides/agents/orchestration>
- OpenAI guardrails and human approvals: <https://developers.openai.com/api/docs/guides/agents/guardrails-approvals>
- OpenAI agent workflow evals: <https://developers.openai.com/api/docs/guides/agent-evals>
- Claude Code subagents: <https://code.claude.com/docs/en/sub-agents>
- Claude Code skills: <https://code.claude.com/docs/en/skills>
- Claude Code hooks: <https://code.claude.com/docs/en/hooks>
- Claude Code memory: <https://code.claude.com/docs/en/memory>
- Anthropic Building Effective Agents: <https://www.anthropic.com/engineering/building-effective-agents>
- Claude evaluation docs: <https://platform.claude.com/docs/en/test-and-evaluate/develop-tests>

Key expectations distilled from those sources:

- Instructions should be durable, concise, discoverable, and scoped to the repository or skill that needs them.
- Skills should be focused on one repeatable job, with clear descriptions, inputs, outputs, and progressive disclosure of references/scripts.
- Specialist agents should have narrow jobs, clear routing descriptions, and tool access matched to their role.
- Multi-agent orchestration should make ownership explicit: who performs work, who reviews, who gives the final answer, and when handoffs happen.
- Guardrails and approvals should be explicit, stateful, and fail safely for sensitive actions.
- Hook code runs with user permissions, so hook inputs and paths should be validated/sanitized and high-risk behavior should be tested.
- Loops should have measurable criteria, environment evidence, stopping conditions, and trace/eval coverage.

## Count Summary

| Severity | Count | Meaning |
|---|---:|---|
| Must-fix | 0 | No finding showed an immediate always-on breakage or confirmed data loss/security exploit in the reviewed state. |
| Should-fix | 6 | Clear mismatch with official guidance or the framework's own contracts; likely to cause workflow drift, false completion, or weak enforcement. |
| Nit | 0 | No cosmetic-only items counted as violations. |

Total counted violations: 6.

Theme count:

| Theme | Count |
|---|---:|
| Runtime role/evidence enforcement | 1 |
| Guardrail dependency fail-open behavior | 1 |
| Human approval parsing | 1 |
| Lifecycle evidence integrity and path safety | 1 |
| Maintainability of enforcement loop code | 1 |
| Agent least-privilege tool surface | 1 |

## Findings

### V1 - Source-changing role requirements can be bypassed when `Required agents` is malformed or omitted

Severity: should-fix

Evidence:

- `skills/assistant-workflow/references/phases.md:258` says source-changing Build tasks must infer at least Code Writer, Builder/Tester, and Code Reviewer.
- `skills/assistant-workflow/references/phases.md:262` says source-changing development/code-work must keep those roles in `Required agents`.
- `skills/assistant-workflow/contracts/phase-gates.yaml:58` requires source-changing development/code-work to include Code Writer, Builder/Tester, and Code Reviewer.
- `hooks/scripts/workflow-phase-gates.sh:1803` starts role inference.
- `hooks/scripts/workflow-phase-gates.sh:1831` adds Code Mapper for medium+ tasks, and `hooks/scripts/workflow-phase-gates.sh:1838` adds Code Reviewer only for Review/Document.
- `hooks/scripts/workflow-phase-gates.sh:1841` then scans the `Required agents` text.
- `hooks/scripts/workflow-phase-gates.sh:2154` returns `complete` when no roles were inferred.

Why this violates guidance:

OpenAI orchestration guidance emphasizes explicit ownership and handoffs for specialists. Claude subagent guidance emphasizes specialized agents with clear responsibilities. The framework's own contract also requires Code Writer, Builder/Tester, and Code Reviewer for source-changing Build work. Runtime enforcement currently trusts the journal too much; it can miss the required Build roles instead of deriving them from source-changing state.

Impact:

A malformed or incomplete task journal can allow Build/Review gates to pass without Code Writer, Builder/Tester, or Code Reviewer evidence, especially for small source-changing work where medium+ Code Mapper inference does not fire.

Recommendation:

Teach `assistant_phase_required_subagent_roles` to infer Code Writer, Builder/Tester, and Code Reviewer whenever the journal indicates source/test/docs/config/hooks/contracts/generated-artifact changes or Build/Verify status for development/code-work. Add regression tests for omitted `Required agents`, malformed `Required agents`, and small source-changing Build tasks.

### V2 - Critical guardrail hooks fail open when `jq` is unavailable

Severity: should-fix

Evidence:

- `hooks/scripts/workflow-enforcer.sh:24` exits 0 if `jq` is missing.
- `hooks/scripts/stop-review.sh:31` exits 0 if `jq` is missing.
- `hooks/scripts/workflow-guard.sh:24` exits 0 if `jq` is missing.
- `hooks/scripts/subagent-monitor.sh:14` exits 0 if `jq` is missing.

Why this violates guidance:

OpenAI guardrail/approval guidance treats guardrails as validation points in the workflow. Claude hook guidance says hooks should be tested carefully because they run with user permissions. A missing parser should not silently disable plan, review, delegation, or evidence gates.

Impact:

If `jq` is missing or not on PATH, core workflow enforcement becomes advisory or disappears entirely. The task can proceed without plan/review/delegation gates even though the hooks appear installed.

Recommendation:

For enforcement hooks, fail closed with a concise blocking message when `jq` is unavailable. For non-critical advisory hooks, keep fail-open behavior but label it intentionally. Add a startup/install check that verifies `jq` before enabling hooks.

### V3 - Delegation approval detection accepts broad substrings as explicit consent

Severity: should-fix

Evidence:

- `hooks/scripts/workflow-enforcer.sh:115` through `hooks/scripts/workflow-enforcer.sh:127` treats phrases such as `use subagents`, `use delegation`, `use agents`, and `delegated agents` as approval anywhere in the prompt.
- `hooks/scripts/workflow-enforcer.sh:463` through `hooks/scripts/workflow-enforcer.sh:468` converts that match into "Current prompt explicitly authorized subagents/delegation."

Why this violates guidance:

OpenAI human approval guidance distinguishes approved/rejected actions and pauses until the human approves. Broad substring matching can turn discussion, quoted text, or a question into authorization. That weakens the explicit-consent contract the framework is trying to enforce.

Impact:

A prompt such as "should I use agents here?" or "do not assume use agents is approval" can be misread as delegation approval depending on surrounding text. That creates false-positive authorization for subagent spawning.

Recommendation:

Use anchored approval intents rather than raw substrings. Require imperative or affirmative forms such as "yes, use subagents", "I approve subagents", or "authorize delegation for this task". Add negative and question-form tests.

### V4 - Codex lifecycle evidence is project-local and can be forged by ordinary workspace writes

Severity: should-fix

Evidence:

- `hooks/scripts/subagent-monitor.sh:37` derives `PROJECT_DIR` from environment or hook input.
- `hooks/scripts/subagent-monitor.sh:59` through `hooks/scripts/subagent-monitor.sh:71` appends lifecycle events to `$PROJECT_DIR/.codex/subagent-events.jsonl`.
- `hooks/scripts/workflow-guard.sh:124` through `hooks/scripts/workflow-guard.sh:130` only guards file-editing tools for orchestrator warnings; Bash writes are not covered by this integrity boundary.

Why this violates guidance:

OpenAI eval/tracing guidance relies on trustworthy traces of tool calls, handoffs, guardrails, and workflow events. Claude hook guidance says hook inputs and paths should be validated and sanitized because hooks run with full user permissions. Here, evidence used to prove subagent spawning lives in the same workspace the model can edit.

Impact:

Workflow gates can treat `.codex/subagent-events.jsonl` as proof of real lifecycle activity even though the file is writable from ordinary workspace operations. A compromised or careless flow could forge evidence, and path-derived writes also need stronger project-boundary validation.

Recommendation:

Persist lifecycle evidence in a protected state location outside project source, or sign/hash hook-written entries with data unavailable to normal model writes. At minimum, validate that `PROJECT_DIR` resolves inside the expected workspace root, reject traversal/symlink escapes, and add tests proving Bash cannot satisfy lifecycle evidence by writing the file directly.

### V5 - `workflow-phase-gates.sh` is a monolithic 2,208-line enforcement surface

Severity: should-fix

Evidence:

- `hooks/scripts/workflow-phase-gates.sh` is 2,208 lines.
- The same file contains scalar parsing, root status parsing, review-loop checks, metrics gates, learning gates, QA gates, subagent role inference, lifecycle evidence checks, and corrective message formatting.
- Role/evidence responsibilities alone span `hooks/scripts/workflow-phase-gates.sh:1453`, `hooks/scripts/workflow-phase-gates.sh:1803`, `hooks/scripts/workflow-phase-gates.sh:1878`, `hooks/scripts/workflow-phase-gates.sh:1943`, `hooks/scripts/workflow-phase-gates.sh:2003`, and `hooks/scripts/workflow-phase-gates.sh:2154`.

Why this violates guidance:

OpenAI and Claude guidance both favor narrow, clearly scoped components: skills for repeatable workflows, agents for narrow jobs, and explicit guardrails. The enforcement surface has grown into a dense multi-domain file, which makes it easier for runtime behavior to drift away from contracts.

Impact:

The file is hard to audit and test by responsibility. Findings V1 and V4 are symptoms of this concentration: small changes in one helper can affect unrelated gates.

Recommendation:

Split by responsibility while preserving the public helper API: parsing/status helpers, plan/build gates, review-loop gates, subagent evidence gates, QA gates, and metrics/learning gates. Add shellcheck-friendly tests around each extracted module.

### V6 - Claude write-capable agents have broader tool access than their role constraints require

Severity: should-fix

Evidence:

- `agents/claude/code-writer.md:4` grants `Bash`, while `agents/claude/code-writer.md:38` says the agent must not run builds or tests.
- `agents/claude/builder-tester.md:4` grants `Edit`, `Write`, and `Bash`, while `agents/claude/builder-tester.md:41` and `agents/claude/builder-tester.md:42` say it must not modify production code and may only create or edit test files/build configuration.
- Read-only Claude agents correctly use read-only tools, for example `agents/claude/code-reviewer.md:4` and `agents/claude/qa-evaluator.md:4`.

Why this violates guidance:

Claude subagent guidance explicitly supports tool allowlists/denylists and recommends limiting tools to enforce role constraints. OpenAI subagent guidance also says custom agents work best when the job and tool surface are clear. The current boundaries for Code Writer and Builder/Tester are mostly prompt-only.

Impact:

The Code Writer can run commands despite being told not to run builds/tests. The Builder/Tester can edit production files despite being told not to. This weakens the intended ownership split and makes violations harder to catch until review.

Recommendation:

Remove `Bash` from Code Writer unless a narrow implementation command use case is explicitly needed. For Builder/Tester, either split test-writing from command-running or add a PreToolUse hook keyed by agent name that blocks production-code writes and unsafe Bash commands. Keep read-only agents as they are.

## Positive Compliance Evidence

- `AGENTS.md` is 7,472 bytes and 129 lines, below Codex's default project-doc budget and within Claude memory guidance to keep repository instructions concise.
- `CLAUDE.md` exists, so Claude Code has a native memory file rather than relying only on `AGENTS.md`.
- Skill validation passes for all 16 skills.
- Contract checks are strong around review loops, QA evaluator separation, harness/eval docs, instruction overload, and task packets.
- The review loop has a terminal cap and contract tests.
- Code Reviewer and QA Evaluator are distinct roles and have read-only Claude tool surfaces.
- Skill eval fixtures and framework instruction eval fixtures validate.
- Generated plugin skill mirrors are in sync.

## Observations Not Counted As Violations

- `CLAUDE.md` duplicates much of `AGENTS.md` rather than importing it. Claude docs support importing an AGENTS.md-style file from CLAUDE.md, but duplication is not automatically a violation because this repo deliberately emits agent-specific guidance. Consider a sync check if drift becomes a recurring issue.
- `assistant-review/SKILL.md` remains a large entrypoint, but current instruction-overload contract checks pass and detailed QA algorithm content has been moved into `references/qa-evaluation-loop.md`.
- Several non-critical hooks also exit 0 when `jq` is missing (`skill-router.sh`, `learning-signals.sh`, `post-tool-context.sh`, `tool-failure-advisor.sh`). These were not counted because they are advisory/routing helpers rather than terminal workflow gates, but install-time dependency validation would still improve reliability.

## Validation Run

| Check | Result |
|---|---|
| `bash tools/skills/validate-skills.sh` | Passed: 16 skills validated |
| `bash tests/p0-p4/instruction-overload-contracts.sh` | Passed: 7 passed, 0 failed |
| `bash tests/p0-p4/review-loop-cap-contracts.sh` | Passed: 4 passed, 0 failed |
| `bash tests/p0-p4/qa-evaluator-contracts.sh` | Passed: 12 passed, 0 failed |
| `bash tools/evals/run-skill-evals.sh --validate-fixture` | Passed: 16 fixtures valid |
| `bash tools/evals/run-framework-instruction-evals.sh --validate-fixture` | Passed |
| `bash tests/test-hooks.sh --filter stop-review` | Passed: 67 passed, 0 failed, 202 skipped |
| `bash tools/plugins/sync-plugin-skills.sh --check` | Passed |
| `bash tests/p0-p4/harness-docs-evals-contracts.sh` | Passed: 8 passed, 0 failed |
| `bash -n hooks/scripts/*.sh` | Passed |

Not run: full `tests/test-hooks.sh`, full `tests/test-p0-p4-contracts.sh`, .NET build/test suites, install dry-run, or install hook test mode.

## Overall Result

Result: `DONE_WITH_CONCERNS`

The framework is broadly aligned with the OpenAI/Claude direction: specialist roles, concise repo instructions, contracts, review loops, QA separation, eval fixtures, and hook-based runtime enforcement are all present. The remaining violations are concentrated in enforcement fidelity: fail-open dependencies, over-broad approval parsing, evidence integrity, a missing role-inference edge, a monolithic gate file, and one Claude least-privilege mismatch.
