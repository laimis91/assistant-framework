#!/usr/bin/env python3
"""Collect skill-activation trials with `claude plugin eval`. This makes paid model calls.

It refuses to start unless --authorized-calls equals the exact call count (R-RUN-7).
Without --run it only prints the plan. Runs grant Edit and Write, never Bash (R-RUN-2).
The listing probe runs first as its own eval, and a failed probe stops the batch (R-RUN-11).
Results hold case identifiers and counts, with no prompts or responses, and every
temporary run directory is deleted even after a failure (R-RUN-8), so run one batch at a
time. The API key stays in the child's environment and is never written or printed.
The activation set collects R-RUN-10 as fresh single-turn runs, with no probe, because their logs show the listing.

A host run that never started (no trace, no turns, no cost) counts as not run, so it cannot make a batch valid.
--fill-from SOURCE reruns only an activation batch's trials that never ran, on the same arm, plugin tree and host,
and writes the merged arm as a new batch.

Usage: run_trials.py --batch NAME --arm PLUGIN --set development|heldout|activation [--ids A,B] [--seeds]
                     --repeats N [--model M] [--host-version V] [--fill-from SOURCE] --max-cost-usd X --authorized-calls N [--run]
"""
import argparse
import fcntl
import glob
import hashlib
import json
import math
import os
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import activation
import generate_plugin
import score_trace
import suite as suite_module

REPO = suite_module.REPO
STATE = REPO / ".codex" / "skill-activation"
PLUGINS = STATE / "plugins"
RESULTS = STATE / "results"
LISTING_PROBE_ID = "listing-probe"
LISTING_BUDGET = "40000"
ALLOW_TOOLS = ("Edit", "Write")
MODELS = {"deepseek-flash": {"base_url": "https://api.deepseek.com/anthropic", "keychain_service": "deepseek-api-key",
                             "config_dir": ".claude-deepseek"}}
ENVIRONMENT_ALLOWLIST = ("PATH", "HOME", "TMPDIR", "LANG", "LC_ALL", "USER", "LOGNAME", "SHELL")
LISTING_PROBE_PROMPT = ("Do not use any tools. Quote, word for word, the description shown for the assistant-workflow skill in your "
                        "available-skills list. If you see the name without a description, reply NAME ONLY. If you see no skills list, reply NO LISTING.")
LISTING_PROBE_PREFIX = {"turns": [["user", "Good afternoon."], ["assistant", "Good afternoon. What are we working on?"]]}
RUN_ROOT_PARENTS = (Path("/private/tmp"), Path(tempfile.gettempdir()).resolve())
BATCH_NAME = re.compile(r"^[a-z0-9][a-z0-9-]*$")


def select_cases(name, ids, seeds):
    suite = {"prefixes": {}, "cases": activation.load_cases()} if name == activation.SET_NAME else suite_module.load_set(name)
    selected = [case for case in suite["cases"] if (not ids or case["id"] in ids) and (not seeds or case.get("seed"))]
    missing = set(ids or ()) - {case["id"] for case in selected}
    if missing:
        raise ValueError(f"unknown case ids: {sorted(missing)}")
    if not selected:
        raise ValueError("no cases selected")
    return suite, selected


def expected_calls(case_count, repeats, probe=True):
    """Cases times repeats, plus the R-RUN-11 listing probe when the cases resume a session."""
    return case_count * repeats + (1 if probe else 0)


def load_manifest(arm):
    """Return the arm's manifest, only if the plugin on disk is still what was generated."""
    plugin = PLUGINS / arm
    manifest = plugin / generate_plugin.MANIFEST
    if not manifest.is_file():
        raise ValueError(f"no generated plugin at {plugin}; run generate_plugin.py first")
    recorded = json.loads(manifest.read_text())
    if generate_plugin.tree_hash(plugin) != recorded["tree_sha256"]:
        raise ValueError(f"plugin {arm} changed after it was generated; generate it again")
    return plugin.resolve(), recorded


def run_refusals(name):
    """Return the reasons a batch from this set may not spend model calls."""
    problems = list(suite_module.validate_all()[0])
    if name == "heldout" and not suite_module.heldout_frozen():
        problems.append("the held-out set is not frozen, or changed after it was frozen (R-EVAL-4)")
    return problems


def suite_hash(name):
    if name == activation.SET_NAME:
        return activation.cases_hash()
    digest = hashlib.sha256()
    for path in (suite_module.CASES / f"{name}.json", suite_module.HERE / "routing.json", suite_module.FIXTURE):
        digest.update(path.read_bytes())
    return digest.hexdigest()


def skill_description(path):
    match = re.search(r"^description:\s*(.*)$", Path(path).read_text(encoding="utf-8"), re.MULTILINE)
    if not match:
        return ""
    value = match.group(1).strip()
    if value.startswith('"'):
        try:
            return json.loads(value)
        except ValueError:
            pass
    return value.strip('"')


def run_plan(args, cases, plugin, manifest):
    fresh = args.set == activation.SET_NAME
    return {"batch": args.batch, "arm": args.arm, "set": args.set, "cases": len(cases), "repeats": args.repeats, "model": args.model,
            "listing_probe_calls": 0 if fresh else 1, "calls": expected_calls(len(cases), args.repeats, not fresh), "max_cost_usd": args.max_cost_usd,
            "permission_mode": "host default, Bash not granted", "granted_tools": list(ALLOW_TOOLS), "listing_budget": LISTING_BUDGET,
            "listing_condition": manifest["listing_condition"], "stubs": manifest["stubs"],
            "stub_description_chars": sum(len(skill_description(path)) for path in plugin.glob("skills/stub-*/SKILL.md")),
            "description_sha256": manifest["description_sha256"]}


def child_environment(model, key, source=None):
    """Build the child's environment from an allowlist, so other tokens and sockets never reach it (R-RUN-2)."""
    source = os.environ if source is None else source
    settings = MODELS[model]
    environment = {name: source[name] for name in ENVIRONMENT_ALLOWLIST if name in source}
    environment.update({
        "CLAUDE_CONFIG_DIR": str(Path(source["HOME"]) / settings["config_dir"]),
        "ANTHROPIC_BASE_URL": settings["base_url"],
        "ANTHROPIC_API_KEY": key,
        "ANTHROPIC_MODEL": model,
        "ANTHROPIC_DEFAULT_OPUS_MODEL": model,
        "ANTHROPIC_DEFAULT_SONNET_MODEL": model,
        "ANTHROPIC_DEFAULT_HAIKU_MODEL": model,
        "CLAUDE_CODE_SUBAGENT_MODEL": model,
        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
        "SLASH_COMMAND_TOOL_CHAR_BUDGET": LISTING_BUDGET,
    })
    return environment


def eval_command(binary, plugin, model, repeats, cap, output):
    return [str(binary), "plugin", "eval", str(plugin), "--model", model, "--ablation", "none", "--runs", str(repeats),
            "--threshold", "0", "--max-cost-usd", str(cap), "--no-publish", "--trust-plugin", "--keep-temp", "--scaffold",
            "--output-dir", str(output), "--allow-tools", *ALLOW_TOOLS]


def redact(text, key, limit=200):
    return str(text).replace(key, "[key]")[:limit] if key else str(text)[:limit]


def host_reason(returncode, stderr, key):
    """Return the host's last stderr line, bounded and with the key removed, or None. The summary keeps it only when something failed."""
    # The host always ends with the path of its report, which says nothing about the failure.
    lines = [line.strip() for line in stderr.splitlines() if line.strip() and not line.strip().startswith("Report:")]
    if not lines:
        return None
    return redact(lines[-1], key)


def run_eval(binary, plugin, model, repeats, cap, output, environment, key):
    """Run the host. Return (exit code, failure reason). subprocess.run kills the child if this is interrupted."""
    output.mkdir(parents=True)
    completed = subprocess.run(eval_command(binary, plugin, model, repeats, cap, output), env=environment, stdin=subprocess.DEVNULL,
                               stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, errors="replace")
    return completed.returncode, host_reason(completed.returncode, completed.stderr, key)


def number(value):
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) else None


def well_formed(data):
    if not isinstance(data, dict) or not isinstance(data.get("cases"), list):
        return False
    for item in data["cases"]:
        if not isinstance(item, dict) or not isinstance(item.get("arms"), dict):
            return False
        runs = item["arms"].get("with", [])
        if not isinstance(runs, list) or not all(isinstance(run, dict) for run in runs):
            return False
    return True


def read_aggregate(output):
    """Return the aggregate, or {} if absent. A malformed one keeps only its cost, and a batch with it is invalid."""
    try:
        data = json.loads((output / "aggregate-result.json").read_text())
    except (OSError, ValueError):
        return {}
    if not well_formed(data):
        return {"malformed": True, "costUsd": number(data.get("costUsd")) if isinstance(data, dict) else None}
    return {**data, "costUsd": number(data.get("costUsd"))}


def claude_binary(version=None):
    """Return the newest installed host, or exactly the pinned one, so an app update can't split arms of one comparison."""
    pattern = str(Path.home() / f"Library/Application Support/Claude/claude-code/{glob.escape(version) if version else '*'}/*/claude.app/Contents/MacOS/claude")
    found = glob.glob(pattern)
    if found:
        return max(found, key=os.path.getmtime)
    if version:
        raise RuntimeError(f"host version {version} is not installed")
    binary = shutil.which("claude")
    if not binary:
        raise RuntimeError("the claude binary was not found")
    return binary


def read_key(model):
    service = MODELS[model]["keychain_service"]
    result = subprocess.run(["security", "find-generic-password", "-s", service, "-w"], capture_output=True, text=True)
    key = result.stdout.strip()
    if result.returncode or not key:
        raise RuntimeError(f"no API key in keychain service {service}")
    return key


def run_roots():
    """List host-made temporary run directories."""
    roots = set()
    for parent in RUN_ROOT_PARENTS:
        for path in Path(parent).glob("e-*"):
            if re.match(r"^e-[A-Za-z0-9]+$", path.name) and path.is_dir() and not path.is_symlink() and path.stat().st_uid == os.getuid():
                roots.add(path.resolve())
    return roots


def belongs_to_plugin(root, plugin):
    """A new run directory is this batch's only if its trace names this plugin. The runner lock excludes other runs of the same arm."""
    try:
        return str(plugin).encode() in (Path(root) / "out" / "trace.jsonl").read_bytes()
    except OSError:
        return False


def unseal(root):
    """Open a run directory's permissions so the key scan can read it and it can be deleted."""
    os.chmod(root, stat.S_IRWXU)
    for directory, names, files in os.walk(root, topdown=True):
        names[:] = [name for name in names if not os.path.islink(os.path.join(directory, name))]
        for name in names:
            os.chmod(os.path.join(directory, name), stat.S_IRWXU)
        for name in files:
            path = os.path.join(directory, name)
            if not os.path.islink(path):
                os.chmod(path, stat.S_IRUSR | stat.S_IWUSR)


def scan_for_secret(root, secret):
    """Return (files holding the secret, paths that could not be read). Clean means both are zero."""
    needle = secret.encode()
    hits = unscanned = 0

    def count_failure(_error):
        nonlocal unscanned
        unscanned += 1

    for directory, _names, files in os.walk(root, onerror=count_failure):
        for name in files:
            path = Path(directory) / name
            if path.is_symlink() or not path.is_file():
                continue
            try:
                hits += needle in path.read_bytes()
            except OSError:
                unscanned += 1
    return hits, unscanned


def trace_tokens(events):
    """Return tokens from the final result event, summed across models so subagents count, or None if absent."""
    for event in reversed(events):
        if isinstance(event, dict) and event.get("type") == "result" and isinstance(event.get("modelUsage"), dict):
            usage = event["modelUsage"].values()
            return {"input": sum(item.get("inputTokens", 0) for item in usage), "output": sum(item.get("outputTokens", 0) for item in usage),
                    "cache_read": sum(item.get("cacheReadInputTokens", 0) for item in usage),
                    "cache_creation": sum(item.get("cacheCreationInputTokens", 0) for item in usage)}
    return None


def load_trace(path):
    with open(path, encoding="utf-8", errors="replace") as handle:
        return score_trace.load_events(handle)


def assistant_blocks(events):
    for event in events:
        if isinstance(event, dict) and event.get("type") == "assistant":
            content = (event.get("message") or {}).get("content")
            for block in content if isinstance(content, list) else []:
                if isinstance(block, dict):
                    yield block


def listing_probe_passed(events, plugin):
    """R-RUN-11: resumed runs keep no session log, so the model quotes a description for comparison.

    Any tool call fails the probe, because a model that read the file proves nothing about the listing.
    """
    blocks = list(assistant_blocks(events))
    if any(block.get("type") == "tool_use" for block in blocks):
        return False
    expected = " ".join(skill_description(Path(plugin) / "skills" / "assistant-workflow" / "SKILL.md").split())
    quoted = " ".join(" ".join(str(block.get("text", "")) for block in blocks if block.get("type") == "text").split())
    return bool(expected) and expected in quoted


def base_row(case, resolved, identity, repeat):
    return {
        **identity, "case": case["id"], "repeat": repeat, "seed": bool(case.get("seed")), "kind": suite_module.case_kind(case, resolved),
        "size": case["dims"][0], "phase": case["dims"][1], "form": case["dims"][2], "wording": case["dims"][3], "target": case["dims"][4],
        "required": resolved["required"], "optional": resolved["optional"], "forbidden": resolved["forbidden"],
        "prefix_activated": resolved["prefix_activated"], "compaction_kind": resolved["compaction_kind"],
        "verdict": "inconclusive", "stop": "not_run", "stop_tool": "", "activated": [], "missing": [], "forbidden_hits": [], "extra": [],
        "reinvoked": None, "turns": None, "cost_usd": None, "seconds": None, "tokens": None,
    }


def score_run(row, run, resolved, plugin, key=""):
    """Fill a row from one run. A run that cannot be scored stays inconclusive, so one bad trace loses only itself."""
    if run is None:
        return row
    if run.get("error"):
        row["host_error"] = host_error(run, key)
    if empty_run(run):
        row["stop"] = "empty_run"
        return row
    row.update(turns=number(run.get("turns")), cost_usd=number(run.get("costUsd")), seconds=number(run.get("durationSeconds")), stop="no_trace")
    if not run.get("tracePath"):
        return row
    try:
        events = load_trace(run["tracePath"])
        verdict = score_trace.score(events, resolved, str(plugin))
        tokens = trace_tokens(events)
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        row["stop"] = "score_error"
        return row
    fields = ("verdict", "stop", "stop_tool", "activated", "missing", "forbidden_hits", "extra", "compaction_kind", "reinvoked")
    row.update({name: verdict[name] for name in fields}, tokens=tokens)
    return row


def runs_by_case(aggregate):
    return {item.get("name"): item["arms"].get("with", []) for item in aggregate.get("cases", [])}


def empty_run(run):
    """A run the host listed but never started: no trace, no turns and no cost. It is not an observed call."""
    return not run.get("tracePath") and not number(run.get("turns")) and not number(run.get("costUsd"))


def host_error(run, key):
    """The host's own error for one run, bounded and with the key removed, or None."""
    error = run.get("error")
    if not error:
        return None
    return redact(error if isinstance(error, str) else json.dumps(error), key)


def collect(aggregate, cases, repeats, suite, routing, plugin, identity, key=""):
    """Return one row per selected case and repeat, so a run that never happened still counts as inconclusive."""
    runs = runs_by_case(aggregate)
    rows = []
    for case in cases:
        resolved = suite_module.resolve(case, suite, routing)
        found = runs.get(case["id"], [])
        for repeat in range(max(repeats, len(found))):
            row = base_row(case, resolved, identity, repeat)
            rows.append(score_run(row, found[repeat] if repeat < len(found) else None, resolved, plugin, key))
    return rows


def observed_runs(aggregate):
    """Runs that actually started. Empty runs are left out, so they cannot make up a batch's call count."""
    return sum(not empty_run(run) for runs in runs_by_case(aggregate).values() for run in runs)


def empty_runs(aggregate):
    return sum(empty_run(run) for runs in runs_by_case(aggregate).values() for run in runs)


def run_counts_match(aggregate, cases, repeats):
    """A matching total can hide a missing run and an unselected one, so each case is counted."""
    # Every listed run must have started, so an extra empty run also fails the match.
    counts = {name: len(runs) if not any(empty_run(run) for run in runs) else -1 for name, runs in runs_by_case(aggregate).items()}
    return counts == {case["id"]: repeats for case in cases}


def probe_outcome(aggregate, plugin):
    """Return True or False from the probe's single run, or None if it did not produce a readable trace."""
    runs = runs_by_case(aggregate).get(LISTING_PROBE_ID, [])
    if len(runs) != 1 or not runs[0].get("tracePath"):
        return None
    try:
        return listing_probe_passed(load_trace(runs[0]["tracePath"]), plugin)
    except (OSError, ValueError, TypeError):
        return None


def probe_usage(aggregate):
    """R-RUN-8 records calls, tokens and time, and the probe is a call."""
    runs = runs_by_case(aggregate).get(LISTING_PROBE_ID, [])
    if len(runs) != 1:
        return {"tokens": None, "seconds": None}
    try:
        tokens = trace_tokens(load_trace(runs[0].get("tracePath")))
    except (OSError, ValueError, TypeError, AttributeError):
        tokens = None
    return {"tokens": tokens, "seconds": number(runs[0].get("durationSeconds"))}


def collect_fresh(aggregate, cases, repeats, plugin, identity, key=""):
    """Rows for single-turn cases. Their session logs show the listing directly, so each run proves its own validity."""
    runs = runs_by_case(aggregate)
    rows = []
    for case in cases:
        found = runs.get(case["id"], [])
        for repeat in range(max(repeats, len(found))):
            run = found[repeat] if repeat < len(found) else None
            row = {**identity, "case": case["id"], "skill": case["skill"], "should_activate": case["should_activate"], "run_only": case["run_only"],
                   "repeat": repeat, "verdict": "inconclusive", "stop": "not_run", "stop_tool": "", "activated": [], "listing_valid": None,
                   "turns": None, "cost_usd": None, "seconds": None, "tokens": None}
            if run is not None and run.get("error"):
                row["host_error"] = host_error(run, key)
            if run is not None and empty_run(run):
                row["stop"] = "empty_run"
            elif run is not None:
                row.update(turns=number(run.get("turns")), cost_usd=number(run.get("costUsd")), seconds=number(run.get("durationSeconds")), stop="no_trace")
                if run.get("tracePath"):
                    try:
                        events = load_trace(run["tracePath"])
                        row["listing_valid"] = activation.listing_valid(Path(run["tracePath"]).parent.parent, plugin)
                        row.update(activation.score(events, case, str(plugin)), tokens=trace_tokens(events))
                    except (OSError, ValueError, KeyError, TypeError, AttributeError):
                        row.update(verdict="inconclusive", stop="score_error")
                    if row["listing_valid"] is not True and row["stop"] != "score_error":
                        row.update(verdict="inconclusive", stop="listing_invalid")
            rows.append(row)
    return rows


def replace_evals(plugin, cases, suite, repeats):
    evals = plugin / "evals"
    if evals.exists():
        shutil.rmtree(evals)
    for case in cases:
        suite_module.materialize_case(case, suite, evals / case["id"], repeats)


def probe_allows_batch(state, probe, crowded):
    """R-RUN-11 stops an isolated batch on a failed probe. In crowded, a missing description is the R-DESC-7 finding, so the batch continues."""
    usable = state["probe"] is True or (crowded and state["probe"] is False)
    return usable and state["probe_exit"] == 0 and not probe.get("partial") and not probe.get("malformed")


def batch_valid(state, cases, repeats, failure, calls, crowded, fresh=False):
    probe, batch = state["probe_aggregate"], state["aggregate"]
    versions = {batch.get("claudeVersion")} if fresh else {probe.get("claudeVersion"), batch.get("claudeVersion")}
    return ((fresh or probe_allows_batch(state, probe, crowded)) and not failure and not batch.get("partial") and not batch.get("malformed")
            and observed_runs(probe) + observed_runs(batch) == calls and run_counts_match(batch, cases, repeats)
            and state["cases_exit"] == 0 and len(versions) == 1 and None not in versions)


def collect_batch(state, args, cases, suite, plugin, raw, key, crowded):
    """Run the probe, then the batch if it passed, recording progress in state so a failure keeps what happened."""
    binary = claude_binary(args.host_version)
    environment = child_environment(args.model, key)
    if args.set == activation.SET_NAME:
        replace_evals(plugin, cases, suite, args.repeats)
        state["cases_exit"], state["cases_reason"] = run_eval(binary, plugin, args.model, args.repeats, args.max_cost_usd, raw / "cases", environment, key)
        state["aggregate"] = read_aggregate(raw / "cases")
        state["identity"]["host_version"] = state["aggregate"].get("claudeVersion")
        state["rows"] = collect_fresh(state["aggregate"], cases, args.repeats, plugin, state["identity"], key)
        return
    probe_case = {"id": LISTING_PROBE_ID, "prompt": LISTING_PROBE_PROMPT, "prefix": "listing"}
    replace_evals(plugin, [probe_case], {"prefixes": {"listing": LISTING_PROBE_PREFIX}}, 1)
    state["probe_exit"], state["probe_reason"] = run_eval(binary, plugin, args.model, 1, args.max_cost_usd, raw / "probe", environment, key)
    probe = state["probe_aggregate"] = read_aggregate(raw / "probe")
    state["probe"] = probe_outcome(probe, plugin)
    state["probe_usage"] = probe_usage(probe)
    state["identity"]["host_version"] = probe.get("claudeVersion")
    remaining = args.max_cost_usd - (probe.get("costUsd") or 0)
    if probe_allows_batch(state, probe, crowded) and remaining > 0:
        replace_evals(plugin, cases, suite, args.repeats)
        state["cases_exit"], state["cases_reason"] = run_eval(binary, plugin, args.model, args.repeats, remaining, raw / "cases", environment, key)
        state["aggregate"] = read_aggregate(raw / "cases")
    state["rows"] = collect(state["aggregate"], cases, args.repeats, suite, suite_module.load_routing(), plugin, state["identity"], key)


def clean_up(before, plugin, raw, key):
    """Scan and delete what this batch made. Return (key hits, unscanned paths, paths not removed, foreign run directories left)."""
    hits = unscanned = failed = foreign = 0
    targets = [raw]
    for root in sorted(run_roots() - before):
        if belongs_to_plugin(root, plugin):
            targets.append(root)
        else:
            foreign += 1
    for root in targets:
        if not root.exists():
            continue
        try:
            unseal(root)
        except OSError:
            failed += 1
        found, missed = scan_for_secret(root, key)
        hits += found
        unscanned += missed
        shutil.rmtree(root, ignore_errors=True)
        failed += root.exists()
    shutil.rmtree(plugin / "evals", ignore_errors=True)
    failed += (plugin / "evals").exists()
    return hits, unscanned, failed, foreign


FILL_IDENTITY = ("arm", "set", "model", "suite_sha256", "source_commit", "source_dirty", "tree_sha256", "description_sha256", "guidance_sha256",
                 "listing_condition", "host_version")


def fill_source(source, expected, repeats, case_ids):
    """Read a finished activation batch to fill. Return (kept rows, {case id: missing repeats}), or raise ValueError saying why it can't be filled."""
    folder = RESULTS / source
    try:
        summary = json.loads((folder / "summary.json").read_text())
        rows = [json.loads(line) for line in (folder / "results.jsonl").read_text().splitlines() if line.strip()]
    except (OSError, ValueError) as error:
        raise ValueError(f"{source} has no readable summary and results: {type(error).__name__}") from error
    for name, value in expected.items():
        if summary.get(name) != value or any(row.get(name) != value for row in rows):
            raise ValueError(f"{source}: {name} differs from this arm")
    problems = [name for name, ok in (("failure", summary.get("failure") is None), ("partial", not summary.get("partial")),
                                      ("malformed aggregate", not summary.get("malformed_aggregate")), ("key in output", not summary.get("key_found_in_output")),
                                      ("unscanned paths", not summary.get("unscanned_paths")), ("repeats", summary.get("repeats") == repeats)) if not ok]
    if problems:
        raise ValueError(f"{source} can't be filled: {', '.join(problems)}")
    if {row["case"] for row in rows} != set(case_ids):
        raise ValueError(f"{source} does not hold every activation case")
    trials = Counter((row["case"], row["repeat"]) for row in rows)
    if any(count > 1 for count in trials.values()) or trials.keys() != {(case, index) for case, _ in trials for index in range(repeats)}:
        raise ValueError(f"{source} does not hold each case's repeats exactly once")
    missing = {}
    for row in sorted(rows, key=lambda item: (item["case"], item["repeat"])):
        if activation.missing_trial(row):
            missing.setdefault(row["case"], []).append(row["repeat"])
    if not missing:
        raise ValueError(f"{source} has no missing trials")
    if len({len(indexes) for indexes in missing.values()}) != 1:
        raise ValueError(f"{source}: cases miss different numbers of repeats, and one host call runs the same number for every case")
    return [row for row in rows if not activation.missing_trial(row)], missing


def merge_fill(rows, kept, missing, source, batch):
    """Put new rows at the repeats they replace and keep the source's trials, all under this batch. Return (rows, every trial present once)."""
    merged = [{**row, "batch": batch, "trial_batch": row.get("trial_batch") or source} for row in kept]
    for row in rows:
        indexes = missing.get(row["case"], [])
        repeat = indexes[row["repeat"]] if row["repeat"] < len(indexes) else None
        merged.append({**row, "repeat": repeat, "trial_batch": batch})
    trials = Counter((row["case"], row["repeat"]) for row in merged)
    expected = {(row["case"], row["repeat"]) for row in kept} | {(case, index) for case, indexes in missing.items() for index in indexes}
    complete = all(count == 1 for count in trials.values()) and set(trials) == expected and not any(activation.missing_trial(row) for row in merged)
    return sorted(merged, key=lambda row: (row["case"], row["repeat"] if row["repeat"] is not None else -1)), complete


def raise_on_sigterm(_signal, _frame):
    raise SystemExit(143)


def run_batch(args, suite, cases, plugin, manifest, plan, output, fill=None):
    key = read_key(args.model)
    raw = output / "raw"
    raw.mkdir(parents=True)
    os.chmod(output, stat.S_IRWXU)
    crowded = manifest["listing_condition"] == "crowded"
    identity = {"batch": args.batch, "arm": args.arm, "set": args.set, "model": args.model, "host_version": None, "suite_sha256": suite_hash(args.set),
                "source_commit": manifest["source_commit"], "source_dirty": manifest["source_dirty"], "tree_sha256": manifest["tree_sha256"],
                "description_sha256": manifest["description_sha256"], "guidance_sha256": manifest["guidance_sha256"],
                "listing_condition": manifest["listing_condition"]}
    state = {"identity": identity, "probe": None, "probe_aggregate": {}, "aggregate": {}, "probe_exit": None, "cases_exit": None, "rows": None,
             "probe_reason": None, "cases_reason": None, "probe_usage": {"tokens": None, "seconds": None}}
    before = run_roots()
    failure = interrupted = None
    previous_handler = signal.signal(signal.SIGTERM, raise_on_sigterm)
    try:
        try:
            collect_batch(state, args, cases, suite, plugin, raw, key, crowded)
        except Exception as error:
            failure = type(error).__name__
        except BaseException as error:
            failure, interrupted = type(error).__name__, error
        fresh = args.set == activation.SET_NAME
        rows = state["rows"]
        if rows is None:
            rows = collect_fresh({}, cases, args.repeats, plugin, identity) if fresh else collect({}, cases, args.repeats, suite, suite_module.load_routing(), plugin, identity)
        valid = batch_valid(state, cases, args.repeats, failure, plan["calls"], crowded, fresh)
        if fill:
            rows, complete = merge_fill(rows, fill["kept"], fill["missing"], args.fill_from, args.batch)
            valid = valid and complete and len({row.get("host_version") for row in rows}) == 1
        (output / "results.jsonl").write_text("".join(json.dumps({**row, "batch_valid": valid}) + "\n" for row in rows))
    finally:
        hits, unscanned, not_removed, foreign = clean_up(before, plugin, raw, key)
        signal.signal(signal.SIGTERM, previous_handler)
    found, missed = scan_for_secret(output, key)
    hits, unscanned = hits + found, unscanned + missed
    empty = empty_runs(state["probe_aggregate"]) + empty_runs(state["aggregate"])
    errors = Counter(host_error(run, key) for aggregate in (state["probe_aggregate"], state["aggregate"])
                     for runs in runs_by_case(aggregate).values() for run in runs if run.get("error"))
    # A host that exits 0 can still have skipped runs, so its last stderr line is kept whenever a run was empty.
    for name in ("probe", "cases"):
        if not state[f"{name}_exit"] and not empty:
            state[f"{name}_reason"] = None
    summary = {**plan, "observed_runs": observed_runs(state["probe_aggregate"]) + observed_runs(state["aggregate"]),
               "empty_runs": empty, "host_errors": [{"error": error, "runs": count} for error, count in errors.most_common(5)],
               "cost_usd": sum(item.get("costUsd") or 0 for item in (state["probe_aggregate"], state["aggregate"])),
               "partial": bool(state["probe_aggregate"].get("partial") or state["aggregate"].get("partial")),
               "malformed_aggregate": bool(state["probe_aggregate"].get("malformed") or state["aggregate"].get("malformed")),
               "listing_probe_passed": state["probe"], "probe_tokens": state["probe_usage"]["tokens"], "probe_seconds": state["probe_usage"]["seconds"],
               "valid": valid, "failure": failure, "key_found_in_output": hits, "unscanned_paths": unscanned, "paths_not_removed": not_removed,
               "foreign_run_directories_left": foreign, "key_scan_scope": "this batch's run directories, raw output and results; not the host config directory",
               "probe_exit": state["probe_exit"], "cases_exit": state["cases_exit"], "probe_reason": state["probe_reason"], "cases_reason": state["cases_reason"],
               "cases_version": state["aggregate"].get("claudeVersion"), **identity}
    text = json.dumps(summary, indent=1) + "\n"
    if key in text:
        # Count it before writing, so the file, the printed summary, the exit code and a later --fill-from all see it.
        hits += 1
        summary = json.loads(text.replace(key, "[key]"))
        summary["key_found_in_output"] = hits
        text = json.dumps(summary, indent=1) + "\n"
    (output / "summary.json").write_text(text)
    print(json.dumps({name: summary[name] for name in ("observed_runs", "empty_runs", "host_errors", "calls", "cost_usd", "partial", "malformed_aggregate", "listing_probe_passed", "valid", "failure",
                                                       "key_found_in_output", "unscanned_paths", "paths_not_removed", "foreign_run_directories_left",
                                                       "probe_exit", "cases_exit", "probe_reason", "cases_reason")}, indent=1))
    if interrupted:
        raise interrupted
    return 0 if valid and not (hits or unscanned or not_removed or foreign) else 4


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--batch", required=True)
    parser.add_argument("--arm", required=True)
    parser.add_argument("--set", required=True, choices=(*suite_module.SETS, activation.SET_NAME))
    parser.add_argument("--ids", default="")
    parser.add_argument("--seeds", action="store_true")
    parser.add_argument("--repeats", type=int, required=True)
    parser.add_argument("--model", default="deepseek-flash", choices=sorted(MODELS))
    parser.add_argument("--host-version", help="run on exactly this installed host version")
    parser.add_argument("--max-cost-usd", type=float, required=True)
    parser.add_argument("--authorized-calls", type=int, required=True)
    parser.add_argument("--fill-from", help="an activation batch of this arm whose trials that never ran are run now")
    parser.add_argument("--run", action="store_true")
    args = parser.parse_args()
    if not BATCH_NAME.match(args.batch) or not BATCH_NAME.match(args.arm):
        raise ValueError("batch and arm must be lowercase words joined by hyphens")
    if args.repeats < 1:
        raise ValueError("repeats must be at least 1")
    if not math.isfinite(args.max_cost_usd) or args.max_cost_usd <= 0:
        raise ValueError("max-cost-usd must be a finite amount above 0")
    suite, cases = select_cases(args.set, [item for item in args.ids.split(",") if item], args.seeds)
    if args.host_version:
        claude_binary(args.host_version)
    plugin, manifest = load_manifest(args.arm)
    if args.set == activation.SET_NAME and manifest["listing_condition"] != "isolated":
        print("refused: R-RUN-10 collects activation_cases in the isolated condition only", file=sys.stderr)
        return 2
    fill = None
    if args.fill_from:
        if args.set != activation.SET_NAME or args.ids or args.seeds or not args.host_version or not BATCH_NAME.match(args.fill_from):
            print("refused: --fill-from takes an activation batch name, all cases and --host-version", file=sys.stderr)
            return 2
        expected = {"arm": args.arm, "set": args.set, "model": args.model, "suite_sha256": suite_hash(args.set), "host_version": args.host_version,
                    **{name: manifest[name] for name in FILL_IDENTITY if name in manifest}}
        try:
            kept, missing = fill_source(args.fill_from, expected, args.repeats, [case["id"] for case in cases])
        except ValueError as error:
            print(f"refused: {error}", file=sys.stderr)
            return 2
        fill = {"kept": kept, "missing": missing}
        arm_cases, arm_repeats = len(cases), args.repeats
        cases = [case for case in cases if case["id"] in missing]
        # The host call runs only the missing repeats; the summary still describes the merged arm.
        args.repeats = len(next(iter(missing.values())))
    plan = run_plan(args, cases, plugin, manifest)
    if fill:
        plan.update(cases=arm_cases, repeats=arm_repeats, fill_from=args.fill_from, filled_cases=len(cases), filled_repeats=args.repeats,
                    kept_trials=len(fill["kept"]), filled_trials=plan["calls"])
    calls = plan["calls"]
    print(json.dumps(plan, indent=1))
    if args.authorized_calls != calls:
        print(f"refused: {args.authorized_calls} calls authorized, this batch makes {calls}", file=sys.stderr)
        return 2
    refusals = run_refusals(args.set)
    if refusals:
        print("refused:\n" + "\n".join(refusals), file=sys.stderr)
        return 2
    if not args.run:
        print("plan only: pass --run to collect")
        return 0
    output = RESULTS / args.batch
    RESULTS.mkdir(parents=True, exist_ok=True)
    with open(RESULTS / ".lock", "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            print("refused: another batch is running", file=sys.stderr)
            return 2
        if output.exists():
            print(f"refused: {output} already exists", file=sys.stderr)
            return 2
        return run_batch(args, suite, cases, plugin, manifest, plan, output, fill)


if __name__ == "__main__":
    sys.exit(main())
