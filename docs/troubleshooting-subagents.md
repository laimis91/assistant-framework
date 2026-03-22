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
| Agent does everything itself, never dispatches | Task triaged as "small" — dispatch rules say minimum is Code Writer → Builder/Tester → Reviewer but agent may interpret small tasks as "do it all inline" | Tell the agent explicitly: "use subagents for this task" |
| Claude uses wrong subagent type | Skill file not loaded or outdated | Re-run `install.sh --agent claude`, verify `~/.claude/skills/assistant-workflow/SKILL.md` has the new 6-role table |
| Codex says "unknown agent" | TOML files not installed | Check `ls ~/.codex/agents/*.toml` — should show 6 files |
| Codex ignores agents entirely | Codex may not read `~/.codex/agents/` automatically | Check Codex docs for `agents_dir` config in `~/.codex/config.toml`, or verify with `codex --list-agents` |
| Subagents spawn but don't get role instructions | Claude: skill not loaded so no prompts. Codex: TOML `developer_instructions` empty | Verify file contents: `cat ~/.codex/agents/reviewer.toml` |
| Agent dispatches but results are ignored | Orchestrator context got too large, lost track | Check if task journal (`.claude/task.md`) exists and is being updated |
| Reviewer never runs | Agent skips review, goes straight to handoff | The `stop-review.sh` hook should block this on Claude. On Codex, hooks aren't supported yet — you'll need to remind it |

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

The most likely issue is that the agent **chooses not to** dispatch subagents because it judges the task as simple enough to handle alone. You can force it:

- "Use the code-mapper agent to map the codebase first"
- "Dispatch a reviewer subagent for the quality review"
- "Run Code Writer and Builder/Tester as separate agents, not inline"

If this happens consistently, it may mean the dispatch rules in the skill need stronger language (e.g., "MUST dispatch" instead of "dispatch"). Update the wording in `skills/assistant-workflow/SKILL.md` under the "Dispatch rules by task size" section to use MUST instead of suggested language, then re-run `install.sh`.
