# Gemini Agent Definitions

Gemini CLI agent definitions are not yet implemented.

Claude uses `.md` files and Codex uses `.toml` files for agent role definitions.
When Gemini CLI supports custom agent definitions, add equivalent files here
and update `install.sh` with a Gemini agent installation block (matching the
Claude/Codex patterns at lines ~389-435).

The following roles should be created:
- explorer — Deep codebase analyst (read-only)
- code-mapper — Lightweight structure mapping (read-only)
- architect — Implementation blueprint design (read-only)
- code-writer — Focused code implementation (write access)
- builder-tester — Build and test automation (write access)
- reviewer — Independent code review (read-only)
