# Plan Boundary Review

Apply these questions within ordinary Plan review before implementation. This
reference is reusable for one or several packets; it does not require a separate
document, extra approval wait or Architect role.

1. **Scope understanding** — each canonical packet advances accepted requirements
   and has exact files, observable criteria and a bounded deviation/rollback rule.
2. **Packet/agent count sanity** — coherent work defaults to one packet. Every
   extra boundary has a concrete acceptance, ownership/context, prerequisite,
   recovery/rollout or binding protocol purpose. Size/file/layer counts alone do
   not force decomposition or Architect. Reject broad layer-only, module-only,
   folder-only, feature-only, setup-only and contract-only splits unless a
   verified deliverable justifies the boundary.
3. **Step/cost budget** — bound steps, rounds, time and cost where relevant;
   direct fallback states its equivalent responsibility and evidence.
4. **Dependency order** — canonical packet_ids resolve exactly once; all
   prerequisites precede dependents and must become evidence-bound VERIFIED.
   Shared/unknown source writers serialize; overlap needs current runtime isolation.
5. **Output-plan match** — criteria, exact CheckSpecs/argv/cwd or non-command
   procedure, binding tuples, success signals and required evidence align. Active
   TDD keeps exactly one applicable selected check per packet. Preserve deferred
   and task-wide obligations explicitly in completion_allocation.
6. **Fallback path** — resolve delegation triggers, current capabilities, safe
   same-scope recovery and stop conditions. Keep spent recovery counters on resume.

Repair the Plan or return to Discover for missing material requirements. Use
`proceed`, `revise_decomposition` or `return_to_discover` as ordinary Plan review
reasoning when useful. Approve the canonical definition once through existing
Plan policy, then admission resolves that exact definition at each worker/state
boundary. Candidate assertions and projection edits cannot redefine authority.
