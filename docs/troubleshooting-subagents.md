# Troubleshooting: Subagents Not Being Used

Assistant Framework relies on each supported agent's native subagent system.
Verify the workflow skill and agent definitions are installed, then look for a
real native dispatch/thread and result rather than framework-generated runtime
messages.

Delegation consent is needed only immediately before an actual spawn. The agent
should continue safe triage, discovery, and planning without asking merely
because subagents might be useful. When a spawn is needed, authorize it
explicitly or approve the bounded request.

## Common causes and fixes

| Symptom | Likely cause | Fix |
|---|---|---|
| Preparation completes without spawning | No current step needs a subagent, or consent has not yet been requested for the first real spawn | If delegation is required, say "Use delegation" or authorize the named roles when the agent is ready to spawn them. |
| A required spawn is never attempted | Installed workflow guidance is stale, or the matching skill was not loaded | Rerun the installer for that agent, confirm the relevant installed `SKILL.md`, and repeat the request with "Use delegation." |
| Codex says "unknown agent" | TOML definitions are missing or names do not match | Check `~/.codex/agents/*.toml` and each file's `name` field, then reinstall if needed. |
| Codex says no subagent tool is visible | Native spawning is not necessarily exposed as a tool named `Task`, `delegate`, or `subagent` | Ask Codex to spawn the configured agent by name. Record `subagents_unavailable` only after a real spawn fails or supported-version evidence proves it unavailable. |
| Claude or Gemini uses the wrong role | Skill or agent files are stale | Rerun the installer and inspect the agent's installed workflow skill and agent definitions. |
| Spawned agents lack role instructions | Agent definition is stale or empty | Inspect the relevant Claude Markdown, Codex TOML, or Gemini definition and reinstall it. |
| Results are ignored after dispatch | The orchestrator lost or failed to update durable task state | Inspect the project task journal and context map, then resume from the last verified step. |

## Quick verification

```bash
# Refresh skills and agent definitions
./install.sh --agent claude
./install.sh --agent codex
./install.sh --agent gemini

# Verify configured Codex agents
ls ~/.codex/agents/*.toml
grep '^name' ~/.codex/agents/*.toml
```

For an older installation, rerun the normal installer and restart the agent.
During the one-release migration window, the installer removes only retired
Assistant Framework lifecycle registrations, preserves unrelated custom
configuration, and neutralizes detected stale framework entrypoints.

Direct fallback is valid only after the user denies delegation, policy forbids
it, or a real spawn attempt fails. Record that reason plus equivalent
implementation, verification, and review evidence instead of treating missing
framework runtime output as proof that subagents are unavailable.
