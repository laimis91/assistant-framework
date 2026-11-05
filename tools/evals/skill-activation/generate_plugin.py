#!/usr/bin/env python3
"""Wrap this repository's installer output as a plugin for `claude plugin eval`.

The installer runs under a throwaway HOME with a minimal environment, so nothing
is written to a real agent home. Output must stay in ignored local state.

Usage: generate_plugin.py --output .codex/skill-activation/plugins/NAME
                          [--guidance-file FILE] [--stubs 40] [--descriptions FILE]
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
ALLOWED_OUTPUT_ROOT = REPO / ".codex" / "skill-activation" / "plugins"
PLUGIN_NAME = "af"
MANIFEST = "generation.json"
MAX_DESCRIPTION = 1024
STUB_TOPICS = [
    "invoices", "calendars", "spreadsheets", "slide decks", "chat exports", "podcasts",
    "recipes", "travel plans", "resumes", "press releases", "contracts", "budgets",
    "newsletters", "meeting notes", "survey data", "maps", "photos", "audio clips",
    "video captions", "tax forms", "lab reports", "floor plans", "menus", "lesson plans",
    "grant proposals", "event schedules", "inventory lists", "shipping labels",
    "insurance claims", "customer tickets", "sales quotes", "job postings", "legal memos",
    "brand guidelines", "wiki pages", "flash cards", "poems", "song lyrics",
    "weather data", "fitness logs",
]


def checked_output(path, allowed_root=ALLOWED_OUTPUT_ROOT):
    """Refuse any target that is not a generated plugin, because the target gets replaced."""
    output = Path(path).resolve()
    root = allowed_root.resolve()
    if root not in output.parents:
        raise ValueError(f"output must be inside {root}: {output}")
    if output.exists() and not (output / MANIFEST).is_file():
        raise ValueError(f"refusing to replace a directory that is not a generated plugin: {output}")
    return output


def skills_guidance(claude_md):
    """Return the installed Skills section, the text R-RUN-12 delivers through a hook."""
    match = re.search(r"^## Skills\n(.*?)(?=^## |\Z)", claude_md, re.MULTILINE | re.DOTALL)
    if not match or not match.group(1).strip():
        raise ValueError("installed CLAUDE.md has no Skills section")
    return match.group(1).strip()


def stub_skill(index, topic):
    return (f'---\nname: stub-{index:02d}\ndescription: "Formats and summarizes {topic}. Use when the user supplies '
            f'{topic} and asks for a cleaned-up summary or a standard layout."\n---\n\nFormat the {topic} as asked.\n')


def install_into(home):
    environment = {"HOME": str(home), "PATH": os.environ.get("PATH", "/usr/bin:/bin"), "TMPDIR": tempfile.gettempdir()}
    subprocess.run(["bash", str(REPO / "install.sh"), "--agent", "claude"], cwd=REPO, env=environment, check=True,
                   stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL)


def apply_descriptions(skills_dir, descriptions):
    """Replace frontmatter descriptions in the generated copy only, so candidates never touch skills/. Return the names that changed."""
    changed = []
    for name, description in descriptions.items():
        path = Path(skills_dir) / name / "SKILL.md"
        if not re.fullmatch(r"assistant-[a-z0-9-]+", name) or not path.is_file():
            raise ValueError(f"not a first-class skill: {name}")
        if not description.strip() or "\n" in description or len(description) > MAX_DESCRIPTION:
            raise ValueError(f"description must be one line of 1 to {MAX_DESCRIPTION} characters: {name}")
        text = path.read_text(encoding="utf-8")
        frontmatter = text.split("---", 2)[1]
        found = re.findall(r"^description:[ \t]*(.*)$", frontmatter, re.MULTILINE)
        if len(found) != 1 or not found[0].strip() or found[0].strip()[0] in ">|":
            raise ValueError(f"expected one single-line description: {name}")
        line = "description: " + json.dumps(description, ensure_ascii=False)
        if found[0].strip() != line.removeprefix("description: "):
            changed.append(name)
        path.write_text(re.sub(r"^description:.*$", lambda _: line, text, count=1, flags=re.MULTILINE), encoding="utf-8")
    return sorted(changed)


def description_hash(skills_dir):
    digest = hashlib.sha256()
    for skill in sorted(skills_dir.glob("assistant-*/SKILL.md")):
        match = re.search(r"^description:\s*(.*)$", skill.read_text(encoding="utf-8"), re.MULTILINE)
        digest.update(f"{skill.parent.name}\0{match.group(1) if match else ''}\n".encode())
    return digest.hexdigest()


def tree_hash(root):
    """Hash the packaged files, since the installer copies uncommitted work too."""
    digest = hashlib.sha256()
    for path in sorted(item for item in root.rglob("*") if item.is_file() and item != root / MANIFEST and root / "evals" not in item.parents):
        digest.update(f"{path.relative_to(root).as_posix()}\0".encode())
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def source_state():
    commit = subprocess.run(["git", "rev-parse", "HEAD"], cwd=REPO, capture_output=True, text=True, check=True)
    status = subprocess.run(["git", "status", "--porcelain"], cwd=REPO, capture_output=True, text=True, check=True)
    return commit.stdout.strip(), bool(status.stdout.strip())


def generate(output_path, guidance_override=None, stubs=0, allowed_root=ALLOWED_OUTPUT_ROOT, descriptions=None):
    output = checked_output(output_path, allowed_root)
    if stubs not in (0, len(STUB_TOPICS)):
        raise ValueError(f"stubs must be 0 (isolated) or {len(STUB_TOPICS)} (crowded), as R-RUN-3 defines them")
    if guidance_override is not None and not guidance_override.strip():
        raise ValueError("the guidance override is empty")
    output.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=".staging-", dir=output.parent))
    try:
        manifest = _build(staging, guidance_override, stubs, descriptions or {})
        if output.exists():
            shutil.rmtree(output)
        staging.rename(output)
    except BaseException:
        shutil.rmtree(staging, ignore_errors=True)
        raise
    return manifest


def _build(output, guidance_override, stubs, descriptions):
    with tempfile.TemporaryDirectory(prefix="skill-activation-home-") as home_name:
        home = Path(home_name)
        install_into(home)
        installed = home / ".claude"
        guidance = guidance_override if guidance_override is not None else skills_guidance(
            (installed / "CLAUDE.md").read_text(encoding="utf-8"))
        (output / ".claude-plugin").mkdir(parents=True)
        shutil.copytree(installed / "skills", output / "skills", symlinks=False)
        shutil.copytree(installed / "tools" / "progress", output / "tools" / "progress", symlinks=False)

    changed = apply_descriptions(output / "skills", descriptions)
    (output / ".claude-plugin" / "plugin.json").write_text(json.dumps({"name": PLUGIN_NAME, "version": "0.0.0"}))
    hooks = output / "hooks"
    hooks.mkdir()
    (hooks / "session-context.json").write_text(json.dumps(
        {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": guidance}}))
    (hooks / "hooks.json").write_text(json.dumps({"hooks": {"SessionStart": [{"hooks": [
        {"type": "command", "command": 'cat "${CLAUDE_PLUGIN_ROOT}/hooks/session-context.json"'}]}]}}))
    description_digest = description_hash(output / "skills")
    for index, topic in enumerate(STUB_TOPICS[:stubs]):
        stub = output / "skills" / f"stub-{index:02d}"
        stub.mkdir()
        (stub / "SKILL.md").write_text(stub_skill(index, topic))
    commit, dirty = source_state()
    manifest = {
        "source_commit": commit,
        "source_dirty": dirty,
        "tree_sha256": tree_hash(output),
        "description_sha256": description_digest,
        "guidance_sha256": hashlib.sha256(guidance.encode()).hexdigest(),
        "listing_condition": "crowded" if stubs else "isolated",
        "stubs": stubs,
        "changed_descriptions": changed,
    }
    (output / MANIFEST).write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    parser.add_argument("--guidance-file")
    parser.add_argument("--stubs", type=int, default=0)
    parser.add_argument("--descriptions")
    args = parser.parse_args()
    override = Path(args.guidance_file).read_text(encoding="utf-8") if args.guidance_file else None
    descriptions = json.loads(Path(args.descriptions).read_text(encoding="utf-8")) if args.descriptions else None
    json.dump(generate(args.output, override, args.stubs, descriptions=descriptions), sys.stdout, indent=2)
    print()


if __name__ == "__main__":
    main()
