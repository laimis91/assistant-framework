# Context Map

Status: VERIFIED
Scope: Memory-graph retrieval, diagnostics, identity resolution, search semantics, installer config refresh, and local memory-store diagnosis improvement batch.

## Architecture Map

- Graph resolver/reconciler: `KnowledgeGraphQueries`, `MemoryGraphReconciler`, `ProjectIdentityMetadata`, `ProjectIdentityResolver`, `ProjectIdentityEquivalence`, and `ProjectResolution` own project lookup, canonical identity, aliases, path metadata, equivalent-project inclusion, and canonical entity FTS liveness.
- Storage/FTS: `MemoryStore`, `MemoryStore.Fts`, and `Models` own persisted graph access, FTS storage/query behavior, non-mutating search results, stale/non-canonical filtering, diagnostics data, and source/entity filter ordering before caps.
- Tools: `MemoryContextTool`, `MemorySearchTool`, `MemoryDoctorTool.*`, and `MemoryAddInsightTool` expose explainable context resolution, corrected search semantics, read-only diagnostics, and insight/project linkage behavior.
- Runtime: `MemoryGraphRuntime` registers the updated memory tools, including the new read-only doctor capability.
- Installer: `install.sh` refreshes existing Codex memory-graph MCP config blocks, preserves unrelated TOML and config file mode, and writes the current memory tool approval set.
- Tests: focused context, search, doctor, reconciler, store, runtime, and shared integration base coverage verifies behavior at tool and storage boundaries.

## Changed File / Component Manifest

| Component | Files | Verification Criteria | Status |
|---|---|---|---|
| Graph resolver/reconciler | `tools/memory-graph/src/MemoryGraph/Graph/KnowledgeGraphQueries.cs`; `MemoryGraphReconciler.cs`; `ProjectIdentityEquivalence.cs`; `ProjectIdentityMetadata.cs`; `ProjectIdentityResolver.cs`; `ProjectResolution.cs` | Identity resolution handles explicit project precedence, aliases, parent/leaf path candidates, equivalent projects, and canonical FTS liveness. | VERIFIED |
| Storage/FTS | `tools/memory-graph/src/MemoryGraph/Storage/MemoryStore.cs`; `MemoryStore.Fts.cs`; `Models.cs` | Search no longer prunes FTS rows; stale/non-canonical rows are filtered from results; source/entity filters run before FTS caps and `LIMIT`. | VERIFIED |
| Tools | `tools/memory-graph/src/MemoryGraph/Tools/MemoryContextTool.cs`; `MemorySearchTool.cs`; `MemoryDoctorTool.cs`; `MemoryDoctorTool.FtsDiagnostics.cs`; `MemoryDoctorTool.ProjectDiagnostics.cs`; `MemoryDoctorTool.RelationDiagnostics.cs`; `MemoryDoctorTool.RuntimeDiagnostics.cs`; `MemoryAddInsightTool.cs` | Context explainability fields are additive; doctor is read-only; search honors uppercase boolean operators and lowercase literal terms. | VERIFIED |
| Runtime | `tools/memory-graph/src/MemoryGraph/Server/MemoryGraphRuntime.cs` | Runtime advertises and dispatches updated memory tools, including `memory_doctor`. | VERIFIED |
| Installer config refresh | `install.sh`; `tests/p0-p4/installer-contracts.sh` | Existing Codex `[mcp_servers.memory-graph]` entries are refreshed instead of skipped; unrelated TOML and file mode are preserved; current memory tool approvals are written, including `memory_doctor`. | VERIFIED |
| Doctor empty-store diagnosis | `tools/memory-graph/src/MemoryGraph/Tools/MemoryDoctorTool.*`; `tools/memory-graph/tests/MemoryGraph.Tests/MemoryDoctorToolIntegrationTests.cs`; `tools/memory-graph/tests/MemoryGraph.Tests/MemoryGraphRuntimeTests.cs` | Doctor emits actionable warnings when the local DB has no retrievable graph context and legacy `graph.jsonl` is missing, but does not warn when a non-empty DB graph exists without `graph.jsonl`. | VERIFIED |
| Tests | `tools/memory-graph/tests/MemoryGraph.Tests/MemoryContextToolIntegrationTests.cs`; `MemorySearchToolIntegrationTests.cs`; `MemoryDoctorToolIntegrationTests.cs`; `ToolIntegrationTestBase.cs`; `MemoryGraphReconcilerTests.cs`; `MemoryGraphRuntimeTests.cs`; `MemoryStoreTests.cs`; `ToolIntegrationTests.cs` | Focused regression suites cover context identity, search semantics, doctor diagnostics, store behavior, reconciler behavior, and runtime registration. | VERIFIED |

## Verification Record

- Repository targeted regression passed: `Context_PrefersParentLeafAliasOverLegacyLeafExact_FromPath`.
- Repository nearby context suite passed: `MemoryContextToolIntegrationTests` 19/19.
- Repository solution build passed with 0 warnings/errors.
- Repository full test suite passed 169/169 after the follow-up bugfix.
- Repository format, complexity, and diff hygiene checks passed.
- Installer contracts passed 10/10.
- Targeted doctor runtime tests passed 3/3.
- Shell syntax checks passed for `install.sh` and `tests/p0-p4/installer-contracts.sh`.
- Review loop completed: round 1 found two should-fix issues, both fixed; round 2 clean with weighted score 4.65.
- Installed Codex tool copy was updated with `./install.sh --agent codex --no-hooks` and verified with build, format, and full test suite 169/169.
- Local `~/.codex/config.toml` contains the refreshed memory-graph tool approvals, including `[mcp_servers.memory-graph.tools.memory_doctor]`, and retained mode `600`.

## Other-PC Verification Map

1. Run `./install.sh --agent codex --no-hooks` from the updated repository on the other PC.
2. Restart Codex or open a new session so MCP tool definitions reload.
3. Verify `~/.codex/config.toml` includes `memory_doctor` and `args = ["--memory-dir", "<home>/.codex/memory"]`.
4. Copy `~/.codex/memory/memory.db` from the source PC while Codex and memory-graph are stopped, or provide/import legacy `graph.jsonl`, when memories should be shared across machines.
5. Run `memory_stats` or `memory_doctor`; empty-store warnings mean the other PC has no local memory data, not that memory queries failed.
