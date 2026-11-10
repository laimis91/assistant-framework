#!/usr/bin/env python3
"""Unit and disposable-home tests for tools/framework-ownership (S11).

Every helper, installer and uninstall run here uses a disposable HOME under a
temporary directory with CODEX_HOME set or unset explicitly. Uninstall cases run
from a temporary clone of this checkout with the working tree committed in it,
never from the real checkout and never against a real home.
"""

import copy
import hashlib
import importlib.util
import io
import json
import os
import pty
import select
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

sys.dont_write_bytecode = True

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TOOL_DIR = os.path.join(REPO, "tools", "framework-ownership")
HELPER = os.path.join(TOOL_DIR, "ownership.py")
CHECKOUT_ENTRY = os.path.join(TOOL_DIR, "ownership-checkout.py")

FDFF = "fdff2dc7cf5719e3c231e5c17f34c9207239c343"
HOOKS = "f68887c3d75c7e711e62749bcaf90aee2a11d312"
CLEANUP_TOOLS = "201709378bd87c868a6b326fc144d61ed500913c"
PLUGINS = "36a59a5600b89058135cf37f26f0fb8aa00d9d52"
D11756D = "d11756d"
SUBSTITUTED = (".md", ".yaml", ".yml", ".json", ".conf", ".toml")


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


ownership = load("ownership_under_test", HELPER)
checkout = load("ownership_checkout_under_test", CHECKOUT_ENTRY)


def git(*arguments, cwd=REPO):
    return subprocess.run(["git", "-C", cwd] + list(arguments), check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout


def git_files(rev, path):
    return git("ls-tree", "-r", "--name-only", rev, "--", path).decode().split()


def installed_bytes(rev, path, agent):
    data = git("show", f"{rev}:{path}")
    if path.endswith(SUBSTITUTED):
        data = data.replace(b"{agent_state_dir}", ("." + agent).encode())
    return data


def write(path, data, mode=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as stream:
        stream.write(data if isinstance(data, bytes) else data.encode())
    if mode is not None:
        os.chmod(path, mode)


def seed_tree(rev, source, target, agent):
    for path in git_files(rev, source):
        write(os.path.join(target, path[len(source) + 1:]), installed_bytes(rev, path, agent))


def seed_file(rev, source, target, agent):
    write(target, installed_bytes(rev, source, agent))


def snapshot(root):
    """Full manifest of a tree: path, type, mode, owner, mtime and content hash."""
    result = {}
    if not os.path.lexists(root):
        return result
    for directory, names, files in os.walk(root, followlinks=False):
        for name in names + files:
            path = os.path.join(directory, name)
            status = os.lstat(path)
            relative = os.path.relpath(path, root)
            if stat.S_ISLNK(status.st_mode):
                value = ("link", os.readlink(path))
            elif stat.S_ISDIR(status.st_mode):
                value = ("dir", "")
            else:
                with open(path, "rb") as stream:
                    value = ("file", hashlib.sha256(stream.read()).hexdigest())
            result[relative] = value + (stat.S_IMODE(status.st_mode), status.st_uid, status.st_mtime_ns)
    return result


def read_json(path):
    with open(path, encoding="utf-8") as stream:
        return json.load(stream)


def parse_digest(output, label="Manifest digest: "):
    for line in output.splitlines():
        if line.startswith(label):
            return line[len(label):].strip()
        if line.strip().startswith(label):
            return line.strip()[len(label):].strip()
    raise AssertionError(f"no digest in output:\n{output}")


def parse_manifest(output):
    start = output.index("BEGIN MANIFEST\n") + len("BEGIN MANIFEST\n")
    end = output.index("END MANIFEST\n")
    return json.loads(output[start:end])


class Home:
    """A disposable HOME with sentinels outside and inside the agent homes."""

    def __init__(self, test):
        self.base = tempfile.mkdtemp(prefix="s11-home.")
        test.addCleanup(shutil.rmtree, self.base, True)
        self.home = os.path.join(self.base, "home")
        os.makedirs(self.home)
        self.sentinel_dir = os.path.join(self.base, "sentinel")
        write(os.path.join(self.sentinel_dir, "SKILL.md"), b"sentinel skill\n")
        write(os.path.join(self.sentinel_dir, "keep.bin"), b"\x00\x01binary\n")
        write(os.path.join(self.base, "telos", "purpose.md"), b"outside telos purpose\n")
        self.codex_home = None

    def agent_home(self, agent):
        if agent == "codex" and self.codex_home:
            return self.codex_home
        return os.path.join(self.home, "." + agent)

    def seed_sentinels(self, agent):
        home = self.agent_home(agent)
        write(os.path.join(home, "config.toml"), b"model = 'x'\n")
        write(os.path.join(home, "tools", "company-custom-tool.txt"), b"\x00custom tool\n")
        write(os.path.join(home, "docs", "evals", "custom.md"), b"custom eval doc\n")
        write(os.path.join(home, "skills", "my-skill", "SKILL.md"), b"user skill\n")
        write(os.path.join(home, "telos", "purpose.md"), b"telos purpose inside home\n")
        write(os.path.join(home, "rules", "default.rules"), b"prefix_rule(pattern=['ls'], decision='allow')\n")
        write(os.path.join(home, "agents", "my-agent.md"), b"user agent\n")
        write(os.path.join(self.home, ".claude.json"), b"{\"user\": true}\n")

    def env(self, codex_home=None, extra=None):
        environment = {"HOME": self.home, "PATH": os.environ.get("PATH", "/usr/bin:/bin"), "LC_ALL": "C.UTF-8", "PYTHONDONTWRITEBYTECODE": "1"}
        if codex_home:
            environment["CODEX_HOME"] = codex_home
        if extra:
            environment.update(extra)
        return environment

    def outside_snapshot(self):
        return {"sentinel": snapshot(self.sentinel_dir), "telos": snapshot(os.path.join(self.base, "telos")), "claude_json": snapshot(os.path.join(self.home, ".claude.json"))}


def run(arguments, env, input_bytes=b"", cwd=None):
    process = subprocess.run(arguments, env=env, input=input_bytes, stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=cwd)
    return process.returncode, process.stdout.decode("utf-8", "replace"), process.stderr.decode("utf-8", "replace")


def helper(home, *arguments, codex_home=None, cwd=None, script=HELPER):
    return run([sys.executable, script] + list(arguments), home.env(codex_home), cwd=cwd)


# ── T1: inventory schema and data ───────────────────────────────────────────


class InventoryValidation(unittest.TestCase):
    def setUp(self):
        with open(os.path.join(TOOL_DIR, "retired-items.json"), "rb") as stream:
            self.inventory = json.loads(stream.read())
        with open(os.path.join(TOOL_DIR, "content-proof.json"), "rb") as stream:
            self.proof = json.loads(stream.read())

    def entry(self, entry_id):
        return next(e for e in self.inventory["entries"] if e["id"] == entry_id)

    def refuse(self, inventory, text):
        with self.assertRaises(ownership.Refusal) as caught:
            ownership.validate_inventory(inventory, self.proof)
        self.assertIn(text, str(caught.exception))

    def test_committed_inventory_and_data_validate(self):
        ownership.validate_inventory(self.inventory, self.proof)

    def test_seeded_memory_skill_anchor(self):
        entry = self.entry("skill/assistant-memory")
        self.assertEqual(entry["source_path"], "skills/assistant-memory")
        self.assertEqual(entry["retired_in"], FDFF, "seeded retired_in for skills/assistant-memory must be fdff2dc")
        self.assertEqual(git("rev-parse", "7e2fedd^").decode().strip(), FDFF)

    def test_seeded_hook_entrypoint_anchor(self):
        entry = self.entry("hook_entrypoint/session-start.sh")
        self.assertEqual(entry["path"], "hooks/assistant/session-start.sh")
        self.assertEqual(entry["source_path"], "hooks/scripts/session-start.sh")
        self.assertEqual(entry["retired_in"], HOOKS)
        self.assertEqual(git("rev-parse", "aba2a4f^").decode().strip(), HOOKS)

    def test_source_only_registration_and_block_entries_carry_no_retired_in(self):
        for entry_id in ("source_only_tool/context-budget-report.sh", "hook_registration/session-start.sh", "instruction_block/memory-protocol/claude"):
            self.assertNotIn("retired_in", self.entry(entry_id))

    def test_node_modules_is_installer_generated(self):
        entry = self.entry("source_only_tool/evals/node_modules")
        self.assertTrue(entry["installer_generated"])
        for field in ("content_proof", "source_path", "retired_in"):
            self.assertNotIn(field, entry)

    def test_memory_graph_has_no_installer_exact_removal(self):
        entry = self.entry("managed_tool/memory-graph")
        self.assertEqual(entry["retired_in"], FDFF)
        self.assertNotIn("installer_exact_removal", entry)

    def test_unknown_major_version_refused(self):
        inventory = copy.deepcopy(self.inventory)
        inventory["schema_version"] = "2.0"
        self.refuse(inventory, "unknown major")

    def test_unknown_kind_refused(self):
        inventory = copy.deepcopy(self.inventory)
        inventory["entries"][0]["kind"] = "plugin_bundle"
        self.refuse(inventory, "unknown kind")

    def test_missing_content_proof_refused(self):
        inventory = copy.deepcopy(self.inventory)
        del inventory["entries"][0]["content_proof"]
        self.refuse(inventory, "content_proof missing")

    def test_unresolved_content_proof_refused(self):
        inventory = copy.deepcopy(self.inventory)
        inventory["entries"][0]["content_proof"] = "skill/nowhere"
        self.refuse(inventory, "does not resolve")

    def test_skill_directory_with_installer_exact_removal_rejected(self):
        inventory = copy.deepcopy(self.inventory)
        inventory["entries"][0]["installer_exact_removal"] = ["unix"]
        self.refuse(inventory, "installer_exact_removal is not allowed on skill_directory")

    def test_traversal_and_unsafe_paths_rejected(self):
        for bad_path in ("skills/../etc", "/skills/assistant-x", "skills//x", "skills/assistant-é", "skills\\assistant-x", "skills/./x"):
            inventory = copy.deepcopy(self.inventory)
            inventory["entries"][0]["path"] = bad_path
            self.refuse(inventory, "invalid path")

    def test_duplicate_and_uppercase_ids_rejected(self):
        inventory = copy.deepcopy(self.inventory)
        inventory["entries"][1]["id"] = inventory["entries"][0]["id"]
        self.refuse(inventory, "duplicate inventory id")
        inventory = copy.deepcopy(self.inventory)
        inventory["entries"][0]["id"] = "Skill/Assistant-Memory"
        self.refuse(inventory, "id missing or invalid")

    def test_inventory_id_with_registration_separator_rejected(self):
        inventory = copy.deepcopy(self.inventory)
        inventory["entries"][0]["id"] = "skill/assistant-a#b"
        self.refuse(inventory, "id missing or invalid")

    def test_source_path_must_map_from_path(self):
        inventory = copy.deepcopy(self.inventory)
        inventory["entries"][0]["source_path"] = "skills/assistant-other"
        self.refuse(inventory, "does not map")

    def test_installer_generated_with_proof_fields_rejected(self):
        inventory = copy.deepcopy(self.inventory)
        entry = next(e for e in inventory["entries"] if e.get("installer_generated"))
        entry["content_proof"] = "skill/assistant-memory"
        self.refuse(inventory, "not allowed on an installer_generated entry")

    def test_split_root_limited_to_windows_codex(self):
        inventory = copy.deepcopy(self.inventory)
        entry = next(e for e in inventory["entries"] if e["root"] == "agents_skills")
        entry["layouts"] = ["unix"]
        self.refuse(inventory, "applies only to codex on windows")

    def test_missing_markers_rejected(self):
        inventory = copy.deepcopy(self.inventory)
        entry = next(e for e in inventory["entries"] if e["kind"] == "instruction_block")
        del entry["markers"]
        self.refuse(inventory, "markers missing")

    def test_broken_proof_data_refused(self):
        proof = copy.deepcopy(self.proof)
        proof["schema_version"] = "2.0"
        with self.assertRaises(ownership.Refusal):
            ownership.validate_inventory(self.inventory, proof)


class InstallerList(unittest.TestCase):
    """The generated TSV equals the base installers' exact-name lists (SI-1 (b))."""

    D11756D_ENTRYPOINTS = ["session-start.sh", "skill-router.sh", "learning-signals.sh", "workflow-enforcer.sh", "workflow-guard.sh", "stop-review.sh", "harness-gate.sh", "subagent-monitor.sh", "pre-compress.sh", "post-compact.sh", "session-end.sh", "post-tool-context.sh", "tool-failure-advisor.sh", "task-completed.sh"]
    D11756D_HELPERS = ["task-journal-resolver.sh", "workflow-phase-gates.sh", "hook-runtime.sh"]
    D11756D_MODULES = ["workflow-phase-gates.d/learning-controller.sh", "workflow-phase-gates.d/metrics.sh", "workflow-phase-gates.d/qa-controller.sh", "workflow-phase-gates.d/review-controller.sh", "workflow-phase-gates.d/subagent-evidence.sh", "workflow-phase-gates.d/subagent-orchestration.sh", "workflow-guard.d/path-policy.sh", "workflow-guard.d/shell-write-parser.sh", "workflow-guard.d/workflow-state-artifacts.sh"]
    BASE_TOOLS = {
        ("source_only_tool", "file", "context-budget-report.sh"),
        ("source_only_tool", "file", "evals/run-codex-framework-evals.sh"),
        ("source_only_tool", "file", "evals/finalize-workflow-kernel-review.sh"),
        ("source_only_tool", "file", "evals/lib/context-budget-evidence.sh"),
        ("source_only_tool", "file", "evals/validate-promotion-decision-schema.cjs"),
        ("source_only_tool", "file", "evals/package.json"),
        ("source_only_tool", "file", "evals/package-lock.json"),
        ("source_only_tool", "directory", "evals/node_modules"),
        ("managed_tool", "file", "plugins/sync-plugin-skills.sh"),
        ("managed_tool_empty_directory", "directory", "plugins"),
        ("managed_tool", "file", "cleanup-memory-graph.ps1"),
        ("managed_tool", "file", "cleanup-memory-graph.sh"),
    }

    def setUp(self):
        with open(os.path.join(TOOL_DIR, "installer-exact-removal.tsv"), encoding="utf-8") as stream:
            self.rows = [tuple(line.rstrip("\n").split("\t")) for line in stream]

    def names(self, kind):
        return [row[2] for row in self.rows if row[0] == kind]

    def test_hook_name_sets_equal_d11756d_lists(self):
        self.assertEqual(self.names("hook_entrypoint"), self.D11756D_ENTRYPOINTS)
        self.assertEqual(self.names("hook_helper"), self.D11756D_HELPERS)
        self.assertEqual(self.names("hook_module"), self.D11756D_MODULES)
        for row in self.rows:
            if row[0].startswith("hook_"):
                self.assertEqual(row[1], "file")

    def test_tool_rows_equal_the_base_installer_set(self):
        tools = {row for row in self.rows if not row[0].startswith("hook_")}
        self.assertEqual(tools, self.BASE_TOOLS)

    def test_no_skill_agent_registration_or_block_rows(self):
        kinds = {row[0] for row in self.rows}
        self.assertTrue(kinds <= {"source_only_tool", "managed_tool", "managed_tool_empty_directory", "hook_entrypoint", "hook_helper", "hook_module"})
        for row in self.rows:
            self.assertEqual(len(row), 3)

    def test_list_retired_equals_the_derived_list(self):
        home = Home(self)
        code, out, _ = helper(home, "list-retired", "--layout", "unix")
        self.assertEqual(code, 0)
        self.assertEqual([tuple(line.split("\t")) for line in out.splitlines()], self.rows)

    def test_static_sync_exclusions_cover_every_source_only_tool(self):
        with open(os.path.join(REPO, "install.sh"), encoding="utf-8") as stream:
            installer = stream.read()
        block = installer[installer.index("set_owned_sync_exclusions() {"):]
        block = block[: block.index("eval-docs)")]
        for row in self.rows:
            if row[0] == "source_only_tool":
                name = row[2]
                top = name.split("/", 1)[0]
                self.assertTrue(f"\n                {name}\n" in block or (("/" not in name) and f" {top}" in block), f"install.sh sync exclusions miss {name}")
        self.assertIn("framework-ownership/ownership-checkout.py", block)
        self.assertIn("framework-ownership/ownership-checkout.ps1", block)

    def test_current_tool_proof_exclusions_equal_the_installer_sync_exclusions(self):
        import re
        with open(os.path.join(REPO, "install.sh"), encoding="utf-8") as stream:
            unix = stream.read()
        block = unix[unix.index("set_owned_sync_exclusions() {"):]
        block = block[block.index("OWNED_SYNC_EXACT_EXCLUDES=(") + len("OWNED_SYNC_EXACT_EXCLUDES=("):]
        unix_list = block[: block.index(")")].split()
        with open(os.path.join(REPO, "install.ps1"), encoding="utf-8") as stream:
            windows = stream.read()
        block = windows[windows.index("$toolSyncExcludedExactPaths = @("):]
        windows_list = re.findall(r"'([^']+)'", block[: block.index(")")])
        with open(os.path.join(TOOL_DIR, "ownership-checkout.ps1"), encoding="utf-8") as stream:
            helper_ps = stream.read()
        block = helper_ps[helper_ps.index("$script:OwnershipToolExactExcludes = @("):]
        helper_ps_list = re.findall(r"'([^']+)'", block[: block.index(")")])
        expected = sorted(checkout.TOOL_EXACT_EXCLUDES)
        self.assertEqual(sorted(unix_list), expected)
        # install.ps1 lists the top-level context-budget-report.sh here; the helpers skip it as a top-level name.
        self.assertEqual(sorted(name for name in windows_list if "/" in name), expected)
        self.assertEqual(sorted(helper_ps_list), expected)


@unittest.skipIf(git("rev-parse", "--is-shallow-repository").decode().strip() == "true", "needs full history")
class RetiredInChecks(unittest.TestCase):
    def setUp(self):
        with open(os.path.join(TOOL_DIR, "retired-items.json"), "rb") as stream:
            self.inventory = json.loads(stream.read())
        self.main = checkout.main_ref(REPO)

    def problems_for(self, entry_id, retired_in):
        inventory = copy.deepcopy(self.inventory)
        for entry in inventory["entries"]:
            if entry["id"] == entry_id:
                entry["retired_in"] = retired_in
        inventory["entries"] = [e for e in inventory["entries"] if e["id"] == entry_id]
        return checkout.check_retired_in(REPO, inventory, self.main)

    def test_seeded_entries_pass(self):
        self.assertEqual(checkout.check_retired_in(REPO, self.inventory, self.main), [])

    def test_seeded_retired_in_with_a_containing_descendant_fails(self):
        grandparent = git("rev-parse", "7e2fedd^^").decode().strip()
        problems = self.problems_for("skill/assistant-memory", grandparent)
        self.assertTrue(any("descendant" in p for p in problems), problems)

    def test_side_branch_deletion_accepted_by_ancestry(self):
        # 2368e95 is not on main's first-parent chain; its parent still qualifies.
        first_parent = git("rev-list", "--first-parent", checkout.main_ref(REPO)).decode().split()
        self.assertNotIn(git("rev-parse", "2368e95").decode().strip(), first_parent)
        self.assertEqual(self.problems_for("managed_tool/cleanup-memory-graph.sh", CLEANUP_TOOLS), [])

    def test_seeded_ids_match_the_introducing_inventory(self):
        self.assertEqual(checkout.check_seeded_ids(REPO, self.inventory), [])


# ── Synthetic repositories: retirement as data, same-change rule ────────────


class SyntheticRepository(unittest.TestCase):
    """A temporary Git repository holding a copy of the ownership tools."""

    def setUp(self):
        self.base = tempfile.mkdtemp(prefix="s11-repo.")
        self.addCleanup(shutil.rmtree, self.base, True)
        self.repo = os.path.join(self.base, "fw")
        os.makedirs(self.repo)
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "user.name", "Test")
        for name in ("install.sh", "install.ps1"):
            write(os.path.join(self.repo, name), b"#!/bin/sh\n")
        target = os.path.join(self.repo, "tools", "framework-ownership")
        os.makedirs(target)
        shutil.copy(HELPER, target)
        with open(CHECKOUT_ENTRY, encoding="utf-8") as stream:
            text = stream.read()
        start = text.index("SEEDED_IDS = frozenset({")
        end = text.index("})", start) + 2
        text = text[:start] + 'SEEDED_IDS = frozenset({"agent/old-agent"})' + text[end:]
        write(os.path.join(target, "ownership-checkout.py"), text.encode())
        write(os.path.join(self.repo, "skills", "assistant-example", "SKILL.md"), b"# Example\nState in {agent_state_dir}/x\n")
        write(os.path.join(self.repo, "skills", "assistant-example", "references", "a.md"), b"ref\n")
        write(os.path.join(self.repo, "agents", "claude", "old-agent.md"), b"old agent\n")
        self.commit("base")

    def git(self, *arguments, check=True):
        process = subprocess.run(["git", "-C", self.repo] + list(arguments), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if check and process.returncode != 0:
            raise AssertionError(process.stderr.decode())
        return process.stdout.decode().strip()

    def commit(self, message):
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)
        return self.git("rev-parse", "HEAD")

    def inventory(self, entries):
        return {"schema_version": "1.0", "entries": entries}

    def agent_entry(self, retired_in):
        return {"id": "agent/old-agent", "kind": "agent_file", "root": "agent_home", "path": "agents/old-agent.md", "node_type": "file",
                "agents": ["claude"], "layouts": ["unix"], "source_path": "agents/claude/old-agent.md", "retired_in": retired_in, "content_proof": "agent/old-agent"}

    def skill_entry(self, retired_in):
        return {"id": "skill/assistant-example", "kind": "skill_directory", "root": "agent_home", "path": "skills/assistant-example", "node_type": "directory",
                "agents": ["claude", "codex", "gemini"], "layouts": ["unix"], "source_path": "skills/assistant-example", "retired_in": retired_in, "content_proof": "skill/assistant-example"}

    def write_inventory(self, entries):
        write(os.path.join(self.repo, "tools", "framework-ownership", "retired-items.json"), json.dumps(self.inventory(entries), indent=2).encode())

    def build(self, check=False):
        arguments = [sys.executable, os.path.join(self.repo, "tools", "framework-ownership", "ownership-checkout.py"), "build-data"]
        if check:
            arguments.append("--check")
        return run(arguments, {"HOME": os.path.join(self.base, "home"), "PATH": os.environ["PATH"]})

    def seed_inventory_with_agent(self):
        base = self.git("rev-parse", "HEAD")
        os.remove(os.path.join(self.repo, "agents", "claude", "old-agent.md"))
        self.commit("remove old agent")
        self.write_inventory([self.agent_entry(base)])
        code, out, err = self.build()
        self.assertEqual(code, 0, out + err)
        return self.commit("introduce inventory")

    def test_synthetic_retirement_needs_only_data(self):
        self.seed_inventory_with_agent()
        base = self.git("rev-parse", "HEAD")
        self.git("checkout", "-q", "-b", "retire")
        shutil.rmtree(os.path.join(self.repo, "skills", "assistant-example"))
        self.write_inventory([self.agent_entry(self.git("rev-parse", "HEAD~2")), self.skill_entry(base)])
        code, out, err = self.build()
        self.assertEqual(code, 0, out + err)
        self.commit("retire example skill")
        code, out, err = self.build(check=True)
        self.assertEqual(code, 0, out + err)
        # Cleanup, uninstall and installer mode all handle the new entries with no code change.
        home = Home(self)
        agent_home = home.agent_home("claude")
        write(os.path.join(agent_home, "skills", "assistant-example", "SKILL.md"), b"# Example\nState in .claude/x\n")
        write(os.path.join(agent_home, "skills", "assistant-example", "references", "a.md"), b"ref\n")
        write(os.path.join(agent_home, "agents", "old-agent.md"), b"old agent\n")
        tools = os.path.join(self.repo, "tools", "framework-ownership")
        code, out, _ = helper(home, "dry-run", "--agent", "claude", script=os.path.join(tools, "ownership.py"))
        self.assertEqual(code, 0, out)
        self.assertIn("skill_directory: skills/assistant-example", out)
        self.assertIn("agent_file: agents/old-agent.md", out)
        code, out, err = run([sys.executable, os.path.join(tools, "ownership-checkout.py"), "install", "--agent", "claude"], home.env())
        self.assertEqual(code, 0, out + err)
        self.assertFalse(os.path.exists(os.path.join(agent_home, "skills", "assistant-example")))
        self.assertFalse(os.path.exists(os.path.join(agent_home, "agents", "old-agent.md")))

    def same_change_branch(self, edit_first=False):
        """Inventory on main; a branch from C that deletes the skill and adds its entry."""
        self.seed_inventory_with_agent()
        c = self.git("rev-parse", "HEAD")
        write(os.path.join(self.repo, "unrelated.txt"), b"main moves on\n")
        self.commit("unrelated main commit")
        self.git("checkout", "-q", "-b", "retire", c)
        if edit_first:
            write(os.path.join(self.repo, "skills", "assistant-example", "SKILL.md"), b"# Edited first\n")
            self.commit("edit before delete")
        shutil.rmtree(os.path.join(self.repo, "skills", "assistant-example"))
        self.write_inventory([self.agent_entry(self.git("rev-parse", "HEAD~2" if not edit_first else "HEAD~3")), self.skill_entry(c)])
        code, out, err = self.build()
        self.assertEqual(code, 0, out + err)
        self.commit("retire example skill")
        # Regenerate once the deletion is committed, so HEAD's tree no longer
        # holds the skill (build-data --check would ask for this).
        code, out, err = self.build()
        self.assertEqual(code, 0, out + err)
        if self.git("status", "--porcelain"):
            self.git("commit", "-q", "-a", "--amend", "--no-edit")
        return c

    def test_same_change_entry_passes_before_and_after_merge(self):
        self.same_change_branch()
        code, out, err = self.build(check=True)
        self.assertEqual(code, 0, "pre-merge: " + out + err)
        for style in ("merge", "squash"):
            self.git("checkout", "-q", "main")
            self.git("reset", "-q", "--hard", "HEAD")
            saved = self.git("rev-parse", "main")
            if style == "merge":
                self.git("merge", "-q", "--no-ff", "-m", "merge retire", "retire")
            else:
                self.git("merge", "-q", "--squash", "retire")
                self.git("commit", "-q", "-m", "squash retire")
            write(os.path.join(self.repo, f"after-{style}.txt"), b"later\n")
            self.commit("later main commit")
            code, out, err = self.build(check=True)
            self.assertEqual(code, 0, f"post-merge ({style}): " + out + err)
            self.git("reset", "-q", "--hard", saved)

    def test_main_commit_touching_path_after_c_fails_pre_merge(self):
        self.same_change_branch()
        self.git("checkout", "-q", "main")
        write(os.path.join(self.repo, "skills", "assistant-example", "SKILL.md"), b"# Changed on main\n")
        self.commit("main edits the skill")
        self.git("checkout", "-q", "retire")
        code, out, _ = self.build(check=True)
        self.assertNotEqual(code, 0)
        self.assertIn("a main commit after it touches", out)

    def test_edit_then_delete_branch_fails_delete_only_rule(self):
        self.same_change_branch(edit_first=True)
        code, out, _ = self.build(check=True)
        self.assertNotEqual(code, 0)
        self.assertIn("other than deleting it", out)
        # PR-style merge ref: the branch merged into a scratch copy of main.
        self.git("checkout", "-q", "-b", "pr-merge", "main")
        self.git("merge", "-q", "--no-ff", "-m", "pr merge", "retire")
        code, out, _ = self.build(check=True)
        self.assertNotEqual(code, 0)
        self.assertIn("other than deleting it", out)

    def test_edit_then_delete_after_merge_or_rebase_fails_and_squash_passes(self):
        self.same_change_branch(edit_first=True)
        saved = self.git("rev-parse", "main")
        self.git("checkout", "-q", "main")
        self.git("merge", "-q", "--no-ff", "-m", "merge", "retire")
        code, out, _ = self.build(check=True)
        self.assertNotEqual(code, 0, "merge commit should fail")
        self.git("reset", "-q", "--hard", saved)
        self.git("checkout", "-q", "-b", "rebased", "retire")
        self.git("rebase", "-q", "main")
        self.git("checkout", "-q", "main")
        self.git("merge", "-q", "--ff-only", "rebased")
        code, out, _ = self.build(check=True)
        self.assertNotEqual(code, 0, "rebase merge should fail")
        self.git("reset", "-q", "--hard", saved)
        self.git("merge", "-q", "--squash", "retire")
        self.git("commit", "-q", "-m", "squash")
        code, out, err = self.build(check=True)
        self.assertEqual(code, 0, "squash merge must pass: " + out + err)

    def test_id_added_to_seeded_ids_after_introduction_fails(self):
        self.seed_inventory_with_agent()
        path = os.path.join(self.repo, "tools", "framework-ownership", "ownership-checkout.py")
        with open(path, encoding="utf-8") as stream:
            text = stream.read()
        write(path, text.replace('{"agent/old-agent"}', '{"agent/old-agent", "skill/assistant-example"}').encode())
        code, out, _ = self.build(check=True)
        self.assertNotEqual(code, 0)
        self.assertIn("SEEDED_IDS differs", out)

    def test_seeded_entry_edited_after_introduction_fails(self):
        self.seed_inventory_with_agent()
        entry = self.agent_entry(self.git("rev-parse", "HEAD~2"))
        entry["note"] = "repointed later"
        self.write_inventory([entry])
        self.build()
        code, out, _ = self.build(check=True)
        self.assertNotEqual(code, 0)
        self.assertIn("a seeded entry was edited", out)

    def test_new_entry_with_installer_exact_removal_fails(self):
        inventory = {"entries": [{"id": "managed_tool/new-tool.sh", "installer_exact_removal": ["unix"]}, {"id": "source_only_tool/context-budget-report.sh", "installer_exact_removal": ["unix"]}]}
        self.assertEqual(checkout.check_exact_removal_ids(inventory), ["managed_tool/new-tool.sh: installer_exact_removal is limited to the entries seeded with it"])

    def test_shallow_clone_refused(self):
        self.seed_inventory_with_agent()
        shallow = os.path.join(self.base, "shallow")
        subprocess.run(["git", "clone", "-q", "--depth", "1", "file://" + self.repo, shallow], check=True)
        code, out, err = run([sys.executable, os.path.join(shallow, "tools", "framework-ownership", "ownership-checkout.py"), "build-data", "--check"], {"HOME": os.path.join(self.base, "home"), "PATH": os.environ["PATH"]})
        self.assertEqual(code, 2)
        self.assertIn("shallow repository", err)


# ── T2: cleanup helper on disposable homes ──────────────────────────────────


class CleanupHelper(unittest.TestCase):
    def setUp(self):
        self.h = Home(self)
        self.outside = self.h.outside_snapshot()

    def tearDown(self):
        self.assertEqual(self.h.outside_snapshot(), self.outside, "a sentinel outside the agent home changed")

    def claude(self):
        return self.h.agent_home("claude")

    def seed_reflexion(self, agent="claude", home=None):
        home = home or self.h.agent_home(agent)
        seed_tree(FDFF, "skills/assistant-reflexion", os.path.join(home, "skills", "assistant-reflexion"), agent)

    def dry_run(self, agent="claude", codex_home=None, out_file=None):
        arguments = ["dry-run", "--agent", agent]
        if out_file:
            arguments += ["--manifest-out", out_file]
        code, out, err = helper(self.h, *arguments, codex_home=codex_home)
        self.assertEqual(code, 0, out + err)
        return out

    def manifest_file(self, out):
        path = os.path.join(self.h.base, f"manifest-{time.time_ns()}.json")
        write(path, json.dumps(parse_manifest(out)).encode())
        return path, parse_digest(out)

    def apply(self, path, digest, agent="claude", yes=True, codex_home=None):
        arguments = ["apply", "--agent", agent, "--manifest", path, "--manifest-digest", digest]
        if yes:
            arguments.append("--yes")
        return helper(self.h, *arguments, codex_home=codex_home)

    def test_cleanup_dry_run_is_byte_for_byte_non_mutating(self):
        self.h.seed_sentinels("claude")
        self.seed_reflexion()
        seed_file(HOOKS, "hooks/scripts/session-start.sh", os.path.join(self.claude(), "hooks", "assistant", "session-start.sh"), "claude")
        before = snapshot(self.h.base)
        out = self.dry_run()
        self.assertIn("skill_directory: skills/assistant-reflexion", out)
        self.assertEqual(snapshot(self.h.base), before)
        installed = os.path.join(self.claude(), "tools", "framework-ownership")
        os.makedirs(installed)
        for name in ("ownership.py", "retired-items.json", "content-proof.json", "installer-exact-removal.tsv"):
            shutil.copy(os.path.join(TOOL_DIR, name), installed)
        environment = self.h.env()
        del environment["PYTHONDONTWRITEBYTECODE"]
        code, out, err = run([sys.executable, "tools/framework-ownership/ownership.py", "dry-run", "--agent", "claude"], environment, cwd=self.claude())
        self.assertEqual(code, 0, out + err)
        self.assertFalse(os.path.exists(os.path.join(installed, "__pycache__")))

    def test_cleanup_dry_run_creates_no_hooks_directory(self):
        os.makedirs(self.claude())
        self.dry_run()
        self.assertFalse(os.path.exists(os.path.join(self.claude(), "hooks")))

    def test_cleanup_keeps_other_product_assistant_memory(self):
        write(os.path.join(self.claude(), "skills", "assistant-memory", "SKILL.md"), b"---\nname: assistant-memory\n---\nOther product\n")
        out = self.dry_run()
        self.assertIn("skills/assistant-memory: content matches no framework revision", out)
        self.assertNotIn("skill_directory: skills/assistant-memory", out)
        path, digest = self.manifest_file(out)
        self.assertEqual(read_json(path)["items"], [])
        code, _, _ = self.apply(path, digest)
        self.assertEqual(code, 0)
        self.assertTrue(os.path.exists(os.path.join(self.claude(), "skills", "assistant-memory", "SKILL.md")))

    def test_cleanup_retired_skill_plus_user_file_ambiguous(self):
        self.seed_reflexion()
        write(os.path.join(self.claude(), "skills", "assistant-reflexion", "notes.md"), b"my notes\n")
        before = snapshot(self.claude())
        out = self.dry_run()
        self.assertIn("skills/assistant-reflexion: file does not match framework content: notes.md", out)
        path, digest = self.manifest_file(out)
        self.apply(path, digest)
        self.assertEqual(snapshot(self.claude()), before)

    def test_cleanup_symlinked_retired_skill_refused(self):
        os.makedirs(os.path.join(self.claude(), "skills"))
        os.symlink(self.h.sentinel_dir, os.path.join(self.claude(), "skills", "assistant-reflexion"))
        out = self.dry_run()
        self.assertIn("skills/assistant-reflexion: symbolic link at skills/assistant-reflexion; not followed", out)
        self.assertTrue(os.path.islink(os.path.join(self.claude(), "skills", "assistant-reflexion")))

    def test_cleanup_linked_ancestor_refused(self):
        os.makedirs(self.claude())
        elsewhere = os.path.join(self.h.base, "elsewhere-skills")
        seed_tree(FDFF, "skills/assistant-reflexion", os.path.join(elsewhere, "assistant-reflexion"), "claude")
        os.symlink(elsewhere, os.path.join(self.claude(), "skills"))
        out = self.dry_run()
        self.assertIn("symbolic link at skills; not followed", out)
        path, digest = self.manifest_file(out)
        self.apply(path, digest)
        self.assertTrue(os.path.isdir(os.path.join(elsewhere, "assistant-reflexion")))

    def settings_with_three_registrations(self, checkout_path="/somewhere/fw"):
        return {
            "hooks": {
                "SessionStart": [{"hooks": [
                    {"type": "command", "command": "$HOME/.claude/hooks/assistant/session-start.sh"},
                    {"type": "command", "command": f"{checkout_path}/hooks/scripts/session-start.sh --x"},
                ]}],
                "Stop": [{"hooks": [{"type": "command", "command": "$HOME/.claude/hooks/assistant/session-start.sh"}]}],
                "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "/usr/local/bin/user-hook.sh"}]}],
            },
            "mcpServers": {"x": {"command": "x"}},
        }

    def test_cleanup_checkout_form_registration_kept_ambiguous(self):
        write(os.path.join(self.claude(), "settings.json"), json.dumps(self.settings_with_three_registrations(), indent=2).encode())
        out = self.dry_run()
        manifest = parse_manifest(out)
        ids = sorted(item["id"] for item in manifest["items"])
        self.assertEqual(ids, ["hook_registration/session-start.sh#settings.json/SessionStart/0", "hook_registration/session-start.sh#settings.json/Stop/0"])
        self.assertIn("(registration settings.json/SessionStart/1): possible framework checkout path", out)
        path, digest = self.manifest_file(out)
        code, applied, err = self.apply(path, digest)
        self.assertEqual(code, 0, applied + err)
        result = read_json(os.path.join(self.claude(), "settings.json"))
        self.assertEqual(result["hooks"]["SessionStart"][0]["hooks"], [{"type": "command", "command": "/somewhere/fw/hooks/scripts/session-start.sh --x"}])
        self.assertNotIn("Stop", result["hooks"])
        self.assertEqual(result["mcpServers"], {"x": {"command": "x"}})
        self.assertEqual(result["hooks"]["PreToolUse"], self.settings_with_three_registrations()["hooks"]["PreToolUse"])
        self.assertNotIn("hook_registration", parse_manifest(self.dry_run())["items"].__repr__())

    def test_cleanup_settings_mode_preserved_and_malformed_preserved(self):
        settings = os.path.join(self.claude(), "settings.json")
        write(settings, json.dumps(self.settings_with_three_registrations(), indent=2).encode(), mode=0o640)
        out = self.dry_run()
        path, digest = self.manifest_file(out)
        self.apply(path, digest)
        self.assertEqual(stat.S_IMODE(os.stat(settings).st_mode), 0o640)
        write(settings, b"{ not json")
        out = self.dry_run()
        self.assertIn("invalid JSON; preserved unchanged", out)
        with open(settings, "rb") as stream:
            self.assertEqual(stream.read(), b"{ not json")

    def test_cleanup_registered_shim_kept_until_registration_removed(self):
        shim = os.path.join(self.claude(), "hooks", "assistant", "session-start.sh")
        write(shim, ownership.SHIM_BYTES)
        write(os.path.join(self.claude(), "settings.json"), json.dumps({"hooks": {"SessionStart": [{"hooks": [{"command": "$HOME/.claude/hooks/assistant/session-start.sh"}]}]}}).encode())
        out = self.dry_run()
        self.assertIn("hooks/assistant/session-start.sh: still registered in settings.json", out)
        self.assertIn("hook_registration: hooks/assistant/session-start.sh (registration settings.json/SessionStart/0)", out)
        path, digest = self.manifest_file(out)
        self.apply(path, digest)
        self.assertTrue(os.path.exists(shim))
        out = self.dry_run()
        self.assertIn("hook_entrypoint: hooks/assistant/session-start.sh", out)
        path, digest = self.manifest_file(out)
        code, _, _ = self.apply(path, digest)
        self.assertEqual(code, 0)
        self.assertFalse(os.path.exists(shim))

    def test_cleanup_apply_refuses_without_manifest(self):
        self.seed_reflexion()
        before = snapshot(self.claude())
        for arguments in (["apply", "--agent", "claude", "--yes"], ["apply", "--agent", "claude", "--manifest-digest", "0" * 64, "--yes"]):
            code, _, err = helper(self.h, *arguments)
            self.assertEqual(code, 2)
            self.assertIn("requires --manifest and --manifest-digest", err)
        self.assertEqual(snapshot(self.claude()), before)

    def test_cleanup_apply_refuses_edited_manifest(self):
        self.seed_reflexion()
        out = self.dry_run()
        manifest = parse_manifest(out)
        manifest["items"].append({"id": "skill/assistant-memory", "root": "agent_home", "path": "skills/assistant-memory", "kind": "skill_directory", "digest": "0" * 64})
        path = os.path.join(self.h.base, "edited.json")
        write(path, json.dumps(manifest).encode())
        before = snapshot(self.claude())
        code, _, err = self.apply(path, parse_digest(out))
        self.assertEqual(code, 2)
        self.assertIn("does not match its manifest_digest", err)
        self.assertEqual(snapshot(self.claude()), before)

    def test_cleanup_apply_refuses_wrong_digest(self):
        self.seed_reflexion()
        path, _ = self.manifest_file(self.dry_run())
        before = snapshot(self.claude())
        code, _, err = self.apply(path, "f" * 64)
        self.assertEqual(code, 2)
        self.assertIn("confirmed digest does not match", err)
        self.assertEqual(snapshot(self.claude()), before)

    def test_cleanup_apply_refuses_noninteractive_without_yes(self):
        self.seed_reflexion()
        path, digest = self.manifest_file(self.dry_run())
        before = snapshot(self.claude())
        code, _, err = self.apply(path, digest, yes=False)
        self.assertEqual(code, 2)
        self.assertIn("requires --yes", err)
        self.assertEqual(snapshot(self.claude()), before)

    def test_cleanup_apply_refuses_install_and_uninstall_and_current_kinds(self):
        self.seed_reflexion()
        out = self.dry_run()
        for change, text in ((lambda m: m.update(operation="install"), "cannot be applied here"),
                             (lambda m: m.update(operation="uninstall"), "cannot be applied here"),
                             (lambda m: m["items"].append({"id": "current/agent_home/skills/assistant-docs", "root": "agent_home", "path": "skills/assistant-docs", "kind": "current_skill_directory", "digest": "0" * 64}), "cannot list a current framework item"),
                             (lambda m: m["items"].append(dict(m["items"][0])), "duplicate manifest item id"),
                             (lambda m: m.update(agent_home="/elsewhere"), "agent_home does not match")):
            manifest = parse_manifest(out)
            change(manifest)
            manifest["manifest_digest"] = ownership.manifest_digest(manifest)
            path = os.path.join(self.h.base, f"m-{time.time_ns()}.json")
            write(path, json.dumps(manifest).encode())
            code, _, err = self.apply(path, manifest["manifest_digest"])
            self.assertEqual(code, 2, text)
            self.assertIn(text, err)
        self.assertTrue(os.path.isdir(os.path.join(self.claude(), "skills", "assistant-reflexion")))

    def test_cleanup_apply_skips_item_changed_after_report(self):
        self.seed_reflexion()
        path, digest = self.manifest_file(self.dry_run())
        skill_md = os.path.join(self.claude(), "skills", "assistant-reflexion", "SKILL.md")
        with open(skill_md, "ab") as stream:
            stream.write(b"\nedited\n")
        before = snapshot(self.claude())
        code, out, _ = self.apply(path, digest)
        self.assertEqual(code, 3)
        self.assertIn("skipped: skills/assistant-reflexion", out)
        self.assertEqual(snapshot(self.claude()), before)

    def test_cleanup_apply_ignores_items_added_after_report(self):
        self.seed_reflexion()
        seed_tree(FDFF, "skills/assistant-memory", os.path.join(self.claude(), "skills", "assistant-memory"), "claude")
        write(os.path.join(self.claude(), "skills", "assistant-memory", "notes.md"), b"user\n")
        out = self.dry_run()
        path, digest = self.manifest_file(out)
        os.remove(os.path.join(self.claude(), "skills", "assistant-memory", "notes.md"))
        seed_file(PLUGINS, "tools/plugins/sync-plugin-skills.sh", os.path.join(self.claude(), "tools", "plugins", "sync-plugin-skills.sh"), "claude")
        code, applied, _ = self.apply(path, digest)
        self.assertEqual(code, 0, applied)
        self.assertIn("not in the confirmed manifest: skills/assistant-memory", applied)
        self.assertTrue(os.path.isdir(os.path.join(self.claude(), "skills", "assistant-memory")))
        self.assertTrue(os.path.exists(os.path.join(self.claude(), "tools", "plugins", "sync-plugin-skills.sh")))
        self.assertFalse(os.path.exists(os.path.join(self.claude(), "skills", "assistant-reflexion")))

    def test_cleanup_custom_codex_home_only(self):
        custom = os.path.join(self.h.base, "custom-codex")
        self.h.codex_home = custom
        self.seed_reflexion("codex", home=custom)
        default = os.path.join(self.h.home, ".codex")
        self.seed_reflexion("codex", home=default)
        before_default = snapshot(default)
        out = self.dry_run("codex", codex_home=custom)
        self.assertIn(f"Agent home: {custom}", out)
        path, digest = self.manifest_file(out)
        code, applied, _ = self.apply(path, digest, agent="codex", codex_home=custom)
        self.assertEqual(code, 0, applied)
        self.assertFalse(os.path.exists(os.path.join(custom, "skills", "assistant-reflexion")))
        self.assertEqual(snapshot(default), before_default)

    def test_cleanup_second_dry_run_idempotent(self):
        self.seed_reflexion()
        write(os.path.join(self.claude(), "skills", "assistant-memory", "SKILL.md"), b"other\n")
        path, digest = self.manifest_file(self.dry_run())
        self.apply(path, digest)
        manifest = parse_manifest(self.dry_run())
        self.assertEqual(manifest["items"], [])

    def test_cleanup_output_never_contains_file_contents(self):
        secret = b"SECRET-CONTENT-SHOULD-NOT-PRINT"
        self.seed_reflexion()
        write(os.path.join(self.claude(), "skills", "assistant-reflexion", "notes.md"), secret)
        write(os.path.join(self.claude(), "skills", "assistant-memory", "SKILL.md"), secret)
        write(os.path.join(self.claude(), "CLAUDE.md"), b"<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->\n" + secret + b"\n<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END -->\n")
        out = self.dry_run()
        path, digest = self.manifest_file(out)
        code, applied, err = self.apply(path, digest)
        for text in (out, applied, err):
            self.assertNotIn(secret.decode(), text)

    def test_cleanup_installed_helper_rejects_install_mode(self):
        self.seed_reflexion()
        before = snapshot(self.claude())
        code, _, err = helper(self.h, "install", "--agent", "claude")
        self.assertEqual(code, 2)
        self.assertIn("no installer mode", err)
        code, _, err = helper(self.h, "--yes", "apply", "--agent", "claude")
        self.assertEqual(code, 2)
        self.assertEqual(snapshot(self.claude()), before)

    def test_cleanup_dry_run_reports_only_inventory_items(self):
        seed_tree(FDFF, "skills/assistant-reflexion", os.path.join(self.claude(), "skills", "assistant-oldname"), "claude")
        out = self.dry_run()
        self.assertNotIn("assistant-oldname", out)

    def test_cleanup_manifest_out_inside_home_refused(self):
        os.makedirs(self.claude())
        code, _, err = helper(self.h, "dry-run", "--agent", "claude", "--manifest-out", os.path.join(self.claude(), "m.json"))
        self.assertEqual(code, 2)
        self.assertIn("outside the agent home", err)
        self.assertFalse(os.path.exists(os.path.join(self.claude(), "m.json")))
        out_file = os.path.join(self.h.base, "out.json")
        self.dry_run(out_file=out_file)
        self.assertTrue(os.path.exists(out_file))
        code, _, err = helper(self.h, "dry-run", "--agent", "claude", "--manifest-out", out_file)
        self.assertEqual(code, 2)

    def test_cleanup_stale_tool_bytes_kept_and_framework_copy_removed(self):
        tools = os.path.join(self.claude(), "tools")
        write(os.path.join(tools, "context-budget-report.sh"), b"stale\n")
        write(os.path.join(tools, "plugins", "sync-plugin-skills.sh"), b"stale\n")
        out = self.dry_run()
        self.assertIn("tools/context-budget-report.sh: content matches no framework revision", out)
        self.assertIn("tools/plugins: directory is not empty", out)
        path, digest = self.manifest_file(out)
        self.apply(path, digest)
        self.assertTrue(os.path.exists(os.path.join(tools, "plugins", "sync-plugin-skills.sh")))
        seed_file(PLUGINS, "tools/plugins/sync-plugin-skills.sh", os.path.join(tools, "plugins", "sync-plugin-skills.sh"), "claude")
        out = self.dry_run()
        self.assertIn("managed_tool: tools/plugins/sync-plugin-skills.sh", out)
        self.assertIn("managed_tool_empty_directory: tools/plugins", out)
        path, digest = self.manifest_file(out)
        code, applied, _ = self.apply(path, digest)
        self.assertEqual(code, 0, applied)
        self.assertFalse(os.path.exists(os.path.join(tools, "plugins")))
        self.assertTrue(os.path.exists(os.path.join(tools, "context-budget-report.sh")))

    def test_cleanup_node_modules_proven_by_location_and_symlink_kept(self):
        modules = os.path.join(self.claude(), "tools", "evals", "node_modules")
        write(os.path.join(modules, "ajv", "index.js"), b"module.exports = 1\n")
        os.makedirs(os.path.join(modules, ".bin"))
        os.symlink("../ajv/index.js", os.path.join(modules, ".bin", "ajv"))
        out = self.dry_run()
        self.assertIn("source_only_tool: tools/evals/node_modules", out)
        path, digest = self.manifest_file(out)
        code, _, _ = self.apply(path, digest)
        self.assertEqual(code, 0)
        self.assertFalse(os.path.exists(modules))
        os.symlink(self.h.sentinel_dir, modules)
        out = self.dry_run()
        self.assertIn("tools/evals/node_modules: symbolic link", out)

    def test_cleanup_hard_linked_file_kept(self):
        self.seed_reflexion()
        skill_md = os.path.join(self.claude(), "skills", "assistant-reflexion", "SKILL.md")
        os.link(skill_md, os.path.join(self.h.base, "hardlink-elsewhere.md"))
        out = self.dry_run()
        self.assertIn("hard-linked file: SKILL.md", out)

    def test_cleanup_case_variant_name_kept(self):
        seed_tree(FDFF, "skills/assistant-reflexion", os.path.join(self.claude(), "skills", "Assistant-Reflexion"), "claude")
        out = self.dry_run()
        self.assertNotIn("skill_directory: skills/assistant-reflexion", out)
        if os.path.exists(os.path.join(self.claude(), "skills", "assistant-reflexion")):
            self.assertIn("only by case or Unicode form", out)

    def test_cleanup_retired_memory_block_removed_with_separator(self):
        user = b"# My instructions\nkeep me\n"
        block = b"<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->\nprotocol\n<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END -->\n"
        write(os.path.join(self.claude(), "CLAUDE.md"), user + b"\n" + block, mode=0o600)
        out = self.dry_run()
        self.assertIn("instruction_block: CLAUDE.md", out)
        path, digest = self.manifest_file(out)
        self.apply(path, digest)
        with open(os.path.join(self.claude(), "CLAUDE.md"), "rb") as stream:
            self.assertEqual(stream.read(), user)
        self.assertEqual(stat.S_IMODE(os.stat(os.path.join(self.claude(), "CLAUDE.md")).st_mode), 0o600)

    def test_cleanup_unbalanced_block_kept(self):
        write(os.path.join(self.claude(), "CLAUDE.md"), b"<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->\nx\n<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->\n")
        out = self.dry_run()
        self.assertIn("CLAUDE.md: ambiguous, duplicate or unbalanced markers", out)

    def test_cleanup_interactive_confirmation(self):
        self.seed_reflexion()
        for answer, expected_code, removed in ((b"nope\n", 2, False), (b"", 2, False), (b"claude\n", 0, True)):
            out = self.dry_run()
            path, digest = self.manifest_file(out)
            code, text = self.run_in_pty(["apply", "--agent", "claude", "--manifest", path, "--manifest-digest", digest], answer)
            self.assertEqual(code, expected_code, text)
            self.assertEqual(not os.path.exists(os.path.join(self.claude(), "skills", "assistant-reflexion")), removed)

    def run_in_pty(self, arguments, answer):
        master, slave = pty.openpty()
        process = subprocess.Popen([sys.executable, HELPER] + arguments, env=self.h.env(), stdin=slave, stdout=slave, stderr=subprocess.DEVNULL)
        os.close(slave)
        output = b""
        sent = False
        deadline = time.time() + 30
        while time.time() < deadline:
            ready, _, _ = select.select([master], [], [], 0.2)
            if ready:
                try:
                    chunk = os.read(master, 4096)
                except OSError:
                    break
                if not chunk:
                    break
                output += chunk
            if not sent and b"Type the agent name" in output:
                if answer:
                    os.write(master, answer)
                else:
                    os.write(master, b"\x04")
                sent = True
            if process.poll() is not None and not ready:
                break
        process.wait(timeout=30)
        os.close(master)
        return process.returncode, output.decode("utf-8", "replace")

    def test_before_delete_callback_change_is_skipped(self):
        self.seed_reflexion()
        homes = ownership.resolve_homes("claude", self.h.env())
        data = ownership.load_data(TOOL_DIR)
        planner = ownership.Planner(data, "claude", "cleanup", homes)
        manifest = ownership.build_manifest(planner, planner.plan())
        skill_md = os.path.join(self.claude(), "skills", "assistant-reflexion", "SKILL.md")

        def tamper(item):
            with open(skill_md, "ab") as stream:
                stream.write(b"x")

        result = ownership.apply_items(planner, manifest["items"], before_delete=tamper)
        self.assertEqual(len(result.skipped), 1)
        self.assertTrue(os.path.exists(skill_md))

    def test_signature_sweep_catches_change_between_proof_and_delete(self):
        self.seed_reflexion()
        homes = ownership.resolve_homes("claude", self.h.env())
        planner = ownership.Planner(ownership.load_data(TOOL_DIR), "claude", "cleanup", homes)
        finding = [f for f in planner.plan() if f.status == "removable"][0]
        skill_md = os.path.join(self.claude(), "skills", "assistant-reflexion", "SKILL.md")
        with open(skill_md, "ab") as stream:
            stream.write(b"x")
        self.assertFalse(ownership.signatures_unchanged(finding.detail))

    def test_two_registrations_one_event_fail_together(self):
        settings = os.path.join(self.claude(), "settings.json")
        data = {"hooks": {"SessionStart": [{"hooks": [{"command": "$HOME/.claude/hooks/assistant/session-start.sh"}, {"command": "$HOME/.claude/hooks/assistant/skill-router.sh"}]}],
                          "Stop": [{"hooks": [{"command": "$HOME/.claude/hooks/assistant/stop-review.sh"}]}]}}
        write(settings, json.dumps(data, indent=2).encode())
        out = self.dry_run()
        ids = sorted(item["id"] for item in parse_manifest(out)["items"])
        self.assertEqual(ids, ["hook_registration/session-start.sh#settings.json/SessionStart/0", "hook_registration/skill-router.sh#settings.json/SessionStart/1", "hook_registration/stop-review.sh#settings.json/Stop/0"])
        path, digest = self.manifest_file(out)
        data["hooks"]["Stop"][0]["hooks"][0]["timeout"] = 5
        write(settings, json.dumps(data, indent=2).encode())
        with open(settings, "rb") as stream:
            before = stream.read()
        code, applied, _ = self.apply(path, digest)
        self.assertEqual(code, 3)
        self.assertEqual(applied.count("skipped:"), 3)
        with open(settings, "rb") as stream:
            self.assertEqual(stream.read(), before)

    def test_manifest_digest_canonical_serialization(self):
        manifest = {"schema_version": "1.0", "operation": "cleanup", "agent": "claude", "layout": "unix", "agent_home": "/h/.claude", "inventory_digest": "a" * 64,
                    "items": [{"id": "x", "root": "agent_home", "path": "p", "kind": "skill_directory", "digest": "b" * 64}]}
        body = json.dumps(manifest, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
        self.assertEqual(ownership.manifest_digest(manifest), hashlib.sha256(body).hexdigest())
        manifest["manifest_digest"] = "ignored"
        self.assertEqual(ownership.manifest_digest(manifest), hashlib.sha256(body).hexdigest())

    def test_registration_index_counts_every_command(self):
        path = os.path.join(self.h.base, "s.json")
        write(path, json.dumps({"hooks": {"E": [{"hooks": [{"command": "a"}, "not-a-dict", {"command": "b"}]}, "bad-group", {"hooks": {"command": "c"}}]}}).encode())
        snap = ownership.SettingsSnapshot(path, "s.json")
        self.assertEqual([(e, i) for e, i, _ in snap.commands()], [("E", 0), ("E", 1), ("E", 2), ("E", 3)])

    def test_remove_registrations_leaves_untouched_events_and_groups_byte_shape(self):
        value = {"hooks": {"E": [{"matcher": "m"}, {"hooks": [{"command": "a"}, {"command": "b"}]}],
                           "Other": {"weird": True}, "Empty": [], "Kept": [{"hooks": [{"command": "c"}]}]}}
        cleaned = ownership.remove_registrations(value, {("E", 0)})
        self.assertEqual(cleaned["hooks"]["E"], [{"matcher": "m"}, {"hooks": [{"command": "b"}]}])
        self.assertEqual(cleaned["hooks"]["Other"], {"weird": True})
        self.assertEqual(cleaned["hooks"]["Empty"], [])
        self.assertEqual(cleaned["hooks"]["Kept"], value["hooks"]["Kept"])
        emptied = ownership.remove_registrations({"hooks": {"E": [{"hooks": [{"command": "a"}]}], "F": []}}, {("E", 0)})
        self.assertEqual(emptied["hooks"], {"F": []})

    def test_trailing_newline_never_passes_a_pattern(self):
        for pattern in (ownership.SEGMENT_PATTERN, ownership.COMMIT_PATTERN, ownership.HASH_PATTERN, ownership.ID_PATTERN):
            self.assertIsNone(pattern.match("a" * 40 + "\n" if pattern is ownership.COMMIT_PATTERN else ("a" * 64 + "\n" if pattern is ownership.HASH_PATTERN else "abc\n")))

    def test_backslash_or_case_variant_command_keeps_the_entrypoint(self):
        path = os.path.join(self.h.base, "s.json")
        write(path, json.dumps({"hooks": {"E": [{"hooks": [{"command": "C:\\Users\\x\\.claude\\Hooks\\Assistant\\session-start.sh"}]}]}}).encode())
        snap = ownership.SettingsSnapshot(path, "s.json")
        self.assertEqual(ownership.Planner.referencing(snap, "session-start.sh"), [("E", 0)])

    def test_case_variant_spellings_of_one_directory_are_the_same_path(self):
        real = os.path.join(self.h.base, "Dev", "fw")
        os.makedirs(real)
        variant = os.path.join(self.h.base, "dev", "FW")
        if not os.path.exists(variant):
            self.skipTest("case-sensitive file system")
        self.assertTrue(ownership.same_or_inside(variant, real))
        self.assertTrue(ownership.same_or_inside(os.path.join(variant, "skills"), real))
        upper_home = self.h.home.upper() if os.path.exists(self.h.home.upper()) else None
        if upper_home and upper_home != self.h.home:
            with self.assertRaises(ownership.Refusal):
                ownership.resolve_homes("codex", {"HOME": self.h.home, "CODEX_HOME": upper_home})

    def test_deletion_never_follows_an_ancestor_swapped_for_a_link(self):
        root = os.path.join(self.h.base, "root")
        write(os.path.join(root, "skills", "x", "SKILL.md"), b"framework\n")
        elsewhere = os.path.join(self.h.base, "elsewhere")
        write(os.path.join(elsewhere, "x", "SKILL.md"), b"user\n")
        shutil.rmtree(os.path.join(root, "skills"))
        os.symlink(elsewhere, os.path.join(root, "skills"))
        with self.assertRaises(OSError):
            ownership.remove_without_following(root, os.path.join(root, "skills", "x", "SKILL.md"))
        self.assertTrue(os.path.exists(os.path.join(elsewhere, "x", "SKILL.md")))
        with self.assertRaises(OSError):
            ownership.remove_without_following(root, os.path.join(self.h.base, "outside.txt"))

    def test_unencodable_unrelated_setting_preserves_the_file(self):
        settings = os.path.join(self.claude(), "settings.json")
        raw = b'{"note": "\\ud800", "hooks": {"SessionStart": [{"hooks": [{"command": "$HOME/.claude/hooks/assistant/session-start.sh"}]}]}}\n'
        write(settings, raw)
        out = self.dry_run()
        path, digest = self.manifest_file(out)
        code, applied, _ = self.apply(path, digest)
        self.assertEqual(code, 3, applied)
        with open(settings, "rb") as stream:
            self.assertEqual(stream.read(), raw)
        self.assertIn("cannot be written back unchanged", applied)

    def test_linked_agent_home_is_refused(self):
        elsewhere = os.path.join(self.h.base, "elsewhere-home")
        self.seed_reflexion(home=elsewhere)
        os.symlink(elsewhere, self.claude())
        code, _, err = helper(self.h, "dry-run", "--agent", "claude")
        self.assertEqual(code, 2, err)
        self.assertIn("symbolic link", err)
        codex_link = os.path.join(self.h.base, "codex-link")
        os.symlink(elsewhere, codex_link)
        code, _, err = helper(self.h, "dry-run", "--agent", "codex", codex_home=codex_link)
        self.assertEqual(code, 2, err)
        self.assertIn("symbolic link", err)
        with self.assertRaises(OSError):
            ownership.remove_without_following(self.claude(), os.path.join(self.claude(), "skills", "assistant-reflexion", "SKILL.md"))
        self.assertTrue(os.path.isfile(os.path.join(elsewhere, "skills", "assistant-reflexion", "SKILL.md")))

    def test_case_variant_home_through_a_link_is_refused(self):
        variant = os.path.join(os.path.dirname(self.h.home), os.path.basename(self.h.home).upper())
        if variant == self.h.home or not os.path.exists(variant):
            self.skipTest("the file system distinguishes case")
        elsewhere = os.path.join(self.h.base, "elsewhere")
        os.makedirs(os.path.join(elsewhere, ".codex"))
        os.symlink(elsewhere, os.path.join(self.h.home, "dotlink"))
        with self.assertRaises(ownership.Refusal) as caught:
            ownership.resolve_homes("codex", {"HOME": self.h.home, "CODEX_HOME": os.path.join(variant, "dotlink", ".codex")})
        self.assertIn("symbolic link", str(caught.exception))

    def test_settings_with_duplicate_keys_are_preserved(self):
        settings = os.path.join(self.claude(), "settings.json")
        raw = (b'{"hooks": {"SessionStart": [{"hooks": [{"command": "$HOME/.claude/hooks/assistant/session-start.sh"}]}]}, '
               b'"Hooks": {}}\n')
        write(settings, raw)
        out = self.dry_run()
        self.assertNotIn("hook_registration: hooks/assistant/session-start.sh", out)
        self.assertIn("duplicate", out)

    def test_settings_with_repeated_keys_are_preserved(self):
        settings = os.path.join(self.claude(), "settings.json")
        raw = (b'{"mcpServers": {"first": {}}, "mcpServers": {"second": {}}, '
               b'"hooks": {"SessionStart": [{"hooks": [{"command": "$HOME/.claude/hooks/assistant/session-start.sh"}]}]}}\n')
        write(settings, raw)
        out = self.dry_run()
        self.assertNotIn("hook_registration: hooks/assistant/session-start.sh", out)
        self.assertIn("duplicate", out)
        path, digest = self.manifest_file(out)
        self.apply(path, digest)
        with open(settings, "rb") as stream:
            self.assertEqual(stream.read(), raw)

    def test_settings_with_non_finite_numbers_are_preserved(self):
        settings = os.path.join(self.claude(), "settings.json")
        for number in (b"1e9999", b"-1e9999", b"NaN", b"Infinity"):
            raw = (b'{"limit": ' + number + b', '
                   b'"hooks": {"SessionStart": [{"hooks": [{"command": "$HOME/.claude/hooks/assistant/session-start.sh"}]}]}}\n')
            write(settings, raw)
            out = self.dry_run()
            self.assertNotIn("hook_registration: hooks/assistant/session-start.sh", out, number)
            self.assertIn("cannot be written back unchanged", out, number)
            path, digest = self.manifest_file(out)
            self.apply(path, digest)
            with open(settings, "rb") as stream:
                self.assertEqual(stream.read(), raw, number)

    def test_deletion_fails_closed_without_dir_fd_support(self):
        root = os.path.join(self.h.base, "root")
        target = os.path.join(root, "skills", "x", "SKILL.md")
        write(target, b"framework\n")
        with mock.patch.object(os, "supports_dir_fd", set()):
            with self.assertRaises(OSError):
                ownership.remove_without_following(root, target)
            with self.assertRaises(OSError):
                ownership.remove_without_following(root, os.path.dirname(target), directory=True)
        self.assertTrue(os.path.isfile(target))

    def test_placeholder_variants_only_for_skill_files(self):
        data = b"state lives in {agent_state_dir}/memory\n"
        identity = ownership.sha256_hex(data)
        substituted = ownership.sha256_hex(data.replace(b"{agent_state_dir}", b".claude"))
        self.assertEqual(ownership.fingerprints_for_blob("skills/assistant-docs/SKILL.md", data, ["claude"]),
                         {"claude": {identity, substituted}})
        for name in ("tools/framework-ownership/README.md", "docs/evals/notes.md", "agents/claude/x.md"):
            self.assertEqual(ownership.fingerprints_for_blob(name, data, ["claude"]), {"claude": {identity}}, name)

    def test_blob_reader_refuses_a_missing_blob(self):
        with self.assertRaises(checkout.Refusal) as caught:
            checkout.read_blobs(REPO, ["0" * 39 + "1"])
        self.assertIn("did not return blob", str(caught.exception))

    def test_walked_files_are_hashed_without_keeping_their_bytes(self):
        root = os.path.join(self.h.base, "walk")
        chunk = 1 << 20
        boundary = b"a" * (chunk - 1) + b"\r\n" + b"b\r\n"
        late_nul = b"x\r\n" * (chunk // 3 + 5) + b"\x00"
        write(os.path.join(root, "boundary.md"), boundary)
        write(os.path.join(root, "late-nul.bin"), late_nul)
        write(os.path.join(root, "nested", "plain.txt"), b"plain\r\ntext\n")
        entries = ownership.walk_directory(root)
        contents = {"boundary.md": boundary, "late-nul.bin": late_nul, "nested/plain.txt": b"plain\r\ntext\n"}
        for relative, typ, value, _ in entries:
            if typ != "file":
                continue
            self.assertNotIsInstance(value, (bytes, bytearray), relative)
            self.assertEqual(value, (ownership.sha256_hex(contents[relative]), ownership.content_hash(contents[relative])), relative)

    def test_crlf_copy_is_proven(self):
        target = os.path.join(self.claude(), "skills", "assistant-reflexion")
        seed_tree(FDFF, "skills/assistant-reflexion", target, "claude")
        for directory, _, files in os.walk(target):
            for name in files:
                path = os.path.join(directory, name)
                with open(path, "rb") as stream:
                    data = stream.read()
                if b"\x00" not in data:
                    write(path, data.replace(b"\n", b"\r\n"))
        out = self.dry_run()
        self.assertIn("skill_directory: skills/assistant-reflexion", out)

    def test_home_equal_to_user_home_or_root_refused(self):
        code, _, err = run([sys.executable, HELPER, "dry-run", "--agent", "codex"], self.h.env(codex_home=self.h.home))
        self.assertEqual(code, 2)
        self.assertIn("user home", err)
        code, _, err = run([sys.executable, HELPER, "dry-run", "--agent", "codex"], self.h.env(codex_home="/"))
        self.assertEqual(code, 2)
        self.assertIn("filesystem root", err)

    def test_inventory_error_refuses_everything(self):
        copy_dir = os.path.join(self.h.base, "tools-copy")
        shutil.copytree(TOOL_DIR, copy_dir)
        self.seed_reflexion()
        for mutate in (lambda inv: inv.update(schema_version="2.0"), lambda inv: inv["entries"][0].update(kind="plugin_bundle"), lambda inv: inv["entries"][0].pop("content_proof")):
            with open(os.path.join(TOOL_DIR, "retired-items.json"), "rb") as stream:
                inventory = json.loads(stream.read())
            mutate(inventory)
            write(os.path.join(copy_dir, "retired-items.json"), json.dumps(inventory).encode())
            code, _, err = helper(self.h, "dry-run", "--agent", "claude", script=os.path.join(copy_dir, "ownership.py"))
            self.assertEqual(code, 2)
            self.assertIn("refused:", err)
        self.assertTrue(os.path.isdir(os.path.join(self.claude(), "skills", "assistant-reflexion")))


# ── T6: uninstall from a disposable committed clone ─────────────────────────


class CheckoutClone:
    """A temporary clone of this checkout with the working tree committed."""

    path = None
    base = None

    @classmethod
    def get(cls):
        if cls.path is None:
            cls.base = tempfile.mkdtemp(prefix="s11-clone.")
            cls.path = os.path.join(cls.base, "fw")
            subprocess.run(["git", "clone", "-q", "--no-hardlinks", REPO, cls.path], check=True)
            head = git("rev-parse", "HEAD").decode().strip()
            subprocess.run(["git", "-C", cls.path, "checkout", "-q", "--detach", head], check=True)
            files = subprocess.run(["git", "-C", REPO, "ls-files", "-z", "--cached", "--others", "--exclude-standard"], check=True, stdout=subprocess.PIPE).stdout.split(b"\0")
            for name in files:
                if not name:
                    continue
                relative = name.decode()
                source = os.path.join(REPO, relative)
                target = os.path.join(cls.path, relative)
                if os.path.lexists(source) and not os.path.isdir(source):
                    os.makedirs(os.path.dirname(target), exist_ok=True)
                    shutil.copy2(source, target, follow_symlinks=False)
                elif not os.path.lexists(source) and os.path.lexists(target):
                    os.remove(target)
            subprocess.run(["git", "-C", cls.path, "add", "-A"], check=True)
            subprocess.run(["git", "-C", cls.path, "-c", "user.email=t@example.invalid", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "working tree"], check=True)
        return cls.path

    @classmethod
    def cleanup(cls):
        if cls.base:
            shutil.rmtree(cls.base, True)


def tearDownModule():
    CheckoutClone.cleanup()


class Uninstall(unittest.TestCase):
    def setUp(self):
        self.fw = CheckoutClone.get()
        self.h = Home(self)
        self.outside = self.h.outside_snapshot()

    def tearDown(self):
        self.assertEqual(self.h.outside_snapshot(), self.outside, "a sentinel outside the agent home changed")

    def install(self, agent, codex_home=None, framework=None):
        framework = framework or self.fw
        code, out, err = run(["bash", os.path.join(framework, "install.sh"), "--agent", agent], self.h.env(codex_home))
        self.assertEqual(code, 0, out + err)
        return out

    def uninstall(self, agent, *arguments, codex_home=None, input_bytes=b""):
        return run(["bash", os.path.join(self.fw, "uninstall.sh"), "--agent", agent] + list(arguments), self.h.env(codex_home), input_bytes=input_bytes)

    def plan_digest(self, agent, codex_home=None):
        code, out, err = self.uninstall(agent, "--dry-run", codex_home=codex_home)
        self.assertEqual(code, 0, out + err)
        return parse_digest(out), out

    def confirmed(self, agent, codex_home=None):
        digest, plan = self.plan_digest(agent, codex_home)
        code, out, err = self.uninstall(agent, "--yes", "--plan-digest", digest, codex_home=codex_home)
        return code, plan + out, err

    def framework_items_left(self, home):
        left = []
        skills = os.path.join(home, "skills")
        if os.path.isdir(skills):
            for name in os.listdir(os.path.join(self.fw, "skills")):
                if os.path.exists(os.path.join(skills, name)):
                    left.append(f"skills/{name}")
        for name in checkout.current_specs(self.fw, "claude"):
            pass
        for name in os.listdir(os.path.join(self.fw, "tools")):
            if name in checkout.TOOL_TOP_LEVEL_EXCLUDES or name in checkout.TOOL_NAME_EXCLUDES:
                continue
            if os.path.lexists(os.path.join(home, "tools", name)):
                left.append(f"tools/{name}")
        for name in os.listdir(os.path.join(self.fw, "docs", "evals")):
            if os.path.lexists(os.path.join(home, "docs", "evals", name)):
                left.append(f"docs/evals/{name}")
        for folder, suffix in (("claude", ".md"), ("codex", ".toml")):
            for name in os.listdir(os.path.join(self.fw, "agents", folder)):
                if name.endswith(suffix) and os.path.exists(os.path.join(home, "agents", name)):
                    left.append(f"agents/{name}")
        return left

    def test_uninstall_noninteractive_without_yes_refuses(self):
        self.install("claude")
        before = snapshot(self.h.home)
        code, _, err = self.uninstall("claude", input_bytes=b"")
        self.assertEqual(code, 2)
        self.assertIn("requires --yes and --plan-digest", err)
        code, _, err = self.uninstall("claude", "--yes")
        self.assertEqual(code, 2)
        self.assertIn("--yes requires --plan-digest", err)
        self.assertEqual(snapshot(self.h.home), before)
        digest, _ = self.plan_digest("claude")
        write(os.path.join(self.h.home, ".claude", "skills", "assistant-docs", "extra.md"), b"x\n")
        before = snapshot(self.h.home)
        code, out, err = self.uninstall("claude", "--yes", "--plan-digest", digest)
        self.assertEqual(code, 2)
        self.assertIn("Current plan digest:", out)
        self.assertEqual(snapshot(self.h.home), before)

    def test_uninstall_claude_complete_removal(self):
        self.h.seed_sentinels("claude")
        self.install("claude")
        claude = self.h.agent_home("claude")
        user_text = b"# Mine\n<!-- CODEX_DEEPSEEK_WORKFLOW_GLOBAL_V1_START -->\nother tool\n<!-- CODEX_DEEPSEEK_WORKFLOW_GLOBAL_V1_END -->\n"
        with open(os.path.join(claude, "CLAUDE.md"), "rb") as stream:
            generated = stream.read()
        write(os.path.join(claude, "CLAUDE.md"), generated + b"\n" + user_text)
        sentinels = {path: snapshot(os.path.join(claude, path)) for path in ("tools/company-custom-tool.txt", "docs/evals/custom.md", "config.toml", "skills/my-skill", "telos", "rules/default.rules", "agents/my-agent.md")}
        code, out, err = self.confirmed("claude")
        self.assertEqual(code, 0, out + err)
        self.assertEqual(self.framework_items_left(claude), [])
        with open(os.path.join(claude, "CLAUDE.md"), "rb") as stream:
            self.assertEqual(stream.read(), user_text)
        for path, value in sentinels.items():
            self.assertEqual(snapshot(os.path.join(claude, path)), value, path)
        digest, plan = self.plan_digest("claude")
        self.assertIn("Removable (0):", plan)

    def test_uninstall_codex_rules_and_agents_link(self):
        self.install("codex")
        codex = self.h.agent_home("codex")
        write(os.path.join(codex, "rules", "default.rules"), b"user rule\n")
        code, out, err = self.confirmed("codex")
        self.assertEqual(code, 0, out + err)
        self.assertFalse(os.path.exists(os.path.join(codex, "rules", "workflow.rules")))
        self.assertIn("no longer installed", out)
        self.assertIn("git push", out)
        with open(os.path.join(codex, "rules", "default.rules"), "rb") as stream:
            self.assertEqual(stream.read(), b"user rule\n")
        self.assertTrue(os.path.islink(os.path.join(self.h.home, ".agents")))
        self.assertIn("~/.agents: symbolic link kept", out)
        self.assertEqual(self.framework_items_left(codex), [])

    def test_uninstall_modified_rules_file_kept(self):
        self.install("codex")
        rules = os.path.join(self.h.agent_home("codex"), "rules", "workflow.rules")
        with open(rules, "ab") as stream:
            stream.write(b"# mine\n")
        code, out, _ = self.confirmed("codex")
        self.assertEqual(code, 3)
        self.assertTrue(os.path.exists(rules))
        self.assertNotIn("no longer installed", out)

    def test_uninstall_ambiguous_agents_md_unchanged_exit_3(self):
        self.install("codex")
        agents_md = os.path.join(self.h.agent_home("codex"), "AGENTS.md")
        with open(agents_md, "ab") as stream:
            stream.write(b"\n<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_START -->\n")
        with open(agents_md, "rb") as stream:
            before = stream.read()
        code, out, _ = self.confirmed("codex")
        self.assertEqual(code, 3)
        self.assertIn("AGENTS.md: ambiguous, duplicate or unbalanced markers", out)
        with open(agents_md, "rb") as stream:
            self.assertEqual(stream.read(), before)

    def test_uninstall_preflight_refuses_overlap(self):
        before = snapshot(self.fw)
        for codex_home in (self.fw, os.path.dirname(self.fw)):
            code, _, err = self.uninstall("codex", "--dry-run", codex_home=codex_home)
            self.assertEqual(code, 2, err)
            self.assertTrue("overlap" in err or "located inside an agent home" in err, err)
        self.assertEqual(snapshot(self.fw), before)
        code, _, err = self.uninstall("codex", "--dry-run", codex_home=self.h.home)
        self.assertEqual(code, 2)

    def test_uninstall_custom_codex_home(self):
        custom = os.path.join(self.h.base, "custom-codex")
        self.install("codex", codex_home=custom)
        code, out, err = self.confirmed("codex", codex_home=custom)
        self.assertEqual(code, 0, out + err)
        self.assertEqual(self.framework_items_left(custom), [])

    def test_uninstall_proves_copies_installed_by_the_d11756d_installer(self):
        old = os.path.join(self.h.base, "old")
        os.makedirs(old)
        archive = subprocess.run(["git", "-C", REPO, "archive", D11756D], check=True, stdout=subprocess.PIPE).stdout
        subprocess.run(["tar", "-x", "-C", old], input=archive, check=True)
        code, out, err = run(["bash", os.path.join(old, "install.sh"), "--agent", "claude"], self.h.env())
        self.assertEqual(code, 0, out + err)
        claude = self.h.agent_home("claude")
        code, out, err = self.confirmed("claude")
        self.assertIn(code, (0, 3), out + err)
        left = [path for path in os.listdir(os.path.join(claude, "skills"))] if os.path.isdir(os.path.join(claude, "skills")) else []
        self.assertEqual(left, [], out)
        self.assertEqual(self.framework_items_left(claude), [], out)

    def test_uninstall_of_a_home_with_no_framework_is_a_no_op(self):
        os.makedirs(self.h.agent_home("gemini"))
        self.h.seed_sentinels("gemini")
        before = snapshot(self.h.home)
        code, out, err = self.confirmed("gemini")
        self.assertEqual(code, 0, out + err)
        self.assertIn("Removable (0):", out)
        self.assertEqual(snapshot(self.h.home), before)

    def test_uninstall_of_a_used_tool_directory(self):
        self.install("claude")
        tool = os.path.join(self.h.agent_home("claude"), "tools", "cognitive-complexity")
        if not os.path.isdir(tool):
            tool = os.path.join(self.h.agent_home("claude"), "tools", "progress")
        for name in ("bin/Debug/x.dll", "obj/project.assets.json", ".publish/run", "__pycache__/x.cpython-39.pyc", "loose.pyc"):
            write(os.path.join(tool, name), b"\x00build output\n")
        code, out, err = self.confirmed("claude")
        self.assertEqual(code, 0, out + err)
        self.assertFalse(os.path.exists(tool))
        self.install("claude")
        write(os.path.join(tool, "bin", "x.dll"), b"\x00")
        write(os.path.join(tool, "notes.md"), b"mine\n")
        code, out, _ = self.confirmed("claude")
        self.assertEqual(code, 3)
        self.assertTrue(os.path.exists(os.path.join(tool, "notes.md")))
        self.assertIn("file does not match framework content: notes.md", out)

    def test_uninstall_keeps_a_linked_evals_node_modules(self):
        self.install("claude")
        evals = os.path.join(self.h.agent_home("claude"), "tools", "evals")
        self.assertTrue(os.path.isdir(evals))
        modules = os.path.join(evals, "node_modules")
        if os.path.lexists(modules):
            shutil.rmtree(modules)
        elsewhere = os.path.join(self.h.base, "shared-node-modules")
        write(os.path.join(elsewhere, "pkg", "index.js"), b"user\n")
        os.symlink(elsewhere, modules)
        code, out, _ = self.confirmed("claude")
        self.assertEqual(code, 3, out)
        self.assertIn("symbolic link inside the item: node_modules", out)
        self.assertTrue(os.path.islink(modules))
        self.assertTrue(os.path.isfile(os.path.join(elsewhere, "pkg", "index.js")))

    def test_uninstall_keeps_never_synced_or_edited_tool_files(self):
        self.install("claude")
        tool = os.path.join(self.h.agent_home("claude"), "tools", "framework-ownership")
        self.assertTrue(os.path.isdir(tool))
        copied = os.path.join(tool, "ownership-checkout.py")
        with open(os.path.join(self.fw, "tools", "framework-ownership", "ownership-checkout.py"), "rb") as stream:
            write(copied, stream.read())
        code, out, _ = self.confirmed("claude")
        self.assertEqual(code, 3, out)
        self.assertIn("tools/framework-ownership: file does not match framework content: ownership-checkout.py", out)
        self.assertTrue(os.path.isfile(copied))
        os.unlink(copied)
        readme = os.path.join(tool, "README.md")
        with open(readme, "rb") as stream:
            text = stream.read()
        self.assertIn(b"{agent_state_dir}", text)
        write(readme, text.replace(b"{agent_state_dir}", b".claude"))
        code, out, _ = self.confirmed("claude")
        self.assertEqual(code, 3, out)
        self.assertIn("tools/framework-ownership: file does not match framework content: README.md", out)
        self.assertTrue(os.path.isfile(readme))

    def test_uninstall_removes_registration_and_shim_in_one_run(self):
        claude = self.h.agent_home("claude")
        write(os.path.join(claude, "hooks", "assistant", "session-start.sh"), ownership.SHIM_BYTES)
        settings = {"hooks": {"SessionStart": [{"hooks": [{"command": "$HOME/.claude/hooks/assistant/session-start.sh"}, {"command": f"{self.fw}/hooks/scripts/session-start.sh"}]}],
                              "Stop": [{"hooks": [{"command": "$HOME/.claude/hooks/assistant/session-start.sh"}]}]}, "mcpServers": {"a": {}}}
        write(os.path.join(claude, "settings.json"), json.dumps(settings).encode())
        digest, plan = self.plan_digest("claude")
        for suffix in ("SessionStart/0", "SessionStart/1", "Stop/0"):
            self.assertIn(f"(registration settings.json/{suffix})", plan)
        code, out, err = self.uninstall("claude", "--yes", "--plan-digest", digest)
        self.assertEqual(code, 0, out + err)
        self.assertFalse(os.path.exists(os.path.join(claude, "hooks", "assistant", "session-start.sh")))
        result = read_json(os.path.join(claude, "settings.json"))
        self.assertEqual(result, {"hooks": {}, "mcpServers": {"a": {}}})

    def test_uninstall_registration_from_another_checkout_kept(self):
        claude = self.h.agent_home("claude")
        write(os.path.join(claude, "settings.json"), json.dumps({"hooks": {"Stop": [{"hooks": [{"command": "/other/fw/hooks/scripts/session-start.sh"}]}]}}).encode())
        code, out, _ = self.uninstall("claude", "--dry-run")
        self.assertIn("possible framework checkout path", out)

    def test_uninstall_keeps_an_unknown_file_inside_a_framework_skill_directory(self):
        self.install("claude")
        notes = os.path.join(self.h.agent_home("claude"), "skills", "assistant-docs", "notes.md")
        write(notes, b"mine\n")
        code, out, _ = self.confirmed("claude")
        self.assertEqual(code, 3)
        self.assertTrue(os.path.exists(notes))
        self.assertIn("skills/assistant-docs: file does not match framework content: notes.md", out)

    def test_uninstall_interactive_confirmation(self):
        self.install("claude")
        for answer, expected, removed in ((b"no\n", 2, False), (b"claude\n", 0, True)):
            master, slave = pty.openpty()
            process = subprocess.Popen(["bash", os.path.join(self.fw, "uninstall.sh"), "--agent", "claude"], env=self.h.env(), stdin=slave, stdout=slave, stderr=subprocess.DEVNULL)
            os.close(slave)
            output, sent = b"", False
            deadline = time.time() + 120
            while time.time() < deadline:
                ready, _, _ = select.select([master], [], [], 0.2)
                if ready:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError:
                        break
                    if not chunk:
                        break
                    output += chunk
                if not sent and b"Type the agent name" in output:
                    os.write(master, answer)
                    sent = True
                if process.poll() is not None and not ready:
                    break
            process.wait(timeout=60)
            os.close(master)
            self.assertEqual(process.returncode, expected, output.decode("utf-8", "replace")[-2000:])
            self.assertEqual(not os.path.exists(os.path.join(self.h.agent_home("claude"), "skills", "assistant-docs")), removed)


if __name__ == "__main__":
    unittest.main(verbosity=1)
