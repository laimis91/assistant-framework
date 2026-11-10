#!/usr/bin/env python3
"""Assistant Framework ownership helper for Unix agent homes.

Reports, then removes only after confirmation, retired Assistant Framework
items that are proven framework-owned. Proof is content based: an item must
sit at an inventory path and every file in it must match a fingerprint of a
main-reachable framework revision (retired-items.json, content-proof.json).

Subcommands:
  dry-run       Report removable and kept items and print the removal manifest.
  apply         Remove the items of a confirmed dry-run manifest.
  list-retired  Print the installers' exact-name retired tool and hook list.
  validate      Validate the inventory and the content-proof data.

The installed copy has no installer mode. It imports only the standard library
and is run as a script, so it writes no bytecode into the agent home.
"""

import hashlib
import json
import os
import re
import stat
import sys
import tempfile
import unicodedata

EXIT_OK = 0
EXIT_INTERNAL = 1
EXIT_REFUSED = 2
EXIT_KEPT = 3

INVENTORY_MAJOR = "1"
PROOF_MAJOR = "1"
MANIFEST_SCHEMA_VERSION = "1.0"
MANIFEST_MAJOR = "1"

AGENTS = ("claude", "codex", "gemini")
LAYOUTS = ("unix", "windows")
ROOTS = ("agent_home", "agents_skills", "agents_tools")
NODE_TYPES = ("file", "directory")
RETIRED_KINDS = (
    "skill_directory",
    "agent_file",
    "hook_entrypoint",
    "hook_helper",
    "hook_module",
    "hook_registration",
    "managed_tool",
    "managed_tool_empty_directory",
    "source_only_tool",
    "instruction_block",
)
CURRENT_KINDS = (
    "current_skill_directory",
    "current_tool_entry",
    "current_eval_doc_entry",
    "current_agent_file",
    "current_codex_rule",
    "current_instruction_block",
)
MANIFEST_KINDS = RETIRED_KINDS + CURRENT_KINDS
OPERATIONS = ("cleanup", "uninstall", "install")
TOOL_KINDS = ("source_only_tool", "managed_tool", "managed_tool_empty_directory")
HOOK_FILE_KINDS = ("hook_entrypoint", "hook_helper", "hook_module")
SOURCE_PATH_KINDS = (
    "skill_directory",
    "agent_file",
    "hook_entrypoint",
    "hook_helper",
    "hook_module",
    "managed_tool",
    "managed_tool_empty_directory",
)
NO_NODE_TYPE_KINDS = ("hook_registration", "instruction_block")
INSTALL_MODE_KINDS = ("skill_directory", "agent_file")

# Extensions whose {agent_state_dir} placeholder the installers substitute
# (install.sh skill copy; install.ps1 Replace-AgentStatePlaceholders).
SUBSTITUTED_EXTENSIONS = (".md", ".yaml", ".yml", ".json", ".conf", ".toml")
PLACEHOLDER = b"{agent_state_dir}"
# Bytes both installers write at each retired hook entrypoint path.
SHIM_BYTES = (
    b"#!/usr/bin/env bash\n"
    b"# Assistant Framework retired-hook compatibility shim.\n"
    b"exit 0\n"
)
# Build output the installers delete from managed tool directories on every
# reinstall (install.sh cleanup_installed_tool_build_artifacts; install.ps1
# $toolExclusions). Uninstall removes these with a current tool directory.
BUILD_ARTIFACT_DIRECTORIES = ("bin", "obj", ".publish", "__pycache__")
SEGMENT_PATTERN = re.compile(r"^[A-Za-z0-9._-]+\Z")
COMMIT_PATTERN = re.compile(r"^[0-9a-f]{40}\Z")
HASH_PATTERN = re.compile(r"^[0-9a-f]{64}\Z")
VERSION_PATTERN = re.compile(r"^([0-9]+)\.([0-9]+)\Z")
ID_PATTERN = re.compile(r"^[a-z0-9][a-z0-9._/@-]*\Z")

CLEANUP_POINTER = "run the assistant-cleanup skill to review kept items"
CHECKOUT_FORM_REASON = (
    "possible framework checkout path; run uninstall from that checkout or remove it by hand"
)


class Refusal(Exception):
    """A refusal: nothing was changed and the exit status is 2."""


# ── Hashing and canonical forms ─────────────────────────────────────────────


def sha256_hex(data):
    return hashlib.sha256(data).hexdigest()


def normalize_text(data):
    """Normalize CRLF to LF for Git-text bytes (no NUL byte); keep binary raw."""
    if b"\x00" in data:
        return data
    return data.replace(b"\r\n", b"\n")


def content_hash(data):
    return sha256_hex(normalize_text(data))


def canonical_json_bytes(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def fingerprints_for_blob(name, data, agents):
    """Return {agent: set(hash)} for one tracked blob as an installer could write it."""
    base = normalize_text(data)
    identity = sha256_hex(base)
    result = {agent: {identity} for agent in agents}
    # The installers substitute the placeholder only in copied skill files.
    if name.startswith("skills/") and name.lower().endswith(SUBSTITUTED_EXTENSIONS) and PLACEHOLDER in base:
        for agent in agents:
            result[agent].add(sha256_hex(base.replace(PLACEHOLDER, ("." + agent).encode("ascii"))))
    return result


# ── Paths ───────────────────────────────────────────────────────────────────


def valid_relative_path(value):
    if not isinstance(value, str) or not value or value.startswith("/"):
        return False
    for segment in value.split("/"):
        if segment in ("", ".", "..") or not SEGMENT_PATTERN.match(segment):
            return False
    return True


def fold_name(name):
    return unicodedata.normalize("NFC", name).casefold()


def helper_directory():
    return os.path.dirname(os.path.abspath(__file__))


def same_path(first, second):
    """True when both name the same existing directory entry, or the same text.

    Identity (device and inode) catches spellings that differ only by case,
    Unicode form or links on file systems that ignore those differences.
    """
    try:
        return os.path.samefile(first, second)
    except OSError:
        return os.path.realpath(first) == os.path.realpath(second)


def same_or_inside(candidate, container):
    """True when candidate is container or lies inside it, by text or identity."""
    real_candidate = os.path.realpath(candidate)
    real_container = os.path.realpath(container)
    if real_candidate == real_container or real_candidate.startswith(real_container.rstrip(os.sep) + os.sep):
        return True
    try:
        container_status = os.stat(real_container)
    except OSError:
        return False
    current = real_candidate
    while True:
        try:
            status = os.stat(current)
        except OSError:
            status = None
        if status is not None and (status.st_dev, status.st_ino) == (container_status.st_dev, container_status.st_ino):
            return True
        parent = os.path.dirname(current)
        if parent == current:
            return False
        current = parent


# ── Inventory and proof data ────────────────────────────────────────────────


class DuplicateKeyError(ValueError):
    pass


def reject_duplicate_keys(pairs):
    """json object_pairs_hook that refuses repeated keys instead of keeping the last."""
    value = {}
    folded = set()
    for key, item in pairs:
        # Keys equal ignoring case are refused too, as the Windows helper does.
        if key in value or key.lower() in folded:
            raise DuplicateKeyError(json.dumps(key))
        value[key] = item
        folded.add(key.lower())
    return value


class NonFiniteNumberError(ValueError):
    pass


def reject_non_finite_float(text):
    """json parse_float that refuses numbers outside the float range (1e9999)."""
    value = float(text)
    if value != value or value in (float("inf"), float("-inf")):
        raise NonFiniteNumberError(text)
    return value


def reject_non_standard_constant(text):
    """json parse_constant that refuses the non-standard NaN and Infinity tokens."""
    raise NonFiniteNumberError(text)


def read_json_file(path, label):
    try:
        with open(path, "rb") as stream:
            raw = stream.read()
    except FileNotFoundError:
        raise Refusal(f"{label} missing: {path}")
    except OSError as error:
        raise Refusal(f"{label} unreadable: {path}: {error.strerror}")
    try:
        value = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        raise Refusal(f"{label} is not valid UTF-8 JSON: {path}")
    return value, raw


def check_version(value, major, label):
    if not isinstance(value, str):
        raise Refusal(f"{label} schema_version missing or not a string")
    match = VERSION_PATTERN.match(value)
    if not match:
        raise Refusal(f"{label} schema_version is not MAJOR.MINOR: {value}")
    if match.group(1) != major:
        raise Refusal(f"{label} schema_version {value} has an unknown major version")


def expected_source_path(entry):
    kind, root, path = entry["kind"], entry["root"], entry["path"]
    if kind == "skill_directory":
        if root == "agents_skills":
            return "skills/" + path
        return path
    if kind == "agent_file":
        name = path.split("/", 1)[1]
        if name.endswith(".md"):
            return "agents/claude/" + name
        return "agents/codex/" + name
    if kind in HOOK_FILE_KINDS:
        return "hooks/scripts/" + path[len("hooks/assistant/"):]
    if kind in ("managed_tool", "managed_tool_empty_directory"):
        if root == "agents_tools":
            return "tools/" + path
        return path
    return None


def tool_relative_path(entry):
    """Path of a tool entry relative to the agent's tools target."""
    if entry["root"] == "agents_tools":
        return entry["path"]
    return entry["path"][len("tools/"):]


def validate_entry(entry, proof):
    if not isinstance(entry, dict):
        raise Refusal("inventory entry is not an object")
    entry_id = entry.get("id")
    if not isinstance(entry_id, str) or not entry_id or entry_id != entry_id.lower() or not ID_PATTERN.match(entry_id):
        raise Refusal(f"inventory entry id missing or invalid: {entry_id!r}")

    def bad(reason):
        raise Refusal(f"inventory entry {entry_id}: {reason}")

    kind = entry.get("kind")
    if kind not in RETIRED_KINDS:
        bad(f"unknown kind {kind!r}")
    root = entry.get("root")
    if root not in ROOTS:
        bad(f"unknown root {root!r}")
    path = entry.get("path")
    if not valid_relative_path(path):
        bad(f"invalid path {path!r}")
    agents = entry.get("agents")
    if not isinstance(agents, list) or not agents or len(set(agents)) != len(agents) or any(a not in AGENTS for a in agents):
        bad("agents must be a non-empty list of claude, codex and gemini")
    layouts = entry.get("layouts")
    if not isinstance(layouts, list) or not layouts or len(set(layouts)) != len(layouts) or any(l not in LAYOUTS for l in layouts):
        bad("layouts must be a non-empty list of unix and windows")
    if root != "agent_home" and (agents != ["codex"] or layouts != ["windows"]):
        bad(f"root {root} applies only to codex on windows")

    node_type = entry.get("node_type")
    if kind in NO_NODE_TYPE_KINDS:
        if "node_type" in entry:
            bad(f"node_type is not allowed for {kind}")
    elif node_type not in NODE_TYPES:
        bad("node_type must be file or directory")

    generated = entry.get("installer_generated", False)
    if not isinstance(generated, bool):
        bad("installer_generated must be a boolean")
    if generated and kind != "source_only_tool":
        bad("installer_generated is allowed only on source_only_tool")

    exact = entry.get("installer_exact_removal", [])
    if not isinstance(exact, list) or len(set(exact)) != len(exact) or any(l not in layouts for l in exact):
        bad("installer_exact_removal must be a subset of layouts")
    if exact and kind not in TOOL_KINDS:
        bad(f"installer_exact_removal is not allowed on {kind}")

    needs_source = kind in SOURCE_PATH_KINDS and not generated
    if needs_source:
        source_path = entry.get("source_path")
        if not valid_relative_path(source_path):
            bad("source_path missing or invalid")
        if source_path != expected_source_path(entry):
            bad(f"source_path {source_path} does not map from path {path}")
        retired_in = entry.get("retired_in")
        if not isinstance(retired_in, str) or not COMMIT_PATTERN.match(retired_in):
            bad("retired_in must be a full lowercase commit id")
    elif generated:
        for field in ("source_path", "retired_in", "content_proof"):
            if field in entry:
                bad(f"{field} is not allowed on an installer_generated entry")

    needs_proof = kind not in NO_NODE_TYPE_KINDS and kind != "managed_tool_empty_directory" and not generated
    if needs_proof:
        key = entry.get("content_proof")
        if not isinstance(key, str) or not key:
            bad("content_proof missing")
        if key not in proof["proofs"]:
            bad(f"content_proof key does not resolve: {key}")
    elif "content_proof" in entry:
        bad(f"content_proof is not allowed on {kind}")

    if kind == "instruction_block":
        markers = entry.get("markers")
        if not isinstance(markers, dict):
            bad("markers missing")
        start, end = markers.get("start"), markers.get("end")
        for marker in (start, end):
            if not isinstance(marker, str) or not marker.strip() or "\n" in marker or "\r" in marker:
                bad("markers.start and markers.end must be single-line strings")
        if start == end:
            bad("markers.start and markers.end must differ")
        if "/" in path:
            bad("instruction_block path must be an instruction file name")

    segments = path.split("/")
    if kind == "skill_directory":
        if node_type != "directory":
            bad("skill_directory must be a directory")
        expected = 1 if root == "agents_skills" else 2
        if len(segments) != expected or (expected == 2 and segments[0] != "skills"):
            bad("skill_directory path must be skills/<name>")
        if not segments[-1].startswith("assistant-"):
            bad("skill_directory name must start with assistant-")
    elif kind == "agent_file":
        if node_type != "file" or len(segments) != 2 or segments[0] != "agents":
            bad("agent_file path must be agents/<name>")
        if segments[1].endswith(".md"):
            if agents != ["claude"]:
                bad("an agents/*.md file applies to claude only")
        elif segments[1].endswith(".toml"):
            if agents != ["codex"]:
                bad("an agents/*.toml file applies to codex only")
        else:
            bad("agent_file must be a .md or .toml file")
    elif kind in ("hook_entrypoint", "hook_helper", "hook_registration"):
        if len(segments) != 3 or segments[:2] != ["hooks", "assistant"]:
            bad(f"{kind} path must be hooks/assistant/<name>")
    elif kind == "hook_module":
        if len(segments) != 4 or segments[:2] != ["hooks", "assistant"] or not segments[2].endswith(".d"):
            bad("hook_module path must be hooks/assistant/<directory>.d/<name>")
    elif kind in TOOL_KINDS:
        if root == "agent_home" and (segments[0] != "tools" or len(segments) < 2):
            bad(f"{kind} path must be under tools/")
        if kind == "managed_tool_empty_directory" and node_type != "directory":
            bad("managed_tool_empty_directory must be a directory")
    if kind in HOOK_FILE_KINDS and node_type != "file":
        bad(f"{kind} must be a file")


def validate_proof_data(proof):
    if not isinstance(proof, dict):
        raise Refusal("content-proof data is not an object")
    check_version(proof.get("schema_version"), PROOF_MAJOR, "content-proof data")
    proofs = proof.get("proofs")
    if not isinstance(proofs, dict):
        raise Refusal("content-proof data has no proofs object")
    for key, value in proofs.items():
        if not isinstance(value, dict) or not isinstance(value.get("files"), dict) or not value["files"]:
            raise Refusal(f"content-proof key {key} has no files")
        for relative, per_agent in value["files"].items():
            if relative != "" and not valid_relative_path(relative):
                raise Refusal(f"content-proof key {key} has an invalid file path")
            if not isinstance(per_agent, dict):
                raise Refusal(f"content-proof key {key} file {relative} is not an object")
            for agent, hashes in per_agent.items():
                if agent not in AGENTS or not isinstance(hashes, list) or not hashes:
                    raise Refusal(f"content-proof key {key} file {relative} has an invalid agent list")
                for value_hash in hashes:
                    if not isinstance(value_hash, str) or not HASH_PATTERN.match(value_hash):
                        raise Refusal(f"content-proof key {key} has an invalid hash")


def validate_inventory(inventory, proof):
    validate_proof_data(proof)
    if not isinstance(inventory, dict):
        raise Refusal("inventory is not an object")
    check_version(inventory.get("schema_version"), INVENTORY_MAJOR, "inventory")
    entries = inventory.get("entries")
    if not isinstance(entries, list) or not entries:
        raise Refusal("inventory entries missing or empty")
    seen = set()
    for entry in entries:
        validate_entry(entry, proof)
        if entry["id"] in seen:
            raise Refusal(f"duplicate inventory id: {entry['id']}")
        seen.add(entry["id"])


class Data:
    """Validated inventory and content-proof data."""

    def __init__(self, inventory, inventory_bytes, proof):
        self.inventory = inventory
        self.inventory_digest = sha256_hex(inventory_bytes)
        self.proof = proof
        self.entries = inventory["entries"]
        self.by_id = {entry["id"]: entry for entry in self.entries}

    def fingerprints(self, key):
        return self.proof["proofs"][key]["files"]


def load_data(directory=None):
    directory = directory or helper_directory()
    inventory, inventory_bytes = read_json_file(os.path.join(directory, "retired-items.json"), "inventory")
    proof, _ = read_json_file(os.path.join(directory, "content-proof.json"), "content-proof data")
    validate_inventory(inventory, proof)
    return Data(inventory, inventory_bytes, proof)


def build_installer_list(inventory, layout):
    """Lines of the installers' exact-name list: kind, node_type, path (tabs)."""
    lines = []
    for entry in inventory["entries"]:
        if entry["kind"] in TOOL_KINDS and layout in entry.get("installer_exact_removal", []):
            if entry["root"] != "agent_home":
                continue
            lines.append((entry, tool_relative_path(entry)))
    for entry in inventory["entries"]:
        if entry["kind"] in HOOK_FILE_KINDS and layout in entry["layouts"]:
            lines.append((entry, entry["path"][len("hooks/assistant/"):]))
    result = []
    for entry, relative in lines:
        if sorted(entry["agents"]) != list(AGENTS):
            raise Refusal(f"inventory entry {entry['id']} is not shared by every agent; the installer list cannot express it")
        result.append(f"{entry['kind']}\t{entry['node_type']}\t{relative}")
    return result


# ── Agent homes ─────────────────────────────────────────────────────────────


def refuse_linked_home(home, user_home):
    """Refuse an agent home that is a link, or is reached through one below the user home.

    Ancestors are matched to the user home by identity, so a spelling that
    differs only by case or Unicode form is still checked. A home outside the
    user home has only itself checked: system links such as macOS /var and
    /tmp sit above it and are not the user's.
    """
    if os.path.islink(home):
        raise Refusal(f"the agent home is a symbolic link; not followed: {home}")
    links = []
    current = os.path.dirname(home)
    while True:
        textual_home = os.path.normcase(current) == os.path.normcase(user_home)
        if textual_home or (not os.path.islink(current) and same_path(current, user_home)):
            break
        if os.path.islink(current):
            links.append(current)
        parent = os.path.dirname(current)
        if parent == current:
            return
        current = parent
    if links:
        raise Refusal(f"the agent home is reached through a symbolic link; not followed: {links[-1]}")


def resolve_homes(agent, environ=None):
    """Return the inventory roots for one agent on Unix, refusing unsafe homes."""
    environ = os.environ if environ is None else environ
    user_home = environ.get("HOME", "")
    if not user_home or not os.path.isabs(user_home):
        raise Refusal("HOME is not set to an absolute path")
    textual = None
    if agent == "codex" and environ.get("CODEX_HOME"):
        textual = environ["CODEX_HOME"]
        if not os.path.isabs(textual):
            raise Refusal("CODEX_HOME must be an absolute path")
        home = os.path.abspath(textual)
    else:
        home = os.path.join(os.path.abspath(user_home), "." + agent)
    refuse_linked_home(home, os.path.abspath(user_home))
    real_home = os.path.realpath(home)
    if real_home == os.path.realpath(user_home) or same_path(real_home, user_home):
        raise Refusal("the agent home resolves to the user home itself")
    if os.path.dirname(real_home) == real_home or same_path(real_home, os.sep):
        raise Refusal("the agent home resolves to a filesystem root")
    return {
        "user_home": os.path.abspath(user_home),
        "agent_home": home,
        "agent_home_text": textual or os.path.join(user_home, "." + agent),
        "roots": {"agent_home": home},
    }


# ── Filesystem inspection ───────────────────────────────────────────────────


def file_signature(status):
    return (status.st_dev, status.st_ino, status.st_size, status.st_mtime_ns, status.st_mode, status.st_nlink)


def read_stable_file(path):
    """Read a regular file and confirm it did not change while reading."""
    before = os.lstat(path)
    if not stat.S_ISREG(before.st_mode):
        raise OSError("not a regular file")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags)
    try:
        opened = os.fstat(descriptor)
        chunks = []
        while True:
            chunk = os.read(descriptor, 1 << 20)
            if not chunk:
                break
            chunks.append(chunk)
    finally:
        os.close(descriptor)
    after = os.lstat(path)
    if file_signature(before) != file_signature(after) or (opened.st_dev, opened.st_ino) != (before.st_dev, before.st_ino):
        raise OSError("file changed while it was read")
    return b"".join(chunks), before


def hash_stable_file(path):
    """Hash a regular file in chunks; return (raw sha256, content hash, lstat).

    The content hash equals content_hash(data): CRLF normalized to LF unless
    the file holds a NUL byte. File bytes are never retained.
    """
    before = os.lstat(path)
    if not stat.S_ISREG(before.st_mode):
        raise OSError("not a regular file")
    descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    raw = hashlib.sha256()
    normalized = hashlib.sha256()
    has_nul = False
    pending_cr = False
    try:
        opened = os.fstat(descriptor)
        while True:
            chunk = os.read(descriptor, 1 << 20)
            if not chunk:
                break
            raw.update(chunk)
            has_nul = has_nul or b"\x00" in chunk
            if pending_cr:
                chunk = b"\r" + chunk
            pending_cr = chunk.endswith(b"\r")
            if pending_cr:
                chunk = chunk[:-1]
            normalized.update(chunk.replace(b"\r\n", b"\n"))
        if pending_cr:
            normalized.update(b"\r")
    finally:
        os.close(descriptor)
    after = os.lstat(path)
    if file_signature(before) != file_signature(after) or (opened.st_dev, opened.st_ino) != (before.st_dev, before.st_ino):
        raise OSError("file changed while it was read")
    raw_hex = raw.hexdigest()
    return raw_hex, (raw_hex if has_nul else normalized.hexdigest()), before


def locate(root, relative):
    """Find relative under root by exact directory-entry names, never following links.

    Returns ("absent", None), ("problem", reason) or ("ok", lstat result).
    """
    try:
        root_status = os.lstat(root)
    except OSError:
        return "absent", None
    if stat.S_ISLNK(root_status.st_mode):
        return "problem", "the inventory root is a symbolic link; not followed"
    if not stat.S_ISDIR(root_status.st_mode):
        return "absent", None
    current = root
    parts = relative.split("/")
    for index, part in enumerate(parts):
        try:
            names = os.listdir(current)
        except OSError:
            return "absent", None
        shown = "/".join(parts[: index + 1])
        if part not in names:
            variants = sorted(name for name in names if fold_name(name) == fold_name(part))
            if variants:
                prefix = "/".join(parts[:index] + [variants[0]])
                return "problem", f"name differs from the inventory path only by case or Unicode form: {prefix}"
            return "absent", None
        current = os.path.join(current, part)
        status = os.lstat(current)
        if stat.S_ISLNK(status.st_mode):
            return "problem", f"symbolic link at {shown}; not followed"
        if index < len(parts) - 1 and not stat.S_ISDIR(status.st_mode):
            return "absent", None
    return "ok", status


def walk_directory(path):
    """List a directory tree without following links.

    Returns entries [(relative, type, value, signature)] in sorted order; type is
    file, dir, link or other.
    """
    entries = []
    stack = [""]
    while stack:
        relative_dir = stack.pop()
        absolute_dir = os.path.join(path, relative_dir) if relative_dir else path
        names = sorted(os.listdir(absolute_dir))
        for name in names:
            relative = f"{relative_dir}/{name}" if relative_dir else name
            absolute = os.path.join(absolute_dir, name)
            status = os.lstat(absolute)
            if stat.S_ISLNK(status.st_mode):
                entries.append((relative, "link", os.readlink(absolute), file_signature(status)))
            elif stat.S_ISDIR(status.st_mode):
                entries.append((relative, "dir", "", file_signature(status)))
                stack.append(relative)
            elif stat.S_ISREG(status.st_mode):
                raw_hex, content_hex, read_status = hash_stable_file(absolute)
                entries.append((relative, "file", (raw_hex, content_hex), file_signature(read_status)))
            else:
                entries.append((relative, "other", "", file_signature(status)))
    entries.sort(key=lambda item: item[0])
    return entries


def directory_digest(entries):
    listing = []
    for relative, kind, value, _ in entries:
        if kind == "file":
            listing.append([relative, "file", value[0]])
        elif kind == "link":
            listing.append([relative, "link", value])
        else:
            listing.append([relative, kind, ""])
    return sha256_hex(canonical_json_bytes(listing))


def inside_any(relative, prefixes):
    for prefix in prefixes:
        if relative == prefix or relative.startswith(prefix + "/"):
            return True
    return False


def artifact_prefixes(entries):
    """Relative paths of real build-artifact directories at any depth."""
    prefixes = []
    for relative, kind, _, _ in entries:
        if kind == "dir" and relative.rsplit("/", 1)[-1] in BUILD_ARTIFACT_DIRECTORIES and not inside_any(relative, prefixes):
            prefixes.append(relative)
    return prefixes


# ── Findings ────────────────────────────────────────────────────────────────


class Finding:
    def __init__(self, item_id, root, path, kind, status, reason="", digest=None, spec=None, detail=None):
        self.id = item_id
        self.root = root
        self.path = path
        self.kind = kind
        self.status = status  # removable, ambiguous, unrelated, info
        self.reason = reason
        self.digest = digest
        self.spec = spec
        self.detail = detail or {}

    def manifest_item(self):
        return {"id": self.id, "root": self.root, "path": self.path, "kind": self.kind, "digest": self.digest}


def first_shell_token(command):
    if not isinstance(command, str):
        return ""
    command = command.strip()
    if not command:
        return ""
    return re.sub(r"\s+", " ", command).split(" ")[0]


def as_list(value):
    if value is None:
        return []
    return value if isinstance(value, list) else [value]


def settings_file_name(agent):
    return "hooks.json" if agent == "codex" else "settings.json"


class SettingsSnapshot:
    """One read of a hook settings file: bytes, parsed value and registrations."""

    def __init__(self, path, relative):
        self.path = path
        self.relative = relative
        self.raw = None
        self.value = None
        self.problem = None
        self.present = False
        state, info = locate(os.path.dirname(path), os.path.basename(path))
        if state == "absent":
            return
        self.present = True
        if state == "problem":
            self.problem = info
            return
        if not stat.S_ISREG(info.st_mode):
            self.problem = "not a regular file"
            return
        if info.st_nlink > 1:
            self.problem = "hard-linked file"
            return
        try:
            self.raw, _ = read_stable_file(path)
            value = json.loads(self.raw.decode("utf-8"), object_pairs_hook=reject_duplicate_keys,
                               parse_float=reject_non_finite_float, parse_constant=reject_non_standard_constant)
        except DuplicateKeyError as error:
            self.problem = f"duplicate JSON key {error}; preserved unchanged"
            return
        except NonFiniteNumberError as error:
            self.problem = f"number {error} cannot be written back unchanged; preserved unchanged"
            return
        except (OSError, UnicodeDecodeError, ValueError):
            self.problem = "invalid JSON; preserved unchanged"
            return
        hooks = value.get("hooks", {}) if isinstance(value, dict) else None
        if not isinstance(value, dict) or (hooks is not None and not isinstance(hooks, dict)):
            self.problem = "not a JSON object with a hooks object; preserved unchanged"
            return
        self.value = value

    def commands(self):
        """Yield (event, index, hook) over each event's flattened hook list."""
        if self.value is None:
            return
        hooks = self.value.get("hooks") or {}
        for event, groups in hooks.items():
            index = 0
            for group in as_list(groups):
                if not isinstance(group, dict):
                    continue
                for hook in as_list(group.get("hooks")):
                    yield event, index, hook
                    index += 1


def remove_registrations(value, targets):
    """Return a copy of settings with the (event, index) hooks removed.

    Only events holding a target change, and within them only groups holding
    a target. A group or event left empty by the removal is dropped, as the
    installers drop them; every other event and group keeps its exact value.
    """
    output = dict(value)
    hooks = value.get("hooks") or {}
    targeted_events = {event for event, _ in targets}
    cleaned = {}
    for event, groups in hooks.items():
        if event not in targeted_events:
            cleaned[event] = groups
            continue
        index = 0
        kept_groups = []
        for group in as_list(groups):
            if not isinstance(group, dict):
                kept_groups.append(group)
                continue
            kept_hooks = []
            removed = False
            for hook in as_list(group.get("hooks")):
                if (event, index) in targets:
                    removed = True
                else:
                    kept_hooks.append(hook)
                index += 1
            if not removed:
                kept_groups.append(group)
            elif kept_hooks:
                kept_group = dict(group)
                kept_group["hooks"] = kept_hooks
                kept_groups.append(kept_group)
        if kept_groups:
            cleaned[event] = kept_groups if isinstance(groups, list) or len(kept_groups) != 1 else kept_groups[0]
    output["hooks"] = cleaned
    return output


def marker_state(lines, start, end):
    """Count exact marker lines as install.sh does; return (state, start, end)."""
    starts = ends = 0
    open_block = False
    bad = False
    first = last = None
    for number, line in enumerate(lines):
        text = line.rstrip(b"\n").lstrip(b" \t").rstrip(b" \t\r")
        if text == start:
            if open_block or starts > 0:
                bad = True
            starts += 1
            open_block = True
            first = number
        elif text == end:
            if not open_block:
                bad = True
            ends += 1
            open_block = False
            last = number
    if bad or open_block or starts > 1 or ends > 1:
        return "ambiguous", None, None
    if starts == 1:
        return "block", first, last
    return "none", None, None


def split_lines(data):
    lines = data.split(b"\n")
    result = [line + b"\n" for line in lines[:-1]]
    if lines[-1]:
        result.append(lines[-1])
    return result


def block_removal(data, start_marker, end_marker):
    """Return (state, removed_bytes, remaining_bytes) for one instruction file."""
    lines = split_lines(data)
    state, first, last = marker_state(lines, start_marker.encode("utf-8"), end_marker.encode("utf-8"))
    if state != "block":
        return state, None, None
    blank = (b"\n", b"\r\n")
    begin, finish = first, last + 1
    if finish < len(lines) and lines[finish] in blank:
        finish += 1
    elif begin > 0 and lines[begin - 1] in blank:
        begin -= 1
    removed = b"".join(lines[begin:finish])
    remaining = b"".join(lines[:begin] + lines[finish:])
    return state, removed, remaining


# ── Planning ────────────────────────────────────────────────────────────────


class Planner:
    """Ownership proof for one agent home and one operation."""

    def __init__(self, data, agent, operation, homes, layout="unix", checkout_dir=None, current_specs=None, current_fingerprints=None):
        self.data = data
        self.agent = agent
        self.operation = operation
        self.homes = homes
        self.layout = layout
        self.checkout_dir = checkout_dir
        self.current_specs = current_specs or []
        self.current_fingerprints = current_fingerprints or {}
        self.roots = homes["roots"]

    # Entries that apply to this agent and layout.
    def entries(self, kinds=None):
        for entry in self.data.entries:
            if self.agent not in entry["agents"] or self.layout not in entry["layouts"]:
                continue
            if entry["root"] not in self.roots:
                continue
            if kinds is not None and entry["kind"] not in kinds:
                continue
            yield entry

    def fingerprints(self, spec):
        key = spec.get("content_proof")
        if key is None:
            return {}
        if spec.get("current"):
            return self.current_fingerprints.get(key, {}).get("files", {})
        return self.data.fingerprints(key)

    def settings_snapshot(self):
        home = self.roots["agent_home"]
        name = settings_file_name(self.agent)
        return SettingsSnapshot(os.path.join(home, name), name)

    # ── path items ──
    def prove_path(self, spec):
        root = self.roots.get(spec["root"])
        if root is None:
            return None
        state, info = locate(root, spec["path"])
        if state == "absent":
            return None
        item_id, kind = spec["id"], spec["kind"]
        if state == "problem":
            return Finding(item_id, spec["root"], spec["path"], kind, "ambiguous", info, spec=spec)
        absolute = os.path.join(root, spec["path"])
        if spec["node_type"] == "file":
            return self.prove_file(spec, absolute, info)
        if not stat.S_ISDIR(info.st_mode):
            return Finding(item_id, spec["root"], spec["path"], kind, "ambiguous", "not a directory", spec=spec)
        if kind == "managed_tool_empty_directory":
            return Finding(item_id, spec["root"], spec["path"], kind, "pending", digest=sha256_hex(canonical_json_bytes([])), spec=spec, detail={"absolute": absolute})
        return self.prove_directory(spec, absolute)

    def prove_file(self, spec, absolute, status):
        item_id, kind = spec["id"], spec["kind"]
        if not stat.S_ISREG(status.st_mode):
            return Finding(item_id, spec["root"], spec["path"], kind, "ambiguous", "not a regular file", spec=spec)
        if status.st_nlink > 1:
            return Finding(item_id, spec["root"], spec["path"], kind, "ambiguous", "hard-linked file; not removed", spec=spec)
        try:
            data, read_status = read_stable_file(absolute)
        except OSError as error:
            return Finding(item_id, spec["root"], spec["path"], kind, "ambiguous", f"unreadable: {error}", spec=spec)
        digest = sha256_hex(data)
        detail = {"absolute": absolute, "files": [(absolute, file_signature(read_status))], "dirs": []}
        if spec.get("installer_generated"):
            return Finding(item_id, spec["root"], spec["path"], kind, "removable", digest=digest, spec=spec, detail=detail)
        known = self.fingerprints(spec).get("", {}).get(self.agent, [])
        matched = content_hash(data) in known or (kind == "hook_entrypoint" and data == SHIM_BYTES)
        if matched:
            return Finding(item_id, spec["root"], spec["path"], kind, "removable", digest=digest, spec=spec, detail=detail)
        return Finding(item_id, spec["root"], spec["path"], kind, "unrelated", "content matches no framework revision", digest=digest, spec=spec)

    def prove_directory(self, spec, absolute):
        item_id, kind = spec["id"], spec["kind"]
        try:
            entries = walk_directory(absolute)
        except OSError as error:
            return Finding(item_id, spec["root"], spec["path"], kind, "ambiguous", f"unreadable: {error}", spec=spec)
        digest = directory_digest(entries)
        detail = {
            "absolute": absolute,
            "files": [(os.path.join(absolute, rel), sig) for rel, typ, _, sig in entries if typ in ("file", "link")],
            "dirs": [(os.path.join(absolute, rel), sig) for rel, typ, _, sig in entries if typ == "dir"],
        }
        if spec.get("installer_generated"):
            if any(typ == "other" for _, typ, _, _ in entries):
                return Finding(item_id, spec["root"], spec["path"], kind, "ambiguous", "holds a special file", spec=spec)
            return Finding(item_id, spec["root"], spec["path"], kind, "removable", digest=digest, spec=spec, detail=detail)
        known = self.fingerprints(spec)
        known_dirs = set()
        for relative in known:
            parts = relative.split("/")
            for index in range(1, len(parts)):
                known_dirs.add("/".join(parts[:index]))
        location_prefixes = list(spec.get("location_subtrees", []))
        if spec.get("build_artifacts"):
            location_prefixes += artifact_prefixes(entries)
        matched = 0
        problems = []
        content_only = True
        for relative, typ, value, sig in entries:
            if inside_any(relative, location_prefixes) or (spec.get("build_artifacts") and typ == "file" and sig[5] <= 1 and relative.endswith(".pyc")):
                if typ == "other":
                    problems.append(f"special file: {relative}")
                    content_only = False
                elif typ == "link" and relative in location_prefixes:
                    # A linked location root (such as node_modules) is not an
                    # installer-made subtree; keep it and the item.
                    problems.append(f"symbolic link inside the item: {relative}")
                    content_only = False
                continue
            if typ == "link":
                problems.append(f"symbolic link inside the item: {relative}")
                content_only = False
            elif typ == "dir":
                if relative not in known_dirs:
                    problems.append(f"unknown directory: {relative}")
            elif typ == "file":
                if sig[5] > 1:
                    problems.append(f"hard-linked file: {relative}")
                    content_only = False
                elif value[1] in known.get(relative, {}).get(self.agent, []):
                    matched += 1
                else:
                    problems.append(f"file does not match framework content: {relative}")
            else:
                problems.append(f"special file: {relative}")
                content_only = False
        if not problems and matched == 0:
            return Finding(item_id, spec["root"], spec["path"], kind, "ambiguous", "directory holds no framework file", digest=digest, spec=spec)
        if not problems:
            return Finding(item_id, spec["root"], spec["path"], kind, "removable", digest=digest, spec=spec, detail=detail)
        if matched == 0 and content_only:
            return Finding(item_id, spec["root"], spec["path"], kind, "unrelated", "content matches no framework revision", digest=digest, spec=spec)
        reason = problems[0] if len(problems) == 1 else f"{problems[0]} (and {len(problems) - 1} more)"
        return Finding(item_id, spec["root"], spec["path"], kind, "ambiguous", reason, digest=digest, spec=spec)

    # ── registrations ──
    def registration_forms(self, name):
        home = self.homes["agent_home"]
        forms = {
            f"$HOME/.{self.agent}/hooks/assistant/{name}",
            f"{home}/hooks/assistant/{name}",
            f"{self.homes['agent_home_text']}/hooks/assistant/{name}",
            f"{os.path.realpath(home)}/hooks/assistant/{name}",
        }
        return forms

    def is_own_checkout_form(self, token, name):
        """True when token is <checkout>/hooks/scripts/<name> for the running checkout."""
        if self.operation != "uninstall" or not self.checkout_dir:
            return False
        suffix = f"/hooks/scripts/{name}"
        if not token.endswith(suffix) or not os.path.isabs(token):
            return False
        directory = token[: -len(suffix)]
        return os.path.realpath(directory) == os.path.realpath(self.checkout_dir)

    def prove_registrations(self, snapshot):
        findings = []
        if snapshot.value is None:
            return findings
        entries = list(self.entries(("hook_registration",)))
        by_name = {entry["path"].rsplit("/", 1)[-1]: entry for entry in entries}
        for event, index, hook in snapshot.commands():
            if not isinstance(hook, dict):
                continue
            token = first_shell_token(hook.get("command"))
            if not token:
                continue
            for name, entry in by_name.items():
                item_id = f"{entry['id']}#{snapshot.relative}/{event}/{index}"
                digest = sha256_hex(canonical_json_bytes({"registration": hook, "settings_file": snapshot.relative, "event": event, "index": index}))
                detail = {"event": event, "index": index, "settings": snapshot.relative}
                if token in self.registration_forms(name) or self.is_own_checkout_form(token, name):
                    findings.append(Finding(item_id, entry["root"], entry["path"], "hook_registration", "removable", digest=digest, spec=entry, detail=detail))
                    break
                if token.endswith(f"/hooks/scripts/{name}"):
                    findings.append(Finding(item_id, entry["root"], entry["path"], "hook_registration", "ambiguous", CHECKOUT_FORM_REASON, digest=digest, spec=entry, detail=detail))
                    break
        return findings

    @staticmethod
    def referencing(snapshot, name):
        # Over-match on purpose: a kept reference only keeps the entrypoint.
        needle = f"/hooks/assistant/{name}".casefold()
        found = []
        for event, index, hook in snapshot.commands():
            command = hook.get("command") if isinstance(hook, dict) else None
            if isinstance(command, str) and needle in command.replace("\\", "/").casefold():
                found.append((event, index))
        return found

    def apply_entrypoint_rule(self, finding, snapshot, removable_registrations):
        """P-8: entrypoints are offered only when no kept registration references them."""
        if finding is None or finding.kind != "hook_entrypoint" or finding.status != "removable":
            return finding
        if snapshot.present and snapshot.value is None:
            finding.status = "ambiguous"
            finding.reason = f"{snapshot.relative} could not be read ({snapshot.problem}); registration state unknown"
            return finding
        name = finding.path.rsplit("/", 1)[-1]
        references = self.referencing(snapshot, name)
        if not references:
            return finding
        if self.operation == "uninstall" and all((event, index) in removable_registrations for event, index in references):
            return finding
        finding.status = "ambiguous"
        finding.reason = f"still registered in {snapshot.relative}"
        return finding

    # ── instruction blocks ──
    def prove_block(self, spec):
        root = self.roots.get(spec["root"])
        state, info = locate(root, spec["path"])
        if state == "absent":
            return None
        item_id, kind = spec["id"], spec["kind"]
        if state == "problem":
            return Finding(item_id, spec["root"], spec["path"], kind, "ambiguous", info, spec=spec)
        if not stat.S_ISREG(info.st_mode):
            return Finding(item_id, spec["root"], spec["path"], kind, "ambiguous", "not a regular file", spec=spec)
        if info.st_nlink > 1:
            return Finding(item_id, spec["root"], spec["path"], kind, "ambiguous", "hard-linked file; not changed", spec=spec)
        absolute = os.path.join(root, spec["path"])
        try:
            data, _ = read_stable_file(absolute)
        except OSError as error:
            return Finding(item_id, spec["root"], spec["path"], kind, "ambiguous", f"unreadable: {error}", spec=spec)
        markers = spec["markers"]
        block_state, removed, remaining = block_removal(data, markers["start"], markers["end"])
        if block_state == "none":
            return None
        if block_state == "ambiguous":
            return Finding(item_id, spec["root"], spec["path"], kind, "ambiguous", "ambiguous, duplicate or unbalanced markers; file preserved unchanged", spec=spec)
        return Finding(item_id, spec["root"], spec["path"], kind, "removable", digest=sha256_hex(removed), spec=spec, detail={"absolute": absolute})

    # ── whole plan ──
    def specs(self):
        """Path and block specs for this run: inventory entries plus current items."""
        for entry in self.entries():
            if entry["kind"] == "hook_registration":
                continue
            yield entry
        for spec in self.current_specs:
            yield spec

    def prove_spec(self, spec):
        if spec["kind"] in ("instruction_block", "current_instruction_block"):
            return self.prove_block(spec)
        finding = self.prove_path(spec)
        if finding is not None and spec.get("current") and finding.status == "unrelated":
            # A current framework path the installer writes: content that matches
            # no framework revision is a modified framework item, kept as ambiguous.
            finding.status = "ambiguous"
            finding.reason = "modified framework item: " + finding.reason
        return finding

    def plan(self, kinds=None):
        snapshot = self.settings_snapshot()
        findings = []
        registrations = []
        if kinds is None or "hook_registration" in kinds:
            if snapshot.problem and snapshot.present:
                findings.append(Finding("settings/" + snapshot.relative, "agent_home", snapshot.relative, "hook_registration", "ambiguous", f"{snapshot.relative}: {snapshot.problem}; registrations not inspected"))
            registrations = self.prove_registrations(snapshot)
            findings.extend(registrations)
        removable_registrations = {(f.detail["event"], f.detail["index"]) for f in registrations if f.status == "removable"}
        for spec in self.specs():
            if kinds is not None and spec["kind"] not in kinds:
                continue
            finding = self.prove_spec(spec)
            if finding is None:
                continue
            finding = self.apply_entrypoint_rule(finding, snapshot, removable_registrations)
            findings.append(finding)
        self.resolve_empty_directories(findings)
        self.drop_nested(findings)
        findings.sort(key=lambda f: f.id)
        return findings

    @staticmethod
    def resolve_empty_directories(findings):
        removable_paths = {(f.root, f.path) for f in findings if f.status == "removable"}
        for finding in findings:
            if finding.status != "pending":
                continue
            absolute = finding.detail["absolute"]
            try:
                names = os.listdir(absolute)
            except OSError as error:
                finding.status, finding.reason = "ambiguous", f"unreadable: {error}"
                continue
            remaining = [name for name in names if (finding.root, f"{finding.path}/{name}") not in removable_paths]
            if remaining:
                finding.status, finding.reason = "ambiguous", "directory is not empty"
            else:
                finding.status = "removable"

    @staticmethod
    def drop_nested(findings):
        directories = [(f.root, f.path) for f in findings if f.status == "removable" and f.kind in ("current_tool_entry", "current_eval_doc_entry", "current_skill_directory") and f.detail.get("dirs") is not None and os.path.isdir(f.detail.get("absolute", ""))]
        if not directories:
            return
        kept = []
        for finding in findings:
            nested = any(finding.root == root and finding.path.startswith(path + "/") for root, path in directories)
            if not nested:
                kept.append(finding)
        findings[:] = kept

    def reprove(self, item):
        """Prove one manifest item now (not registrations)."""
        spec = None
        for candidate in self.specs():
            if candidate["id"] == item["id"]:
                spec = candidate
                break
        if spec is None:
            return None
        finding = self.prove_spec(spec)
        if finding is not None and finding.status == "pending":
            self.resolve_empty_directories([finding])
        if finding is not None and finding.kind == "hook_entrypoint":
            # Re-prove against the settings file as it is now: any remaining
            # reference keeps the entrypoint, whatever this run removed.
            snapshot = self.settings_snapshot()
            finding = self.apply_entrypoint_rule(finding, snapshot, set())
        return finding


# ── Manifest ────────────────────────────────────────────────────────────────


def build_manifest(planner, findings):
    items = [f.manifest_item() for f in findings if f.status == "removable"]
    items.sort(key=lambda item: item["id"])
    manifest = {
        "schema_version": MANIFEST_SCHEMA_VERSION,
        "operation": planner.operation,
        "agent": planner.agent,
        "layout": planner.layout,
        "agent_home": planner.homes["agent_home"],
        "inventory_digest": planner.data.inventory_digest,
        "items": items,
    }
    manifest["manifest_digest"] = manifest_digest(manifest)
    return manifest


def manifest_digest(manifest):
    body = {key: value for key, value in manifest.items() if key != "manifest_digest"}
    return sha256_hex(canonical_json_bytes(body))


def validate_manifest(manifest, planner, expected_digest, allowed_operations):
    """Refuse unless the manifest is well formed, bound and for this run."""
    if not isinstance(manifest, dict):
        raise Refusal("manifest is not a JSON object")
    check_version(manifest.get("schema_version"), MANIFEST_MAJOR, "manifest")
    operation = manifest.get("operation")
    if operation not in OPERATIONS:
        raise Refusal(f"manifest operation is unknown: {operation!r}")
    if operation not in allowed_operations:
        raise Refusal(f"a manifest with operation {operation} cannot be applied here")
    recorded = manifest.get("manifest_digest")
    if not isinstance(recorded, str) or not HASH_PATTERN.match(recorded):
        raise Refusal("manifest_digest missing or invalid")
    computed = manifest_digest(manifest)
    if computed != recorded:
        raise Refusal("manifest content does not match its manifest_digest")
    if expected_digest != computed:
        raise Refusal("the confirmed digest does not match the manifest")
    expected = {
        "agent": planner.agent,
        "layout": planner.layout,
        "agent_home": planner.homes["agent_home"],
        "inventory_digest": planner.data.inventory_digest,
    }
    for key, value in expected.items():
        if manifest.get(key) != value:
            raise Refusal(f"manifest {key} does not match this run")
    items = manifest.get("items")
    if not isinstance(items, list):
        raise Refusal("manifest items missing")
    seen = set()
    for item in items:
        if not isinstance(item, dict):
            raise Refusal("manifest item is not an object")
        for field in ("id", "root", "path", "kind", "digest"):
            if not isinstance(item.get(field), str):
                raise Refusal(f"manifest item field {field} missing")
        if item["id"] in seen:
            raise Refusal(f"duplicate manifest item id: {item['id']}")
        seen.add(item["id"])
        if item["kind"] not in MANIFEST_KINDS:
            raise Refusal(f"unknown manifest kind: {item['kind']}")
        if item["root"] not in ROOTS or not valid_relative_path(item["path"]):
            raise Refusal(f"manifest item {item['id']} has an invalid root or path")
        if not HASH_PATTERN.match(item["digest"]):
            raise Refusal(f"manifest item {item['id']} has an invalid digest")
        if operation == "cleanup" and item["kind"] in CURRENT_KINDS:
            raise Refusal(f"a cleanup manifest cannot list a current framework item: {item['id']}")
        if operation == "install" and item["kind"] not in INSTALL_MODE_KINDS:
            raise Refusal(f"an install manifest cannot list {item['kind']}")
        if item["kind"] in RETIRED_KINDS:
            entry_id = item["id"].split("#", 1)[0]
            entry = planner.data.by_id.get(entry_id)
            if entry is None or entry["kind"] != item["kind"] or entry["root"] != item["root"] or entry["path"] != item["path"]:
                raise Refusal(f"manifest item {item['id']} does not match an inventory entry")
            if (item["kind"] == "hook_registration") != ("#" in item["id"]):
                raise Refusal(f"manifest item {item['id']} has an invalid registration id")
    return items


# ── Apply ───────────────────────────────────────────────────────────────────


def signatures_unchanged(detail):
    for path, signature in detail.get("files", []) + detail.get("dirs", []):
        try:
            status = os.lstat(path)
        except OSError:
            return False
        current = file_signature(status)
        if stat.S_ISDIR(status.st_mode):
            # Directory mtimes are not compared; their entries are.
            if current[:2] != signature[:2]:
                return False
        elif current != signature:
            return False
    return True


def fsync_directory(directory):
    try:
        descriptor = os.open(directory, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    except OSError:
        return
    try:
        os.fsync(descriptor)
    except OSError:
        pass
    finally:
        os.close(descriptor)


NOFOLLOW_DIRECTORY = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)


def remove_without_following(root, path, directory=False):
    """Unlink or rmdir path, reaching it from root one directory at a time.

    Every directory below root is opened without following links, so an
    ancestor swapped for a link after the proof makes the open fail instead
    of redirecting the deletion. Where the platform lacks dir_fd support the
    deletion fails closed instead of following a path that may have changed.
    """
    relative = os.path.relpath(path, root)
    parts = relative.split(os.sep)
    if relative.startswith(os.pardir) or os.path.isabs(relative) or not parts or "" in parts:
        raise OSError(f"outside the agent home: {path}")
    supported = os.unlink in os.supports_dir_fd and os.rmdir in os.supports_dir_fd and os.open in os.supports_dir_fd
    if not supported:
        raise OSError(f"this platform cannot delete without following links; kept: {path}")
    descriptor = os.open(root, NOFOLLOW_DIRECTORY)
    try:
        for part in parts[:-1]:
            child = os.open(part, NOFOLLOW_DIRECTORY, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = child
        if directory:
            os.rmdir(parts[-1], dir_fd=descriptor)
        else:
            os.unlink(parts[-1], dir_fd=descriptor)
    finally:
        os.close(descriptor)


def delete_proven(detail, root):
    """Delete exactly the proven entries, deepest first; never follow links."""
    for path, _ in sorted(detail.get("files", []), key=lambda item: item[0].count(os.sep), reverse=True):
        remove_without_following(root, path)
    for path, _ in sorted(detail.get("dirs", []), key=lambda item: item[0].count(os.sep), reverse=True):
        remove_without_following(root, path, directory=True)
    absolute = detail["absolute"]
    if os.path.isdir(absolute) and not os.path.islink(absolute):
        remove_without_following(root, absolute, directory=True)


def atomic_rewrite(path, data, expected_bytes):
    """Replace path with data only if its bytes still equal expected_bytes."""
    status = os.lstat(path)
    if not stat.S_ISREG(status.st_mode) or status.st_nlink > 1:
        raise OSError("changed type or gained a hard link")
    current, _ = read_stable_file(path)
    if current != expected_bytes:
        raise OSError("changed since it was read")
    directory = os.path.dirname(path)
    descriptor, temp_path = tempfile.mkstemp(prefix=".assistant-framework-ownership.", dir=directory)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temp_path, stat.S_IMODE(status.st_mode))
        current, _ = read_stable_file(path)
        if current != expected_bytes:
            raise OSError("changed since it was read")
        os.replace(temp_path, path)
        fsync_directory(directory)
    except BaseException:
        if os.path.exists(temp_path):
            os.unlink(temp_path)
        raise


class ApplyResult:
    def __init__(self):
        self.removed = []
        self.skipped = []
        self.unlisted = []

    @property
    def exit_code(self):
        return EXIT_KEPT if self.skipped else EXIT_OK


def apply_items(planner, items, before_delete=None):
    """Remove the listed items with per-item re-proof. Returns an ApplyResult."""
    result = ApplyResult()
    listed_ids = {item["id"] for item in items}
    start_plan = planner.plan()
    for finding in start_plan:
        if finding.status == "removable" and finding.id not in listed_ids:
            result.unlisted.append(finding)

    registration_items = [item for item in items if item["kind"] == "hook_registration"]
    block_items = [item for item in items if item["kind"] in ("instruction_block", "current_instruction_block")]
    empty_items = [item for item in items if item["kind"] == "managed_tool_empty_directory"]
    entrypoint_items = [item for item in items if item["kind"] == "hook_entrypoint"]
    path_items = [item for item in items if item not in registration_items + block_items + empty_items + entrypoint_items]

    if registration_items:
        apply_registrations(planner, registration_items, result, before_delete)
    for item in block_items:
        apply_block(planner, item, result, before_delete)
    ordered = sorted(path_items, key=lambda item: item["path"].count("/"), reverse=True)
    for item in ordered + entrypoint_items + empty_items:
        apply_path(planner, item, result, before_delete)
    return result


def apply_registrations(planner, items, result, before_delete):
    snapshot = planner.settings_snapshot()
    if snapshot.value is None:
        for item in items:
            result.skipped.append((item, f"{snapshot.relative} could not be read"))
        return
    current = {f.id: f for f in planner.prove_registrations(snapshot)}
    failures = []
    targets = set()
    for item in items:
        if before_delete is not None:
            before_delete(item)
        finding = current.get(item["id"])
        if finding is None or finding.status != "removable" or finding.digest != item["digest"]:
            failures.append(item)
        else:
            targets.add((finding.detail["event"], finding.detail["index"]))
    if failures:
        for item in items:
            reason = "changed since the report" if item in failures else f"another registration in {snapshot.relative} changed since the report"
            result.skipped.append((item, reason))
        return
    updated = remove_registrations(snapshot.value, targets)
    try:
        payload = (json.dumps(updated, indent=2, ensure_ascii=False, allow_nan=False) + "\n").encode("utf-8")
    except (UnicodeEncodeError, ValueError):
        for item in items:
            result.skipped.append((item, f"{snapshot.relative} holds text that cannot be written back unchanged; preserved"))
        return
    try:
        atomic_rewrite(snapshot.path, payload, snapshot.raw)
    except OSError as error:
        for item in items:
            result.skipped.append((item, f"{snapshot.relative} {error}"))
        return
    result.removed.extend(items)


def apply_block(planner, item, result, before_delete):
    if before_delete is not None:
        before_delete(item)
    finding = planner.reprove(item)
    if finding is None or finding.status != "removable" or finding.digest != item["digest"]:
        result.skipped.append((item, "changed since the report"))
        return
    absolute = finding.detail["absolute"]
    try:
        data, _ = read_stable_file(absolute)
        markers = finding.spec["markers"]
        _, removed, remaining = block_removal(data, markers["start"], markers["end"])
        if removed is None or sha256_hex(removed) != item["digest"]:
            raise OSError("changed since the report")
        atomic_rewrite(absolute, remaining, data)
    except OSError as error:
        result.skipped.append((item, str(error)))
        return
    result.removed.append(item)


def apply_path(planner, item, result, before_delete):
    if before_delete is not None:
        before_delete(item)
    finding = planner.reprove(item)
    if finding is None:
        result.skipped.append((item, "no longer present"))
        return
    if finding.status != "removable" or finding.digest != item["digest"] or finding.kind != item["kind"]:
        reason = finding.reason if finding.status != "removable" and finding.reason else "changed since the report"
        result.skipped.append((item, reason))
        return
    try:
        root = planner.homes["roots"][finding.root]
        if item["kind"] == "managed_tool_empty_directory":
            remove_without_following(root, finding.detail["absolute"], directory=True)
        else:
            if not signatures_unchanged(finding.detail):
                raise OSError("changed during removal")
            if finding.spec.get("node_type") == "file":
                remove_without_following(root, finding.detail["absolute"])
            else:
                delete_proven(finding.detail, root)
    except OSError as error:
        result.skipped.append((item, f"not removed: {error.strerror or error}"))
        return
    result.removed.append(item)


# ── Reporting ───────────────────────────────────────────────────────────────


def display_path(planner, finding):
    if finding.root == "agent_home":
        return finding.path
    return f"<{finding.root}>/{finding.path}"


def print_report(planner, findings, manifest, out, title):
    removable = [f for f in findings if f.status == "removable"]
    ambiguous = [f for f in findings if f.status == "ambiguous"]
    unrelated = [f for f in findings if f.status == "unrelated"]
    info = [f for f in findings if f.status == "info"]
    out.write(f"{title} for {planner.agent} ({planner.layout})\n")
    out.write(f"Agent home: {planner.homes['agent_home']}\n")
    out.write(f"Removable ({len(removable)}):\n")
    for finding in removable:
        out.write(f"  {finding.kind}: {display_path(planner, finding)}{registration_suffix(finding)}\n")
    out.write(f"Kept, ambiguous ({len(ambiguous)}):\n")
    for finding in ambiguous:
        out.write(f"  {display_path(planner, finding)}{registration_suffix(finding)}: {finding.reason}\n")
    out.write(f"Kept, unrelated ({len(unrelated)}):\n")
    for finding in unrelated:
        out.write(f"  {display_path(planner, finding)}: {finding.reason}\n")
    for finding in info:
        out.write(f"Note: {display_path(planner, finding)}: {finding.reason}\n")
    out.write(f"Manifest digest: {manifest['manifest_digest']}\n")


def registration_suffix(finding):
    if finding.kind == "hook_registration" and "#" in finding.id:
        return f" (registration {finding.id.split('#', 1)[1]})"
    return ""


def print_apply_result(result, out):
    for item in result.removed:
        out.write(f"removed: {item['kind']}: {item['path']}{' (' + item['id'].split('#', 1)[1] + ')' if '#' in item['id'] else ''}\n")
    for item, reason in result.skipped:
        out.write(f"skipped: {item['path']}: {reason}\n")
    for finding in result.unlisted:
        out.write(f"not in the confirmed manifest: {finding.path}\n")
    out.write(f"Removed {len(result.removed)}, skipped {len(result.skipped)}.\n")


# ── Confirmation ────────────────────────────────────────────────────────────


def interactive():
    try:
        return os.isatty(sys.stdin.fileno()) and os.isatty(sys.stdout.fileno())
    except (OSError, ValueError, AttributeError):
        return False


def confirm_by_typing(agent, count, out):
    out.write(f"Type the agent name ({agent}) to remove {count} item(s), anything else to abort: ")
    out.flush()
    try:
        answer = sys.stdin.readline()
    except KeyboardInterrupt:
        return False
    if not answer:
        return False
    return answer.strip() == agent


# ── Command line ────────────────────────────────────────────────────────────


SUBCOMMANDS = ("dry-run", "apply", "list-retired", "validate", "install")


def parse_options(arguments, spec):
    """Parse --name value / --flag options exactly; refuse unknown or repeated ones."""
    values = {}
    index = 0
    while index < len(arguments):
        argument = arguments[index]
        if argument not in spec:
            raise Refusal(f"unknown argument: {argument}")
        if argument in values:
            raise Refusal(f"repeated argument: {argument}")
        if spec[argument]:
            if index + 1 >= len(arguments):
                raise Refusal(f"missing value for {argument}")
            values[argument] = arguments[index + 1]
            index += 2
        else:
            values[argument] = True
            index += 1
    return values


def require_agent(values):
    agent = values.get("--agent")
    if agent not in AGENTS:
        raise Refusal("--agent must be claude, codex or gemini")
    return agent


def check_manifest_out(path, homes):
    if not os.path.isabs(path):
        path = os.path.abspath(path)
    if os.path.lexists(path):
        raise Refusal("--manifest-out must name a file that does not exist yet")
    parent = os.path.dirname(path)
    if not os.path.isdir(parent):
        raise Refusal("--manifest-out directory does not exist")
    for root in homes["roots"].values():
        if same_or_inside(parent, root) or same_or_inside(path, root):
            raise Refusal("--manifest-out must be outside the agent home and every inventory root")
    return path


def write_new_file(path, data):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(data)


def command_dry_run(arguments, out):
    values = parse_options(arguments, {"--agent": True, "--manifest-out": True})
    agent = require_agent(values)
    homes = resolve_homes(agent)
    data = load_data()
    planner = Planner(data, agent, "cleanup", homes)
    findings = planner.plan()
    manifest = build_manifest(planner, findings)
    print_report(planner, findings, manifest, out, "Assistant Framework cleanup dry run")
    serialized = json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    if "--manifest-out" in values:
        target = check_manifest_out(values["--manifest-out"], homes)
        write_new_file(target, serialized.encode("utf-8"))
        out.write(f"Manifest written to: {target}\n")
    else:
        out.write("BEGIN MANIFEST\n")
        out.write(serialized)
        out.write("END MANIFEST\n")
    return EXIT_OK


def command_apply(arguments, out, before_delete=None):
    values = parse_options(arguments, {"--agent": True, "--manifest": True, "--manifest-digest": True, "--yes": False})
    agent = require_agent(values)
    if "--manifest" not in values or "--manifest-digest" not in values:
        raise Refusal("apply requires --manifest and --manifest-digest from a prior dry run")
    homes = resolve_homes(agent)
    data = load_data()
    planner = Planner(data, agent, "cleanup", homes)
    manifest, _ = read_json_file(values["--manifest"], "manifest")
    items = validate_manifest(manifest, planner, values["--manifest-digest"], ("cleanup",))
    out.write(f"Confirmed manifest for {agent}: {len(items)} item(s), digest {manifest['manifest_digest']}\n")
    for item in items:
        out.write(f"  {item['kind']}: {item['path']}\n")
    if not values.get("--yes"):
        if not interactive():
            raise Refusal("a non-interactive apply requires --yes")
        if not confirm_by_typing(agent, len(items), out):
            raise Refusal("confirmation not given; nothing was removed")
    result = apply_items(planner, items, before_delete=before_delete)
    print_apply_result(result, out)
    if result.skipped:
        out.write(f"Some items were kept; {CLEANUP_POINTER}.\n")
    return result.exit_code


def command_list_retired(arguments, out):
    values = parse_options(arguments, {"--layout": True})
    layout = values.get("--layout", "unix")
    if layout not in LAYOUTS:
        raise Refusal("--layout must be unix or windows")
    data = load_data()
    for line in build_installer_list(data.inventory, layout):
        out.write(line + "\n")
    return EXIT_OK


def command_validate(arguments, out):
    parse_options(arguments, {})
    data = load_data()
    out.write(f"Inventory valid: {len(data.entries)} entries, digest {data.inventory_digest}\n")
    return EXIT_OK


def main(argv=None, out=None):
    argv = sys.argv[1:] if argv is None else argv
    out = out or sys.stdout
    if not argv or argv[0] not in SUBCOMMANDS:
        sys.stderr.write("refused: the first argument must be one of: dry-run, apply, list-retired, validate\n")
        return EXIT_REFUSED
    command, arguments = argv[0], argv[1:]
    try:
        if command == "install":
            raise Refusal("the installed helper has no installer mode; installers run the checkout entry point")
        if command == "dry-run":
            return command_dry_run(arguments, out)
        if command == "apply":
            return command_apply(arguments, out)
        if command == "list-retired":
            return command_list_retired(arguments, out)
        return command_validate(arguments, out)
    except Refusal as refusal:
        sys.stderr.write(f"refused: {refusal}\n")
        return EXIT_REFUSED
    except KeyboardInterrupt:
        sys.stderr.write("refused: interrupted\n")
        return EXIT_REFUSED


if __name__ == "__main__":
    sys.exit(main())
