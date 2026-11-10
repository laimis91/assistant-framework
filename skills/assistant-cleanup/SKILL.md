---
name: assistant-cleanup
description: "Remove retired or legacy Assistant Framework skills, agents, hooks and tools from an installed agent home after an update, or give the framework's uninstall command."
---

# Framework Cleanup

## Shared operating guidance

Load [the common outcome guidance and shared stagnation policy](../../tools/progress/operating-guidance.md) for this activity. Keep specialist methods, authority and completion evidence below; single-pass work needs no progress artifact.


Remove Assistant Framework items that an update retired from one installed agent home, using only the installed ownership helper. The helper proves each item is framework-owned before it can be removed; you never decide that yourself. This skill is not for code cleanup, dead code, refactoring, deleting project files, or removing other software.

## Resolve the agent and home

Work on one agent: `claude`, `codex` or `gemini`. Take it from the request or from the agent you are running in; ask when it is unclear. The helper resolves the home: `~/.claude`, `~/.gemini`, or for Codex `CODEX_HOME` when it is set and `~/.codex` otherwise. Never assume `~/.codex`.

The helper lives in the home at `tools/framework-ownership/`. Run it with the agent home as the working directory, set through the host's working-directory option. A host without one changes directory in a separate preceding command, never `cd … &&`. If the helper is missing, tell the user to update the framework with its installer first, and stop.

On Windows, Codex must not be running while its home is checked or changed. When you are Codex on Windows, ask the user to close Codex and run the helper from a terminal, and give them the commands below.

## Uninstall requests

A request to uninstall the framework itself is answered with the command only. Run nothing. The installed skill cannot know where the user's framework checkout is, so give two separate steps and ask the user to replace the placeholder:

1. `cd <path-to-your-framework-checkout>`
2. `./uninstall.sh --agent <agent>` (on Windows: `pwsh -NoProfile -File uninstall.ps1 -Agent <agent>`, or with Windows PowerShell 5.1 only: `powershell -NoProfile -File uninstall.ps1 -Agent <agent>`)

Put the user's agent in place of `<agent>`. Say that uninstall prints its full plan and digest first and asks them to type the agent name before it removes anything, and that `--dry-run` (`-DryRun` on Windows) shows the plan without changing anything. Never put the placeholder path in front of the script name and never join the steps with `&&`.

## Clean up retired items

1. **Dry run first, always.** Choose a manifest file path that does not exist yet, outside every agent home (for example in the system temporary directory), and run:
   - `python3 tools/framework-ownership/ownership.py dry-run --agent <agent> --manifest-out <manifest-file>`
   - on Windows: `pwsh -NoProfile -File tools/framework-ownership/ownership.ps1 dry-run -Agent <agent> -ManifestOut <manifest-file>`; with Windows PowerShell 5.1 only, the same with `powershell` in place of `pwsh`
2. **Show the plan.** List the items to remove, the items kept as ambiguous with their reasons, and the items kept as unrelated. Give paths only, never file contents. Show the manifest digest. When nothing is removable, say so and stop.
3. **Wait for confirmation of that exact digest.** Remove only after the user confirms the digest you showed, in chat. "Show me first", "what would it remove" or a general go-ahead given before they saw the plan is not confirmation. If they ask for changes to the plan, explain that the helper decides ownership; items kept as ambiguous are theirs to inspect and remove by hand.
4. **Apply in the fixed form only**, with the same working directory:
   - `python3 tools/framework-ownership/ownership.py apply --agent <agent> --manifest <manifest-file> --manifest-digest <digest> --yes`
   - on Windows: `pwsh -NoProfile -File tools/framework-ownership/ownership.ps1 apply -Agent <agent> -Manifest <manifest-file> -ManifestDigest <digest> -Yes`
   - with Windows PowerShell 5.1 only: `powershell -NoProfile -File tools/framework-ownership/ownership.ps1 apply -Agent <agent> -Manifest <manifest-file> -ManifestDigest <digest> -Yes`

   The helper re-proves every item before it deletes it and refuses when the home changed since the dry run. On a refusal, report it and start again from step 1; never retry with different arguments.
5. **Report the outcome**: removed, kept as ambiguous and kept as unrelated, paths only. Then run the dry run again and show that nothing is left to remove except items kept as ambiguous.

## Boundaries

- Never compose deletion commands (`rm`, `Remove-Item`, `del`, `rmdir`, file-manager actions or scripts) for framework items, even when the user asks you to. Removal goes through the helper or the user's own hands.
- Never call the checkout-only entry point, and never run the installer or uninstall for the user.
- Never edit the inventory, the generated proof data, the manifest file or settings files to make an item removable.
- Host permission prompts and Codex rules stay in force; do not look for ways around them.
- Exit status 2 means the helper refused and changed nothing; 3 means it finished and kept some items. Report both plainly.
