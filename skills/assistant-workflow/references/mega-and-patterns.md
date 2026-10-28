# Mega Tasks, Patterns, and Anti-Patterns

## Mega Task Decomposition

Use the strict slice packet fields from `implementation_steps` for every executable brief.

- Default to one coherent packet; additional packets require a concrete acceptance, ownership/context, prerequisite, recovery/rollout or binding protocol purpose
- Contract-only/setup-only work is valid only when it is the verified deliverable artifact slice; otherwise include enabling changes in the slice that first uses them
- Each slice: Plan --> [Design] --> Build
- Keep slice ownership explicit through task packets. Source-changing packets in a shared or unknown workspace are sequential. Parallel source-changing packets require the runtime explicitly proves isolated workspaces; independent read-only analysis may run in parallel.
- Verify each completed slice before dependent work starts. After all slices are integrated, full-scope validation is required before fresh Review. Integrated selected and binding checks remain due for one or multiple packets before fresh independent Review; packet-local evidence cannot waive them.

## Agent Portability

Claude, Codex, and Gemini all use the same skill format (SKILL.md + directory).
Agent definitions are per-platform: Claude uses `.md` files in `agents/claude/`, Codex uses `.toml` files in `agents/codex/`.

## Related skills (invoke when applicable)

- **assistant-review**: Autonomous review loop — MUST be invoked for the Stage 2 final acceptance review
- **assistant-tdd**: Test-Driven Development enforcement — Red-Green-Refactor cycle (Build phase, when TDD is active)
- **assistant-thinking**: Structured reasoning for architecture decisions (Discovery, Plan phases)
- **assistant-research**: Information gathering during Discovery phase
- **assistant-security**: Security analysis during Plan/Build phases
- **assistant-docs**: Documentation generation in Document phase or standalone
- **assistant-onboard**: Systematic project learning when entering a new codebase
- **assistant-ideate**: Brainstorming pipeline during idea-to-action decomposition
- **assistant-diagrams**: Visual documentation during Plan/Document phases

## Anti-Patterns

- **Guess:** Ask when ambiguous, state assumptions when clear
- **Skip Discovery:** Even small tasks get quick validation
- **Conditional Decompose:** skip for coherent work; refine the same canonical implementation_steps collection only when an execution purpose needs another boundary. Preparation-only produces no execution.
- **Mega-step:** One plan step at a time
- **Silent drift:** Stop and flag plan deviations
- **Tests after:** Write tests alongside each step
- **Skip review:** For implementation/execution work, NEVER skip review. Invoke `assistant-review` skill when the Review phase applies. `prepare_only` retains requested/required fresh readiness-plan review and selected research isolation; it makes no post-Build review or final-handoff claim.
- **Review once and done:** Review has two stages (spec + quality) and quality is an autonomous loop
- **No gate:** Always wait for approval before Build
- **No checkpoints:** Exact phase checkpoints are required only when controller intensity, explicit project policy, or the user requires them. Missing required checkpoints = workflow not followed.
- **Skip SOLID:** For implementation/execution work, evaluate the graduated SOLID checklist after each Build step, not as a batch at the end.
- **Context hoarding:** Every file read must serve a purpose
