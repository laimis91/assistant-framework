#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"
source "$P0P4_SUITE_DIR/lib/response-fixture-preflight.sh"

preflight_test_root="$(mktemp -d "${TMPDIR:-/tmp}/response-preflight-test.XXXXXX")"
p0p4_register_cleanup "$preflight_test_root"
preflight_test_fixture="$preflight_test_root/cases.json"
cat >"$preflight_test_fixture" <<'JSON'
{"skill":"fixture-skill","cases":[
  {"id":"structured","machine_expectations":{"structured_json_assertions":[{}]}},
  {"id":"semantic","semantic_validator":"assistant-research.five_lens_v3","machine_expectations":{}},
  {"id":"text","machine_expectations":{}}
]}
JSON

preflight_test_builder() {
    mkdir -p "$1/fixture-skill"
    printf '{"status":"ok"}\n' >"$1/fixture-skill/structured.txt"
    printf '{"status":"ok"}\n' >"$1/fixture-skill/semantic.txt"
    printf 'Plain response.\n' >"$1/fixture-skill/text.txt"
    case "$preflight_test_mutation" in
        missing) rm "$1/fixture-skill/structured.txt" ;;
        empty) : >"$1/fixture-skill/text.txt" ;;
        whitespace) printf ' \n\t' >"$1/fixture-skill/text.txt" ;;
        malformed) printf '{broken' >"$1/fixture-skill/structured.txt" ;;
        multiple) printf '{}\n{}\n' >"$1/fixture-skill/structured.txt" ;;
        semantic_malformed) printf '{broken' >"$1/fixture-skill/semantic.txt" ;;
        semantic_multiple) printf '{}\n{}\n' >"$1/fixture-skill/semantic.txt" ;;
        exit_failure) return 1 ;;
        counted_failure) fail "fixture builder reported a failure" ;;
    esac
}

test_start "response preflight accepts complete assertion, semantic-validator, and plain fixtures"
preflight_test_mutation=valid
if p0p4_preflight_response_fixtures preflight_test_builder "$preflight_test_fixture" >"$preflight_test_root/valid.log" 2>&1; then
    pass
else
    fail "complete response fixtures were rejected"
fi

for preflight_test_mutation in missing empty whitespace malformed multiple semantic_malformed semantic_multiple exit_failure counted_failure; do
    test_start "response preflight rejects $preflight_test_mutation output"
    if p0p4_preflight_response_fixtures preflight_test_builder "$preflight_test_fixture" >"$preflight_test_root/$preflight_test_mutation.log" 2>&1; then
        fail "preflight accepted $preflight_test_mutation"
    else
        pass
    fi
done

test_start "response preflight cannot reuse files from an earlier builder invocation"
preflight_test_mutation=valid
preflight_empty_builder() { :; }
if p0p4_preflight_response_fixtures preflight_test_builder "$preflight_test_fixture" >/dev/null 2>&1 \
    && ! p0p4_preflight_response_fixtures preflight_empty_builder "$preflight_test_fixture" >"$preflight_test_root/stale.log" 2>&1; then
    pass
else
    fail "preflight reused stale files or rejected its valid control"
fi

test_start "real suite entrypoints accept current fixtures and stop unhandled cases before grading"
if python3 - "$FRAMEWORK_DIR" "$preflight_test_root" <<'PY'
from pathlib import Path
import json
import os
import shutil
import signal
import subprocess
import sys

source, destination = Path(sys.argv[1]), Path(sys.argv[2]) / "suite-probe"
for relative in ("tests", "skills", "tools/evals/lib"):
    shutil.copytree(source / relative, destination / relative)
marker = destination / "grader-was-called"
runner = destination / "tools/evals/run-skill-evals.sh"
runner.write_text('#!/usr/bin/env bash\ntouch "$(dirname "$0")/../../grader-was-called"\nexit 91\n')
runner.chmod(0o755)

def run(suite, *arguments):
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

suites = ("skill-eval-contracts.sh", "progressive-discovery-contracts.sh")
for suite in suites:
    status, output = run(suite, "--fixtures-only")
    assert status == 0 and "Passed: 1" in output, output

fixture = destination / "skills/assistant-workflow/evals/cases.json"
document = json.loads(fixture.read_text())
case = next(case.copy() for case in document["cases"]
            if case.get("machine_expectations", {}).get("structured_json_assertions"))
case["id"] = "unhandled-preflight-regression"
document["cases"].append(case)
fixture.write_text(json.dumps(document))
for suite in suites:
    status, output = run(suite)
    assert status != 0 and "unhandled-preflight-regression" in output, output
    assert "semantic grading was not started" in output, output
PY
then
    pass
else
    fail "real suite preflight did not preserve positive or fail-fast behavior"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
