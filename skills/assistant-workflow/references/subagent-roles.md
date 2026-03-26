# Subagent Role Definitions

Reference for dispatching subagents via the Agent tool. When the framework's custom agents are installed (`~/.claude/agents/` or `~/.codex/agents/`), use agent names directly as subagent_type — each agent carries its own system prompt, tool restrictions, and model settings.

## Installed agents

When custom agents are installed, dispatch by name. The agent's own configuration handles everything:

```
Agent(subagent_type="reviewer", prompt="Review the changes in {files}. This is round {N}...")
Agent(subagent_type="explorer", prompt="Trace execution paths for {feature}...")
Agent(subagent_type="architect", prompt="Design implementation for {feature}...")
Agent(subagent_type="code-mapper", prompt="Map the structure around {area}...")
Agent(subagent_type="code-writer", prompt="Implement the following plan: {plan}...")
Agent(subagent_type="builder-tester", prompt="Build and test the project...")
```

The prompt you provide is the **task context** — what to do, not how to do it. The agent's built-in system prompt handles the "how."

## Agent summary

| Agent | Model | Access | Phase | Purpose |
|---|---|---|---|---|
| `code-mapper` | haiku | Read-only | Discover | Produces context map (`.claude/context-map.md`) — entry points, interfaces, data flow, conventions |
| `explorer` | sonnet | Read-only | Discover | Deep analysis: execution paths, design decisions, hidden dependencies |
| `architect` | opus | Read-only | Plan | Implementation blueprints: files, interfaces, data flows, build sequence |
| `code-writer` | opus | Write | Build | Implements code following a plan. No builds, no tests, no review |
| `builder-tester` | sonnet | Write | Build | Builds, writes tests, runs tests. Returns concise summaries, not logs |
| `reviewer` | opus | Read-only | Review | Finds bugs, security issues, architecture violations, structural problems |

## Dispatch rules by task size

| Size | Agents used | Flow |
|---|---|---|
| **Small** | Code Writer → Builder/Tester → Reviewer | Sequential, minimal |
| **Medium** | Code Mapper → Code Writer → Builder/Tester → Reviewer | Mapper feeds Writer |
| **Large** | Code Mapper → Explorer → Architect → Code Writer → Builder/Tester → Reviewer | Full pipeline |
| **Mega** | All roles, parallel Code Writers per sub-task | Mapper → Explorer → Architect → parallel Writers → Builder/Tester and Reviewer at integration |

## Reviewer dispatch (review rounds)

**Round 1:**
```
Use the reviewer agent to review all code changes. Find real issues, not nitpicks.
Review for: bugs, logic errors, edge cases, security vulnerabilities, architecture violations,
code quality, test coverage, and structural organization.
Report at 80%+ confidence only.
```

**Round N > 1:**
```
Use the reviewer agent. This is review round {N}.
The following {count} items were already found and fixed — do NOT re-report them:
{previously_fixed list}
Focus ONLY on NEW high-confidence findings.
Confidence threshold: Round 1-2: 80%+ | Round 3-4: 85%+ | Round 5: 90%+
```

## Fallback: agents not installed

If custom agents are not installed, use these built-in subagent types with inline prompts:

| Role | Fallback subagent_type | Model override |
|---|---|---|
| Code Mapper | `Explore` | haiku (default) |
| Explorer | `Explore` | sonnet |
| Architect | `general-purpose` | opus |
| Code Writer | `general-purpose` | opus |
| Builder/Tester | `general-purpose` | sonnet |
| Reviewer | `general-purpose` | opus |

When using fallback types, include the full role instructions in the dispatch prompt (the agent won't have a built-in system prompt for the role). See the agent definition files in the framework's `agents/claude/` directory for the complete prompts.
