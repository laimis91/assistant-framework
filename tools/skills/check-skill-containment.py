#!/usr/bin/env python3
"""Check that every skill folder is self-contained.

Rule 1: every relative Markdown link in a skill resolves to an existing file
inside that skill or inside a skill it declares in `requires`.
Rule 2: no runtime-instruction path reaches outside the skill folder (into
framework `tools/`, `docs/`, `agents/`, `hooks/` or an agent home's
tools directory), unless the exact file and path are allowlisted
below with a reason.
Rule 3: every backtick path naming a skill file (`references/`, `contracts/`,
`evals/`, `scripts/`) resolves; see BACKTICK_REF below.

See docs/specs/self-contained-skills.md (R-SC-4).
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

LINK = re.compile(r"\]\(([^)\s]+)\)")
RUNTIME_PATH = re.compile(
    r"(?:\.\./)+(?:tools|docs|agents|hooks)/[^\s`)\"']*"
    r"|<framework-tools>/[^\s`)\"']*"
    r"|\{agent_state_dir\}/tools[^\s`)\"']*"
    r"|parents\[\d+\]\s*/\s*\"tools/[^\"]*\""
    r"|(?<![\w./-])(?:tools|docs)/[\w.-]+/[^\s`)\"']*"
    r"|(?:~|\$\{?HOME\}?|\$\{?CODEX_HOME\}?)/(?:\.[\w-]+/)?tools/[^\s`)\"']*"
    r"|(?<![\w~}$./-])(?:/[\w.@-]+)*/\.(?:claude|codex|agents)/tools/[^\s`)\"']*"
)
# Rule 3 (docs/specs/contract-test-cleanup.md D-TC-2): a backtick path naming a
# skill file resolves from the skill root, the file's folder, a skill named just
# before it ("workflow's `references/x.md`"), an explicit skill prefix, or a skill
# in `requires`.
BACKTICK_REF = re.compile(
    r"(?:\b([A-Za-z][\w-]*)'s\s+)?"
    r"`((?:[a-z0-9-]+/)?(?:references|contracts|evals|scripts)/[A-Za-z0-9_./-]+"
    r"\.(?:md|yaml|yml|json|py|sh))(?:#[^`]*)?`"
)
# (skill-relative file, exact path text) -> reason, for paths that name files of
# another project rather than of a framework skill.
ALLOWED_REFERENCES = {
    ("assistant-skill-creator/references/upstream-guidance.md", "references/schemas.md"):
        "names a file of the upstream Anthropic skill-creator",
    ("assistant-skill-creator/references/upstream-guidance.md", "references/openai_yaml.md"):
        "names a file of the upstream OpenAI skill-creator",
    ("assistant-skill-creator/references/upstream-guidance.md", "scripts/quick_validate.py"):
        "names a file of the upstream OpenAI skill-creator",
}
TEXT_SUFFIXES = {".md", ".yaml", ".yml", ".json", ".py", ".sh", ".ps1", ".toml", ".txt"}

# Whole files that are maintainer notes, eval inputs or synced repository docs.
EXEMPT_FILES = {
    "assistant-skill-creator/references/skill-contract-design-guide.md":
        "synced copy of docs/skill-contract-design-guide.md; repository maintainer guide",
    "assistant-skill-creator/references/upstream-guidelines.json":
        "upstream provenance manifest naming repository sources",
}
EXEMPT_GLOBS = {
    "*/evals/cases.json": "eval prompts and fixtures, not runtime instructions",
}

# Maintainer notes naming the repository sync tools, in any file (source and
# generated-view headers). They tell maintainers how copies are produced; no
# runtime instruction depends on them.
MAINTAINER_PREFIXES = {
    "tools/skills/sync-": "maintainer sync note (R-SC-4)",
}

# (skill-relative file, exact path text) -> reason. Entries marked with a slice
# are removed by that slice of docs/specs/self-contained-skills.md. An entry that
# no longer matches its file is reported, so stale entries cannot hide a path.
ALLOWED_PATHS = {
    ("assistant-workflow/references/design-pattern-retrieval.md", "<framework-tools>/patterns/pattern-library.sh"):
        "optional, used only if configured (P-1)",
    ("assistant-docs/api-docs.md", "docs/api/"):
        "names a directory in the user's project, not a framework dependency",
    ("assistant-review/references/review-checklists.md", "~/.codex/tools/"):
        "names a path the reviewed change may hard-code, not a dependency",
    ("assistant-security/install-boundaries.md", "docs/evals/"):
        "names an installed directory under audit, not a dependency",
    ("assistant-workflow/contracts/input.yaml", "docs/readme/document/changelog"):
        "request keywords, not a path",
}


def read_requires(skill_md: Path) -> list[str]:
    lines = skill_md.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0].strip() != "---":
        return []
    requires: list[str] = []
    active = False
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if line.startswith("requires:"):
            active = True
            continue
        if active and line.startswith("  - "):
            requires.append(line[4:].strip())
        elif active:
            active = False
    return requires


def is_exempt(rel: str) -> bool:
    if rel in EXEMPT_FILES:
        return True
    return any(Path(rel).match(pattern) for pattern in EXEMPT_GLOBS)


def check(skills_dir: Path) -> list[str]:
    errors: list[str] = []
    used: set[tuple[str, str]] = set()
    used_refs: set[tuple[str, str]] = set()
    skills = sorted(p.parent for p in skills_dir.glob("*/SKILL.md"))
    names = {s.name for s in skills}
    for skill in skills:
        allowed_roots = [skill.resolve()]
        for dep in read_requires(skill / "SKILL.md"):
            if dep not in names:
                errors.append(f"{skill.name}/SKILL.md: requires unknown skill '{dep}'")
            allowed_roots.append((skills_dir / dep).resolve())
        for path in sorted(skill.rglob("*")):
            if not path.is_file() or path.suffix not in TEXT_SUFFIXES:
                continue
            rel = path.relative_to(skills_dir).as_posix()
            if is_exempt(rel):
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            for lineno, line in enumerate(text.splitlines(), 1):
                if path.suffix == ".md":
                    for target in LINK.findall(line):
                        target = target.split("#", 1)[0]
                        if not target or re.match(r"^[a-z][a-z0-9+.-]*:", target) or target.startswith("/"):
                            continue
                        resolved = (path.parent / target).resolve()
                        if not any(resolved == root or root in resolved.parents for root in allowed_roots):
                            errors.append(f"{rel}:{lineno}: link leaves the skill and its requires: {target}")
                        elif not resolved.exists():
                            errors.append(f"{rel}:{lineno}: link target does not exist: {target}")
                    for owner, target in BACKTICK_REF.findall(line):
                        if (rel, target) in ALLOWED_REFERENCES:
                            used_refs.add((rel, target))
                            continue
                        if not reference_resolves(skills_dir, skill, path, owner, target, allowed_roots, names):
                            errors.append(f"{rel}:{lineno}: reference path does not exist: {target}")
                for match in RUNTIME_PATH.finditer(line):
                    found = match.group(0).rstrip(".,;:")
                    if any(found.startswith(p) for p in MAINTAINER_PREFIXES):
                        continue
                    if (rel, found) in ALLOWED_PATHS:
                        used.add((rel, found))
                        continue
                    errors.append(f"{rel}:{lineno}: runtime path leaves the skill folder: {found}")
    for rel, found in sorted(set(ALLOWED_PATHS) - used):
        if (skills_dir / rel).is_file():
            errors.append(f"{rel}: allowlist entry no longer matches; remove it: {found}")
    for rel, found in sorted(set(ALLOWED_REFERENCES) - used_refs):
        if (skills_dir / rel).is_file():
            errors.append(f"{rel}: reference allowlist entry no longer matches; remove it: {found}")
    return errors


def reference_resolves(skills_dir: Path, skill: Path, path: Path, owner: str, target: str,
                       allowed_roots: list[Path], names: set[str]) -> bool:
    candidates = [skill / target, path.parent / target]
    first = target.split("/", 1)[0]
    if first in names:
        candidates.append(skills_dir / target)
    if owner:
        owners = [n for n in (owner.lower(), f"assistant-{owner.lower()}") if n in names]
        if not owners and not (skill / target).is_file():
            # Another skill's file named in prose ("Workflow's `scripts/x.py`"); that
            # skill is not in this copy, so there is nothing to resolve against.
            return True
        candidates.extend(skills_dir / name / target for name in owners)
    candidates.extend(root / target for root in allowed_roots[1:])
    return any(candidate.is_file() for candidate in candidates)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--skills-dir", type=Path, default=REPO_ROOT / "skills")
    args = parser.parse_args(argv)
    errors = check(args.skills_dir)
    for error in errors:
        print(f"ERROR {error}", file=sys.stderr)
    if errors:
        print(f"skill containment failed: {len(errors)} problem(s)", file=sys.stderr)
        return 1
    print("checked skill containment")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
