# Agent and Tool Authority

Load this when the assessed target has agent, tool, prompt, memory or task-state flows: content an agent reads, tools or roles it can invoke, approvals it acts on, or context it keeps between turns or sessions.

## Untrusted input

Treat as untrusted: web pages, repository and user files, tool output, MCP server and tool metadata, retrieved or remembered content, and results returned by delegated agents. Untrusted content can steer a model; that alone is not a finding.

## When prompt injection is a finding

Report it only when a deterministic boundary fails. The content must do at least one of these:

- reach another principal's context (a different user, tenant, session or privileged role);
- invoke authority the requester lacks;
- drive a sink the requester cannot reach directly (shell, network, file write, publish, payment, message);
- cause an action the affected principal did not request or approve.

Name the lower-trust author of the content, the boundary, the affected principal and the resulting action. "The README could contain an injection" with no reachable capability is not a finding.

## Instructed versus enforced

Keep "instructed" distinct from "enforced". Text in a prompt, skill or system message that tells a model not to do something is instructed: it guides behaviour but stops nothing. An enforced control is a check outside the model that its output cannot override. In this repository, `codex-rules/workflow.rules` `decision` values (`prompt`, `forbidden`) are enforced for the command prefixes they match (an alternate spelling, such as a shell wrapper, may not match), and the `tools:` lines in `agents/claude/*.md` are enforced; the prose in skills and agent bodies is instructed. Never count an instruction-only guardrail as the control that blocks an attack path.

## Delegated authority

For each subagent or role, check which identity and tools it receives (for example the `tools:` line of its definition) and whether the parent treats its return as untrusted input. A read-only role whose return is then executed by a write-capable parent has delegated write authority in effect.

## Action-approval binding

An approval binds the exact action, its arguments and its target. Check that:

- the stored approval records what was approved, not only that something was;
- a retry, resume or post-compaction continuation re-checks the binding and cannot widen it (for example, an approval for one commit reused to push a different branch);
- a side effect already performed is not repeated on retry.

## Durable context

Trace each durable context store from every writer to every later reader that makes a privileged decision: memory notes, persisted task state, installer-managed instruction blocks and similar files loaded into future sessions. A store written from untrusted input and read before a privileged action is a boundary to analyse, even when both steps run as the same user.
