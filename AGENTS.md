# AGENTS.md

## Repository

Assistant Framework is a framework repository, not an application. It installs skills, agents, rules, and tools for Claude Code, Codex, and Gemini CLI.

Root `skills/assistant-*` directories are the editable source of truth. Plugin-local skill copies are generated mirrors. See `README.md` and `docs/plugin-architecture.md` for architecture and platform details.

## Workflow

- Keep behavior-driving skill prose, contracts, evals, tests, and documentation aligned.
- Before changing skills, read `docs/skill-contract-design-guide.md`; keep detailed contract rules there.
- Run focused checks first, then the aggregate verification appropriate to the changed surface.

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

# Cognitive complexity tool
dotnet build tools/cognitive-complexity/CognitiveComplexity.csproj --tl:on -v:minimal
```

Codex execution policies live in `codex-rules/`; do not weaken permission prompts or destructive-operation safeguards. C# code targets modern .NET and follows the existing Clean Architecture style. Tests use descriptive names and Arrange-Act-Assert where applicable.
