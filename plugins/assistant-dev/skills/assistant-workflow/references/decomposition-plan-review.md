# Decomposition Plan Review

Use this before medium/large/mega work spends implementation effort on subagents, candidate swarms, or component execution. The goal is to catch a bad task split while it is still cheap to fix.

## Review questions

Before leaving Decompose, review the proposed component/subagent plan against these checks:

1. **Scope understanding** — every component maps to an accepted goal, acceptance criterion, gate pack, or required deliverable. No unrelated work is introduced.
2. **Agent/subtask count sanity** — the number of components/subagents fits the task size and risk. Medium tasks should stay small; large/mega tasks need explicit justification for broad parallelism.
3. **Step/cost budget sanity** — the plan names a bounded step/round/time/cost budget or explains why direct fallback has no subagent budget.
4. **Dependency order** — independent work comes first, shared contracts precede dependents, and no circular dependency remains.
5. **Output-plan match** — each component declares artifact type, files, verification criteria, and expected success signal that match the user-visible deliverable.
6. **Fallback path** — if subagents are unavailable or policy-disallowed, the direct execution path preserves the same component order and evidence requirements.

## Required packet

Add this packet to the Decompose output and carry it into Plan for medium+ work:

```text
Decomposition Plan Review:
- Scope understanding: [pass/fix needed + evidence]
- Component/subagent count: [count + sanity rationale]
- Step/cost budget: [budget or direct-fallback rationale]
- Dependency order: [summary]
- Output-plan match: [artifact/verification alignment]
- Fallback path: [subagent path or direct equivalent]
- Decision: proceed | revise_decomposition | return_to_discover
```

## Stop rules

- If scope is misunderstood, return to Discover before planning.
- If agent/subtask count is excessive, merge or sequence components before approval.
- If budget is unbounded, add a bound before dispatch.
- If output artifacts or verification criteria do not match the requested deliverable, repair the component manifest before Plan.
