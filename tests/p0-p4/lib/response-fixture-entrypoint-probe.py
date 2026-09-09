#!/usr/bin/env python3
"""Exercise one shard's response-builder entrypoint without semantic grading."""

import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile


def probe(suite):
    source = Path(__file__).resolve().parents[3]
    with tempfile.TemporaryDirectory(prefix="response-entrypoint-probe-") as temporary:
        destination = Path(temporary)
        for relative in ("tests", "skills", "tools/evals/lib"):
            shutil.copytree(source / relative, destination / relative)
        marker = destination / "grader-was-called"
        runner = destination / "tools/evals/run-skill-evals.sh"
        runner.write_text('#!/usr/bin/env bash\ntouch "$(dirname "$0")/../../grader-was-called"\nexit 91\n')
        runner.chmod(0o755)

        def run(*arguments):
            process = subprocess.Popen(
                ["bash", str(destination / "tests/p0-p4" / suite), *arguments],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                start_new_session=True,
            )
            try:
                output, _ = process.communicate(timeout=45)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.communicate()
                raise AssertionError(f"{suite} did not finish its bounded preflight")
            assert not marker.exists(), f"{suite} invoked semantic grading"
            return process.returncode, output

        status, output = run("--fixtures-only")
        assert status == 0 and "Passed: 1" in output, output

        fixture = destination / "skills/assistant-workflow/evals/cases.json"
        document = json.loads(fixture.read_text())
        case = next(case.copy() for case in document["cases"]
                    if case.get("machine_expectations", {}).get("structured_json_assertions"))
        case["id"] = "unhandled-preflight-regression"
        document["cases"].append(case)
        fixture.write_text(json.dumps(document))
        status, output = run()
        assert status != 0 and "unhandled-preflight-regression" in output, output
        assert "semantic grading was not started" in output, output
        print(f"PASS {suite}: complete fixtures accepted; unhandled case rejected before grading")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("suite", choices=("skill-eval-contracts.sh", "progressive-discovery-contracts.sh"))
    probe(parser.parse_args().suite)
