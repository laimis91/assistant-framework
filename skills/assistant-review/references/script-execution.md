# Executing a changed script during review

Default: review scripts statically. Audit stays read-only, so it stays static. Reviewer
passes never execute; the orchestrator runs any execution. This reference states the
user-approved exception to "installs retain explicit approval" in `SKILL.md` for fixture
runs only; everything else keeps that approval.

Run a changed script without further approval only when all hold:

- The script stays within the write targets it had before the change. A new directory or
  file target needs approval.
- It runs inside a throwaway fixture. Before running, list every environment variable and
  path the script reads, and block if any path source cannot be overridden. Override at
  least `HOME`, `CODEX_HOME`, `USERPROFILE`, `APPDATA`, `LOCALAPPDATA`, `XDG_*`,
  `DOTNET_CLI_HOME`, `NUGET_*`, `TMPDIR`, `TEMP`, `TMP`; keep `PATH` as is.
- Every write the script makes resolves inside the fixture, and it performs no network,
  package-install, elevation, scheduler, keychain or system-service action; otherwise it
  needs approval. A hard-coded absolute write target is not redirected by environment
  variables, so treat it as outside the fixture.
- It runs a copy of the whole repository tree from inside the fixture, with the working
  directory and temp variables in the fixture, so script-relative or relative writes
  cannot reach the real checkout.
- Inputs are disposable. Record a baseline, clean up, and compare hashes of the originals
  before and after; hashes detect damage, they do not prevent it.
- The extra-testing rule applies: name a distinct important uncovered failure and why
  existing evidence is inadequate, and respect any carried reduced-testing boundary.

Anything touching real user paths needs explicit approval. A discovery run succeeds by
failing, so it cannot be recorded as passing build/test evidence; report it as an
orchestrator-run probe until a typed evidence slot exists. In workflow-composed review,
follow the composing workflow's verification selection.
