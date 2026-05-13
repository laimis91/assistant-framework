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
| [`contracts/output.yaml`](contracts/output.yaml) | project_summary, key_files[], conventions[], memory_updated, questions[] |

- `project_path` is required; `depth` defaults to standard when not specified
- `key_files` entries include path and purpose; `conventions` entries include pattern and example
- `questions` must be specific to unclear areas discovered during onboarding

Systematic protocol for learning a new codebase. Produces structured project orientation that accelerates future work; durable cross-session memory still lives in the knowledge graph.

Core principle: **Understand before acting. Map the territory before navigating it.**

## Goal

Build a compact, evidence-based orientation for the project so future development starts from real structure, commands, conventions, and gaps.

## Success Criteria

- Surface scan, architecture mapping, pattern recognition, and gap reporting are complete for the selected depth.
- Key files include path and purpose; conventions include pattern and concrete example.
- Questions are specific to discovered gaps, not generic prompts.
- Artifacts and durable memory updates are reported accurately.

## Constraints

- Ask only when the focus area or depth materially changes which files are inspected and cannot be inferred from the user's request.
- Do not edit production code during onboarding.
- Do not claim full coverage from a representative sample; label gaps and assumptions clearly.

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

1. **README.md** — stated purpose, setup instructions
2. **CLAUDE.md** — existing agent instructions
3. **.gitignore** — what's excluded reveals what's used
4. **Root directory listing** — project shape
5. **Build files** — .csproj, package.json, Makefile, Dockerfile
6. **CI/CD config** — .github/workflows, azure-pipelines.yml

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

### Phase 4: Knowledge Gaps

Print: `>> Onboarding: Identifying unknowns`

List what you still don't understand:
- Areas of code that seem complex or unusual
- Patterns that deviate from convention
- Dependencies whose purpose isn't clear
- Configuration values that need context

Present gaps to user for clarification.

### Phase 5: Generate Project Orientation

Print: `>> Onboarding: Generating project orientation`

Create or update `.claude/memory.md` as a generated project-local orientation artifact, not as the cross-session memory source of truth:

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

## Gotchas
- [non-obvious thing 1]
- [non-obvious thing 2]
```

Record discoveries in the knowledge graph:
- `memory_add_entity` — register the project (type Project) with key observations
- `memory_add_relation` — link technology dependencies (Uses), patterns (Follows), conventions (HasConvention)
- `memory_add_insight` — record discovered conventions and non-obvious findings
- `memory_add_entity` with type `Rule` — if any behavioral constraints are discovered (e.g., "never force-push to main")

### Phase 6: Report

Print: `>> Onboarding complete`

Present a concise summary:

```
Project: [name]
Stack: [tech stack summary]
Architecture: [pattern]
Size: [small/medium/large] (~[N] files, ~[N]k lines)
Conventions: [key conventions]
Unknowns: [any remaining gaps]

Project orientation saved to .claude/memory.md
Ready to work on this codebase.
```

## Output

Return:
- **Project summary** - purpose, stack, architecture, and approximate size.
- **Key files** - important paths with their role in the system.
- **Conventions** - discovered patterns with concrete examples.
- **Artifacts** - orientation or memory files created or updated, or "none" if no files changed.
- **Gaps** - unknowns, assumptions, and specific questions for the user.
- **Status** - onboarded, partially onboarded, or blocked by missing access/context.

## Incremental Onboarding

When returning to a known project after significant time:

1. Read existing `.claude/memory.md` if present
2. Check `git log --since="[last session date]"` for changes
3. Update memory with new information
4. Print: `>> Refreshed project context — [N] changes since last session`

## Rules

- **Never skip Phase 1** — even for "quick" tasks in a new repo
- **Don't read everything** — sample representative files, don't read every file
- **Ask about unknowns** — don't guess business logic or domain concepts
- **Keep memory concise** — under 100 lines, focused on what matters for development
- **Update, don't overwrite** — if memory.md exists, update sections, don't regenerate

## Stop Rules

- Stop and ask one focused question when project path, focus area, or onboarding depth cannot be inferred and changes the inspection plan.
- Stop and report blocked status when required files cannot be read.
- Do not proceed to code changes as part of onboarding.
