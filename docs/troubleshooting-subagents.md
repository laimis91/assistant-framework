# Troubleshooting: Subagents Not Being Used

## What to look for

### On Claude Code
1. The workflow skill should reference `references/subagent-roles.md` and dispatch agents using the `Agent` tool
2. Look for messages like "Launching Explorer agent..." or "Dispatching Reviewer..." in the output
3. If the agent does everything sequentially in one context — it's not using subagents

### On Codex
1. Look for agent names (`code-mapper`, `reviewer`, etc.) being mentioned when work starts
2. Codex should show subagent threads in the CLI output
3. Check `~/.codex/agents/` — the TOML files must exist there

## Common causes and fixes

| Symptom | Likely cause | Fix |
|---|---|---|
| Agent does everything itself, never dispatches | Subagent policy state was never resolved, strict evidence was not required by the active profile, subagents are unavailable, or the task entered direct fallback | In strict mode this is a workflow failure unless the task journal records `subagent_execution_mode=direct_fallback`, explicit `Direct fallback reason: authorization_denied | subagents_unavailable | policy_disallowed`, and Code Writer/Builder/Tester/Reviewer direct evidence. If you want delegation, explicitly say "use subagents for this task" and verify Agent Dispatch Log entries exist. |
| Claude uses wrong subagent type | Skill file not loaded or outdated | Re-run `install.sh --agent claude`, verify `~/.claude/skills/assistant-workflow/SKILL.md` has the new 6-role table |
| Codex says "unknown agent" | TOML files not installed or agent name mismatch | Check `ls ~/.codex/agents/*.toml` — should show 6 files, and `grep "^name" ~/.codex/agents/*.toml` should match the names you asked Codex to spawn |
| Codex says no subagent tool is visible/available | Codex subagent spawning is a native CLI/app workflow, not necessarily exposed as a visible tool named `Task`, `delegate`, or `subagent` | Do not switch to `subagents_unavailable` from tool-list inspection alone. Explicitly ask Codex to spawn the configured agent name (for example `Spawn the code-writer agent...`). Use `subagents_unavailable` only after a real spawn attempt fails or installed Codex version/docs prove no subagent support |
| Codex ignores agents entirely | User authorization was not explicit enough, AGENTS.md/skill guidance is stale, or custom agents are not installed | Re-run `install.sh --agent codex`, verify `~/.codex/AGENTS.md` contains the native subagent guidance, verify `~/.codex/agents/*.toml`, then ask: `Spawn the code-writer, builder-tester, and reviewer agents...` |
| Subagents spawn but don't get role instructions | Claude: skill not loaded so no prompts. Codex: TOML `developer_instructions` empty or stale | Verify file contents: `cat ~/.codex/agents/reviewer.toml` |
| Agent dispatches but results are ignored | Orchestrator context got too large, lost track | Check if task journal (`.claude/task.md`, `.codex/task.md`, or equivalent state dir) exists and is being updated |
| Reviewer never runs | Agent skips review, goes straight to handoff | The `stop-review.sh` hook should block this in strict hook profiles when hook support is installed/enabled |

## Quick verification commands

```bash
# Claude: verify skill has new roles
grep "Code Mapper" ~/.claude/skills/assistant-workflow/SKILL.md

# Claude: verify role reference file exists
ls ~/.claude/skills/assistant-workflow/references/subagent-roles.md

# Codex: verify agents installed
ls ~/.codex/agents/

# Codex: check a specific agent definition
cat ~/.codex/agents/reviewer.toml

# Codex: verify TOML name fields match expected agent names
grep "^name" ~/.codex/agents/*.toml
```

## If subagents still aren't used

First check whether subagent spawning is authorized and available for the active tool. If explicit authorization is required, the agent must not spawn subagents until you ask for them. You can authorize a scope explicitly:

- "Use the code-mapper agent to map the codebase first"
- "Dispatch a reviewer subagent for the quality review"
- "Run Code Writer and Builder/Tester as separate agents, not inline"

If this happens consistently after authorization, check that `subagent_policy_state=delegation_authorized` and `subagent_execution_mode=delegated` are recorded. In delegated mode, completion also requires Agent Dispatch Log evidence: `Code Writer dispatch`/`Code Writer result`, `Builder/Tester dispatch`/`Builder/Tester result`, and `Reviewer dispatch`/`Reviewer result`; medium+ slice work also requires `Per-slice dispatch evidence`. If authorization is denied, unavailable, or policy-disallowed, the correct behavior is direct fallback with explicit `Direct fallback reason` plus equivalent Code Writer, Builder/Tester, and Reviewer evidence — not silent one-thread execution.
