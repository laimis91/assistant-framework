---
name: assistant-onboard
description: "This skill performs systematic codebase learning for new projects. Maps structure, identifies patterns, and may generate project-local orientation artifacts. Use when the user says 'learn this codebase', 'onboard', 'get familiar with', 'map this project', 'what does this project do', 'new to this repo', 'first time here'."
effort: high
triggers:
  - pattern: "learn this codebase|onboard|get familiar with|map this project|what does this project do|new to this repo|first time"
    priority: 65
    min_words: 4
    reminder: "This request matches assistant-onboard. Load and follow this SKILL.md and its contracts for systematic codebase learning."
---

# Project Onboarding

## Contracts

| File | Purpose |
|---|---|
| [`contracts/input.yaml`](contracts/input.yaml) | project_path, focus_area, depth |
| [`contracts/output.yaml`](contracts/output.yaml) | project_summary, key_files[], conventions[], risky_areas[], likely_change_points[], artifacts[], artifact_updated, durable_memory_updated, questions[] |

- `project_path` is required; `depth` defaults to standard when not specified
- `key_files` entries include path and purpose; `conventions` entries include pattern and example
- `risky_areas` and `likely_change_points` make the orientation actionable for future development work
- `questions` must be specific to unclear areas discovered during onboarding

Systematic protocol for learning a new codebase. Produces structured project orientation that accelerates future work. Project-local orientation artifacts are optional and must follow the active agent/workplace policy; do not assume third-party memory tooling is available.

Core principle: **Understand before acting. Map the territory before navigating it.**

Company-safe defaults:
- Read local project files and run read-only/local discovery commands only.
- Do not install analyzers, upload source, or call external services without explicit approval.
- Do not store secrets, customer data, private URLs, or transient task progress in orientation artifacts.
- Prefer agent-agnostic project notes; if the environment has a configured agent memory path, use that path, otherwise report the orientation in the response without writing files.

## Goal

Build a compact, evidence-based orientation for the project so future development starts from real structure, commands, conventions, and gaps.

## Success Criteria

- Surface scan, architecture mapping, pattern recognition, and gap reporting are complete for the selected depth.
- Key files include path and purpose; conventions include pattern and concrete example.
- Build/test/run commands are identified from project files when available.
- Risky areas and likely change points are called out for future development work.
- Questions are specific to discovered gaps, not generic prompts.
- Artifacts and durable memory updates are reported accurately.

## Constraints

- Ask only when the focus area or depth materially changes which files are inspected and cannot be inferred from the user's request.
- Do not edit production code during onboarding.
- Do not claim full coverage from a representative sample; label gaps and assumptions clearly.
- Do not create or overwrite orientation/memory files unless the user or project policy allows it.
- Do not persist secrets, credentials, private endpoints, or temporary task status.

## When to Activate

- First time working with a repository
- User explicitly asks to learn/understand a codebase
- No project-local orientation artifact exists for the project
- Existing project-local orientation is stale (> 60 days old with significant changes)

## Onboarding Protocol

### Phase 1: Surface Scan (fast, always do)

Print: `>> Onboarding: Surface scan`

Read in this order (stop early if small project):

When the active adapter supports parallel reads, batch independent reads such as README, agent instructions, `.gitignore`, root listing, build files, and CI config. If parallel reads are unavailable, use the order below.

1. **README.md / docs index** — stated purpose, setup instructions
2. **Agent/project instructions** — AGENTS.md, CLAUDE.md, CONTRIBUTING.md, `.cursorrules`, or equivalent
3. **.gitignore** — what's excluded reveals what's used
4. **Root directory listing** — project shape
5. **Build files** — .csproj, package.json, pyproject.toml, Makefile, Dockerfile, go.mod, Cargo.toml, etc.
6. **CI/CD config** — .github/workflows, azure-pipelines.yml, GitLab CI, build scripts

Extract:
- Project name and purpose
- Tech stack (language, framework, major dependencies)
- Build and test commands
- Project structure pattern (monorepo, single project, multi-project solution)

### Phase 2: Architecture Map (medium+ projects)

Print: `>> Onboarding: Architecture mapping`

For medium+ projects, dispatch a **Code Mapper** subagent if available.
If delegation is unavailable in the active adapter or tool policy, perform a lightweight local map and record that Code Mapper dispatch was unavailable.

Map:
- **Entry points**: where execution starts
- **Layer boundaries**: how code is organized (by feature, by layer, hybrid)
- **Key abstractions**: interfaces/base classes that define the architecture
- **Data model**: entities, their relationships, persistence strategy
- **External integrations**: databases, APIs, message queues
- **Configuration**: what's configurable, where settings live

### Phase 3: Pattern Recognition

Print: `>> Onboarding: Pattern recognition`

Identify the project's conventions by reading 3-5 representative files:
- Naming conventions (PascalCase, camelCase, prefixes)
- Error handling pattern (exceptions, Result types, error codes)
- Logging approach (structured, unstructured, what framework)
- Testing patterns (framework, naming, organization)
- DI patterns (registration style, lifetime choices)
- Code organization within files (ordering of members, regions)

### Phase 4: Knowledge Gaps and Risky Areas

Print: `>> Onboarding: Identifying unknowns and risk areas`

List what you still don't understand:
- Areas of code that seem complex or unusual
- Patterns that deviate from convention
- Dependencies whose purpose isn't clear
- Configuration values that need context

Also identify practical development guidance:
- **Risky areas**: auth, permissions, persistence, migrations, external integrations, shell/file operations, weak tests, unclear ownership
- **Likely change points**: files/directories most future tasks are likely to touch
- **Verification entry points**: focused test/build commands and smoke checks discovered locally

Present only specific gaps to the user. Do not ask generic "anything else?" questions.

### Phase 5: Generate Project Orientation

Print: `>> Onboarding: Generating project orientation`

Create or update a project-local orientation artifact only when allowed by user/project policy. Prefer the active agent's configured project note path; examples include `{agent_state_dir}/memory.md`, or a documented repo-local equivalent. If no safe path is known, do not write a file; return the orientation in the response.

```markdown
# [Project Name]

## Purpose
[What it does, who uses it]

## Tech Stack
- Language: [language] [version]
- Framework: [framework] [version]
- Database: [database]
- Key dependencies: [list]

## Architecture
- Pattern: [pattern name]
- Entry points: [list with paths]
- Layers: [list with descriptions]

## Conventions
- Naming: [convention]
- Error handling: [pattern]
- Testing: [framework, naming convention]
- DI: [registration pattern]

## Build and Test Commands
```bash
[build command]
[test command]
```

## Key Files
- [path]: [purpose]
- [path]: [purpose]

## Risky Areas
- [path/surface]: [risk and why it matters]

## Likely Change Points
- [path/directory]: [when future work should look here]

## Verification Entry Points
- [command]: [what it validates]

## Gotchas
- [non-obvious thing 1]
- [non-obvious thing 2]
```

Durable memory / knowledge graph updates are optional and policy-dependent:
- If local memory tools are approved and available, record only stable conventions, project identity, and non-obvious development rules.
- If memory tools are unavailable or policy-disallowed, skip durable memory updates and set `durable_memory_updated=false` in the report.
- Project-local orientation artifacts are tracked separately in `artifacts[]`; writing an orientation file does not imply durable memory was updated.
- Never store secrets, internal credentials, private endpoints, customer data, transient task progress, PR numbers, or issue status.

### Phase 6: Report

Print: `>> Onboarding complete`

Present a concise summary:

```
Project: [name]
Stack: [tech stack summary]
Architecture: [pattern]
Size: [small/medium/large] (~[N] files, ~[N]k lines)
Commands: [build/test/run summary]
Conventions: [key conventions]
Risky areas: [auth/data/integration/test gaps/etc.]
Likely change points: [top directories/files]
Unknowns: [any remaining gaps]

Project orientation: [saved to path | returned in response only]
Ready to work on this codebase.
```

## Output

Return:
- **Project summary** - purpose, stack, architecture, approximate size, and primary build/test/run commands.
- **Key files** - important paths with their role in the system.
- **Conventions** - discovered patterns with concrete examples.
- **Risky areas** - surfaces that need extra care in future work and why.
- **Likely change points** - files/directories future features or fixes will likely touch.
- **Artifacts** - orientation or memory files created or updated, or "none" if no files changed.
- **Gaps** - unknowns, assumptions, and specific questions for the user.
- **Status** - onboarded, partially onboarded, or blocked by missing access/context.

## Incremental Onboarding

When returning to a known project after significant time:

1. Read existing project-local orientation if present and policy-allowed (`{agent_state_dir}/memory.md`, or configured equivalent)
2. Check `git log --since="[last session date]"` for changes when git history is available
3. Update orientation only with stable conventions or structural changes; otherwise report refresh results without writing
4. Print: `>> Refreshed project context — [N] changes since last session`

## Rules

- **Never skip Phase 1** — even for "quick" tasks in a new repo
- **Don't read everything** — sample representative files, don't read every file
- **Ask about unknowns** — don't guess business logic or domain concepts
- **Keep memory concise** — under 100 lines, focused on stable development conventions
- **Update, don't overwrite** — if memory.md exists, update sections, don't regenerate

## Stop Rules

- Stop and ask one focused question when project path, focus area, or onboarding depth cannot be inferred and changes the inspection plan.
- Stop and report blocked status when required files cannot be read.
- Do not proceed to code changes as part of onboarding.
