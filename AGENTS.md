# AGENTS.md

## Repository

Assistant Framework is a framework repository, not an application. It installs skills, agents, rules, and tools for Claude Code, Codex, and Gemini CLI.

Root `skills/assistant-*` directories are the editable source of truth. Plugin-local skill copies are generated mirrors; refresh them with `tools/plugins/sync-plugin-skills.sh --apply` and verify with `--check`. See `README.md` and `docs/plugin-architecture.md` for architecture and platform details.

## Workflow

- Route requests through installed skill descriptions and follow a matching `SKILL.md`.
- All supported agents use their native skill discovery and routing. Workflow discipline comes from skill contracts, evals, project instructions, and review rather than lifecycle scripts.
- Keep work proportional to risk. Plan medium or larger changes before implementation, add tests with behavior changes, run relevant verification, and review before completion.
- Preserve unrelated user changes. Avoid destructive Git operations and never hardcode secrets or log PII.

When creating or modifying skills, read `docs/skill-contract-design-guide.md`. Contracts must follow that guide; do not duplicate its rules here.

## Commands

```bash
# Install with native skill routing
./install.sh --agent codex
./install.sh --agent codex --skill assistant-workflow
./install.sh --agent codex --dry-run

# Skills and generated plugin mirrors
tools/skills/validate-skills.sh
tools/plugins/sync-plugin-skills.sh --check
tools/plugins/sync-plugin-skills.sh --apply

# Contract suites
./tests/test-p0-p4-contracts.sh

# Memory Graph (.NET 8)
dotnet build tools/memory-graph/src/MemoryGraph/MemoryGraph.csproj --tl:on -v:minimal
dotnet test tools/memory-graph/tests/MemoryGraph.Tests/MemoryGraph.Tests.csproj --tl:on -v:minimal

# Cognitive complexity tool
dotnet build tools/cognitive-complexity/CognitiveComplexity.csproj --tl:on -v:minimal
```

Codex execution policies live in `codex-rules/`; do not weaken permission prompts or destructive-operation safeguards. C# code targets modern .NET and follows the existing Clean Architecture style. Tests use descriptive names and Arrange-Act-Assert where applicable.
