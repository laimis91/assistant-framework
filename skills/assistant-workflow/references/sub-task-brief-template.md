# Strict Slice Brief Template

Use this template when decomposing mega tasks into strict slice packets. Each approved slice gets its own brief that can be pasted into a new conversation.

## Decomposition rules

- Aim for one or more smallest iterable slice packets; use a single slice when correct and record the rationale
- Do not split by layer, module, folder, broad feature bucket, setup step, or broad component unless that split is itself a verified deliverable artifact slice
- Contract-only work is valid only when it is the verified deliverable artifact slice
- Dependent slice branches start from the integration branch after prerequisite slices are verified
- UI slices include a Design step, backend slices skip it
- Slice packets add code comments but do NOT update README, CHANGELOG, or architecture docs

## Git branching strategy

```
main
 └── feature/[mega-task-name]/integration        ← integration branch
      ├── feature/[mega-task]/slice-[slice_id]   ← verified deliverable slice
      ├── feature/[mega-task]/slice-[slice_id]
      ├── feature/[mega-task]/slice-[slice_id]
      └── feature/[mega-task]/slice-[slice_id]
```

Workflow:
1. Create integration branch from main
2. Build the first verified deliverable slice, merge into integration branch
3. Each dependent slice branch starts from integration branch after its prerequisites are verified
4. Slices execute independently on their branches
5. Integration: merge all into integration branch, resolve conflicts
6. Final merge: integration branch → main

## Brief template

````markdown
## Slice Brief: [name]

### Agent
Agent: [code-writer | architect | reviewer | explorer | builder-tester | code-mapper]
Role: [Implementer | Architect | Reviewer | Explorer]

### Context
Project: [name]
Parent task: [one-sentence description of the mega task]
This is slice [N] of [total]. Other slice packets are handling: [list].

### Strict slice packet (execution contract)
This packet is the executable contract for the slice. Supporting context below cannot satisfy or override these fields. If any required field is missing, return `NEEDS_CONTEXT` instead of executing from loose Goal/Scope prose.

- slice_id: [approved slice id]
- slice_name: [approved slice name]
- observable_increment: [what becomes visible/verifiable after this slice]
- deliverable_type: behavior | artifact | contract | docs | eval | config | migration | refactor
- files_to_create:
  - [exact path, or "none"]
- files_to_modify:
  - [exact path, or "none"]
- files_to_test:
  - [exact test path or verification target, or "none with reason"]
- enabling_changes_included:
  - [setup, contracts, wiring, config, or "none"]
- depends_on:
  - [slice id, or "none"]
- acceptance_criteria:
  - [ ] [binary pass/fail criterion]
- verification_command: [exact command or inspection method]
- expected_success_signal: [specific passing output, file, or review signal]
- evidence_to_record:
  - [test result, eval fixture, changed file, review note, or artifact proof]
- deviation_rollback_rule: [what to do if required files/behavior differ from this packet]

### Supporting context (not the execution contract)
- Parent goal: [one-sentence description of the mega task]
- Adjacent slices: [what other slice packets are handling]
- Relevant files/modules: [context only; strict files_to_* fields above control execution]
- Architecture notes: [rules from the parent plan]

### Prerequisite slice outputs (already verified)
[Paste the interfaces, DTOs, schemas, generated artifacts, or config this slice must implement or consume.
Include the actual code/signatures or artifact paths, not just names.]

### Constraints
- Must not modify: [files owned by other slice packets]
- Must implement: [interface/contract/artifact from prerequisite slices]
- Must follow the strict slice packet; do not use supporting context as permission to expand scope
- Naming conventions: [from project]
- Git branch: [branch name to work on]

### What to do
Read configured project-local memory/context (for example `{agent_state_dir}/memory.md`, or another documented equivalent) when available and policy-allowed before starting.
Run: Plan → [Design →] Build.
Implement only the strict slice packet fields above.
Follow project conventions.
Add code comments where intent isn't obvious.
Do NOT update README, CHANGELOG, or architecture docs —
that happens in the final Document phase after integration.

### Completion status

When the slice is complete, report status using one of these values:

| Status | Meaning | What happens next |
|---|---|---|
| `DONE` | All acceptance criteria met, tests pass, no concerns | Proceed to integration |
| `DONE_WITH_CONCERNS` | Criteria met but there are trade-offs or risks worth noting | Orchestrator reviews concerns before integration |
| `NEEDS_CONTEXT` | Blocked by missing information not in the brief | Orchestrator provides context or adjusts the brief |
| `BLOCKED` | Cannot proceed — dependency issue, tooling failure, or design conflict | Orchestrator investigates and unblocks |
| `DEVIATED` | Work cannot follow the strict slice packet exactly | Orchestrator applies the deviation rollback rule before continuing |

**Report format:**
```text
## Slice Status: [DONE | DONE_WITH_CONCERNS | NEEDS_CONTEXT | BLOCKED | DEVIATED]

### Summary
[1-3 sentences: what was accomplished]

### Concerns (if DONE_WITH_CONCERNS)
- [trade-off or risk worth noting]

### Blocker (if NEEDS_CONTEXT or BLOCKED)
- What's needed: [specific missing information or resolution]

### Changes made
- [file]: [what changed]

### Slice evidence
- slice_id: [id]
- verification_command: [command or method]
- expected_success_signal: [signal]
- result: [pass/fail/blocker]
- evidence_recorded: [evidence from evidence_to_record]

### Deviation (if DEVIATED)
- deviation_rollback_rule applied: [yes/no + details]
```
````

## Execution strategies

**Parallel sessions (multiple conversations):**
Best when slices have no dependencies after prerequisite slices. Start each with its brief.

**Sequential sessions:**
Best when slices depend on each other. Complete one, carry verified output to next.

**Multi-agent (Claude Code, Codex CLI):**
Each agent gets a brief as its prompt. Requires well-defined contracts and an integration step.

Brief files use `briefs/slice-<N>-<slice_id>.md`.

```bash
codex exec "$(cat 'briefs/slice-<N>-<slice_id>.md')" --cwd .
codex exec "$(cat 'briefs/slice-<N+1>-<next_slice_id>.md')" --cwd .
```

## Decomposition rules

**Smallest iterable slice:** Each slice must deliver observable behavior, artifact output, contract surface, docs, eval coverage, config, migration, or refactor evidence that can be verified before the next slice starts.

**Invalid live splits:** Broad feature-only splits are invalid live decomposition output. Do not split by architectural layer, module, folder, feature bucket, broad component, standalone contract setup, or standalone setup work as the execution pattern. Contract-only/setup-only work is valid only when it is the deliverable artifact slice with acceptance criteria and verification evidence.

**Dependency handling:** Put enabling contracts, config, wiring, and setup inside the first slice that needs them unless they are themselves the verified deliverable.

## Integration phase prompt

```
All slice packets are verified. Now integrate:
1. Merge all slice branches into integration branch
2. Resolve merge conflicts
3. Confirm verified prerequisite slice outputs are present and consumed
4. Run integration checks for DI, routes, configs, data flow, and cross-slice behavior
5. Run integration tests across slice boundaries
6. Run full test suite
7. Fix integration mismatches

Verified slices completed:
- [name]: [what was built, branch]
- [name]: [what was built, branch]

Verified prerequisite slice outputs: [list]
```

## When decomposition goes wrong

| Problem | Sign | Fix |
|---|---|---|
| Too coupled | Every slice needs every other | Redraw boundaries |
| Contracts too vague | Lots of integration mismatches | Define as actual code signatures |
| Too small | Brief overhead exceeds the work | Merge slices |
| Too many | Coordination overhead kills gains | Merge into fewer smallest iterable slices |
| Missing slice | Integration reveals unowned gap | Add a slice or assign to integration |
| Context lost | New session misses conventions | Add project rules to each brief |
| Merge conflicts | Overlapping file modifications | Tighten scope around slice boundaries |
