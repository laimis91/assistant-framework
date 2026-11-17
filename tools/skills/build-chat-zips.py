#!/usr/bin/env python3
"""Build upload ZIPs of the chat-suitable skills for Claude chat (Customize -> Skills).

Usage: build-chat-zips.py [--check] [--out DIR] [skill ...]

Each ZIP holds one top-level <skill>/ folder copied from skills/, without evals/.
The build fails for a skill outside CHAT_SKILLS, a skill that declares `requires`,
a Markdown link that leaves the skill folder, or frontmatter over the limits
below. --check validates without writing. The default output is dist/chat-skills/.
"""
import os
import re
import sys
import zipfile
from pathlib import Path

REPO = Path(os.environ.get("CHAT_ZIPS_REPO_ROOT", Path(__file__).resolve().parents[2]))
CHAT_SKILLS = ("assistant-clarify", "assistant-research", "assistant-thinking")
# Agent Skills limits as understood on 2026-11-17; recheck against Anthropic's help when uploading.
NAME_PATTERN = re.compile(r"^[a-z0-9-]{1,64}$")
MAX_DESCRIPTION = 1024
EXCLUDED_NAMES = {"evals", ".DS_Store", "__pycache__"}
LINK = re.compile(r"\]\(([^)\s]+)\)")


def frontmatter(text):
    if not text.startswith("---\n"):
        return {}, False
    end = text.find("\n---", 4)
    block = text[4:end]
    fields = {}
    current = None
    for line in block.splitlines():
        match = re.match(r"^([A-Za-z_][\w-]*):\s*(.*)$", line)
        if match:
            current = match.group(1)
            fields[current] = match.group(2).strip()
        elif current and line.startswith((" ", "\t")):
            fields[current] = (fields[current] + " " + line.strip()).strip()
    return fields, True


def unquote(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


def skill_files(root):
    for directory, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in EXCLUDED_NAMES)
        for name in sorted(filenames):
            if name not in EXCLUDED_NAMES and not name.endswith(".pyc"):
                yield Path(directory) / name


def problems_for(skill):
    root = REPO / "skills" / skill
    found = []
    if skill not in CHAT_SKILLS:
        found.append(f"{skill} is not in the chat-suitable set {CHAT_SKILLS}")
    skill_md = root / "SKILL.md"
    if not skill_md.is_file():
        return found + [f"{skill} has no SKILL.md"]
    fields, ok = frontmatter(skill_md.read_text(encoding="utf-8"))
    if not ok:
        found.append(f"{skill} SKILL.md has no frontmatter")
    if "requires" in fields:
        found.append(f"{skill} declares requires, so one folder cannot carry it")
    name = unquote(fields.get("name", ""))
    if not NAME_PATTERN.match(name):
        found.append(f"{skill} name {name!r} is not 1-64 lowercase letters, digits or hyphens")
    description = unquote(fields.get("description", ""))
    if not description or len(description) > MAX_DESCRIPTION:
        found.append(f"{skill} description is empty or over {MAX_DESCRIPTION} characters ({len(description)})")
    resolved_root = root.resolve()
    for path in skill_files(root):
        if path.suffix != ".md":
            continue
        for target in LINK.findall(path.read_text(encoding="utf-8")):
            if re.match(r"^[a-z]+:", target) or target.startswith("#"):
                continue
            resolved = (path.parent / target.split("#", 1)[0]).resolve()
            if resolved_root not in resolved.parents and resolved != resolved_root:
                found.append(f"{path.relative_to(REPO)} links outside its folder: {target}")
    return found


def build(skill, out_dir):
    root = REPO / "skills" / skill
    out_dir.mkdir(parents=True, exist_ok=True)
    target = out_dir / f"{skill}.zip"
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in skill_files(root):
            info = zipfile.ZipInfo(str(Path(skill) / path.relative_to(root)), date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, path.read_bytes())
    return target


def main(argv):
    args = argv[1:]
    check_only = "--check" in args
    args = [a for a in args if a != "--check"]
    out_dir = REPO / "dist" / "chat-skills"
    if "--out" in args:
        index = args.index("--out")
        out_dir = Path(args[index + 1]).resolve()
        del args[index:index + 2]
    skills = args or list(CHAT_SKILLS)
    problems = [p for skill in skills for p in problems_for(skill)]
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    if check_only:
        print(f"chat skills valid: {', '.join(skills)}")
        return 0
    for skill in skills:
        print(build(skill, out_dir).relative_to(REPO) if out_dir.is_relative_to(REPO) else build(skill, out_dir))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
