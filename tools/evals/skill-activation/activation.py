#!/usr/bin/env python3
"""Load and score the existing activation_cases as single-turn trials (R-RUN-10). Makes no model calls.

Trials grant no Bash, so the run-only cases cannot run their command. They are still collected,
because what they measure is whether a skill activates, and the report names them.
"""
import glob
import hashlib
import json
from collections import Counter
from pathlib import Path

import score_trace
import suite as suite_module

SET_NAME = "activation"
CASE_FILES = "skills/*/evals/cases.json"
RUN_ONLY = ("Run the existing skill without modifying its design.", "Run the existing route test command and report its exit status.")
CONCLUSIVE_STOPS = ("mutation", "final_answer")
UNRELIABLE_STOPS = ("unclassified_bash", "truncated", "run_error")


def case_paths():
    return sorted(glob.glob(str(suite_module.REPO / CASE_FILES)))


def load_cases():
    """Return one case per activation_case, in a stable order."""
    cases = []
    for path in case_paths():
        skill = Path(path).parent.parent.name
        for index, item in enumerate(json.loads(Path(path).read_text(encoding="utf-8")).get("activation_cases", [])):
            cases.append({"id": f"a-{skill.removeprefix('assistant-')}-{index:02d}", "skill": skill, "prompt": item["user_request"],
                          "should_activate": item["should_activate"], "prefix": None, "run_only": item["user_request"] in RUN_ONLY})
    return cases


def cases_hash():
    digest = hashlib.sha256()
    for case in load_cases():
        digest.update(json.dumps([case["id"], case["skill"], case["prompt"], case["should_activate"]]).encode())
    digest.update(suite_module.FIXTURE.read_bytes())
    return digest.hexdigest()


def score(events, case, installed_root):
    """Apply R-RUN-10 selection: all activations on a positive case, only the first on a negative one."""
    activated, stop, stop_tool = score_trace.walk(events, installed_root)
    skill = case["skill"]
    if stop in UNRELIABLE_STOPS:
        verdict = "inconclusive"
    elif case["should_activate"]:
        verdict = "pass" if skill in activated else "fail" if stop in CONCLUSIVE_STOPS else "inconclusive"
    elif activated:
        verdict = "fail" if activated[0] == skill else "pass"
    else:
        verdict = "pass" if stop in CONCLUSIVE_STOPS else "inconclusive"
    return {"verdict": verdict, "stop": stop, "stop_tool": stop_tool, "activated": activated}


def listing_valid(run_root, plugin):
    """R-RUN-11 for fresh runs. Return True or False from the session log's listing, or None if there is no listing to read."""
    skills = [path.name for path in Path(plugin).glob("skills/assistant-*")]
    for log in sorted(Path(run_root).glob("config/projects/*/*.jsonl")):
        with open(log, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                try:
                    row = json.loads(line)
                except ValueError:
                    continue
                attachment = row.get("attachment") if isinstance(row, dict) else None
                if isinstance(attachment, dict) and attachment.get("type") == "skill_listing":
                    lines = str(attachment.get("content", "")).split("\n")
                    return all(any(text.startswith(f"- af:{skill}: ") and text.split(": ", 1)[1].strip() for text in lines) for skill in skills)
    return None


def missing_trial(row):
    """A trial that never ran. Older batches recorded an empty host run as no_trace with no turns and no cost."""
    return row["stop"] in ("not_run", "empty_run") or (row["stop"] == "no_trace" and not row.get("turns") and not row.get("cost_usd"))


def case_results(rows):
    """Return {(arm, model, case): pass|fail|inconclusive} by majority of conclusive repeats."""
    tallies = {}
    for row in rows:
        tally = tallies.setdefault((row["arm"], row["model"], row["case"]), {"pass": 0, "fail": 0})
        if row["verdict"] in tally:
            tally[row["verdict"]] += 1
    return {key: "pass" if tally["pass"] > tally["fail"] else "fail" if tally["fail"] > tally["pass"] else "inconclusive" for key, tally in tallies.items()}


def mixed_inputs(rows):
    """Return the inputs that differ inside one arm and model, because such repeats don't form one measurement."""
    return [name for name in ("suite_sha256", "host_version", "tree_sha256", "listing_condition") if len({row.get(name) for row in rows}) > 1]


def comparison_problems(rows, baselines, candidate):
    """Return why these arms can't be compared under R-RUN-10. Absent cases must not read as no regression."""
    arms = [*baselines, candidate]
    if len(baselines) != 2 or len(set(arms)) != 3:
        return ["needs two different baselines and a candidate that is neither"]
    problems = [f"{arm} has no valid rows" for arm in arms if not any(row["arm"] == arm for row in rows)]
    if problems:
        return problems
    named = [row for row in rows if row["arm"] in arms]
    if any(count > 1 for count in Counter((row.get("batch"), row["arm"], row["model"], row["case"], row.get("repeat")) for row in named).values()):
        problems.append("the same trial appears more than once")
    for model in sorted({row["model"] for row in named}):
        members = [row for row in named if row["model"] == model]
        problems += [f"{model}: {name} differs between arms" for name in ("suite_sha256", "host_version", "listing_condition") if len({row.get(name) for row in members}) > 1]
        coverage = [Counter(row["case"] for row in members if row["arm"] == arm) for arm in arms]
        if any(item != coverage[0] for item in coverage):
            problems.append(f"{model}: arms did not run the same cases and repeats")
        problems += [f"{model}: {arm} mixes plugin trees" for arm in arms if len({row.get("tree_sha256") for row in members if row["arm"] == arm}) > 1]
        if len({row.get("tree_sha256") for row in members if row["arm"] in baselines}) > 1:
            problems.append(f"{model}: the baselines are different plugins")
    return problems


def compared_cases(rows, baselines, candidate):
    """Count (model, case) pairs with a conclusive result in both baselines and the candidate, the only ones that can show a regression."""
    results = case_results(rows)
    pairs = {(key[1], key[2]) for key in results}
    return sum(all(results.get((arm, model, case)) in ("pass", "fail") for arm in [*baselines, candidate]) for model, case in pairs)


def regressions(rows, baselines, candidate):
    """Return (regressions, baseline disagreements) per model. A regression passes in both baselines and fails on the candidate."""
    results = case_results(rows)
    found, disagree = [], []
    for model, case in sorted({(key[1], key[2]) for key in results}):
        first, second = (results.get((arm, model, case)) for arm in baselines)
        if first != second:
            disagree.append((model, case))
        elif first == "pass" and results.get((candidate, model, case)) == "fail":
            found.append((model, case))
    return found, disagree
