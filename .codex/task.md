# Task Journal

Status: DONE
Current phase: DOCUMENT COMPLETE

## Task

Implement the first batch of memory-system retrieval improvements after review found cases where LLMs queried project memory but received no results, especially with keyword/OR searches and project identity drift across sessions.

## Scope

- Add a read-only `memory_doctor` tool for project, relation, FTS, and runtime diagnostics.
- Add explainability fields to `memory_context`: `resolvedProject`, `resolvedBy`, `pathCandidates`, `equivalentProjectsIncluded`, and `warnings`.
- Keep `memory_search` read-only at search time by removing FTS pruning; filter stale/non-canonical rows from returned results without deleting them.
- Add read-only FTS diagnostics for doctor output.
- Strengthen project identity, path, alias, and equivalent-project resolution.
- Apply source/entity filters before FTS caps, with uppercase-only boolean operators and lowercase `and`/`or`/`not` treated as literal terms.
- Register the new runtime tool and cover behavior with focused tests.

## Approved Plan

1. Split project identity resolution into dedicated graph metadata, resolver, resolution, and equivalence components.
2. Separate storage FTS behavior from core memory store code and expose read-only FTS diagnostics.
3. Add `memory_doctor` diagnostics while preserving read-only semantics.
4. Extend context/search tool behavior for identity explainability, equivalent-project aggregation, filter ordering, and boolean query parsing.
5. Register runtime capabilities and add focused regression coverage for context, search, doctor, store, reconciler, and runtime behavior.
6. Reinstall the Codex tool copy and verify both repository and installed memory-graph solutions.

## Components

- Graph resolver/reconciler: canonical project identity, path metadata, alias precedence, equivalent-project aggregation, and FTS liveness.
- Storage/FTS: split FTS implementation, no search-time pruning, read-only diagnostics, and pre-limit filtering.
- Tools: `memory_context`, `memory_search`, `memory_doctor`, and add-insight integration behavior.
- Runtime: server registration for the new doctor tool and updated tool metadata.
- Tests: focused context/search/doctor integration suites plus nearby store, reconciler, and runtime tests.

## Review Log

- Round 1: fixed canonical entity FTS liveness, split FTS storage responsibilities, and split project identity logic.
- Round 2: fixed lowercase `and`/`or`/`not` literal handling, pre-cap mixed source filtering, and doctor implementation split.
- Round 3: split overloaded integration tests into focused context, search, and doctor files with a shared base.
- Round 4: fixed equivalent-project context aggregation across relations/preferences, parent/leaf path alias handling, and entity-type FTS filtering before `LIMIT`.
- Round 5: fixed parent/leaf alias precedence over legacy basename exact project while preserving explicit project precedence.

## Verification

- Targeted final regression: `Context_PrefersParentLeafAliasOverLegacyLeafExact_FromPath` passed.
- Nearby context identity tests: `MemoryContextToolIntegrationTests` passed 19/19.
- Repository build: `dotnet build tools/memory-graph/MemoryGraph.sln` succeeded with 0 warnings/errors.
- Repository full suite: `dotnet test tools/memory-graph/MemoryGraph.sln` passed 167/167.
- Repository format: `dotnet format tools/memory-graph/MemoryGraph.sln --verify-no-changes` passed.
- Repository complexity: `bash ~/.codex/tools/cognitive-complexity/run-complexity.sh --changed` passed.
- Repository diff hygiene: `git diff --check` passed.
- Installed copy updated with `./install.sh --agent codex --no-hooks`.
- Installed copy full suite: `dotnet test /Users/laimis/.codex/tools/memory-graph/MemoryGraph.sln` passed 167/167.
- Installed copy build was rerun sequentially after a transient parallel file lock and passed with 0 warnings/errors.
- Installed copy format verification passed.

## Blockers

None.

## Notes

- The current MCP process may need a restart or a new session to load the installed `memory_doctor` and memory tool changes.

## Follow-up Bugfix: Other-PC Memory Not Found

User reported that after trying the latest changes on another PC, the LLM still could not find memory data.

### Root Causes

1. Memory data is local per machine under `~/.codex/memory`; installing the repository tools does not copy memories. Another PC needs `memory.db` copied from the source machine or a legacy `graph.jsonl` available/imported.
2. `install.sh` skipped already-registered Codex memory-graph MCP config, so stale command, args, and tool approval blocks could remain. The local live config was missing the `memory_doctor` approval before this fix.

### Implemented Fix

- `install.sh` now refreshes an existing Codex `[mcp_servers.memory-graph]` config instead of skipping it.
- The installer preserves unrelated TOML and preserves the existing config file mode, such as `0600`.
- The installer writes current tool approval blocks, including `memory_doctor`, `memory_decide`, `memory_pattern`, `memory_consolidate`, remove tools, and related memory tools.
- `memory_doctor` now emits actionable warnings for an empty local memory store and a missing legacy graph file when no retrievable graph context exists.
- Added a negative doctor test proving a non-empty DB graph with missing `graph.jsonl` does not warn.

### Follow-up Verification

- `bash tests/p0-p4/installer-contracts.sh`: passed 10/10.
- Targeted doctor runtime tests passed 3/3.
- `dotnet build tools/memory-graph/MemoryGraph.sln`: succeeded with 0 warnings/errors.
- `dotnet test tools/memory-graph/MemoryGraph.sln`: passed 169/169.
- `dotnet format tools/memory-graph/MemoryGraph.sln --verify-no-changes`: passed.
- `bash ~/.codex/tools/cognitive-complexity/run-complexity.sh --changed`: passed.
- `git diff --check`, `bash -n install.sh`, and `bash -n tests/p0-p4/installer-contracts.sh`: passed.
- Review loop: round 1 found two should-fix issues; both were fixed. Round 2 was clean with weighted score 4.65.
- Installed local Codex copy updated with `./install.sh --agent codex --no-hooks`.
- Local `~/.codex/config.toml` now includes `[mcp_servers.memory-graph.tools.memory_doctor]` and current memory tool approvals; config mode remains `600`.
- Installed copy build passed.
- Installed copy tests passed 169/169.
- Installed copy format verification passed.

### Other-PC Verification Steps

1. Run `./install.sh --agent codex --no-hooks` on the other PC from the updated repository.
2. Restart Codex or start a new session so the MCP tool list reloads.
3. Confirm `~/.codex/config.toml` contains `memory_doctor` and `args = ["--memory-dir", "<home>/.codex/memory"]`.
4. If memory data should be shared, copy `~/.codex/memory/memory.db` from the source PC to the other PC while Codex and memory-graph are stopped, or provide/import `graph.jsonl`. Without this, memory tools are correctly empty.
5. Use `memory_stats` or `memory_doctor` in the new session; empty-store warnings indicate missing local memory data rather than query failure.
