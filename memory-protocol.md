<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->
# Assistant Framework — Memory Protocol

<!-- This is a template. Paths like ~/{agent_state_dir}/ are substituted during install.sh for the active agent. -->
<!-- Appended by Assistant Framework install. Do not remove this marker. -->

Cross-session memory is available through the memory-graph MCP and its local store under `~/{agent_state_dir}/memory`.

- Query memory only for relevant corrections, stable preferences, requested recall, task recovery, or durable lessons; otherwise skip it. Try `memory_context` before `memory_search`.
- If present, read `{agent_state_dir}/task.md` and `{agent_state_dir}/session.md` to resume active work. Use `{agent_state_dir}/working-buffer.md` only as temporary recovery context.
- Treat memory as supporting context, not as a replacement for current repository evidence. Verify drift-prone facts before changing code or configuration.
- Save only durable rules, preferences, or reusable insights when useful. Routine completion does not require reflection, metrics, memory writes, consolidation, or health checks.
- Never store credentials, API keys, secrets, PII, private endpoints, customer data, or temporary task progress in memory.

<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END -->
