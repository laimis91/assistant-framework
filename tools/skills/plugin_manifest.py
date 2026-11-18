"""Shared plugin manifest writer for the marketplace plugin and eval plugins.

Claude Code reads `.claude-plugin/plugin.json`; Codex reads the portable root
`plugin.json`. Both carry the same name, version and description. Codex treats a
root `plugin.json` as a manifest only when it declares the Agent Plugins
`$schema`; without it Codex reports the plugin as missing or invalid.
"""
import json
from pathlib import Path

CLAUDE_MANIFEST = Path(".claude-plugin") / "plugin.json"
PORTABLE_MANIFEST = Path("plugin.json")
AGENT_PLUGIN_SCHEMA = "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"


def manifest_payloads(name, version, description=None, extra=None):
    """Return {relative path: dict} for every manifest a plugin root carries."""
    payload = {"name": name, "version": version}
    if description:
        payload["description"] = description
    if extra:
        payload.update(extra)
    return {CLAUDE_MANIFEST: dict(payload), PORTABLE_MANIFEST: {"$schema": AGENT_PLUGIN_SCHEMA, **payload}}


def render(payload):
    return json.dumps(payload, indent=2) + "\n"


def write_manifests(plugin_root, name, version, description=None, extra=None, claude_only=False):
    """Write the plugin manifests under plugin_root and return the written paths."""
    root = Path(plugin_root)
    written = []
    for relative, payload in manifest_payloads(name, version, description, extra).items():
        if claude_only and relative != CLAUDE_MANIFEST:
            continue
        target = root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(render(payload), encoding="utf-8")
        written.append(target)
    return written
