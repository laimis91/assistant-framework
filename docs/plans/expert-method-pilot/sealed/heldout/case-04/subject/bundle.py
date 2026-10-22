"""Read a local support bundle. This is a capture reader, not a live health probe."""
import argparse
import json
from pathlib import Path


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", choices=["inventory", "current", "incident"])
    args = parser.parse_args()
    root = Path(__file__).parent
    captures = json.loads((root / "captures.json").read_text())
    if args.capture == "inventory":
        result = {"files": sorted(path.name for path in root.iterdir() if path.is_file()), "exported_at": captures["exported_at"], "incident_window": captures["incident_window"]}
    else:
        result = captures[args.capture]
    print(json.dumps(result, sort_keys=True))
    if args.capture == "incident" and result["availability"] == "unavailable":
        raise SystemExit(3)
