# Troubleshooting: Subagents Not Being Used

Assistant Framework relies on each supported agent's native subagent system.
Verify the workflow skill and agent definitions are installed, then look for a
real native dispatch/thread and result rather than framework-generated runtime
messages.

Subagent use is triggered by a direct user request or by applicable project or
skill instructions. The agent should not ask for separate spawn consent after a
trigger applies. An explicit user opt-out still prevents delegation for that
scope.

## Common causes and fixes

| Symptom | Likely cause | Fix |
|---|---|---|
| Preparation completes without spawning | No applicable instruction requires a subagent for the current step, or the work is small enough for direct execution | If you want delegation beyond the skill's requirements, ask for it directly. |
| A required spawn is never attempted | Installed workflow guidance is stale, the matching skill was not loaded, or an explicit opt-out is active | Rerun the installer, confirm the relevant installed `SKILL.md`, and remove any unintended opt-out. |
| Codex says "unknown agent" | TOML definitions are missing or names do not match | Check `~/.codex/agents/*.toml` and each file's `name` field, then reinstall if needed. |
| The agent reports delegation unavailable | Runtime capability or installed configuration has not been verified | Check the active runtime's supported delegation mechanism and configured role, then look for a real dispatch and result. Record `subagents_unavailable` only after a real spawn failure or supported configuration proof of unavailability. |
| Claude or Gemini uses the wrong role | Skill or agent files are stale | Rerun the installer and inspect the agent's installed workflow skill and agent definitions. |
| Spawned agents lack role instructions | Agent definition is stale or empty | Inspect the relevant Claude Markdown, Codex TOML, or Gemini definition and reinstall it. |
| Results are ignored after dispatch | The orchestrator lost or failed to update durable task state | Inspect the project task journal and context map, then resume from the last verified step. |

## Selective upgrades and ownership compatibility

`INCOMPATIBLE_WORKFLOW_ROLE_UPGRADE` means a selective Codex, Claude, or Gemini
install would refresh shared tools or roles while retaining an incompatible live
Workflow controller. For any retained controller, the installer requires regular
`SKILL.md`, `contracts/index.yaml`, and `contracts/handoffs.yaml` files, with both
contracts declaring matching schema `15.0` and the supported ownership stage
tuples. It refuses before any write, including in dry-run mode. Required
writer-source definitions are checked only for Codex and Claude.

Refresh the workflow and its review, verification, and TDD dependencies first,
then retry the original selection in the same environment:

```bash
./install.sh --agent codex --skill assistant-workflow
./install.sh --agent codex --skill assistant-docs
```

```powershell
.\install.ps1 -Agent codex -Skill assistant-workflow
.\install.ps1 -Agent codex -Skill assistant-docs
```

Use `claude` for Claude installations, and substitute the original selected skill
for `assistant-docs`. A full install also refreshes the coupled controller and
profiles. A genuinely absent workflow or a compatible declared controller permits
the selective install without adding or refreshing the workflow. Gemini retains
its native profile behavior.

The Bash installer checks workflow under `${CODEX_HOME:-$HOME/.codex}/skills`
for Codex. The PowerShell installer checks `%USERPROFILE%/.agents/skills` for
Codex skills independently of `CODEX_HOME`; Claude uses its own native home.

## Quick verification

```bash
# Validate the source definitions without invoking Codex or requiring auth
bash tools/smoke-test-codex-agents.sh --check-only

# Refresh Codex skills and agent definitions
./install.sh --agent codex

# Verify the ten installed definitions exactly match the repository sources
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

Direct fallback is valid only after the user opts out of delegation, policy
forbids it, or a real spawn attempt fails. Record that reason plus equivalent
implementation, verification, and review evidence instead of treating missing
framework runtime output as proof that subagents are unavailable.

## Codex writer migration

The source inventory is eleven normal roles plus standalone deprecated
`code-writer` (twelve TOMLs). New implementation packets select
`intelligent-writer` (gpt-6.1-sol/high) by default or `mechanical-writer`
(gpt-6-luna/high) with all four current eligibility evidence references. The
legacy definition is explicit intelligent compatibility, not a native alias.
A missing new configured name is a deployment mismatch; stop and report it.
Do not silently choose a generic worker. Explicit legacy or authorized bootstrap
execution records its actual runtime identity without claiming native activation.

`tools/smoke-test-codex-agents.sh --check-only` validates twelve source definitions.
The five live representatives, when separately authorized and supported, are
mapper, mechanical writer, intelligent writer, legacy writer and architect:
four configured model/effort tuples and all three writer identities. The probe
parent remains intentionally pinned to gpt-5.6-luna/low, independently from child
configuration. Metadata proves dispatch identity only; artifact correctness and
consequential actions need fixed outcome evaluation and independent review.

Claude uses native intelligent-writer/Opus and mechanical-writer/Sonnet defaults,
with standalone deprecated code-writer as explicit intelligent compatibility.
Gemini retains supported native/default tiers without custom definitions. Real installation is a separate authorized action
and can overwrite managed installed TOMLs. Compatibility removal needs a later
retirement change and ownership-safe cleanup. Static source checks do not prove
native activation, Windows runtime execution, or total workflow savings.
