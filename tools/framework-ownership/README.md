# Framework ownership

This directory proves which files in an agent home the Assistant Framework installed, so that cleanup, uninstall and the installers remove only those. Requirements live in [S11 cleanup and uninstall](../../docs/specs/framework-value-improvements/S11-cleanup-and-uninstall.md); user commands are in the repository [README](../../README.md#uninstall-and-legacy-cleanup).

## Files

| File | Role | Installed into agent homes |
|---|---|---|
| `retired-items.json` | Inventory of every retired framework item (schema `1.0`) | yes |
| `content-proof.json` | Generated fingerprints for inventory entries | yes |
| `installer-exact-removal.tsv` | Generated retired tool and hook list for `install.sh` when Python is missing | yes |
| `ownership.py` | Unix helper: `dry-run`, `apply`, `list-retired`, `validate`; standard library only | yes |
| `ownership.ps1`, `ownership-core.ps1` | Windows helper with the same commands, and its proof library | yes |
| `installer-primitives.ps1` | Generated from `install.ps1`: path, reparse, atomic-write and JSON-identity functions the Windows helper reuses | yes |
| `ownership-checkout.py`, `ownership-checkout.ps1` | Checkout-only entry points: installer mode, uninstall, data generation | **no** |

The checkout-only entry points refuse to run outside a Git checkout that holds `install.sh` and `install.ps1`, from inside any agent home or `~/.agents` root,; `build-data` and `uninstall` also refuse a shallow clone. Installer mode runs in one, where missing history can only make fewer items provable. Both installers exclude them from the tools sync.

## Proof rules

An item is removable only when all of these hold:

- its name matches the inventory exactly (case and Unicode variants are ambiguous);
- neither it nor any ancestor up to the home is a link, junction or reparse point, and no file has more than one hard link;
- every file under it matches a fingerprint of framework content. Fingerprints are SHA-256 over the file bytes after replacing `{agent_state_dir}` in `.md`, `.yaml`, `.yml`, `.json`, `.conf` and `.toml` files and normalizing CRLF to LF in every file that has no NUL byte. Hook entrypoints also match the inert shim bytes;
- a directory holds nothing outside its fingerprints. For uninstall, build output in current tool directories (`bin`, `obj`, `.publish`, `__pycache__`, `*.pyc`) also counts as owned;
- a settings registration's first command token is exactly a known retired entrypoint path, and an instruction block is exactly one balanced marker pair.

Anything else is kept and reported as ambiguous with its reason, or as unrelated when nothing framework-like is there. Exit status: 0 done, 1 internal error, 2 refused with nothing changed, 3 finished with items kept.

## Commands

The installed helper runs with the agent home as the working directory:

```bash
python3 tools/framework-ownership/ownership.py dry-run --agent claude --manifest-out /tmp/framework-cleanup.json
python3 tools/framework-ownership/ownership.py apply --agent claude --manifest /tmp/framework-cleanup.json --manifest-digest <digest> --yes
python3 tools/framework-ownership/ownership.py list-retired --layout unix
python3 tools/framework-ownership/ownership.py validate
```

`dry-run` writes the manifest to a new file outside every agent home and prints the plan and the manifest digest (SHA-256 of the canonical JSON: sorted keys, compact separators, UTF-8). `apply` refuses unless the manifest and its digest match this agent, home and inventory; it then re-proves each item just before deleting it and skips, with a reason, any item that changed since the dry run, and removes only listed items: registrations, then instruction blocks, then files and directories deepest first, then emptied directories. Without `--yes` it asks you to type the agent name.

From a checkout:

```bash
python3 tools/framework-ownership/ownership-checkout.py build-data --check
python3 tools/framework-ownership/ownership-checkout.py install --agent claude --dry-run
python3 tools/framework-ownership/ownership-checkout.py uninstall --agent claude --dry-run
```

`install` is the installers' retired-item step: it removes only retired skill directories and agent files, takes no manifest, and never fails the install. `uninstall` covers retired items and the current install, deriving current-item fingerprints from the checkout's history at run time. Use `uninstall.sh` or `uninstall.ps1` rather than calling it directly.

## Retire an item

1. Delete the item from the source in its own commit, or in a change that only deletes it.
2. Add an entry to `retired-items.json`: a unique lowercase `id`, `kind`, `root` (`agent_home`, `agents_skills` or `agents_tools`), `path` relative to that root, `node_type`, `agents`, `layouts`, `source_path`, `retired_in` (the last commit on the main branch whose tree still holds `source_path`; for a deletion made in the current change, the main commit the change branches from), `content_proof` naming its fingerprint key, and a `note` on how the installers placed it. Never add `installer_exact_removal`: only the seeded tool entries may carry it, so proof-free installer removal never grows. For example, a retired skill `skills/assistant-example`:

   ```json
   {"id": "skill/assistant-example", "kind": "skill_directory", "root": "agent_home",
    "path": "skills/assistant-example", "node_type": "directory",
    "agents": ["claude", "codex", "gemini"], "layouts": ["unix"],
    "source_path": "skills/assistant-example", "retired_in": "<commit>",
    "content_proof": "skill/assistant-example", "note": "Installed by both installers into <agent home>/skills."}
   ```

3. Regenerate and check the data, then commit it with the inventory:

   ```bash
   python3 tools/framework-ownership/ownership-checkout.py build-data
   python3 tools/framework-ownership/ownership-checkout.py build-data --check
   ```

   On Windows, also regenerate `installer-primitives.ps1` after changing any function it extracts from `install.ps1`: `pwsh -NoProfile -File tools/framework-ownership/ownership-checkout.ps1 build-primitives`.

`build-data --check` fails when the data is stale, when an entry's `retired_in` is not where the path was deleted, when an entry seeded in the first inventory was changed in any field, or when an entry other than the seeded tool entries sets `installer_exact_removal`.

## Tests

```bash
python3 -B tests/framework-ownership/test_ownership.py
bash tests/p0-p4/framework-ownership-contracts.sh
```

On Windows: `.\tests\windows\framework-ownership-contracts.ps1`. Every destructive case runs against a disposable home and a temporary clone.
