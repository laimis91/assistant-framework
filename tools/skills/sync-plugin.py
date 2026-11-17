#!/usr/bin/env python3
"""Build or check the marketplace plugin in plugins/assistant-framework/.

Usage: sync-plugin.py --apply|--check

The editable source stays skills/. --apply copies every skill (without its
evals/ folder) into the plugin and writes both manifests with the version from
version.txt. --check fails on any drift, on a marketplace file that disagrees,
on a plugin skill with no source, or on an agents/, hooks/ or commands/ folder.
"""
import filecmp
import json
import os
import shutil
import sys
from pathlib import Path

REPO = Path(os.environ.get("SYNC_PLUGIN_REPO_ROOT", Path(__file__).resolve().parents[2]))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import plugin_manifest  # noqa: E402

PLUGIN_NAME = "assistant-framework"
MARKETPLACE_NAME = "assistant-framework"
PLUGIN_SOURCE = "./plugins/assistant-framework"
DESCRIPTION = (
    "Assistant Framework skills: workflow, review, verification, TDD, debugging, "
    "research, security and more, for Claude Code and Codex."
)
EXCLUDED_NAMES = {"evals", ".DS_Store", "__pycache__"}

SKILLS = REPO / "skills"
PLUGIN = REPO / "plugins" / PLUGIN_NAME
CLAUDE_MARKETPLACE = REPO / ".claude-plugin" / "marketplace.json"
CODEX_MARKETPLACE = REPO / ".agents" / "plugins" / "marketplace.json"


def version():
    return (REPO / "version.txt").read_text(encoding="utf-8").strip()


def shipped_skills():
    return sorted(p.parent.name for p in SKILLS.glob("*/SKILL.md"))


def ignore(_directory, names):
    return [n for n in names if n in EXCLUDED_NAMES or n.endswith(".pyc")]


def expected_files(skill):
    root = SKILLS / skill
    files = []
    for directory, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in EXCLUDED_NAMES)
        for name in sorted(filenames):
            if name in EXCLUDED_NAMES or name.endswith(".pyc"):
                continue
            files.append((Path(directory) / name).relative_to(root))
    return files


def actual_files(root):
    files = []
    for directory, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(dirnames)
        for name in sorted(filenames):
            files.append((Path(directory) / name).relative_to(root))
    return files


def claude_marketplace():
    return {
        "name": MARKETPLACE_NAME,
        "description": "Assistant Framework skills for Claude Code.",
        "owner": {"name": "laimis91"},
        "plugins": [{"name": PLUGIN_NAME, "source": PLUGIN_SOURCE, "description": DESCRIPTION}],
    }


def codex_marketplace():
    return {
        "name": MARKETPLACE_NAME,
        "interface": {"displayName": "Assistant Framework"},
        "plugins": [{
            "name": PLUGIN_NAME,
            "source": {"source": "local", "path": PLUGIN_SOURCE},
            "policy": {"installation": "AVAILABLE", "authentication": "ON_INSTALL"},
            "category": "Productivity",
        }],
    }


def apply():
    if PLUGIN.exists():
        shutil.rmtree(PLUGIN)
    for skill in shipped_skills():
        shutil.copytree(SKILLS / skill, PLUGIN / "skills" / skill, ignore=ignore, symlinks=False)
    plugin_manifest.write_manifests(PLUGIN, PLUGIN_NAME, version(), DESCRIPTION)
    for path, payload in ((CLAUDE_MARKETPLACE, claude_marketplace()), (CODEX_MARKETPLACE, codex_marketplace())):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(plugin_manifest.render(payload), encoding="utf-8")
    print(f"synced {len(shipped_skills())} skills into {PLUGIN.relative_to(REPO)} at version {version()}")


def check():
    problems = []
    plugin_skills = PLUGIN / "skills"
    present = sorted(p.name for p in plugin_skills.iterdir() if p.is_dir()) if plugin_skills.is_dir() else []
    for skill in sorted(set(present) - set(shipped_skills())):
        problems.append(f"plugin has a skill with no source: {skill}")
    for skill in shipped_skills():
        target = plugin_skills / skill
        if not target.is_dir():
            problems.append(f"missing skill copy: {skill}")
            continue
        want, have = expected_files(skill), actual_files(target)
        for rel in sorted(set(want) ^ set(have)):
            problems.append(f"{skill}/{rel} {'missing from' if rel in want else 'extra in'} the plugin")
        for rel in sorted(set(want) & set(have)):
            if not filecmp.cmp(SKILLS / skill / rel, target / rel, shallow=False):
                problems.append(f"{skill}/{rel} differs from skills/")
    for relative, payload in plugin_manifest.manifest_payloads(PLUGIN_NAME, version(), DESCRIPTION).items():
        path = PLUGIN / relative
        if not path.is_file() or json.loads(path.read_text(encoding="utf-8")) != payload:
            problems.append(f"manifest {relative} is missing or differs (version {version()})")
    for path, payload in ((CLAUDE_MARKETPLACE, claude_marketplace()), (CODEX_MARKETPLACE, codex_marketplace())):
        if not path.is_file() or json.loads(path.read_text(encoding="utf-8")) != payload:
            problems.append(f"marketplace {path.relative_to(REPO)} is missing or differs")
    extra_components = [n for n in ("agents", "hooks", "commands") if (PLUGIN / n).exists()]
    for name in extra_components:
        problems.append(f"plugin must not carry a {name}/ folder")
    if problems:
        print("\n".join(problems), file=sys.stderr)
        print("Error: plugin is out of date; run tools/skills/sync-plugin.py --apply", file=sys.stderr)
        return 1
    print(f"plugin matches skills/ ({len(shipped_skills())} skills, version {version()})")
    return 0


def main(argv):
    if argv[1:] == ["--apply"]:
        apply()
        return 0
    if argv[1:] == ["--check"]:
        return check()
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
