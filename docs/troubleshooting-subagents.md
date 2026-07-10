# Troubleshooting: Subagents Not Being Used

## Start with the active profile

### Claude Code

Claude keeps its existing `minimal` hook default. Verify the workflow skill and the expected agent definitions are installed, then look for explicit dispatch messages or subagent threads.

### Codex

Plain `./install.sh --agent codex` is native and hookless. Subagents, permissions, skill routing, execution-policy rules, and compaction remain native Codex capabilities; absence of Assistant Framework hook output is expected.

Delegation consent is needed only immediately before an actual spawn. Codex should continue safe triage, discovery, and planning without asking merely because agents might be useful. When a spawn is needed, authorize it explicitly or approve Codex's bounded request, then look for subagent threads and verify `~/.codex/agents/*.toml` exists.

Codex hook profiles are opt-in:

- `minimal`: compatibility skill routing plus session/compaction context.
- `workflow`: workflow/delegation enforcement without the compatibility skill router.
- `strict`: all supported enforcement hooks without the compatibility skill router.
- `none`: native Codex default; no Assistant Framework hook commands.

Claude and Gemini defaults are unchanged.

## Common causes and fixes

| Symptom | Likely cause | Fix |
|---|---|---|
| Codex completes preparation without spawning | No task step needed a subagent yet, or consent has not been requested for the first real spawn | This is normal in native mode. If delegation is required, say “Use delegation” or authorize the specific agents when Codex is ready to spawn them. |
| Codex needs a spawn but never asks | Installed workflow/AGENTS guidance is stale, or the matching skill was not loaded | Rerun `./install.sh --agent codex`, confirm the relevant `~/.codex/skills/*/SKILL.md`, and repeat the request with “Use delegation.” |
| Codex says “unknown agent” | TOML definitions are missing or names do not match | Check `ls ~/.codex/agents/*.toml` and each file's `name` field, then reinstall if needed. |
| Codex says no subagent tool is visible | Native spawning is not necessarily exposed as a tool named `Task`, `delegate`, or `subagent` | Ask Codex to spawn the configured agent by name. Record `subagents_unavailable` only after a real spawn fails or supported-version evidence proves it unavailable. |
| A `workflow` or `strict` run silently bypasses required delegation/review | Enforcement profile was not installed, hooks are disabled, or the run entered valid direct fallback | Reinstall with the intended explicit profile, inspect `~/.codex/hooks.json`, and check the task journal for denial, policy restriction, or a real unavailable-agent failure. |
| Claude uses the wrong agent | Skill or agent files are stale | Rerun `./install.sh --agent claude` and inspect `~/.claude/skills/assistant-workflow/` plus `~/.claude/agents/`. |
| Spawned agents lack role instructions | Agent definition is stale or empty | Inspect the relevant Claude Markdown or Codex TOML definition and reinstall it. |
| Results are ignored after dispatch | The orchestrator lost or failed to update durable task state | Inspect the project task journal and context map, then resume from the last verified step. |

## Quick verification

```bash
# Codex: native default should have no Assistant Framework hook commands
./install.sh --agent codex

# Codex: verify configured agents
ls ~/.codex/agents/*.toml
grep '^name' ~/.codex/agents/*.toml

# Codex: opt into deterministic workflow enforcement when required
./install.sh --agent codex --hook-profile workflow

# Claude: refresh its unchanged minimal default
./install.sh --agent claude
```

## Migrating an older Codex install

Run `./install.sh --agent codex` and restart Codex. The installer removes only known Assistant Framework commands from `~/.codex/hooks.json`, preserves unrelated custom hooks, and leaves silent shims for cached framework entrypoints until the running process is replaced. Use an explicit `minimal`, `workflow`, or `strict` profile only when compatibility or deterministic enforcement is desired.

Direct fallback is valid only after the user denies delegation, policy forbids it, or a real spawn attempt fails. In those cases, record the reason and equivalent implementation, verification, and review evidence instead of silently treating native mode as proof that subagents are unavailable.
