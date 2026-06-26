# Project Cleanup Audit and Execution Report - 2026-06-25

## Purpose

This document records both the original cleanup audit and the cleanup execution completed from it. It should remain useful for later cleanup sessions by preserving:

- what was safe to clear,
- what should not be touched directly,
- which cleanup slices are now complete,
- which opportunities remain,
- the verification matrix for future branches.

The stable target is unchanged: reduce repeated always-loaded instructions and ignored build clutter while preserving enforcement, evidence, generated-artifact boundaries, delegation behavior, and safety gates.

## Execution Summary

Status: cleanup slices below were completed, validated, and final Stage 1/Stage 2 review completed cleanly.

| Slice | Status | Result | Verification receipt |
|---|---|---|---|
| Prior slice - AGENTS.md agent wording | COMPLETED | Cleaned stale agent-name casing and install examples before this continuation. | Previously verified before this final documentation update. |
| A1 - ignored `.DS_Store` files | COMPLETED | Removed ignored `.DS_Store` files outside `.git/.codex`. | Verified no remaining `.DS_Store` outside excluded trees and no unintended tracked changes. |
| A2 - ignored .NET output roots | COMPLETED | Removed ignored .NET output roots under memory-graph and cognitive-complexity. | MemoryGraph build passed; MemoryGraph tests passed 171/0; CognitiveComplexity build passed. NU1900 service-index warnings occurred, but commands exited 0. |
| B - hook output benchmark | COMPLETED | Added `tools/hooks/benchmark-hook-output.sh`, `docs/hook-output-benchmarks.md`, and the benchmark guard in `tests/p0-p4/instruction-overload-contracts.sh`. | Benchmark produced 7 rows; hook suite passed 166 tests; instruction-overload contracts passed 6 tests. |
| C - workflow hook output trimming | COMPLETED | Trimmed `hooks/scripts/workflow-enforcer.sh`, `hooks/scripts/session-start.sh`, and `hooks/scripts/post-compact.sh` while preserving first blocker/action signals. | Focused hook tests and P0/P4 contracts passed after repair. Benchmark deltas: session-start 2122 bytes/225 words to 1766/183; workflow-enforcer 1892/232 to 1625/184; post-compact 2131/218 to 1526/154. |
| E - assistant-review distillation | COMPLETED | Reduced `skills/assistant-review/SKILL.md` from 3242 to 2504 words; added `skills/assistant-review/references/review-checklists.md` at 956 words; synced plugin mirror. | Passed assistant-review skill validation, instruction-quality contracts, skill-eval contracts, assistant-review fixture validation, plugin sync apply/check. |
| F1 - assistant-ideate distillation | COMPLETED | Reduced `skills/assistant-ideate/SKILL.md` from 1194 to 596 words; added `skills/assistant-ideate/references/ideation-pipeline.md` at about 731 words; synced plugin mirror. | Passed assistant-ideate skill validation, instruction-quality contracts, skill-eval contracts, assistant-ideate fixture validation, plugin sync apply/check, and root/plugin diff check. |
| F2 - assistant-workflow plan-template distillation | COMPLETED | Reduced `skills/assistant-workflow/references/plan-template.md` from 2216 to 1846 words; synced plugin mirror. | Passed assistant-workflow skill validation, task-packet contracts, workflow-basics contracts, spec-review contracts, instruction-overload contracts, assistant-workflow fixture validation, plugin sync apply/check. |

Final review receipt:

- Stage 1 Spec Review: PASS. No missing acceptance criteria, extra scope, changed-file mismatch, verification mismatch, or required fixes.
- Stage 2 Quality Review Round 1: found two should-fix items: ideate DECIDE contract drift and broad P0/P4 guard growth.
- Round 1 fixes: added `decision_point` and `decision_options`; made `user_decision` conditional on explicit follow-up; moved new ideate/review guards into focused P0/P4 scripts and the aggregate runner.
- Fix validation passed: assistant-ideate skill validation, focused reference contracts, broad instruction-quality contracts, skill-eval contracts, assistant-ideate/review eval fixture validation, full P0/P4 aggregate, plugin sync check, and diff check.
- Stage 2 Quality Review Round 2: CLEAN. No must-fix, should-fix, or nits above threshold. Weighted score 4.48 PASS; semantic contract, behavioral contract, and agentic loop safety clean.

## Evidence Sources

- Original local inventory from `git ls-files`, `find`, `wc`, `du`, `.gitignore`, and hook/skill file inspection.
- Existing project guidance in `docs/instruction-overload-reduction.md`, `docs/plugin-architecture.md`, `docs/skill-contract-design-guide.md`, `AGENTS.md`, and `CLAUDE.md`.
- Plugin mirror checks with `tools/plugins/sync-plugin-skills.sh --check` and completed sync apply/check runs from the execution slices.
- Delegated audit passes from `code-mapper`, `explorer`, `architect`, and `reviewer`.
- Completed cleanup-session receipts listed in the execution summary above.
- External reference: [`juliusbrussee/caveman`](https://github.com/juliusbrussee/caveman), used only as measured brevity inspiration: compact output, exact commands/errors/code, and safety-aware instruction design. Stable framework behavior remains more important than maximum terseness.

Validation run while producing the original audit:

```bash
bash tools/skills/validate-skills.sh
tools/plugins/sync-plugin-skills.sh --check
bash tests/p0-p4/instruction-overload-contracts.sh
bash tests/test-hooks.sh --filter workflow-enforcer
bash tools/skills/validate-skills.sh --skill skills/assistant-review
bash tools/skills/validate-skills.sh --skill skills/assistant-workflow
bash tests/p0-p4/skill-instruction-quality-contracts.sh
bash tests/p0-p4/skill-eval-contracts.sh
tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-review
```

## Delegated Audit Receipts

The delegated passes below informed this report. They are copied here because `.codex/` session state is ignored and may be cleared after the task.

| Agent | ID | Status | Key findings used |
|---|---|---|---|
| `code-mapper` | `019effd3-b405-79e0-a10e-e6a1ed9ea464` | `DONE_WITH_CONCERNS` | Mapped 484 tracked files; confirmed plugin-local skill copies are exact generated mirrors; identified ignored `.DS_Store` and .NET build outputs as safe disk cleanup; flagged contracts/evals/hooks as behavior-driving surfaces. |
| `explorer` | `019effd3-b4b7-7cf0-a35e-80f43b403840` | `DONE_WITH_CONCERNS` | Traced installer, hooks, plugin sync, validators, and tests; recommended preserving small always-on safety/delegation/phase signals while moving long procedural detail behind skills and references; recommended hook output benchmarking before prose reduction. |
| `architect` | `019effdb-0be3-7ab3-beef-1844020bfb8c` | `DONE_WITH_CONCERNS` | Proposed cleanup slices: local artifacts, generated mirror boundary, hook output benchmark, always-loaded prose consolidation, and per-skill distillation; classified plugin mirrors, contracts, delegation policy, and safety exceptions as no-touch or high-care surfaces. |
| `reviewer` | `019effe1-e811-7630-badb-4fa256d2140f` | `DONE_WITH_CONCERNS` | Found no must-fix issues in the original audit; requested stronger guardrails for `assistant-review` checklist/eval behavior and durable inclusion of delegated evidence in this report. |

## Original Current State Snapshot

The counts in this section are the original audit snapshot. Later execution changed some file sizes and added benchmark/reference files; use the execution summary for completed-slice measurements.

### Tracked Repository Surface

`git ls-files` reported 484 tracked files during the audit.

| Area | Tracked files | Notes |
|---|---:|---|
| `plugins/` | 159 | Plugin-local skill copies and manifests. Treat skill copies as generated mirrors. |
| `skills/` | 156 | Root skill source of truth. Contains 16 assistant `SKILL.md` entry points plus contracts, references, playbooks, scripts, and agent configs. |
| `tools/` | 85 | Memory graph, cognitive complexity, skill/plugin tooling. |
| `tests/` | 26 | Hook, skill, plugin, and P0/P4 contract tests. |
| `hooks/` | 19 | Lifecycle hook templates and scripts. |
| `docs/` | 16 | Design docs, architecture notes, instruction-overload plan, contract guide. |
| `agents/` | 13 | Codex/Claude agent role definitions. |
| Root files | 14 | Installer, README, AGENTS, CLAUDE, memory protocol, license, version, rules, seed data. |

### Largest Instruction Surfaces

Root skill entry points originally totaled 22,554 words. The largest `SKILL.md` files at audit time were:

| Skill entrypoint | Original words | Cleanup posture |
|---|---:|---|
| `skills/assistant-review/SKILL.md` | 3,242 | COMPLETED in slice E. Keep loop semantics and confidence thresholds; moved checklist detail to references with mandatory entrypoint pointers. |
| `skills/assistant-workflow/SKILL.md` | 2,499 | Still high-care. Slice F2 trimmed its plan template, not the whole entrypoint. Keep phase gates, delegation policy, and handoff contract pointers. |
| `skills/assistant-skill-creator/SKILL.md` | 1,921 | Remaining opportunity for reference extraction if contract design behavior stays covered. |
| `skills/assistant-telos/SKILL.md` | 1,769 | Remaining opportunity for moving examples/templates to references. |
| `skills/assistant-tdd/SKILL.md` | 1,526 | Remaining opportunity. Preserve red-green-refactor gates; consider moving extended checklists to references. |
| `skills/assistant-onboard/SKILL.md` | 1,521 | Remaining opportunity for reference extraction. |
| `skills/assistant-reflexion/SKILL.md` | 1,385 | Remaining opportunity for moving longer reflection templates to references. |

Hook scripts originally totaled 3,333 lines. The largest hook scripts at audit time were:

| Hook script | Original lines | Cleanup posture |
|---|---:|---|
| `hooks/scripts/workflow-phase-gates.sh` | 533 | Behavior-critical. Avoid trimming without focused tests. |
| `hooks/scripts/workflow-enforcer.sh` | 525 | COMPLETED in slice C for emitted text. Preserve enforcement and benchmark coverage. |
| `hooks/scripts/task-journal-resolver.sh` | 500 | Utility logic. Do not shrink unless tests cover resolver behavior. |
| `hooks/scripts/skill-router.sh` | 199 | Routing-critical. Keep concise trigger output. |
| `hooks/scripts/stop-review.sh` | 196 | Stop-gate critical. Preserve first-actionable-stop behavior. |
| `hooks/scripts/workflow-guard.sh` | 183 | Delegation/ownership safety. Preserve direct-edit warning semantics. |
| `hooks/scripts/subagent-monitor.sh` | 165 | Delegation evidence. Preserve spawn/fallback signal collection. |
| `hooks/scripts/post-compact.sh` | 149 | COMPLETED in slice C for emitted text. Preserve rehydration signal coverage. |
| `hooks/scripts/session-start.sh` | 147 | COMPLETED in slice C for emitted text. Preserve startup state and next-action output. |

### Ignored Local Clutter

`.gitignore` already ignores build outputs, publish outputs, `.DS_Store`, Unity skills, `Assistant2/`, and `.codex/`.

At audit time, ignored outputs included `.DS_Store` files and .NET build/publish products. Disk usage snapshot:

| Path | Approx size |
|---|---:|
| Repository root | 109M |
| `tools/` | 88M |
| `tools/memory-graph/src/MemoryGraph/bin` | 25M |
| `tools/memory-graph/tests/MemoryGraph.Tests/bin` | 29M |
| `tools/cognitive-complexity/bin` | 16M |
| `tools/cognitive-complexity/.publish` | 16M |

Slices A1 and A2 cleared the safe ignored artifacts. Future sessions may still see recreated `bin/` and `obj/` directories after build/test commands; that is expected.

## Safe To Clear

These can be removed without changing tracked project behavior. Completed items are listed with their execution status for future reference.

1. Ignored `.DS_Store` files outside `.git/`.
   - Status: COMPLETED in slice A1 for `.DS_Store` outside `.git/.codex`.
   - Future posture: safe to clear again if macOS recreates them outside excluded trees.
   - Do not manually clean `.git/**` unless doing a deliberate repository-maintenance task.

2. Ignored .NET build and publish outputs.
   - Status: COMPLETED in slice A2 for memory-graph and cognitive-complexity output roots.
   - Future posture: safe to clear when disk cleanup is needed.
   - Common paths: `tools/**/bin/`, `tools/**/obj/`, and `tools/cognitive-complexity/.publish/`.
   - These are reproducible through `dotnet build`, `dotnet test`, or publish commands.

3. Stale `.codex/` workflow state after the active task is complete.
   - Status: NOT CLEARED by this execution.
   - Current `.codex/**` remains ignored live workflow state.
   - Clear `.codex/task.md`, `.codex/context-map.md`, `.codex/working-buffer.md`, `.codex/session.md`, or `.codex/subagent-events.jsonl` only after no active task needs resume context.

Recommended verification after clearing ignored files:

```bash
git status --short --ignored
git ls-files -i --exclude-standard -o
dotnet build tools/memory-graph/src/MemoryGraph/MemoryGraph.csproj --tl:on -v:minimal
dotnet test tools/memory-graph/tests/MemoryGraph.Tests/MemoryGraph.Tests.csproj --tl:on -v:minimal
dotnet build tools/cognitive-complexity/CognitiveComplexity.csproj --tl:on -v:minimal
```

Note: `dotnet build` and `dotnet test` will recreate some `bin/` and `obj/` directories. That is expected; the purpose is to prove they are reproducible, not to keep the working tree free of build outputs forever.

## Do Not Touch Directly

These are cleanup traps. They may look redundant, but deleting or editing them directly can create behavior drift.

1. Plugin-local skill copies under `plugins/*/skills/`.
   - They are generated release artifacts from root `skills/assistant-*`.
   - Use `tools/plugins/sync-plugin-skills.sh --check` to detect drift and `tools/plugins/sync-plugin-skills.sh --apply` to regenerate.
   - Manual prose cleanup should happen in root `skills/`, then be synced.

2. Skill contract files.
   - `contracts/input.yaml`, `contracts/output.yaml`, `contracts/phase-gates.yaml`, and `contracts/handoffs.yaml` encode behavior, not decoration.
   - Removing required fields is breaking unless the contract guide and consuming tests are updated in the same slice.

3. P0/P4 tests and contract tests.
   - They are the safety net that lets instruction surfaces shrink without losing behavior.
   - Cleanup should add or update tests when reducing always-loaded rules.

4. Delegation permission and fallback wording.
   - The framework has a live policy boundary around explicit user authorization for subagents.
   - Preserve: ask once when needed, spawn configured agents when authorized, record delegated mode when real delegation happens, and use direct fallback only after an actual denial, spawn failure, or policy block.

5. Safety and irreversible-action ambiguity rules.
   - Keep short always-on exceptions for destructive commands, security-sensitive work, migrations, public contracts, secrets, and multi-step ambiguity.
   - These are allowed to be concise, but not absent.

6. `.git/**`.
   - Report ignored artifacts inside `.git/` if noticed, but do not clean them as part of project cleanup.

## Cleanup Tickets and Remaining Opportunities

### Ticket A - Remove ignored local artifacts

Status: COMPLETED.

Completed scope:

- A1 removed ignored `.DS_Store` files outside `.git/.codex`.
- A2 removed ignored .NET output roots under memory-graph and cognitive-complexity.

Verification receipts:

```text
No remaining .DS_Store outside excluded trees.
No unintended tracked changes.
MemoryGraph build passed.
MemoryGraph tests passed: 171 passed, 0 failed.
CognitiveComplexity build passed.
NU1900 service-index warnings occurred, but commands exited 0.
```

Remaining opportunity:

- Repeat this as routine local cleanup if ignored artifacts reappear.
- Keep `.codex/**` until the active task no longer needs resume context.

### Ticket B - Add hook output benchmark

Status: COMPLETED.

Completed scope:

- Added `tools/hooks/benchmark-hook-output.sh`.
- Added `docs/hook-output-benchmarks.md`.
- Added benchmark guard coverage in `tests/p0-p4/instruction-overload-contracts.sh`.

Verification receipts:

```text
Benchmark output produced 7 rows.
Hook suite passed: 166 tests.
Instruction-overload contracts passed: 6 tests.
```

Remaining opportunity:

- Refresh benchmark rows when hook output changes.
- Use benchmark deltas as supporting evidence, not as the only acceptance criterion.

### Ticket C - Trim workflow hook emitted text

Status: COMPLETED.

Completed scope:

- Trimmed `hooks/scripts/workflow-enforcer.sh`.
- Trimmed `hooks/scripts/session-start.sh`.
- Trimmed `hooks/scripts/post-compact.sh`.
- Preserved first blocker/action signals.

Benchmark deltas:

| Hook | Before | After |
|---|---:|---:|
| `session-start.sh` | 2122 bytes / 225 words | 1766 bytes / 183 words |
| `workflow-enforcer.sh` | 1892 bytes / 232 words | 1625 bytes / 184 words |
| `post-compact.sh` | 2131 bytes / 218 words | 1526 bytes / 154 words |

Verification receipts:

```text
Focused hook tests passed after repair.
P0/P4 contracts passed after repair.
First blocker/action signals unchanged.
```

Remaining opportunity:

- Do not trim more hook text without benchmark and focused hook-test evidence.
- Preserve phase state, blockers, active skill reminders, subagent authorization state, and exact next action.

### Ticket D - Fix stale generated agent docs

Status: COMPLETED for the known stale AGENTS.md agent-name casing/install example cleanup.

Completed scope:

- Cleaned the known stale `AGENTS.md` agent-name casing and install example issue before this continuation.

Verification receipt:

```text
The AGENTS.md casing/install example cleanup was already verified before this continuation.
```

Remaining opportunity:

- If future cleanup touches installer-generated instruction blocks, verify installer output for each affected agent.
- Preserve installer markers and user custom sections.

Suggested future validation:

```bash
./install.sh --agent codex --dry-run
./install.sh --agent claude --dry-run
./install.sh --agent gemini --dry-run
bash tests/p0-p4/instruction-overload-contracts.sh
```

### Ticket E - Distill `assistant-review`

Status: COMPLETED.

Completed scope:

- Reduced `skills/assistant-review/SKILL.md` from 3242 to 2504 words.
- Created `skills/assistant-review/references/review-checklists.md` at 956 words.
- Synced plugin mirror.

Verification receipts:

```text
assistant-review skill validation passed.
instruction-quality contracts passed.
skill-eval contracts passed.
assistant-review fixture validation passed.
plugin sync apply/check passed.
```

Remaining opportunity:

- Keep the entrypoint pointers to behavior-driving checklists mandatory.
- If future review behavior changes, update fixture coverage with the behavior change.

### Ticket F - Distill additional skill surfaces

Status: PARTIALLY COMPLETED.

Completed F1 scope:

- Reduced `skills/assistant-ideate/SKILL.md` from 1194 to 596 words.
- Created `skills/assistant-ideate/references/ideation-pipeline.md` at about 731 words.
- Synced plugin mirror.

Completed F1 verification:

```text
assistant-ideate skill validation passed.
instruction-quality contracts passed.
skill-eval contracts passed.
assistant-ideate fixture validation passed.
plugin sync apply/check passed.
root/plugin diff check passed.
```

Completed F2 scope:

- Reduced `skills/assistant-workflow/references/plan-template.md` from 2216 to 1846 words.
- Synced plugin mirror.

Completed F2 verification:

```text
assistant-workflow skill validation passed.
task-packet contracts passed.
workflow-basics contracts passed.
spec-review contracts passed.
instruction-overload contracts passed.
assistant-workflow fixture validation passed.
plugin sync apply/check passed.
```

Remaining opportunities:

- `skills/assistant-workflow/SKILL.md` remains high-care if its entrypoint is distilled later.
- `skills/assistant-skill-creator/SKILL.md`, `skills/assistant-telos/SKILL.md`, `skills/assistant-tdd/SKILL.md`, `skills/assistant-onboard/SKILL.md`, and `skills/assistant-reflexion/SKILL.md` remain candidates for reference extraction.

General acceptance criteria for future skill distillation:

- `SKILL.md` still tells the agent when to stop and ask.
- Every referenced file exists.
- Contract fields still cover all required outputs.
- Behavior-driving checklists either remain in the entrypoint or are referenced by mandatory load/apply instructions with eval coverage.
- Plugin-local mirrors are regenerated after root skill edits.
- Tests prove behavior, not just line-count or word-count reduction.

Suggested future validation:

```bash
bash tools/skills/validate-skills.sh
bash tests/p0-p4/skill-instruction-quality-contracts.sh
bash tests/p0-p4/skill-eval-contracts.sh
bash tests/p0-p4/task-packet-contracts.sh
tools/plugins/sync-plugin-skills.sh --check
```

## Verification Matrix For Future Cleanup Branches

Use the smallest validation set that covers the touched surface.

| Touched surface | Minimum validation |
|---|---|
| Ignored files only | `git status --short --ignored`, relevant `dotnet build` or `dotnet test` if outputs were cleared. |
| Root skill docs/contracts | `bash tools/skills/validate-skills.sh`, relevant P0/P4 contract test, plugin sync check. |
| Plugin-local skill copies | Prefer no manual edit; use sync apply/check. |
| Hook scripts/templates | `bash tests/test-hooks.sh --filter <hook-or-area>`, `bash tests/p0-p4/instruction-overload-contracts.sh`. |
| Installer docs/templates | `./install.sh --agent <agent> --dry-run`, instruction-overload contracts, plugin manifest contracts. |
| Workflow/delegation behavior | Task packet contracts, hook tests, subagent monitor tests if present, manual scenario notes. |
| Memory protocol text | Session-start/post-compact tests, memory protocol readback, no secret/PII checks. |
| Benchmark data | Run `tools/hooks/benchmark-hook-output.sh` and confirm required signals, not just smaller byte counts. |

## Cleanup Philosophy

Borrow only the useful part of Caveman-style compression: measure output, keep commands/errors/code exact, and make the always-loaded layer small. Do not borrow the persona or over-optimize for terseness. This framework should prefer stable outcomes over minimum tokens.

The practical rule:

```text
Delete generated clutter freely.
Distill repeated prose carefully.
Preserve behavior-driving contracts, tests, and safety gates.
Measure token savings before claiming them.
```

## Open Review Items

- No final Stage 1/Stage 2 review blockers remain open for the completed cleanup slices.
- Decide whether this dated cleanup report should remain the canonical execution receipt or whether later sessions should promote durable guidance into a living `docs/cleanup-roadmap.md`.
- If hook output benchmarks keep evolving, decide whether baseline data belongs in markdown, fixtures, generated test output, or a mix.
- If more skill entrypoints are distilled, define target sizes as guidance, not hard gates.
- Clear `.codex/**` only after no active task needs resume context.
