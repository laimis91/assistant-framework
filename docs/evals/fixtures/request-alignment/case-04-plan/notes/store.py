"""Load and save the notes.json file."""
import json
import os
import tempfile

FORMAT_VERSION = 1


def load(path):
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    if data.get("version") != FORMAT_VERSION:
        raise ValueError(f"unsupported notes.json version: {data.get('version')}")
    return [{"id": note["id"], "text": note["text"]} for note in data["notes"]]


def save(path, notes):
    payload = {
        "version": FORMAT_VERSION,
        "notes": [{"id": note["id"], "text": note["text"]} for note in notes],
    }
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=directory, suffix=".tmp")
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
    os.replace(tmp, path)
