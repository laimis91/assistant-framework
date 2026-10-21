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
- logical CodeWriter — Selected tests plus implementation; use supported native/default routing until custom definitions exist
- logical Builder/Tester — Execution-only selected checks; writes designated generated outputs/evidence logs, with authored fixes returned to the same writer
- reviewer — Independent code review (read-only)
- lens-researcher — Independent frozen five-lens evidence collection (read-only)
- research-peer-reviewer — Independent five-lens synthesis critique (read-only)

Current fallback follows shared writer_selection judgment and worker_stage ownership: the selected native writer authors tests, fixtures, snapshots, helpers and test/build configuration, then production/refactor subject to RED/GREEN gates. Do not invent custom Gemini role names or model overrides.

The actual native/default writer also retains explicit reduced-testing scope/source,
rationale/exclusions, omissions and stop rule. Reuse adequate coverage; additions
need a distinct important uncovered failure and inadequate-existing-evidence
rationale. Use workflow Build reuse-first ordering with complete consumers/error
paths. Classify expectations before repair; incidental assertions do not justify
production changes. Preserve controlling checks, selected meaningful TDD and
shared three-consecutive-unproductive-cycle guard across tests, checks, workers
and sessions. Material expansion returns to selection/approval.

For unmatched work, explicitly read `~/.gemini/tools/progress/operating-guidance.md` as the operating guidance for this chat, then handle the request. Standing coverage requires the user's existing native instruction source; installation alone does not demonstrate activation.
