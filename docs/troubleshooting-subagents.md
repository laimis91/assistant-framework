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
# Validate the source definitions without invoking Codex or requiring auth
bash tools/smoke-test-codex-agents.sh --check-only

# Refresh Codex skills and agent definitions
./install.sh --agent codex

# Verify the eight installed definitions exactly match the repository sources
for file in agents/codex/*.toml; do
  cmp "$file" "${CODEX_HOME:-$HOME/.codex}/agents/${file##*/}"
done

# Exercise one fixed representative for every unique model/effort combination
bash tools/smoke-test-codex-agents.sh --live
```

`--check-only` validates the fixed source inventory, model/effort matrix, and
compact operating stances. It does not invoke `codex` and does not require an
installed Codex home, session history, or authentication. `--live` additionally
requires `codex`, `jq`, and `git`, an installed configuration identical to the
repository sources, a working Codex runtime, and writable Codex session
metadata. It runs each fixed probe in a temporary Git repository and reports
only expected and observed role/model/effort metadata.

The live smoke intentionally pins its probe parent to Luna/low. The current
Luna/v1 runtime exposes the `agent_type` spawn field, so the probe can select
each configured child deterministically and then verify that the child TOML
overrides the parent's model and effort. This parent pin is a probe mechanism,
not a recommendation for normal orchestration, and requires no unstable feature
flags.

Current Sol/Terra v2 runtimes may omit custom-role selection from their reserved
spawn schema. When a child session has no configured role metadata under those
runtimes, that is a runtime dispatch limitation rather than evidence that its
TOML is wrong. In short, this is a runtime limitation, not a TOML mismatch. The
smoke proves the installed definitions and their child
tuples through a runtime that can select them; it does not promise every parent
model/runtime can select custom roles today. This caveat can be retired when
the newer runtime schema exposes deterministic custom-role selection.

Live failures use three classifications:

- `ENVIRONMENT_FAILURE`: a required command, installed directory, session
  directory, temporary repository, or Codex execution is unavailable.
- `RUNTIME_DISPATCH_OR_SCHEMA_FAILURE`: the named subagent was not recorded in
  the new sessions or the expected metadata path is absent.
- `CONFIG_MISMATCH`: source and installed TOMLs differ, or the runtime reports a
  model/effort tuple different from the configured one.

The short operating stances take inspiration from the role clarity in
[msitarzewski/agency-agents](https://github.com/msitarzewski/agency-agents/),
but they are framework-specific summaries rather than copied prompts. See the
official Codex documentation for [custom
agents](https://learn.chatgpt.com/docs/agent-configuration/subagents) and the
[Codex model families and effort
levels](https://learn.chatgpt.com/docs/models).

For an older installation, rerun the normal installer and restart the agent.
During the one-release migration window, the installer removes only retired
Assistant Framework lifecycle registrations, preserves unrelated custom
configuration, and neutralizes detected stale framework entrypoints.

Direct fallback is valid only after the user denies delegation, policy forbids
it, or a real spawn attempt fails. Record that reason plus equivalent
implementation, verification, and review evidence instead of treating missing
framework runtime output as proof that subagents are unavailable.
