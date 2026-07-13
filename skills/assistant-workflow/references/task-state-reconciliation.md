# Task State Reconciliation

Treat persisted task state as a **freshness-checked persisted claim**, not as
authority that can override the newest user request or current repository.
Run this check before resuming from a journal, context map, replay packet, or
carried-forward plan.

## Required identity

Record or recover:

- stable task identity and latest user-goal reference;
- repository root;
- recorded branch, baseline, and HEAD when Git is available;
- last verified milestone and its evidence;
- last reconciliation time and result.

## Reconciliation order

1. Read the persisted state without acting on its next step.
2. Read the newest user request and later corrections.
3. Inspect the current repository root, branch, HEAD, worktree, and relevant
   artifact evidence when available.
4. Compare task identity, goal, repository identity, and verified milestone.
5. Classify the state as `active | stale | superseded | completed`.
6. Resume only an `active` state. Repair `stale`, archive or replace
   `superseded`, and do not restart `completed` work without a new request.
7. Before acting or returning, persist any `stale`, `superseded`, or `completed`
   classification to the framework-owned `{agent_state_dir}/task.md`, including its reason,
   current task identity, and repaired exact next action.

## Classification

- `active`: goal and repository identity still match and no newer evidence
  invalidates the recorded next action.
- `stale`: the goal still applies, but repository identity, progress, or
  verification evidence changed. Refresh the state before continuing.
- `superseded`: a newer user request or approved plan replaced the recorded
  objective or scope. Create/reconcile state for the newer task.
- `completed`: repository and verification evidence show the recorded goal is
  already complete. Report that evidence or start a distinct follow-up task.

## Authority and recovery rules

- Newest explicit user intent outranks persisted prose.
- Current repository and verification evidence outrank unverified progress
  claims.
- A branch or HEAD change is evidence to inspect, not automatic invalidation.
- Never discard user-authored files while reconciling framework-owned state.
- Record the classification, reason, evidence, and repaired exact next action.

If repository identity is unavailable, reconcile against the newest user
request and available artifact evidence, state the limitation, and lower
confidence rather than pretending the journal is current.
