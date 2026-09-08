#!/usr/bin/env python3
"""Validate and materialize bounded exact instruction overlays.

The manifest binds a small instruction-only payload to the current canonical
assistant-workflow source.  This helper deliberately has no dependency beyond
the Python standard library so the eval adapter can reject unsafe input before
it writes a plan or invokes a model.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import stat
import sys
from pathlib import Path, PurePosixPath
from typing import Optional


MAX_MANIFEST_BYTES = 64 * 1024
MAX_OVERLAY_FILES = 128
MAX_OVERLAY_BYTES = 1024 * 1024
HEX_SHA256 = set("0123456789abcdef")


class OverlayError(ValueError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(64 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def reject_duplicate_object_keys(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise OverlayError("instruction overlay manifest contains duplicate JSON keys")
        result[key] = value
    return result


def ensure_regular(path: Path, description: str) -> os.stat_result:
    try:
        metadata = path.lstat()
    except FileNotFoundError as error:
        raise OverlayError(f"{description} is missing") from error
    if stat.S_ISLNK(metadata.st_mode):
        raise OverlayError(f"{description} must not be a symlink")
    if not stat.S_ISREG(metadata.st_mode):
        raise OverlayError(f"{description} must be a regular file")
    return metadata


def ensure_directory(path: Path, description: str) -> None:
    try:
        metadata = path.lstat()
    except FileNotFoundError as error:
        raise OverlayError(f"{description} is missing") from error
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        raise OverlayError(f"{description} must be a real directory")


def is_sha256(value: object) -> bool:
    return isinstance(value, str) and len(value) == 64 and set(value) <= HEX_SHA256


def validate_relative_path(value: object) -> str:
    if not isinstance(value, str) or not value:
        raise OverlayError("overlay file path must be a nonempty string")
    if any(ord(character) < 32 or ord(character) == 127 for character in value):
        raise OverlayError("overlay file path contains a control character")
    if "\\" in value or value.startswith("/"):
        raise OverlayError("overlay file path is not canonical")
    path = PurePosixPath(value)
    if path.as_posix() != value or any(part in {"", ".", ".."} for part in path.parts):
        raise OverlayError("overlay file path is not canonical")
    if value != "SKILL.md" and not (value.startswith("references/") or value.startswith("contracts/")):
        raise OverlayError("overlay file path is outside the instruction surface")
    return value


def source_files(root: Path) -> list[tuple[str, Path]]:
    ensure_directory(root, "canonical source tree")
    result: list[tuple[str, Path]] = []
    for current, directories, files in os.walk(root, followlinks=False):
        current_path = Path(current)
        directories[:] = sorted(directory for directory in directories if not (current_path == root and directory == "evals"))
        for directory in directories:
            directory_path = current_path / directory
            if stat.S_ISLNK(directory_path.lstat().st_mode):
                raise OverlayError("canonical source tree must not contain symlinks")
        for filename in sorted(files):
            path = current_path / filename
            ensure_regular(path, "canonical source entry")
            result.append((path.relative_to(root).as_posix(), path))
    return sorted(result)


def tree_sha256(root: Path) -> str:
    inventory = "".join(f"{relative} {sha256_file(path)}\n" for relative, path in source_files(root))
    return hashlib.sha256(inventory.encode("utf-8")).hexdigest()


def load_manifest(path: Path) -> tuple[dict[str, object], str]:
    metadata = ensure_regular(path, "instruction overlay manifest")
    if metadata.st_size < 1 or metadata.st_size > MAX_MANIFEST_BYTES:
        raise OverlayError(f"instruction overlay manifest must be 1..{MAX_MANIFEST_BYTES} bytes")
    try:
        raw = path.read_bytes()
        document = json.loads(raw, object_pairs_hook=reject_duplicate_object_keys)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise OverlayError("instruction overlay manifest must be valid UTF-8 JSON") from error
    if not isinstance(document, dict) or set(document) != {"schema_version", "mode", "base_skill", "base_source_sha256", "files"}:
        raise OverlayError("instruction overlay manifest has an unsupported shape")
    if document["schema_version"] != "1.0" or document["mode"] != "hashed_instruction_overlay" or document["base_skill"] != "assistant-workflow":
        raise OverlayError("instruction overlay manifest has an unsupported identity")
    if not is_sha256(document["base_source_sha256"]):
        raise OverlayError("instruction overlay manifest base_source_sha256 is invalid")
    files = document["files"]
    if not isinstance(files, list) or not files or len(files) > MAX_OVERLAY_FILES:
        raise OverlayError("instruction overlay manifest files are out of bounds")
    paths: list[str] = []
    for entry in files:
        if not isinstance(entry, dict) or set(entry) != {"path", "sha256"}:
            raise OverlayError("instruction overlay manifest file entry has an unsupported shape")
        relative = validate_relative_path(entry["path"])
        if not is_sha256(entry["sha256"]):
            raise OverlayError("instruction overlay manifest file hash is invalid")
        paths.append(relative)
    if paths != sorted(paths) or len(paths) != len(set(paths)) or "SKILL.md" not in paths:
        raise OverlayError("instruction overlay manifest files must be sorted, unique, and include SKILL.md")
    return document, sha256_bytes(raw)


def validate_payload(manifest_path: Path, document: dict[str, object], base_root: Path, manifest_hash: str) -> dict[str, object]:
    base_hash = tree_sha256(base_root)
    if document["base_source_sha256"] != base_hash:
        raise OverlayError("instruction overlay manifest base source hash is stale")
    parent = manifest_path.parent
    ensure_directory(parent, "instruction overlay payload directory")
    expected = {entry["path"]: entry["sha256"] for entry in document["files"]}  # type: ignore[index]
    allowed_directories = {""}
    for relative in expected:
        parts = relative.split("/")[:-1]
        for index in range(1, len(parts) + 1):
            allowed_directories.add("/".join(parts[:index]))
    actual: dict[str, Path] = {}
    total_bytes = 0
    pending = [("", parent)]
    while pending:
        current_relative, current_path = pending.pop()
        with os.scandir(current_path) as entries:
            for entry in entries:
                path = Path(entry.path)
                relative = entry.name if not current_relative else f"{current_relative}/{entry.name}"
                if entry.is_symlink():
                    raise OverlayError("instruction overlay payload must not contain symlinks")
                if entry.is_dir(follow_symlinks=False):
                    if relative not in allowed_directories:
                        raise OverlayError("instruction overlay payload contains an unlisted directory")
                    pending.append((relative, path))
                    continue
                if not entry.is_file(follow_symlinks=False):
                    raise OverlayError("instruction overlay payload entry must be a regular file")
                metadata = ensure_regular(path, "instruction overlay payload entry")
                if path == manifest_path:
                    continue
                if relative not in expected:
                    raise OverlayError("instruction overlay payload contains missing or unlisted files")
                actual[relative] = path
                total_bytes += metadata.st_size
                if total_bytes > MAX_OVERLAY_BYTES:
                    raise OverlayError(f"instruction overlay payload must be at most {MAX_OVERLAY_BYTES} bytes")
    if total_bytes > MAX_OVERLAY_BYTES:
        raise OverlayError(f"instruction overlay payload must be at most {MAX_OVERLAY_BYTES} bytes")
    if set(actual) != set(expected):
        raise OverlayError("instruction overlay payload contains missing or unlisted files")
    for relative, expected_hash in expected.items():
        path = actual[relative]
        if sha256_file(path) != expected_hash:
            raise OverlayError(f"instruction overlay payload hash is stale: {relative}")
    return {
        "mode": "hashed_instruction_overlay",
        "source_manifest_sha256": manifest_hash,
        "base_source_sha256": base_hash,
        "overlay_file_count": len(expected),
    }


def inspect(manifest: Path, base_root: Path) -> dict[str, object]:
    document, manifest_hash = load_manifest(manifest)
    return validate_payload(manifest, document, base_root, manifest_hash)


def copy_bytes(source: Path, destination: Path, expected_hash: Optional[str] = None) -> None:
    data = source.read_bytes()
    digest = sha256_bytes(data)
    if expected_hash is not None and digest != expected_hash:
        raise OverlayError(f"instruction overlay payload hash is stale: {source.name}")
    destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    destination.write_bytes(data)


def materialize(manifest: Path, base_root: Path, destination: Path) -> dict[str, object]:
    document, manifest_hash = load_manifest(manifest)
    metadata = validate_payload(manifest, document, base_root, manifest_hash)
    if destination.exists() or destination.is_symlink():
        raise OverlayError("instruction overlay destination must not already exist")
    destination.mkdir(mode=0o700, parents=True)
    try:
        for relative, source in source_files(base_root):
            target = destination / relative
            copy_bytes(source, target)
        if tree_sha256(destination) != metadata["base_source_sha256"]:
            raise OverlayError("canonical source changed while the instruction overlay was staged")
        for entry in document["files"]:  # type: ignore[index]
            relative = entry["path"]
            source = manifest.parent / relative
            target = destination / relative
            copy_bytes(source, target, entry["sha256"])
    except Exception:
        shutil.rmtree(destination, ignore_errors=True)
        raise
    return metadata


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("inspect", "materialize", "source-hash"):
        command = commands.add_parser(name)
        command.add_argument("--base-skill-tree", required=True)
        if name != "source-hash":
            command.add_argument("--manifest", required=True)
        if name == "materialize":
            command.add_argument("--destination", required=True)
    arguments = parser.parse_args()
    try:
        base_root = Path(arguments.base_skill_tree)
        if arguments.command == "source-hash":
            result = {"base_source_sha256": tree_sha256(base_root)}
        else:
            manifest = Path(arguments.manifest)
            if arguments.command == "inspect":
                result = inspect(manifest, base_root)
            else:
                result = materialize(manifest, base_root, Path(arguments.destination))
    except OverlayError as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
