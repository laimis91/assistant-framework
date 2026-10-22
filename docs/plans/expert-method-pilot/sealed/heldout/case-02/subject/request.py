"""Replay the current request path with a captured profile."""
import argparse
import json
from pathlib import Path


def request(profile, dependency_delay_ms):
    timeout_ms = float(profile["upstream_timeout_ms"])
    return {
        "profile": profile["profile"],
        "timeout_ms": timeout_ms,
        "dependency_delay_ms": dependency_delay_ms,
        "status": "ok" if dependency_delay_ms <= timeout_ms else "upstream_timeout",
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", default="configs/current.json")
    parser.add_argument("--dependency-delay-ms", type=float, default=30)
    args = parser.parse_args()
    if args.dependency_delay_ms < 0 or args.dependency_delay_ms > 1000:
        parser.error("dependency delay must be between 0 and 1000 milliseconds")
    path = Path(__file__).parent / args.profile
    print(json.dumps(request(json.loads(path.read_text()), args.dependency_delay_ms), sort_keys=True))
