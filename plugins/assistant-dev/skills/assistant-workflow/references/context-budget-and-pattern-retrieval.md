# Context Budget and Pattern Retrieval

Use this reference when a task has large review/research material, many files, long logs, prior examples, or a risk of stuffing too much into one prompt.

## Context budget rules

1. **Keep exact**
   - Latest user goal and acceptance criteria.
   - Safety/policy constraints and output contract.
   - Changed file list and files intentionally in scope.
   - Exact failing errors, test names, stack traces, and critical diff hunks.
   - Validation commands and pass/fail/blocker results.

2. **Summarize**
   - Repetitive logs after extracting the first failure, final failure, and representative pattern.
   - Large tool outputs after extracting evidence paths, counts, and exact errors.
   - Long conversation history after preserving pinned requirements.
   - Similar files/patterns after recording the canonical example and why it applies.

3. **Drop or defer**
   - Stale assumptions replaced by tool output or later user instructions.
   - Raw logs that do not contain failures, evidence, or decisions.
   - Unrelated search results and files outside accepted scope.
   - Secrets or proprietary values that are not needed for continuation.

4. **Split instead of stuffing**
   - If material is too large to review faithfully, split by slice, task packet, or risk surface.
   - Delegate isolated inspections instead of placing all raw context in one prompt.
   - Carry a context index: paths, commands, evidence excerpts, and what was intentionally omitted.

## Pattern retrieval before edits

Before editing a framework skill, contract, eval, hook, or workflow surface, retrieve local patterns first:

1. Search for similar skills/contracts/evals/hooks in the repo.
2. Pick one canonical pattern and one counterexample/edge case when available.
3. Record the source paths or exact search queries used as patterns in the plan or task packet; placeholders such as `[paths/queries]` do not satisfy the gate.
4. Adapt the pattern; do not copy stale placeholders or unrelated requirements.
5. If no good pattern exists, state that explicitly and create the smallest new pattern with tests.

## Required context budget note

For medium+ tasks or any task with large material, include a compact note in the plan or task packet:

```text
Context Budget:
- Exact/pinned: [goal, criteria, files, errors, validation, constraints]
- Summarized: [logs/tool output/history summarized]
- Omitted/deferred: [what was excluded and why]
- Split/delegation plan: [if scope exceeds one prompt]

Pattern Retrieval:
- Similar patterns searched: [real repo paths or search queries; no placeholders]
- Canonical pattern used: [real repo path, or N/A with no-pattern rationale]
- Counterexample/edge case checked: [real repo path, or N/A with explanation]
- No-pattern rationale: [if applicable]
```

## Review check

A plan or handoff is incomplete when it says “review all files/logs” but does not say what was kept exact, summarized, omitted, or split. A framework edit is incomplete when it introduces a new shape without searching existing local patterns first.
