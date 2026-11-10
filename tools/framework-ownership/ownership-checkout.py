#!/usr/bin/env python3
"""Checkout-only Assistant Framework ownership entry point (Unix).

Never installed into an agent home: both installers exclude this file from the
tools sync. It reuses the installed helper's proof code (ownership.py) and adds:

  install    Installer mode: remove proven-owned retired skills and agent files.
             Called by install.sh; takes no manifest and never prompts.
  uninstall  Remove every proven framework-owned item for one agent.
  build-data Regenerate content-proof.json and installer-exact-removal.tsv from
             Git history; --check verifies them and the inventory's retired_in.

It refuses to run unless it sits in a Git checkout whose root holds install.sh
and install.ps1, outside every agent home and ~/.agents.
"""

import importlib.util
import json
import os
import subprocess
import sys

sys.dont_write_bytecode = True

SCRIPT_DIRECTORY = os.path.dirname(os.path.realpath(__file__))


def load_helper():
    spec = importlib.util.spec_from_file_location("assistant_framework_ownership", os.path.join(SCRIPT_DIRECTORY, "ownership.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


helper = load_helper()
Refusal = helper.Refusal

INVENTORY_RELATIVE = "tools/framework-ownership/retired-items.json"
PROOF_FILE = "content-proof.json"
TSV_FILE = "installer-exact-removal.tsv"

# Ids seeded when the inventory was introduced (S11). Frozen: never extended.
# Every later entry is a same-change retirement validated by the same-change rule.
SEEDED_IDS = frozenset({
    "skill/assistant-memory",
    "skill/assistant-memory@windows",
    "skill/assistant-memory@agents-skills",
    "skill/assistant-reflexion",
    "skill/assistant-reflexion@windows",
    "skill/assistant-reflexion@agents-skills",
    "hook_entrypoint/session-start.sh",
    "hook_entrypoint/skill-router.sh",
    "hook_entrypoint/learning-signals.sh",
    "hook_entrypoint/workflow-enforcer.sh",
    "hook_entrypoint/workflow-guard.sh",
    "hook_entrypoint/stop-review.sh",
    "hook_entrypoint/harness-gate.sh",
    "hook_entrypoint/subagent-monitor.sh",
    "hook_entrypoint/pre-compress.sh",
    "hook_entrypoint/post-compact.sh",
    "hook_entrypoint/session-end.sh",
    "hook_entrypoint/post-tool-context.sh",
    "hook_entrypoint/tool-failure-advisor.sh",
    "hook_entrypoint/task-completed.sh",
    "hook_helper/task-journal-resolver.sh",
    "hook_helper/workflow-phase-gates.sh",
    "hook_helper/hook-runtime.sh",
    "hook_module/workflow-phase-gates.d/learning-controller.sh",
    "hook_module/workflow-phase-gates.d/metrics.sh",
    "hook_module/workflow-phase-gates.d/qa-controller.sh",
    "hook_module/workflow-phase-gates.d/review-controller.sh",
    "hook_module/workflow-phase-gates.d/subagent-evidence.sh",
    "hook_module/workflow-phase-gates.d/subagent-orchestration.sh",
    "hook_module/workflow-guard.d/path-policy.sh",
    "hook_module/workflow-guard.d/shell-write-parser.sh",
    "hook_module/workflow-guard.d/workflow-state-artifacts.sh",
    "hook_registration/session-start.sh",
    "hook_registration/skill-router.sh",
    "hook_registration/learning-signals.sh",
    "hook_registration/workflow-enforcer.sh",
    "hook_registration/workflow-guard.sh",
    "hook_registration/stop-review.sh",
    "hook_registration/harness-gate.sh",
    "hook_registration/subagent-monitor.sh",
    "hook_registration/pre-compress.sh",
    "hook_registration/post-compact.sh",
    "hook_registration/session-end.sh",
    "hook_registration/post-tool-context.sh",
    "hook_registration/tool-failure-advisor.sh",
    "hook_registration/task-completed.sh",
    "hook_registration/task-journal-resolver.sh",
    "hook_registration/workflow-phase-gates.sh",
    "hook_registration/hook-runtime.sh",
    "source_only_tool/context-budget-report.sh",
    "source_only_tool/evals/run-codex-framework-evals.sh",
    "source_only_tool/evals/finalize-workflow-kernel-review.sh",
    "source_only_tool/evals/lib/context-budget-evidence.sh",
    "source_only_tool/evals/validate-promotion-decision-schema.cjs",
    "source_only_tool/evals/package.json",
    "source_only_tool/evals/package-lock.json",
    "source_only_tool/evals/node_modules",
    "managed_tool/plugins/sync-plugin-skills.sh",
    "managed_tool_empty_directory/plugins",
    "managed_tool/cleanup-memory-graph.ps1",
    "managed_tool/cleanup-memory-graph.sh",
    "managed_tool/memory-graph",
    "instruction_block/memory-protocol/claude",
    "instruction_block/memory-protocol/codex",
    "instruction_block/memory-protocol/gemini",
})

# Top-level tools entries the installers never install (install.sh
# set_owned_sync_exclusions; install.ps1 $toolExclusions and source-only paths).
TOOL_TOP_LEVEL_EXCLUDES = (".DS_Store", "memory-graph", "context-budget-report.sh", "plugins")
TOOL_NAME_EXCLUDES = (".DS_Store", ".publish", "bin", "obj", "__pycache__")
CURRENT_BLOCK_MARKERS = {
    "start": "<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_START -->",
    "end": "<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_END -->",
}
CURRENT_INSTRUCTION_FILES = {"claude": "CLAUDE.md", "codex": "AGENTS.md"}
RULES_NOTICE = (
    "The framework's Codex execution-policy safeguards are no longer installed: the prompts "
    "for git push, force push, git commit, git reset --hard, git branch -D and rm -rf "
    "(rules/workflow.rules)."
)


# ── Location checks ─────────────────────────────────────────────────────────


def checkout_root():
    return os.path.dirname(os.path.dirname(SCRIPT_DIRECTORY))


def location_problem(environ=None):
    """Return why this entry point must not run here, or None."""
    environ = os.environ if environ is None else environ
    root = checkout_root()
    for name in ("install.sh", "install.ps1"):
        if not os.path.isfile(os.path.join(root, name)):
            return f"not inside a framework checkout ({name} missing at {root})"
    if not os.path.lexists(os.path.join(root, ".git")):
        return f"not inside a Git checkout (no .git at {root})"
    user_home = environ.get("HOME", "")
    homes = []
    if user_home:
        homes += [os.path.join(user_home, ".claude"), os.path.join(user_home, ".codex"), os.path.join(user_home, ".gemini")]
        agents_root = os.path.join(user_home, ".agents")
        homes.append(agents_root)
        if os.path.islink(agents_root):
            homes.append(os.path.realpath(agents_root))
    if environ.get("CODEX_HOME"):
        homes.append(environ["CODEX_HOME"])
    for home in homes:
        if helper.same_or_inside(SCRIPT_DIRECTORY, home):
            return f"located inside an agent home or ~/.agents ({home})"
    return None


def require_location():
    problem = location_problem()
    if problem:
        raise Refusal(problem)


# ── Git history ─────────────────────────────────────────────────────────────


def git(repo, *arguments, input_bytes=None, check=True):
    process = subprocess.run(["git", "-C", repo] + list(arguments), input=input_bytes, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if check and process.returncode != 0:
        raise Refusal(f"git {' '.join(arguments[:2])} failed: {process.stderr.decode('utf-8', 'replace').strip()}")
    return process


def main_ref(repo, required=True):
    for ref in ("refs/remotes/origin/main", "refs/heads/main"):
        if git(repo, "rev-parse", "--verify", "--quiet", ref + "^{commit}", check=False).returncode == 0:
            return ref
    if required:
        raise Refusal("no main ref (refs/remotes/origin/main or refs/heads/main) in the checkout")
    return None


def require_full_history(repo):
    shallow = git(repo, "rev-parse", "--is-shallow-repository").stdout.decode().strip()
    if shallow == "true":
        raise Refusal("shallow repository: content proof and retired_in checks need full Git history (fetch-depth: 0)")


def history_blobs(repo, revisions, paths, include_head_tree=True):
    """Return {(path, blob)} for every version of the paths reachable from revisions."""
    found = set()
    if not paths:
        return found
    if revisions:
        output = git(repo, "log", "--full-history", "--raw", "--no-renames", "--no-abbrev", "-m", "--root", "--format=commit %H", *revisions, "--", *paths).stdout
        for line in output.decode("utf-8", "surrogateescape").splitlines():
            if not line.startswith(":"):
                continue
            meta, path = line.split("\t", 1)
            fields = meta.split()
            mode, blob = fields[1], fields[3]
            if mode in ("100644", "100755") and set(blob) != {"0"}:
                found.add((path, blob))
    if include_head_tree:
        output = git(repo, "ls-tree", "-r", "--full-tree", "HEAD", "--", *paths).stdout
        for line in output.decode("utf-8", "surrogateescape").splitlines():
            meta, path = line.split("\t", 1)
            mode, kind, blob = meta.split()
            if kind == "blob" and mode in ("100644", "100755"):
                found.add((path, blob))
    return found


def read_blobs(repo, blobs):
    contents = {}
    unique = sorted(set(blobs))
    if not unique:
        return contents
    process = git(repo, "cat-file", "--batch", input_bytes=("\n".join(unique) + "\n").encode("ascii"))
    data = process.stdout
    position = 0
    for blob in unique:
        newline = data.index(b"\n", position)
        header = data[position:newline].decode("ascii").split()
        size = int(header[2])
        start = newline + 1
        contents[blob] = data[start:start + size]
        position = start + size + 1
    return contents


def fingerprint_items(repo, items, revisions, include_head_tree=True):
    """items: [(key, source_path, node_type, agents, add_shim)] -> proofs dict."""
    paths = sorted({source for _, source, _, _, _ in items})
    blobs = history_blobs(repo, revisions, paths, include_head_tree)
    contents = read_blobs(repo, [blob for _, blob in blobs])
    proofs = {}
    for key, source, node_type, agents, add_shim in items:
        files = proofs.setdefault(key, {"files": {}})["files"]
        for path, blob in blobs:
            if node_type == "file":
                if path != source:
                    continue
                relative = ""
            else:
                if not path.startswith(source + "/"):
                    continue
                relative = path[len(source) + 1:]
            per_agent = files.setdefault(relative, {})
            for agent, hashes in helper.fingerprints_for_blob(path, contents[blob], agents).items():
                per_agent.setdefault(agent, set()).update(hashes)
        if add_shim:
            per_agent = files.setdefault("", {})
            for agent in agents:
                per_agent.setdefault(agent, set()).add(helper.sha256_hex(helper.SHIM_BYTES))
    for value in proofs.values():
        for per_agent in value["files"].values():
            for agent in list(per_agent):
                per_agent[agent] = sorted(per_agent[agent])
    return proofs


# ── Data build ──────────────────────────────────────────────────────────────


def proof_source(entry):
    if entry["kind"] == "source_only_tool":
        return "tools/" + helper.tool_relative_path(entry)
    return entry["source_path"]


def proof_items(inventory):
    grouped = {}
    for entry in inventory["entries"]:
        key = entry.get("content_proof")
        if not key:
            continue
        source = proof_source(entry)
        current = grouped.setdefault(key, [source, entry["node_type"], set(), entry["kind"] == "hook_entrypoint"])
        if current[0] != source or current[1] != entry["node_type"]:
            raise Refusal(f"content_proof key {key} is shared by entries with different sources")
        current[2].update(entry["agents"])
    return [(key, source, node_type, sorted(agents), shim) for key, (source, node_type, agents, shim) in sorted(grouped.items())]


def generate_data(repo, inventory, revisions):
    proofs = fingerprint_items(repo, proof_items(inventory), revisions)
    empty = sorted(key for key, value in proofs.items() if not value["files"])
    if empty:
        raise Refusal(f"no history found for content_proof keys: {', '.join(empty)}")
    proof = {"schema_version": "1.0", "proofs": proofs}
    proof_text = json.dumps(proof, indent=1, sort_keys=True) + "\n"
    tsv_text = "".join(line + "\n" for line in helper.build_installer_list(inventory, "unix"))
    return proof, proof_text, tsv_text


def read_inventory(directory):
    inventory, inventory_bytes = helper.read_json_file(os.path.join(directory, "retired-items.json"), "inventory")
    return inventory, inventory_bytes


def tree_contains(repo, commit, path):
    return git(repo, "cat-file", "-e", f"{commit}:{path}", check=False).returncode == 0


def is_ancestor(repo, ancestor, descendant):
    return git(repo, "merge-base", "--is-ancestor", ancestor, descendant, check=False).returncode == 0


def delete_only(repo, commit, path):
    output = git(repo, "log", "--full-history", "-m", "--format=", "--name-status", "--no-renames", "HEAD", "^" + commit, "--", path).stdout.decode("utf-8", "replace")
    for line in output.splitlines():
        if line.strip() and not line.startswith("D\t"):
            return False
    return True


def check_retired_in(repo, inventory, main):
    problems = []
    seeded_queries = {}
    for entry in inventory["entries"]:
        commit = entry.get("retired_in")
        if not commit:
            continue
        source = entry["source_path"]
        label = f"{entry['id']}: retired_in {commit[:12]}"
        if not tree_contains(repo, commit, source):
            problems.append(f"{label} does not contain {source}")
            continue
        if not is_ancestor(repo, commit, main):
            problems.append(f"{label} is not reachable from {main}")
            continue
        if tree_contains(repo, "HEAD", source):
            problems.append(f"{entry['id']}: the tree holding the entry still contains {source}")
            continue
        if entry["id"] in SEEDED_IDS:
            seeded_queries.setdefault(commit, []).append((entry, source))
            continue
        if not is_ancestor(repo, commit, "HEAD"):
            problems.append(f"{label} is not an ancestor of HEAD")
            continue
        if tree_contains(repo, main, source):
            touched = git(repo, "log", "--full-history", "--format=%H", main, "^" + commit, "--", source).stdout.strip()
            if touched:
                problems.append(f"{label}: a main commit after it touches {source}; update retired_in")
                continue
        if not delete_only(repo, commit, source):
            problems.append(f"{label}: a commit after it changes {source} other than deleting it")
    for commit, pairs in seeded_queries.items():
        descendants = git(repo, "rev-list", "--ancestry-path", f"{commit}..{main}").stdout.decode().split()
        if not descendants:
            continue
        queries = "".join(f"{descendant}:{source}\n" for descendant in descendants for _, source in pairs)
        output = git(repo, "cat-file", "--batch-check", input_bytes=queries.encode("utf-8")).stdout.decode("utf-8", "replace").splitlines()
        index = 0
        for descendant in descendants:
            for entry, source in pairs:
                line = output[index]
                index += 1
                if not line.endswith(" missing"):
                    problems.append(f"{entry['id']}: retired_in {commit[:12]} has a main-reachable descendant {descendant[:12]} that contains {source}")
    return sorted(set(problems))


# Entries allowed to carry installer_exact_removal: the tool paths the base
# installers already removed by exact path. Proof-free installer removal never
# grows (D-S11-8), so a new entry may not join this list.
EXACT_REMOVAL_IDS = frozenset((
    "managed_tool/cleanup-memory-graph.ps1",
    "managed_tool/cleanup-memory-graph.sh",
    "managed_tool/plugins/sync-plugin-skills.sh",
    "managed_tool_empty_directory/plugins",
    "source_only_tool/context-budget-report.sh",
    "source_only_tool/evals/finalize-workflow-kernel-review.sh",
    "source_only_tool/evals/lib/context-budget-evidence.sh",
    "source_only_tool/evals/node_modules",
    "source_only_tool/evals/package-lock.json",
    "source_only_tool/evals/package.json",
    "source_only_tool/evals/run-codex-framework-evals.sh",
    "source_only_tool/evals/validate-promotion-decision-schema.cjs",
))


def check_exact_removal_ids(inventory):
    carrying = {entry["id"] for entry in inventory["entries"] if entry.get("installer_exact_removal")}
    extra = sorted(carrying - EXACT_REMOVAL_IDS)
    return [f"{entry_id}: installer_exact_removal is limited to the entries seeded with it" for entry_id in extra]


def check_seeded_ids(repo, inventory):
    introduced = git(repo, "log", "--diff-filter=A", "--format=%H", "HEAD", "--", INVENTORY_RELATIVE).stdout.decode().split()
    if introduced:
        blob = git(repo, "show", f"{introduced[-1]}:{INVENTORY_RELATIVE}").stdout
        ids = {entry["id"] for entry in json.loads(blob.decode("utf-8"))["entries"]}
        where = f"the commit that introduced the inventory ({introduced[-1][:12]})"
    else:
        ids = {entry["id"] for entry in inventory["entries"]}
        where = "the uncommitted inventory"
    if ids != SEEDED_IDS:
        extra = sorted(SEEDED_IDS - ids)
        missing = sorted(ids - SEEDED_IDS)
        return [f"SEEDED_IDS differs from {where}: only in SEEDED_IDS {extra}; only in the inventory {missing}"]
    if introduced:
        seeded = {entry["id"]: entry for entry in json.loads(blob.decode("utf-8"))["entries"]}
        current = {entry["id"]: entry for entry in inventory["entries"]}
        return [f"{entry_id}: a seeded entry was edited after {where}" for entry_id in sorted(SEEDED_IDS) if current.get(entry_id) != seeded[entry_id]]
    return []


def command_build_data(arguments, out):
    values = helper.parse_options(arguments, {"--check": False})
    require_location()
    repo = checkout_root()
    require_full_history(repo)
    main = main_ref(repo)
    inventory, inventory_bytes = read_inventory(SCRIPT_DIRECTORY)
    proof, proof_text, tsv_text = generate_data(repo, inventory, [main])
    helper.validate_inventory(inventory, proof)
    proof_path = os.path.join(SCRIPT_DIRECTORY, PROOF_FILE)
    tsv_path = os.path.join(SCRIPT_DIRECTORY, TSV_FILE)
    if not values.get("--check"):
        with open(proof_path, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(proof_text)
        with open(tsv_path, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(tsv_text)
        out.write(f"Wrote {PROOF_FILE} ({len(proof['proofs'])} keys) and {TSV_FILE}\n")
        return helper.EXIT_OK
    problems = []
    for path, expected, label in ((proof_path, proof_text, PROOF_FILE), (tsv_path, tsv_text, TSV_FILE)):
        try:
            with open(path, "r", encoding="utf-8", newline="") as stream:
                actual = stream.read()
        except OSError:
            actual = None
        if actual != expected:
            problems.append(f"{label} differs from what the inventory and history produce; run build-data")
    head_proof = fingerprint_items(repo, proof_items(inventory), ["HEAD"])
    for key, value in proof["proofs"].items():
        for relative, per_agent in value["files"].items():
            for agent, hashes in per_agent.items():
                allowed = set(head_proof.get(key, {}).get("files", {}).get(relative, {}).get(agent, []))
                if not set(hashes) <= allowed:
                    problems.append(f"content proof for {key} holds a hash from no commit reachable from HEAD")
    problems += check_retired_in(repo, inventory, main)
    problems += check_seeded_ids(repo, inventory)
    problems += check_exact_removal_ids(inventory)
    if problems:
        for problem in sorted(set(problems)):
            out.write(f"problem: {problem}\n")
        raise Refusal(f"data check failed ({len(set(problems))} problem(s))")
    out.write(f"Data check passed: {len(inventory['entries'])} entries, {len(proof['proofs'])} content-proof keys\n")
    return helper.EXIT_OK


# ── Installer mode ──────────────────────────────────────────────────────────


def run_install(agent, dry_run, out, after_plan=None):
    """Plan and remove proven-owned retired skills and agent files for one agent."""
    homes = helper.resolve_homes(agent)
    data = helper.load_data(SCRIPT_DIRECTORY)
    planner = helper.Planner(data, agent, "install", homes)
    findings = planner.plan(kinds=helper.INSTALL_MODE_KINDS)
    manifest = helper.build_manifest(planner, findings)
    removable = [f for f in findings if f.status == "removable"]
    kept = [f for f in findings if f.status in ("ambiguous", "unrelated")]
    out.write(f"Retired skills and agents for {agent}:\n")
    for finding in removable:
        out.write(f"  remove: {helper.display_path(planner, finding)} ({finding.kind})\n")
    for finding in kept:
        label = "kept (unrelated)" if finding.status == "unrelated" else "kept"
        out.write(f"  {label}: {helper.display_path(planner, finding)}: {finding.reason}\n")
    out.write(f"  Retired-item plan digest: {manifest['manifest_digest']}\n")
    if after_plan is not None:
        after_plan(manifest)
    if dry_run:
        out.write(f"  [dry-run] Retired items: {len(removable)} to remove, {len(kept)} kept.\n")
        if kept:
            out.write(f"  Kept items stay in place; {helper.CLEANUP_POINTER}.\n")
        return helper.EXIT_KEPT if kept else helper.EXIT_OK
    result = helper.apply_items(planner, manifest["items"])
    for item in result.removed:
        out.write(f"  removed: {item['path']}\n")
    for item, reason in result.skipped:
        out.write(f"  skipped: {item['path']}: {reason}\n")
    total_kept = len(kept) + len(result.skipped)
    out.write(f"  Retired items: {len(result.removed)} removed, {total_kept} kept.\n")
    if total_kept:
        out.write(f"  Kept items stay in place; {helper.CLEANUP_POINTER}.\n")
    return helper.EXIT_KEPT if total_kept else helper.EXIT_OK


def command_install(arguments, out):
    values = helper.parse_options(arguments, {"--agent": True, "--dry-run": False})
    agent = helper.require_agent(values)
    require_location()
    return run_install(agent, bool(values.get("--dry-run")), out)


# ── Uninstall ───────────────────────────────────────────────────────────────


def current_specs(repo, agent):
    """Current framework items the installers write for this agent (Unix layout)."""
    specs = []

    def add(kind, path, node_type, source, **extra):
        spec = {"id": f"current/agent_home/{path}", "kind": kind, "root": "agent_home", "path": path, "node_type": node_type,
                "content_proof": "current:" + source, "source": source, "current": True}
        spec.update(extra)
        specs.append(spec)

    skills = os.path.join(repo, "skills")
    for name in sorted(os.listdir(skills)):
        if name.startswith("assistant-") and os.path.isfile(os.path.join(skills, name, "SKILL.md")):
            add("current_skill_directory", f"skills/{name}", "directory", f"skills/{name}")
    tools = os.path.join(repo, "tools")
    for name in sorted(os.listdir(tools)):
        if name in TOOL_TOP_LEVEL_EXCLUDES or name in TOOL_NAME_EXCLUDES or name.endswith(".pyc"):
            continue
        absolute = os.path.join(tools, name)
        if os.path.islink(absolute):
            continue
        if os.path.isdir(absolute):
            add("current_tool_entry", f"tools/{name}", "directory", f"tools/{name}", build_artifacts=True,
                location_subtrees=["node_modules"] if name == "evals" else [])
        else:
            add("current_tool_entry", f"tools/{name}", "file", f"tools/{name}")
    evals = os.path.join(repo, "docs", "evals")
    if os.path.isdir(evals):
        for name in sorted(os.listdir(evals)):
            if name == ".DS_Store" or os.path.islink(os.path.join(evals, name)):
                continue
            node_type = "directory" if os.path.isdir(os.path.join(evals, name)) else "file"
            add("current_eval_doc_entry", f"docs/evals/{name}", node_type, f"docs/evals/{name}")
    if agent in ("claude", "codex"):
        folder, suffix = ("claude", ".md") if agent == "claude" else ("codex", ".toml")
        source_dir = os.path.join(repo, "agents", folder)
        if os.path.isdir(source_dir):
            for name in sorted(os.listdir(source_dir)):
                if name.endswith(suffix) and os.path.isfile(os.path.join(source_dir, name)):
                    add("current_agent_file", f"agents/{name}", "file", f"agents/{folder}/{name}")
    if agent == "codex":
        rules = os.path.join(repo, "codex-rules")
        for name in sorted(os.listdir(rules)):
            if name.endswith(".rules") and os.path.isfile(os.path.join(rules, name)):
                add("current_codex_rule", f"rules/{name}", "file", f"codex-rules/{name}")
    if agent in CURRENT_INSTRUCTION_FILES:
        name = CURRENT_INSTRUCTION_FILES[agent]
        specs.append({"id": f"current/agent_home/{name}", "kind": "current_instruction_block", "root": "agent_home", "path": name,
                      "markers": dict(CURRENT_BLOCK_MARKERS), "current": True})
    return specs


def current_fingerprints(repo, agent, specs):
    items = [(spec["content_proof"], spec["source"], spec["node_type"], [agent], False) for spec in specs if "source" in spec]
    main = main_ref(repo, required=False)
    revisions = [main] if main else ["HEAD"]
    return fingerprint_items(repo, items, revisions)


def assert_no_checkout_overlap(home, repo):
    if helper.same_or_inside(home, repo) or helper.same_or_inside(repo, home):
        raise Refusal(f"the agent home and the framework checkout overlap: {home} and {repo}")


def uninstall_planner(agent):
    require_location()
    repo = checkout_root()
    homes = helper.resolve_homes(agent)
    assert_no_checkout_overlap(homes["agent_home"], repo)
    require_full_history(repo)
    data = helper.load_data(SCRIPT_DIRECTORY)
    specs = current_specs(repo, agent)
    fingerprints = current_fingerprints(repo, agent, specs)
    return helper.Planner(data, agent, "uninstall", homes, checkout_dir=repo, current_specs=specs, current_fingerprints=fingerprints)


def agents_link_note(planner):
    if planner.agent != "codex":
        return []
    link = os.path.join(planner.homes["user_home"], ".agents")
    if os.path.islink(link):
        return [helper.Finding("agents-link", "agent_home", "~/.agents", "info", "info", "symbolic link kept; it may serve other agentskills.io tools")]
    return []


def command_uninstall(arguments, out, before_delete=None):
    values = helper.parse_options(arguments, {"--agent": True, "--dry-run": False, "--yes": False, "--plan-digest": True})
    agent = helper.require_agent(values)
    planner = uninstall_planner(agent)
    findings = planner.plan()
    manifest = helper.build_manifest(planner, findings)
    helper.print_report(planner, findings + agents_link_note(planner), manifest, out, "Assistant Framework uninstall plan")
    if values.get("--dry-run"):
        out.write("Dry run: nothing was removed.\n")
        return helper.EXIT_OK
    if values.get("--yes"):
        given = values.get("--plan-digest")
        if not given:
            raise Refusal("--yes requires --plan-digest from a prior dry run")
        if given != manifest["manifest_digest"]:
            out.write(f"Current plan digest: {manifest['manifest_digest']}\n")
            raise Refusal("the plan changed since the dry run (digest mismatch); review the new plan and rerun")
    elif "--plan-digest" in values:
        raise Refusal("--plan-digest is used only with --yes")
    else:
        if not helper.interactive():
            raise Refusal("a non-interactive uninstall requires --yes and --plan-digest")
        if not helper.confirm_by_typing(agent, len(manifest["items"]), out):
            raise Refusal("confirmation not given; nothing was removed")
    result = helper.apply_items(planner, manifest["items"], before_delete=before_delete)
    helper.print_apply_result(result, out)
    if any(item["kind"] == "current_codex_rule" and item["path"] == "rules/workflow.rules" for item in result.removed):
        out.write(RULES_NOTICE + "\n")
    kept = [f for f in findings if f.status == "ambiguous"]
    if kept or result.skipped:
        out.write("Completed with items kept; they are listed above.\n")
        return helper.EXIT_KEPT
    return helper.EXIT_OK


SUBCOMMANDS = ("install", "uninstall", "build-data")


def main(argv=None, out=None):
    argv = sys.argv[1:] if argv is None else argv
    out = out or sys.stdout
    if not argv or argv[0] not in SUBCOMMANDS:
        sys.stderr.write("refused: the first argument must be one of: install, uninstall, build-data\n")
        return helper.EXIT_REFUSED
    command, arguments = argv[0], argv[1:]
    try:
        if command == "install":
            return command_install(arguments, out)
        if command == "uninstall":
            return command_uninstall(arguments, out)
        return command_build_data(arguments, out)
    except Refusal as refusal:
        if command == "install":
            out.write(f"  ownership helper refused: {refusal}; kept\n")
        sys.stderr.write(f"refused: {refusal}\n")
        return helper.EXIT_REFUSED
    except KeyboardInterrupt:
        sys.stderr.write("refused: interrupted\n")
        return helper.EXIT_REFUSED


if __name__ == "__main__":
    sys.exit(main())
