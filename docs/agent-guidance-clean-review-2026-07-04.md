# Agent Guidance Clean Review - 2026-07-04

## Result

The original pre-fix audit found 6 counted violations, all should-fix, documented in `docs/agent-guidance-violation-audit-2026-07-03.md`.

Terminal clean-review result: remaining official-source violation count = 0.

## Remediation Matrix

| Violation | Major fix surfaces |
|---|---|
| V1 source-changing role inference | `workflow-phase-gates` subagent modules and tests. |
| V2 missing `jq` fail-closed | `hook-runtime` plus enforcement hooks and tests. |
| V3 bounded delegation approval | `workflow-enforcer` and tests. |
| V4 protected task-bound lifecycle evidence | `hook-runtime`, `subagent-monitor`, phase gates, task template, and tests. |
| V5 monolithic phase gates and later workflow guard split | `workflow-phase-gates.d` and `workflow-guard.d` modules, install support, and tests. |
| V6 least-privilege Claude roles and Builder/Tester guards | `agents/claude/code-writer.md`, workflow-guard modules, and tests. |

## Review Loop

Initial terminal Round 10 review found one remaining shell wrapper blocker (`nohup`, `timeout`, `stdbuf`, `flock`). Follow-up Slice S2 fixed those wrappers with a clean independent review. Previous fixes covered Builder/Tester shell mutator and wrapper parsing, quoted wrapper redirection false positive handling, and the `workflow-guard` module split.

## Validation Evidence

- `workflow-guard: builder-tester` 38/38
- `workflow-guard` 61/61
- S2 common executor wrapper deny probes 4/4
- S2 preserved allow probes 4/4
- S2 previous deny spot checks 3/3
- Codex install/default/strict install filters passed
- `bash tests/test-hooks.sh` 309/309
- `bash tests/test-p0-p4-contracts.sh` 227/227
- Broad bash syntax checks passed, including `workflow-guard.d` modules
- `validate-skills` first-class skills
- Plugin sync check all mirrors checked
- `git diff --check` passed
- .NET builds succeeded; MemoryGraph NU1900 warning because NuGet vulnerability data was unreachable.

## Official Sources Checked

- <https://developers.openai.com/api/docs/guides/prompt-guidance?model=gpt-5.5>
- <https://developers.openai.com/cookbook/examples/gpt-5/codex_prompting_guide>
- <https://openai.github.io/openai-agents-python/>
- <https://openai.github.io/openai-agents-python/multi_agent/>
- <https://openai.github.io/openai-agents-python/guardrails/>
- <https://openai.github.io/openai-agents-python/human_in_the_loop/>
- <https://docs.anthropic.com/en/docs/claude-code/hooks>
- <https://docs.anthropic.com/en/docs/claude-code/sub-agents>
- <https://www.anthropic.com/engineering/building-effective-agents>

## Residual Risks

- Shell write-target parsing remains heuristic for simple proven commands, but the reviewed unsupported, wrapper, and indirect shell grammar paths now fail closed as an unproven shell write target.
- The NuGet vulnerability data warning is environmental.
- No blocking residual official-source violations remain.

## Evidence Sources

- `docs/agent-guidance-violation-audit-2026-07-03.md`
- `.codex/task.md`
