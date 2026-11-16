#!/usr/bin/env python3
"""Check that every skill folder is self-contained.

Rule 1: every relative Markdown link in a skill resolves to an existing file
inside that skill or inside a skill it declares in `requires`.
Rule 2: no runtime-instruction path reaches outside the skill folder (into
framework `tools/`, `docs/`, `agents/`, `hooks/`, `codex-rules/` or the
installed tools directory), unless the exact file and path are allowlisted
below with a reason.

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
    r"(?:\.\./)+(?:tools|docs|agents|hooks|codex-rules)/[^\s`)\"']*"
    r"|<framework-tools>/[^\s`)\"']*"
    r"|\{agent_state_dir\}/tools[^\s`)\"']*"
    r"|parents\[\d+\]\s*/\s*\"tools/[^\"]*\""
    r"|(?<![\w./-])(?:tools|docs)/[\w.-]+/[^\s`)\"']*"
    r"|(?:~|\$\{?HOME\}?|\$\{?CODEX_HOME\}?)/(?:\.[\w-]+/)?tools/[^\s`)\"']*"
    r"|(?<![\w~}$./-])(?:/[\w.@-]+)*/\.(?:claude|codex|gemini|agents)/tools/[^\s`)\"']*"
)
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
    ("assistant-cleanup/SKILL.md", "tools/framework-ownership/"):
        "installer-only skill; runs the installed ownership helper (R-SC-6)",
    ("assistant-cleanup/SKILL.md", "tools/framework-ownership/ownership.py"):
        "installer-only skill; runs the installed ownership helper (R-SC-6)",
    ("assistant-cleanup/SKILL.md", "tools/framework-ownership/ownership.ps1"):
        "installer-only skill; runs the installed ownership helper (R-SC-6)",
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
    ("assistant-workflow/references/prompts/pr-review.md", "<framework-tools>/cognitive-complexity/run-complexity.sh"):
        "pending slice B",
    ("assistant-workflow/references/prompts/pr-review.md", "{agent_state_dir}/tools"):
        "pending slice B",
    ("assistant-ci-audit/references/test-maintenance.md", "tools/cognitive-complexity/run-complexity.sh"):
        "pending slice B",
    ("assistant-workflow/scripts/task-packet-admission.py", 'parents[3] / "tools/progress/stagnation.py"'):
        "pending slice C",
    ("assistant-workflow/references/change-impact.md", "../../tools/change-impact/validate-change-impact.cjs"):
        "pending slice D",
    ("assistant-review/references/change-impact.md", "../../tools/change-impact/validate-change-impact.cjs"):
        "pending slice D",
    ("assistant-debugging/references/change-impact.md", "../../tools/change-impact/validate-change-impact.cjs"):
        "pending slice D",
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
    return errors


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
