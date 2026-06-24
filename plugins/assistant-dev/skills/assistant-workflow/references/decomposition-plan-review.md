# Decomposition Plan Review

Use this before medium/large/mega work spends implementation effort on subagents, candidate swarms, or slice execution. The goal is to catch a bad task split while it is still cheap to fix.

## Review questions

Before leaving Decompose, review the proposed slice/subagent plan against these checks:

1. **Scope understanding** — every slice maps to an accepted goal, acceptance criterion, gate pack, or required deliverable. No unrelated work is introduced.
2. **Slice/subagent count sanity** — the number of slices/subagents fits the task size and risk. Medium tasks should stay small; large/mega tasks need explicit justification for broad parallelism, and a single slice must include a single-slice rationale.
3. **Step/cost budget sanity** — the plan names a bounded step/round/time/cost budget or explains why direct fallback has no subagent budget.
4. **Dependency order** — independent slices come first, dependencies reference slice ids, and no circular dependency remains.
5. **Output-plan match** — each slice declares deliverable type, observable increment, files, acceptance criteria, verification command, expected success signal, and evidence to record that match the user-visible deliverable.
6. **Fallback path** — if subagents are unavailable or policy-disallowed, the direct execution path preserves the same slice order and evidence requirements.
7. **Broad-split rejection** — layer-only, module-only, folder-only, feature-only, setup-only, contract-only, and broad component-style splits are rejected unless they are a verified deliverable artifact slice.

## Required packet

Add this packet to the Decompose output and carry it into Plan for medium+ work:

```text
Decomposition Plan Review:
- Scope understanding: [pass/fix needed + evidence]
- Slice/subagent count: [count + sanity rationale]
- Step/cost budget: [budget or direct-fallback rationale]
- Dependency order: [summary]
- Output-plan match: [artifact/verification alignment]
- Fallback path: [subagent path or direct equivalent]
- Broad-split rejection: [how invalid layer/module/folder/feature/setup/contract/component-only splits were rejected or folded into verified deliverable artifact slices]
- Decision: proceed | revise_decomposition | return_to_discover
```

## Stop rules

- If scope is misunderstood, return to Discover before planning.
- If slice/subagent count is excessive, merge or sequence slices before approval.
- If budget is unbounded, add a bound before dispatch.
- If output artifacts or verification criteria do not match the requested deliverable, repair the slice manifest before Plan.
- If the split is only by layer, module, folder, feature, setup, contracts, or broad components without a verified deliverable artifact, repair the slice manifest before Plan.
