# Mega Tasks, Patterns, and Anti-Patterns

## Mega Task Decomposition

Read `references/sub-task-brief-template.md` for brief format.

- 3-7 sub-tasks
- Sub-task #1: shared contracts (interfaces, DTOs, entities) -- build first
- Each sub-task: Plan --> [Design] --> Build
- Git: integration branch + per-sub-task branches

Automation scripts in `scripts/` (bash):
- `decompose.sh` -- create branches, worktrees, briefs
- `run-agents.sh` -- launch parallel agents (reads `agent.conf` for CLI)
- `check-integration.sh` -- validate integration readiness
- `generate-agents-md.sh` -- capture project knowledge

## Agent Portability

Claude, Codex, and Gemini all use the same skill format (SKILL.md + directory).
Agent definitions are per-platform: Claude uses `.md` files in `agents/claude/`, Codex uses `.toml` files in `agents/codex/`.

## Related skills (invoke when applicable)

- **assistant-review**: Autonomous review loop — MUST be invoked for Stage 2 quality review
- **assistant-tdd**: Test-Driven Development enforcement — Red-Green-Refactor cycle (Build phase, when TDD is active)
- **assistant-thinking**: Structured reasoning for architecture decisions (Discovery, Plan phases)
- **assistant-research**: Information gathering during Discovery phase
- **assistant-security**: Security analysis during Plan/Build phases
- **assistant-memory**: Capture insights at task completion (Phase 7)
- **assistant-reflexion**: Lesson recall in Discovery phase; post-task reflection in Document phase
- **assistant-docs**: Documentation generation in Document phase or standalone
- **assistant-onboard**: Systematic project learning when entering a new codebase
- **assistant-ideate**: Brainstorming pipeline during idea-to-action decomposition
- **assistant-diagrams**: Visual documentation during Plan/Document phases

## Anti-Patterns

- **Guess:** Ask when ambiguous, state assumptions when clear
- **Skip Discovery:** Even small tasks get quick validation
- **Skip Decompose:** Medium+ tasks MUST decompose into components. "It's straightforward" is not an excuse — decomposition reveals hidden complexity.
- **Mega-step:** One plan step at a time
- **Silent drift:** Stop and flag plan deviations
- **Tests after:** Write tests alongside each step
- **Skip review:** NEVER skip review. Invoke `assistant-review` skill. If you don't see `--- PHASE: REVIEW ---` in the output, review was skipped.
- **Review once and done:** Review has two stages (spec + quality) and quality is an autonomous loop
- **No gate:** Always wait for approval before Build
- **No checkpoints:** Every phase MUST print `--- PHASE: [name] ---` messages. Missing checkpoints = workflow not followed.
- **Skip SOLID:** Evaluate the graduated SOLID checklist after each build step, not as a batch at the end
- **Context hoarding:** Every file read must serve a purpose
