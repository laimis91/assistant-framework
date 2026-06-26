# Hook Output Benchmarks

Current local benchmark for hook output size and first-action signals. Values are generated on this machine and may vary modestly by shell, jq, and date-sensitive hook text.

Run to refresh:

```bash
bash tools/hooks/benchmark-hook-output.sh --write-doc docs/hook-output-benchmarks.md
```

Current rows: 7

| hook_name | scenario | stdout_bytes | stdout_words | stderr_bytes | exit_code | first_blocker_or_action |
|---|---|---:|---:|---:|---:|---|
| session-start | codex active task journal | 1766 | 183 | 0 | 0 | ACTIVE TASK JOURNAL (read this first — it has full task state): |
| workflow-enforcer | codex building phase gates | 1625 | 184 | 0 | 0 | WORKFLOW STATE (auto-injected every prompt): |
| post-compact | codex restored active task | 1526 | 154 | 0 | 0 | RESTORED AFTER COMPACTION — Task journal: |
| skill-router | codex assistant-workflow route | 498 | 47 | 0 | 0 | SKILL MATCH (1/1): This request matches assistant-workflow. You MUST load and follow this SKILL.md and its contracts before acting. At minimum: triage the task size, then build with tests included in the Build phase. Skipping workflow for speed is explicitly prohibited. Required inputs for this skill: [task_description,task_type,clarification_status,unresolved_clarification_topics,clarification_defaults_applied] |
| stop-review | codex missing spec review blocker | 371 | 54 | 0 | 0 | Task journal shows an active workflow but no Spec Review was run. You MUST run Stage 1 first: load references/prompts/spec-review.md, compare each approved plan step/task packet/component against actual changes, append a structured Spec Review entry with Result: PASS or FAIL, fix any FAIL items, then continue to quality review. |
| subagent-monitor | codex code-writer start | 200 | 20 | 0 | 0 | SUBAGENT CONSTRAINT: You are a code writer. Write code only. Do NOT run builds or tests — builder-tester handles that. |
| subagent-monitor | codex code-writer stop | 0 | 0 | 0 | 0 | recorded SubagentStop lifecycle evidence |

## Trim History

The C slice trimmed repeated explanatory prose from `session-start`, `workflow-enforcer`, and `post-compact` while preserving enforcement signals. The first blocker/action signal was unchanged for all touched hooks.

| slice | hook_name | before_bytes | before_words | after_bytes | after_words |
|---|---|---:|---:|---:|---:|
| c-hook-output-trim | session-start | 2122 | 225 | 1766 | 183 |
| c-hook-output-trim | workflow-enforcer | 1892 | 232 | 1625 | 184 |
| c-hook-output-trim | post-compact | 2131 | 218 | 1526 | 154 |

## Signal Anchors Checked

- `session-start` / `codex active task journal`: `ACTIVE TASK JOURNAL`, `memory_context`, `memory_search`
- `workflow-enforcer` / `codex building phase gates`: `WORKFLOW STATE`, `RUNTIME PHASE GATES`, `Current phase is BUILDING`
- `post-compact` / `codex restored active task`: `RESTORED AFTER COMPACTION`, `memory_context`, `Preserve response phase separation after compaction`
- `skill-router` / `codex assistant-workflow route`: `SKILL MATCH`, `assistant-workflow`, `Required inputs for this skill`
- `stop-review` / `codex missing spec review blocker`: `decision`, `block`, `no Spec Review`
- `subagent-monitor` / `codex code-writer start`: `SUBAGENT CONSTRAINT`, `SubagentStart`, `code-writer`
- `subagent-monitor` / `codex code-writer stop`: `SubagentStart`, `SubagentStop`, `cw-bench-1`

The subagent stop scenario emits no user-facing stdout in the current hook behavior. The benchmark records the locally feasible lifecycle evidence by checking the project-local `.codex/subagent-events.jsonl` file written by `subagent-monitor.sh`.
