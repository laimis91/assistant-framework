#!/usr/bin/env python3
"""Summarize trial results as counts with denominators (R-SCORE-2). Makes no model calls.

Each case set, arm, model and listing condition is summarized apart, and batches marked invalid are left
out and named. Gate comparisons between arms are not computed here. Scores are diagnostic, not
proof of benefit (R-SCORE-3). Per-case verdicts print only
with --cases, so held-out results can go to a candidate writer as aggregates (R-EVAL-4).

Usage: report.py RESULTS.jsonl [RESULTS.jsonl ...] [--cases] [--json] [--baselines A,B --candidate C]
"""
import argparse
import json
import sys
from collections import Counter, defaultdict

import activation


def _ratio(hits, total):
    return {"hits": hits, "total": total}


def _text(value):
    return f"{value['hits']}/{value['total']}" if value["total"] else "-"


def _group_verdicts(rows, key):
    groups = defaultdict(lambda: {"pass": 0, "fail": 0, "inconclusive": 0})
    for row in rows:
        groups[str(row.get(key))][row["verdict"]] += 1
    return dict(sorted(groups.items()))


def _per_skill(rows):
    """Recall per skill over conclusive trials. A skill satisfied by the prefix is not a chance to activate it."""
    skills = defaultdict(lambda: [0, 0])
    for row in rows:
        if row["verdict"] == "inconclusive":
            continue
        for skill in row.get("required", []):
            if skill in row.get("prefix_activated", []):
                continue
            skills[skill][1] += 1
            if skill not in row.get("missing", []):
                skills[skill][0] += 1
    return {skill: _ratio(*counts) for skill, counts in sorted(skills.items())}


def _not_graded(row):
    """R-EVAL-9: a compaction case whose whole requirement activated before compaction reports re-invocation instead."""
    return row.get("compaction_kind") == "activated_before" and set(row.get("required", [])) <= set(row.get("prefix_activated", []))


def summarize(rows):
    conclusive = [row for row in rows if row["verdict"] != "inconclusive"]
    graded = [row for row in conclusive if row.get("required") and not _not_graded(row)]
    several = [row for row in graded if len(row["required"]) > 1]
    mutating = [row for row in graded if row.get("stop") == "mutation"]
    activated = sum(len(set(row.get("activated", []))) for row in conclusive)
    unexpected = sum(len(set(row.get("extra", [])) | set(row.get("forbidden_hits", []))) for row in conclusive)
    false_members = [row for row in conclusive if row.get("kind") == "negative_none" or row.get("forbidden")]
    false_hits = [row for row in false_members if row.get("forbidden_hits") or (row.get("kind") == "negative_none" and row.get("activated"))]
    never = [row for row in conclusive if row.get("compaction_kind") == "never_activated"]
    before = [row for row in conclusive if row.get("compaction_kind") == "activated_before"]
    negatives = {}
    for kind in ("negative_none", "negative_neighbour"):
        members = [row for row in conclusive if row.get("kind") == kind]
        negatives[kind] = _ratio(sum(row["verdict"] == "pass" for row in members), len(members))
    return {
        "trials": len(rows),
        "pass_rate": _ratio(sum(row["verdict"] == "pass" for row in graded), len(graded)),
        "compaction_not_graded": sum(_not_graded(row) for row in conclusive),
        "false_activation": _ratio(len(false_hits), len(false_members)),
        "extra_activations": sum(len(set(row.get("extra", [])) - set(row.get("forbidden_hits", []))) for row in conclusive),
        "inconclusive": _ratio(len(rows) - len(conclusive), len(rows)),
        "recall_by_skill": _per_skill(rows),
        "precision": _ratio(activated - unexpected, activated),
        "set_completeness": _ratio(sum(not row.get("missing") for row in several), len(several)),
        "complete_before_mutation": _ratio(sum(not row.get("missing") for row in mutating), len(mutating)),
        "no_skill_before_mutation": _ratio(sum(not row.get("activated") and not row.get("prefix_activated") for row in mutating), len(mutating)),
        "compaction_never_activated": _ratio(sum(row["verdict"] == "pass" for row in never), len(never)),
        "compaction_reinvoked": _ratio(sum(bool(row.get("reinvoked")) for row in before), len(before)),
        "negatives": negatives,
        "by_phase": _group_verdicts(rows, "phase"),
        "seeds": _group_verdicts([row for row in rows if row.get("seed")], "phase"),
        "tokens": {name: sum((row.get("tokens") or {}).get(name, 0) for row in rows) for name in ("input", "output", "cache_read", "cache_creation")},
        "trials_without_tokens": sum(not row.get("tokens") for row in rows),
        "seconds": round(sum(row.get("seconds") or 0 for row in rows), 1),
        "cost_usd": round(sum(row.get("cost_usd") or 0 for row in rows), 4),
    }


def by_group(rows):
    """Summarize each case set, arm, model and listing condition apart, because a figure across them means nothing."""
    groups = defaultdict(list)
    for row in rows:
        groups[tuple(str(row.get(name)) for name in ("set", "arm", "model", "listing_condition"))].append(row)
    summaries = {}
    for key, members in sorted(groups.items()):
        summary = summarize(members)
        summary["mixed_inputs"] = any(len({row.get(name) for row in members}) > 1 for name in ("suite_sha256", "host_version", "tree_sha256"))
        summaries[" / ".join(key)] = summary
    return summaries


def activation_summary(rows):
    """R-RUN-10 per arm and model: cases by majority, plus how many trials had no usable listing or ran a run-only case."""
    counts = defaultdict(Counter)
    for (arm, model, _case), result in activation.case_results(rows).items():
        counts[f"{arm} / {model}"][result] += 1
    return {name: {"pass": value["pass"], "fail": value["fail"], "inconclusive": value["inconclusive"],
                   "mixed_inputs": activation.mixed_inputs([row for row in rows if f"{row['arm']} / {row['model']}" == name]),
                   "listing_invalid_trials": sum(row["stop"] == "listing_invalid" and f"{row['arm']} / {row['model']}" == name for row in rows),
                   "run_only_trials": sum(bool(row.get("run_only")) and f"{row['arm']} / {row['model']}" == name for row in rows)}
            for name, value in sorted(counts.items())}


def render(summary):
    lines = [f"Trials: {summary['trials']}. Pass rate {_text(summary['pass_rate'])}. False activation {_text(summary['false_activation'])}. Inconclusive {_text(summary['inconclusive'])}.",
             f"Compaction cases not graded (R-EVAL-9): {summary['compaction_not_graded']}. Extra activations: {summary['extra_activations']}.",
             f"Precision {_text(summary['precision'])}. Set completeness {_text(summary['set_completeness'])}.",
             f"Of trials that mutated: complete first {_text(summary['complete_before_mutation'])}, no skill at all {_text(summary['no_skill_before_mutation'])}.",
             f"Compaction: never activated, passed {_text(summary['compaction_never_activated'])}; activated before, re-invoked {_text(summary['compaction_reinvoked'])}.",
             f"Negatives: no skill {_text(summary['negatives']['negative_none'])}, neighbour {_text(summary['negatives']['negative_neighbour'])}.",
             "", "Recall by skill:"]
    lines += [f"  {skill}: {_text(value)}" for skill, value in summary["recall_by_skill"].items()]
    for title, key in (("phase", "by_phase"), ("phase, seeds only", "seeds")):
        lines += ["", f"By {title} (pass/fail/inconclusive):"]
        lines += [f"  {name}: {counts['pass']}/{counts['fail']}/{counts['inconclusive']}" for name, counts in summary[key].items()]
    lines += ["", f"Tokens {summary['tokens']}, {summary['trials_without_tokens']} trials without a count. Time {summary['seconds']}s. Estimated cost ${summary['cost_usd']}. These figures exclude listing probes; each batch's summary.json has them."]
    if summary.get("mixed_inputs"):
        lines.insert(0, "WARNING: this group mixes case suites, host versions or plugin trees.")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("results", nargs="+")
    parser.add_argument("--cases", action="store_true")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--baselines", help="two arms, comma-separated, for R-RUN-10 regressions")
    parser.add_argument("--candidate", help="the arm to compare with the baselines")
    args = parser.parse_args()
    if bool(args.baselines) != bool(args.candidate):
        parser.error("--baselines and --candidate go together")
    rows = []
    for path in args.results:
        with open(path, encoding="utf-8") as handle:
            rows.extend(json.loads(line) for line in handle if line.strip())
    fresh = [row for row in rows if row.get("set") == activation.SET_NAME and row.get("batch_valid")]
    valid = [row for row in rows if row.get("batch_valid") and row.get("set") != activation.SET_NAME]
    invalid = sorted({str(row.get("batch")) for row in rows if not row.get("batch_valid")})
    groups = by_group(valid)
    existing = activation_summary(fresh)
    problems = activation.comparison_problems(fresh, args.baselines.split(","), args.candidate) if args.candidate else []
    compared = activation.compared_cases(fresh, args.baselines.split(","), args.candidate) if args.candidate and not problems else 0
    if args.candidate and not problems and not compared:
        problems = ["no case is conclusive in all three arms"]
    found, disagree = activation.regressions(fresh, args.baselines.split(","), args.candidate) if args.candidate and not problems else (None, None)
    total = len(activation.load_cases())
    if args.json:
        print(json.dumps({"groups": groups, "invalid_batches": invalid, "activation_cases": existing, "comparison_problems": problems, "compared_cases": compared, "total_cases": total, "regressions": found, "baseline_disagreements": disagree}, indent=1))
    else:
        for name, summary in groups.items():
            print(f"== {name} ==\n{render(summary)}\n")
        for name, value in existing.items():
            warning = f"WARNING: this arm mixes {', '.join(value['mixed_inputs'])}.\n" if value["mixed_inputs"] else ""
            print(f"== activation_cases: {name} ==\n{warning}Cases pass {value['pass']}, fail {value['fail']}, inconclusive {value['inconclusive']}. "
                  f"Trials with no usable listing {value['listing_invalid_trials']}. Run-only trials, which could not run their command: {value['run_only_trials']}.\n")
        if problems:
            print(f"Regressions on {args.candidate}: not evaluated. " + " ".join(f"{problem}." for problem in problems) + "\n")
        elif found is not None:
            print(f"Regressions on {args.candidate}, over {compared} of {total} cases conclusive in all three arms: {found or 'none'}. Baselines disagree, so not gated: {disagree or 'none'}.\n")
        print(f"Invalid batches, left out above: {', '.join(invalid) or 'none'}")
    if args.cases:
        for row in valid:
            print(row["arm"], row["case"], row["repeat"], row["verdict"], row["stop"], ",".join(row.get("activated", [])) or "-",
                  "missing:" + (",".join(row.get("missing", [])) or "-"))
        for row in fresh:
            print(row["arm"], row["case"], row["repeat"], row["verdict"], row["stop"], ",".join(row.get("activated", [])) or "-")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
