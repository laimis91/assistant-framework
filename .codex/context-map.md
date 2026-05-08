# Context Map: Runtime Phase-Gate Enforcement

## Runtime Hook Entry Points
- `hooks/scripts/workflow-enforcer.sh` injects workflow reminders and active task state on `UserPromptSubmit` / `BeforeAgent`.
- `hooks/scripts/workflow-guard.sh` warns when edit/build tools are used during active task states.
- `hooks/scripts/stop-review.sh` blocks stop/after-agent completion when active tasks lack structured review and metrics evidence.
- `hooks/scripts/harness-gate.sh` blocks stop/after-agent completion when medium+ tasks lack plan approval or rubric scoring.
- `hooks/scripts/task-journal-resolver.sh` resolves the active task journal, suppresses completed journals, and manages cached workflow state.

## Hook Configuration
- `hooks/codex-settings.json` wires SessionStart, UserPromptSubmit, Stop, PreToolUse, PreCompact, and PostCompact hooks.
- `hooks/claude-settings.json` wires UserPromptSubmit, SessionStart, PreToolUse, Stop, TaskCompleted, SubagentStart, and SessionEnd hooks.
- `hooks/gemini-settings.json` wires BeforeAgent, SessionStart, PreToolUse, PreCompress, AfterAgent, and SessionEnd hooks.

## Test Surface
- `tests/test-hooks.sh` contains source-level hook tests for workflow enforcer, stop review, harness gate, resolver, installer, and provider behavior.
- `tests/p0-p4/workflow-basics-contracts.sh` validates canonical workflow phase language and absence of stale `VERIFYING` labels in workflow docs/scripts.
- `tests/p0-p4/spec-review-contracts.sh` validates Spec Review and Quality Review contract language.
- `tests/p0-p4/installed-hook-smoke.sh` validates installed Codex hook behavior and completed journal suppression.

## Documentation Surface
- `README.md` has the public hook/features overview and currently under-describes workflow-enforcer, workflow-guard, and harness-gate as runtime phase enforcement.
- `docs/skill-contract-design-guide.md` describes Level 3 hook-based validation and currently frames runtime enforcement as the next improvement direction.
- `docs/harness-design-guide.md` documents harness lifecycle behavior and medium+ detection via `Triaged as`.

## Current Enforcement Gap
- Prompt-time state exists but does not produce a unified runtime phase-gate summary for DECOMPOSE, PLAN, BUILD, REVIEW, and DOCUMENT.
- Stop-time gates block build/review completion but do not consistently cover `DOCUMENTING`, which can hide unfinished review or metrics work if the status advances too early.
