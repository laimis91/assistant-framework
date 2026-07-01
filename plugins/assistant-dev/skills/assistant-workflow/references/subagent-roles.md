# Subagent Role Definitions

Reference for dispatching subagents through the active runtime's agent mechanism. When the framework's custom agents are installed (`~/{agent_state_dir}/agents/`), dispatch by the configured agent name — each agent carries its own system prompt, tool restrictions, and provider-specific model settings when that runtime supports them. Do not assume every runtime exposes a Claude-style `Agent` tool or `subagent_type` parameter.

## Model selection guidance

Use **capability tiers**, not provider-specific model names, when deciding which model a role should use. Different runtimes name models differently, and some (for example Gemini CLI today) may not support custom per-role model files yet.

| Tier | Use for | Selection rule |
|---|---|---|
| **Fast / economical** | Shallow mapping, file inventory, locating entry points | Cheapest/fastest model that can follow structured output reliably |
| **Balanced / standard** | Deep reading, build/test loops, noisy output summarization | Default strong coding model for day-to-day reasoning and tool use |
| **Strongest / deep reasoning** | Architecture, implementation, high-confidence review | Best available coding/reasoning model; spend tokens here when mistakes are expensive |

Provider examples are only examples, not requirements:

- Claude: fast ≈ Haiku, balanced ≈ Sonnet, strongest ≈ Opus.
- Codex/OpenAI: fast ≈ the configured lightweight coding model, balanced ≈ the default coding model, strongest ≈ the highest-reasoning coding model available in the environment.
- Gemini: fast ≈ Flash-class, balanced ≈ Pro-class/default coding model, strongest ≈ highest-reasoning Pro/Ultra-class model available.

If the runtime does not expose model overrides for subagents, keep the role separation and tool-access constraints; use the default model and include the tier as guidance in the dispatch prompt.

## Installed agents

When custom agents are installed, dispatch by name. The agent's own configuration handles everything; the runtime syntax differs:

### Claude Code

Claude exposes the `Agent` tool with `subagent_type` values matching installed agent names:

```
Agent(subagent_type="reviewer", prompt="Review the changes in {files}. This is round {N}...")
Agent(subagent_type="explorer", prompt="Trace execution paths for {feature}...")
Agent(subagent_type="architect", prompt="Design implementation for {feature}...")
Agent(subagent_type="code-mapper", prompt="Map the structure around {area}...")
Agent(subagent_type="code-writer", prompt="Implement the following plan: {plan}...")
Agent(subagent_type="builder-tester", prompt="Build and test the project...")
```

### Codex

Current Codex CLI/app releases support native subagent workflows by default. Codex custom agents are standalone TOML files under `~/.codex/agents/` for personal agents or `.codex/agents/` for project-scoped agents. Ask Codex to spawn the configured agent by name; do not look for a visible Claude-style `Agent` tool or `subagent_type` parameter before deciding delegation is available:

```
Spawn the reviewer agent to review the changes in {files}. This is round {N}...
Spawn the explorer agent to trace execution paths for {feature}...
Spawn the architect agent to design implementation for {feature}...
Spawn the code-mapper agent to map the structure around {area}...
Spawn the code-writer agent to implement the following plan: {plan}...
Spawn the builder-tester agent to build and test the project...
```

Codex global `[agents]` settings such as `max_threads` and `max_depth` are optional limits; absence of those settings is not proof that subagents are unavailable.

The prompt you provide is the **task context** — what to do, not how to do it. The agent's built-in system prompt handles the "how."

## Agent summary

| Agent | Recommended tier | Access | Phase(s) | Purpose |
|---|---|---|---|---|
| `code-mapper` | Fast / economical | Read-only | Discover | Produces context map (`{agent_state_dir}/context-map.md`) — entry points, interfaces, data flow, conventions |
| `explorer` | Balanced / standard | Read-only | Discover | Deep analysis: execution paths, design decisions, hidden dependencies |
| `architect` | Strongest / deep reasoning | Read-only | Decompose, Plan, Design | Strict slice decomposition, implementation blueprints, design direction |
| `code-writer` | Strongest / deep reasoning | Write | Build | Implements code following a plan. No builds, no tests, no review |
| `builder-tester` | Balanced / standard | Write | Build | Builds, writes tests, runs tests. Returns concise summaries, not logs |
| `reviewer` | Strongest / deep reasoning | Read-only | Review | Finds bugs, security issues, architecture violations, structural problems |

## Dispatch rules by task size

| Size | Agents used | Flow |
|---|---|---|
| **Small** | Code Writer → Builder/Tester → Reviewer | Sequential, minimal (no Decompose) |
| **Medium** | Code Mapper → Architect (decompose) → Code Writer → Builder/Tester → Reviewer | Mapper feeds Architect, slices feed Writer |
| **Large** | Code Mapper → Explorer → Architect (decompose + plan) → Code Writer → Builder/Tester → Reviewer | Full pipeline with slice verification |
| **Mega** | All roles, parallel Code Writers per slice | Mapper → Explorer → Architect → parallel Writers → Builder/Tester and Reviewer at integration |

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
Confidence threshold: Round 1-3: 80%+ | Round 4-7: 85%+ | Round 8-10: 90%+
```

## Fallback: agents not installed

If custom agents are not installed, use the nearest available built-in subagent type and choose by capability tier rather than by provider-specific model name:

| Role | Fallback subagent_type | Recommended tier |
|---|---|---|
| Code Mapper | `Explore` or nearest read-only explorer | Fast / economical |
| Explorer | `Explore` or nearest read-only explorer | Balanced / standard |
| Architect | `general-purpose` or nearest planning agent | Strongest / deep reasoning |
| Code Writer | `general-purpose` or nearest coding agent | Strongest / deep reasoning |
| Builder/Tester | `general-purpose` or nearest coding agent with shell/test access | Balanced / standard |
| Reviewer | `general-purpose` or nearest read-only reviewer | Strongest / deep reasoning |

When using fallback types, include the full role instructions in the dispatch prompt (the agent won't have a built-in system prompt for the role). Prefer the matching role definition for the active runtime under the framework's `agents/` directory when available; otherwise adapt the closest provider-neutral role prompt.
