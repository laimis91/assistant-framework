# Assistant Framework instruction block

This is the canonical text of the optional instruction block. The framework's skills work without it. Paste it into a global or project instructions file to apply the framework's routing and working rules when no skill has loaded yet:

- Claude Code: `~/.claude/CLAUDE.md` (all projects) or `CLAUDE.md` in a project.
- Codex: `~/.codex/AGENTS.md` (all projects) or `AGENTS.md` in a project.

Nothing writes it for you, and no hook injects it. To remove it later, delete everything between the two marker comments, including the markers.

This file is the only copy: the README links here, and `tests/p0-p4/plugin-packaging-contracts.sh` checks its shape.

<!-- instruction-block:start -->
```markdown
<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_START -->
# Assistant Framework instructions

Each assistant skill loads its own `references/operating-guidance.md`. When no skill matches, the sections below are the working rules.

## Skills

- When a skill's description matches the request, read its `SKILL.md` and follow it through to its handoff, loading only the references and contracts the current phase needs.
- For ordinary repository changes, use assistant-workflow when that skill is installed; use assistant-clarify for unclear or tangled intent.
- Do not skip a matched skill's gates, verification, or review to save time or because work is small. Direct implementation means no delegation, not no skill.

## Involving the user

Work autonomously and resolve what you can from the repository and the request. Stop for the user only to:

- decide a consequential choice about intent, scope, safety, or acceptance that is still open;
- approve a destructive, external, or hard-to-reverse action, or one beyond the granted access or cost;
- approve a plan before medium+ or elevated-risk development edits;
- hear that the shared stagnation guard stopped corrective work.

Do not ask for routine confirmation or repeat an approval already given for the same scope. Otherwise report once at the end: outcome, files changed and why, checks and results, material limits, and next action.

## Operating stance

- Implement and verify directly when useful, at every size/risk. Choose optional execution delegation for concrete benefit; retain proportionate validation and a local self-check.
- Formal plan, code, finding-closure and acceptance reviews use newly created independent agents with fresh context; Codex uses fork_turns=none. Selected five-lens research keeps separate sibling-blind agents.
- Keep orchestration proportional; direct work uses actual main identity without fabricated worker records.

## Boundaries

- Use subagents when the user asks or applicable project or skill instructions require them; no separate spawn consent is needed.
- Preserve user-authored files and existing dirty work.
- Verify changes with repository commands and review the approved scope before handoff.
- Keep credentials, secrets, PII, and private endpoints out of code, logs, task state, and memory.
<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_END -->
```
<!-- instruction-block:end -->
