#!/usr/bin/env python3
"""Validate the stateful activation suite, freeze its held-out set, and materialize eval cases.

Makes no model calls. Usage:
  suite.py validate
  suite.py freeze [--refreeze]
  suite.py materialize --set development [--ids A,B | --seeds] --out PLUGIN/evals
"""
import argparse
import hashlib
import itertools
import json
import os
import re
import shutil
import sys
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
SPEC = REPO / "docs" / "specs" / "skill-activation.md"
CASES = HERE / "cases"
HELDOUT_HASH = CASES / "heldout.sha256"
FIXTURE = HERE / "fixtures" / "demo-repo.sh"
SETS = ("development", "heldout")
DIMENSIONS = {
    "size": ("typo", "small", "medium", "large"),
    "phase": ("new", "approval", "mid_build", "ci_failure", "review_feedback", "pr_creation", "compaction"),
    "form": ("terse", "conceptual", "keyword", "pasted", "multi"),
    "wording": ("names", "implies", "none"),
    "target": ("code", "skills", "specs", "tests"),
}
NEIGHBOUR_PAIRS = (
    ("assistant-spike", "assistant-research"), ("assistant-spike", "assistant-workflow"),
    ("assistant-review", "assistant-skill-creator"), ("assistant-verification", "assistant-tdd"),
    ("assistant-debugging", "assistant-ci-audit"), ("assistant-debugging", "assistant-thinking"),
    ("assistant-research", "assistant-thinking"), ("assistant-research", "assistant-ideate"),
    ("assistant-thinking", "assistant-ideate"), ("assistant-workflow", "assistant-thinking"),
)
PHASED_SKILLS = {
    "assistant-workflow": DIMENSIONS["phase"],
    "assistant-skill-creator": ("new", "approval", "mid_build", "review_feedback", "compaction"),
}
PRIVATE_TERMS_ENV = "SKILL_ACTIVATION_PRIVATE_TERMS"


def private_text(home=None, terms=None):
    """Match identifying paths and secrets, the running user's home path, and any comma-separated terms the caller names.

    A bare username is not matched by default: it can be an ordinary word, such as root or runner.
    """
    home = str(Path.home() if home is None else home).rstrip("/")
    terms = os.environ.get(PRIVATE_TERMS_ENV, "") if terms is None else terms
    parts = [r"/Users/|/home/[a-z]|gmail\.com|(?<![\w-])sk-[A-Za-z0-9]{8}|ghp_[A-Za-z0-9]{8}|BEGIN [A-Z ]*PRIVATE KEY"]
    if home:
        parts.append(rf"{re.escape(home)}(?![\w.-])")
    parts += [rf"(?<!\w){re.escape(term.strip())}(?!\w)" for term in terms.split(",") if term.strip()]
    return re.compile("|".join(parts), re.IGNORECASE)


PRIVATE_TEXT = private_text()
LIMITS = {"max_turns": 8, "timeout_seconds": 300, "allowed_tools": ["Read", "Glob", "Grep", "Skill", "Agent", "TodoWrite", "Edit", "Write"]}
SESSION = "11111111-1111-4111-8111-111111111111"
STAMP = "2026-11-03T10:00:00.000Z"


def load_routing():
    return json.loads((HERE / "routing.json").read_text(encoding="utf-8"))


def load_set(name):
    return json.loads((CASES / f"{name}.json").read_text(encoding="utf-8"))


def resolve(case, suite, routing):
    """Return the scorer's case for a suite case, applying R-ROUTE-1 to its matched rows."""
    rows = [routing["rows"][row] for row in case["rows"]]
    prefix = suite["prefixes"][case["prefix"]]
    required = sorted({skill for row in rows for skill in row["required"]})
    every = any(row["forbidden"] == "*" for row in rows) or case.get("forbidden") == "*"
    forbidden = "*" if every else sorted({skill for row in rows for skill in row["forbidden"]} | set(case.get("forbidden", [])))
    optional = sorted({skill for row in rows for skill in row["optional"]} - set(required) - (set() if every else set(forbidden)))
    activated = list(prefix.get("activated", []))
    kind = ""
    if prefix.get("compacted"):
        kind = "" if not required else "activated_before" if set(required) & set(activated) else "never_activated"
    excused = sorted({skill for name in required + activated for skill in routing["body_directs"].get(name, [])} - set(required))
    return {"required": required, "optional": optional, "excused": excused, "forbidden": forbidden,
            "prefix_activated": activated, "compaction_kind": kind}


def case_kind(case, resolved):
    if case.get("neighbour"):
        return "negative_neighbour"
    if resolved["forbidden"] == "*" and not resolved["required"]:
        return "negative_none"
    return "positive" if resolved["required"] else "informative"


def spec_table():
    """Return the routing table in the spec as {situation: (required, optional, forbidden)}."""
    table = {}
    section = SPEC.read_text(encoding="utf-8").split("### Routing oracle", 1)[1].split("- **R-ROUTE-1", 1)[0]
    for line in section.splitlines():
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) == 4 and cells[0] not in ("Situation", "---"):
            names = [tuple(re.findall(r"assistant-[a-z-]+", cell)) for cell in cells[1:]]
            table[cells[0]] = (names[0], names[1], "*" if cells[3] == "Every skill" else names[2])
    return table


def routing_problems(routing):
    table = spec_table()
    problems = []
    rows = {row["situation"]: row for row in routing["rows"].values()}
    for situation in sorted(set(table) ^ set(rows)):
        problems.append(f"routing row not in both spec and routing.json: {situation}")
    for situation in sorted(set(table) & set(rows)):
        row = rows[situation]
        forbidden = row["forbidden"] if row["forbidden"] == "*" else set(row["forbidden"])
        spec_forbidden = table[situation][2] if table[situation][2] == "*" else set(table[situation][2])
        same_optional = set(row["optional"]) == set(table[situation][1]) or situation == "One-word typo"
        if set(row["required"]) != set(table[situation][0]) or not same_optional or forbidden != spec_forbidden:
            problems.append(f"routing row differs from the spec: {situation}")
    return problems


def uncovered_pairs(cases):
    names = list(DIMENSIONS)
    seen = {tuple(case["dims"][index] for index in pair) + pair for case in cases for pair in itertools.combinations(range(5), 2)}
    missing = []
    for first, second in itertools.combinations(range(5), 2):
        for values in itertools.product(DIMENSIONS[names[first]], DIMENSIONS[names[second]]):
            if values + (first, second) not in seen:
                missing.append(f"{names[first]}={values[0]} {names[second]}={values[1]}")
    return missing


def heldout_hash():
    """Hash the held-out cases and everything that decides their verdicts or their starting state."""
    digest = hashlib.sha256()
    for path in (CASES / "heldout.json", HERE / "routing.json", FIXTURE):
        digest.update(path.read_bytes())
    return digest.hexdigest()


def heldout_frozen():
    return HELDOUT_HASH.exists() and HELDOUT_HASH.read_text().strip() == heldout_hash()


def neighbour_problem(case, resolved):
    """A neighbour case must be able to fail on the neighbour, so one skill is required and the other forbidden."""
    first, second = case["neighbour"]
    for wins, loses in ((first, second), (second, first)):
        if wins in resolved["required"] and loses in resolved["forbidden"]:
            return None
    return f"R-EVAL-7: neighbour case cannot fail on the neighbour: {case['id']}"


def validate_all():
    """Return (problems, facts). A non-empty problem list fails validation."""
    routing = load_routing()
    problems = routing_problems(routing)
    suites = {name: load_set(name) for name in SETS}
    ids = {}
    all_cases = []
    for name, suite in suites.items():
        for case in suite["cases"]:
            where = f"{name}/{case.get('id')}"
            if case["id"] in ids:
                problems.append(f"duplicate id: {where}")
            ids[case["id"]] = name
            all_cases.append(case)
            if len(case["dims"]) != 5 or any(value not in DIMENSIONS[dimension] for dimension, value in zip(DIMENSIONS, case["dims"])):
                problems.append(f"bad dims: {where}")
            if not set(case["rows"]) <= set(routing["rows"]) or not case["rows"]:
                problems.append(f"unknown rows: {where}")
                continue
            if case["prefix"] not in suite["prefixes"]:
                problems.append(f"unknown prefix: {where}")
                continue
            resolved = resolve(case, suite, routing)
            if resolved["required"] and (resolved["forbidden"] == "*" or set(resolved["required"]) & set(resolved["forbidden"])):
                problems.append(f"required and forbidden conflict: {where}")
            if not case.get("prompt", "").strip():
                problems.append(f"empty prompt: {where}")
        for key, prefix in suite["prefixes"].items():
            if not prefix.get("turns"):
                problems.append(f"empty prefix: {name}/{key}")
    prompts = [(case["prompt"], case["id"]) for case in all_cases]
    for text, group in itertools.groupby(sorted(prompts), key=lambda item: item[0]):
        members = [item[1] for item in group]
        if len({ids[member] for member in members}) > 1:
            problems.append(f"prompt shared across sets: {members}")
    turns = {json.dumps(prefix["turns"]) for prefix in suites["development"]["prefixes"].values()}
    problems.extend(f"prefix shared across sets: {key}" for key, prefix in suites["heldout"]["prefixes"].items() if json.dumps(prefix["turns"]) in turns)
    text = (CASES / "development.json").read_text() + (CASES / "heldout.json").read_text() + FIXTURE.read_text()
    if PRIVATE_TEXT.search(text):
        problems.append(f"private text in fixtures: {PRIVATE_TEXT.search(text).group()}")

    heldout = suites["heldout"]
    resolved_heldout = [(case, resolve(case, heldout, routing)) for case in heldout["cases"]]
    stateful = {}
    phases = {}
    for case, resolved in resolved_heldout:
        # A neighbour case is still a positive case for the skill that must win.
        for skill in resolved["required"]:
            stateful[skill] = stateful.get(skill, 0) + 1
            phases.setdefault(skill, set()).add(case["dims"][1])
    skills = sorted(path.name for path in (REPO / "skills").iterdir() if (path / "SKILL.md").is_file())
    for skill in skills:
        if stateful.get(skill, 0) < 3:
            problems.append(f"R-EVAL-6: {skill} has {stateful.get(skill, 0)} held-out positive cases, needs 3")
    for skill, needed in PHASED_SKILLS.items():
        for phase in needed:
            if phase not in phases.get(skill, ()):
                problems.append(f"R-EVAL-6: {skill} has no held-out case for phase {phase}")
    development_kinds = set()
    for case in suites["development"]["cases"]:
        development_kinds.add(case_kind(case, resolve(case, suites["development"], routing)))
    for name, suite in suites.items():
        pairs = set()
        kinds = set()
        for case in suite["cases"]:
            resolved = resolve(case, suite, routing)
            kinds.add(case_kind(case, resolved))
            if case.get("neighbour"):
                pairs.add(tuple(sorted(case["neighbour"])))
                problem = neighbour_problem(case, resolved)
                if problem:
                    problems.append(problem)
        for pair in NEIGHBOUR_PAIRS:
            if tuple(sorted(pair)) not in pairs:
                problems.append(f"R-EVAL-7: {name} has no neighbour case for {pair}")
        if "negative_none" not in kinds:
            problems.append(f"R-EVAL-7: {name} has no no-skill case")
    compaction = {case_resolved[1]["compaction_kind"] for case_resolved in resolved_heldout} - {""}
    if compaction != {"never_activated", "activated_before"}:
        problems.append(f"R-EVAL-9: held-out has compaction kinds {sorted(compaction)}")
    missing = uncovered_pairs(all_cases)
    problems.extend(f"R-EVAL-5 pair not covered: {pair}" for pair in missing)
    if not any(case.get("seed") for case in all_cases):
        problems.append("R-EVAL-3: no seed cases")
    facts = {"development": len(suites["development"]["cases"]), "heldout": len(heldout["cases"]),
             "seeds": sum(1 for case in all_cases if case.get("seed")), "uncovered_pairs": len(missing),
             "heldout_positive_by_skill": stateful}
    return problems, facts


def history_lines(prefix, seed):
    lines, parent = [], None
    common = {"isSidechain": False, "userType": "external", "cwd": "/tmp/fixture", "sessionId": SESSION, "version": "2.1.309", "timestamp": STAMP}
    for index, (role, text) in enumerate(prefix["turns"]):
        identifier = str(uuid.uuid5(uuid.NAMESPACE_OID, f"{seed}-{index}"))
        row = dict(common, uuid=identifier, parentUuid=parent, type=role)
        if prefix.get("compacted") and index == 0:
            boundary = str(uuid.uuid5(uuid.NAMESPACE_OID, f"{seed}-boundary"))
            lines.append(dict(common, uuid=boundary, parentUuid=None, type="system", subtype="compact_boundary", content="Conversation compacted",
                              level="info", compactMetadata={"trigger": "auto", "preTokens": 150000}))
            row.update(parentUuid=boundary, isCompactSummary=True, isVisibleInTranscriptOnly=True)
        if role == "user":
            row["message"] = {"role": "user", "content": text}
        else:
            row["message"] = {"id": f"msg_{index}", "type": "message", "role": "assistant", "model": "fixture", "stop_reason": "end_turn",
                              "stop_sequence": None, "usage": {"input_tokens": 1, "output_tokens": 1}, "content": [{"type": "text", "text": text}]}
        lines.append(row)
        parent = identifier
    return "".join(json.dumps(line) + "\n" for line in lines)


def materialize_case(case, suite, directory, repeats=1):
    directory.mkdir(parents=True)
    front = "".join(f"{key}: {json.dumps(value)}\n" for key, value in {**LIMITS, "runs": repeats}.items())
    (directory / "prompt.md").write_text(f"---\n{front}---\n\n{case['prompt']}\n", encoding="utf-8")
    # A case with no prefix starts a fresh session.
    prefix = suite["prefixes"][case["prefix"]] if case.get("prefix") else None
    # A prefix's setup makes the repository match what the prefix says was already done.
    (directory / "fixture.sh").write_text(FIXTURE.read_text(encoding="utf-8") + "\n" + (prefix or {}).get("setup", ""), encoding="utf-8")
    history = ""
    if prefix:
        (directory / "history.jsonl").write_text(history_lines(prefix, case["id"]), encoding="utf-8")
        history = "  history_file: history.jsonl\n"
    (directory / "case.yaml").write_text(
        f'schema_version: "1.1"\nname: {case["id"]}\ncontext:\n  scaffold_script: fixture.sh\n{history}', encoding="utf-8")
    (directory / "graders").mkdir()
    # The built-in score is unused; the case format needs a grader, and scoring happens in score_trace.py.
    (directory / "graders" / "ran.md").write_text("---\ntype: tool_used\ntool: Skill\n---\n", encoding="utf-8")


def materialize(name, ids, seeds, out):
    suite = load_set(name)
    selected = [case for case in suite["cases"] if (not ids or case["id"] in ids) and (not seeds or case.get("seed"))]
    missing = set(ids or ()) - {case["id"] for case in selected}
    if missing:
        raise ValueError(f"unknown case ids: {sorted(missing)}")
    if not selected:
        raise ValueError("no cases selected")
    out = Path(out)
    if out.name != "evals" or not (out.parent / "generation.json").is_file():
        raise ValueError("output must be the evals directory of a generated plugin")
    if out.exists():
        shutil.rmtree(out)
    for case in selected:
        materialize_case(case, suite, out / case["id"])
    return selected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["validate", "freeze", "materialize"])
    parser.add_argument("--set", choices=SETS)
    parser.add_argument("--ids", default="")
    parser.add_argument("--seeds", action="store_true")
    parser.add_argument("--out")
    parser.add_argument("--refreeze", action="store_true")
    args = parser.parse_args()
    if args.command == "materialize":
        selected = materialize(args.set, [item for item in args.ids.split(",") if item], args.seeds, args.out)
        print(f"materialized {len(selected)} cases")
        return 0
    problems, facts = validate_all()
    if args.command == "freeze":
        if problems:
            print("\n".join(problems))
            print("not frozen: fix the problems first")
            return 1
        if HELDOUT_HASH.exists() and not heldout_frozen() and not args.refreeze:
            print("refused: the set was frozen with different content. Results against the old freeze no longer compare; pass --refreeze to accept that")
            return 1
        HELDOUT_HASH.write_text(heldout_hash() + "\n")
    frozen = heldout_frozen()
    if HELDOUT_HASH.exists() and not frozen:
        problems.append("held-out cases changed since they were frozen")
    print(json.dumps(dict(facts, heldout_frozen=frozen), indent=1))
    print("\n".join(problems) if problems else "OK")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
