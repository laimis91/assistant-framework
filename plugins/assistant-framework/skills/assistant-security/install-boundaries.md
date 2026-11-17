# Installer and Filesystem Ownership Boundaries

Load this when the assessed target installs, syncs, rewrites, moves or deletes files that a user or another tool may own.

## Boundary classes

Before trusting any write, check each class:

1. **Managed marker blocks.** Markers are exact full lines, balanced, not nested and not duplicated. Text that merely mentions a marker inside prose is not a marker.
2. **Links.** Symbolic and hard links at the target leaf and at every parent directory. A write through a link changes the link's target, which may be outside the install root.
3. **Shared roots.** A destination directory that also holds unrelated siblings. A sync with deletion, or a recursive copy, can remove or replace files the installer never owned.
4. **Path equality or overlap.** Source and target that are the same path, or where one is an ancestor of the other, including a configured home such as `CODEX_HOME` pointing inside the source tree.
5. **User-owned sentinels.** Files or bytes the installer must leave untouched.

Compare the sibling implementation for the same boundary (for example the Unix installer against the Windows installer). A boundary handled in one and not the other is still open.

## Evidence

- **Preservation** is shown by sentinel bytes that stay byte-identical after the run, and by rejection of an ambiguous input before the first write.
- **A confirmed preservation failure** is shown by changed or missing sentinel bytes, or by a mutation that happens before the input is rejected.
- A claim such as "user files are preserved" without the sentinel and the rejection point is not evidence.

Executing an installer or target script stays within existing authorization. Fixture execution follows assistant-review's fixture rules in [script-execution.md](../assistant-review/references/script-execution.md); diff review of such a script applies assistant-review's user-owned file probe in [review-checklists.md](../assistant-review/references/review-checklists.md) ("High-impact operation guards"). Do not restate either here. Do not claim isolation the host does not enforce: when a disposable home or other isolation the check needs is unavailable, report the item under **Needs validation** with a disposable-fixture plan an owner can run.

## Worked examples

These come from the project audit (F1, F2, F4, F5). They are examples of the method, not repair tasks. Status was checked on main at 7c9bdf8; re-check before relying on it.

- **F1 — marker blocks (fixed).** Since #77 (commit 32fbe01), `install.sh` counts exact marker lines and leaves a file with unbalanced, nested or duplicate markers unchanged. The check that shows it: seed sentinel text around ambiguous markers in a disposable home, run, and confirm the file is byte-identical and the warning fires before any write.
- **F2 — links at non-skill destinations (unrepaired).** Agent definitions and rules files are still copied with plain `cp` into their target directories. A symbolic link at the destination would be followed. Not reproduced; it needs a disposable home with a planted link and a sentinel at the link target.
- **F4 — shared roots (unrepaired).** The shared tool and eval-doc directories under the agent home (`tools/`, `docs/evals/`) are synced with `rsync -a --delete`. A destination that also holds unrelated user files would lose them. Per-skill directories are synced separately, after a link and directory-type check. Not reproduced; seed a sibling sentinel and confirm whether it survives.
- **F5 — source and target overlap (unrepaired).** No check rejects a target equal to, or nested with, the source tree. Not reproduced; set the configured home inside the checkout in a fixture and confirm whether the installer rejects it before the first write.
