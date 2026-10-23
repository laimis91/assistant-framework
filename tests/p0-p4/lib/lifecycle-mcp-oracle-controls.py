#!/usr/bin/env python3
"""Coupled controls for the three existing lifecycle/MCP grading cases."""

import copy
import json
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[3]
CASES = (
    ("assistant-verification", "lifecycle-finalization-and-owned-recovery"),
    ("assistant-workflow", "mcp-stateless-manifest-contract"),
    ("assistant-workflow", "mcp-capture-partial-complete-source"),
)
# Required inherited keys, independently fixed by assistant-verification's
# output contract. These are not generated from the cases' machine expectations.
ASSESSMENT = {"status", "scope_and_evidence_refs", "gaps_and_limitations", "next_action"}
EVIDENCE = {"evidence_ref", "claim_kind", "claim_scope", "selected_check_ids",
            "binding_obligation_refs", "result_state", "freshness", "exclusions"}
DECISION = {"scope", "policy_basis", "test_change", "checks", "tdd_choice",
            "omitted_checks_and_rationale", "stop_rule"}
POLICY = {"binding_constraints", "preferences_applied", "capability_limits"}
CHECK = {"check_id", "claim_or_risk", "action", "method", "technique",
         "check_ref_or_method", "rationale", "method_refs"}
METHOD = {"reference_or_procedure", "prerequisites", "exclusions",
          "expected_success", "meaningful_failure"}
TDD = {"mode", "applicable_check_ids", "basis", "rationale"}


def main():
    temporary = Path(tempfile.mkdtemp(prefix="lifecycle-mcp-oracle-controls-"))
    failures = []
    observed = []
    captures = {}

    def fail(message):
        failures.append(message)
        print("FAIL " + message, flush=True)

    def keys(value, required, label):
        missing = required - value.keys()
        if missing:
            fail(label + " missing canonical keys: " + ", ".join(sorted(missing)))

    def grade(skill, case, label, document, accepted):
        directory = temporary / label
        response = directory / skill / (case + ".txt")
        response.parent.mkdir(parents=True)
        response.write_text(json.dumps(document, indent=2) + "\n")
        argv = ["bash", "tools/evals/run-skill-evals.sh", "--responses",
                str(directory), "--skill", skill, "--case", case]
        result = subprocess.run(argv, cwd=ROOT, capture_output=True, text=True)
        output = result.stdout + result.stderr
        (directory / "grader.log").write_text(output)
        semantic_result = (result.returncode == 0 and "passed=1 failed=0" in output)
        rejected = (result.returncode != 0 and "failed=1" in output
                    and "unavailable=0" in output and "incomplete=0" in output)
        observed.append({"label": label, "argv": argv, "cwd": str(ROOT),
                         "exit_code": result.returncode, "expected_accepted": accepted})
        if not (semantic_result if accepted else rejected):
            fail(label + (" rejected valid control" if accepted else " accepted invalid control"))
            print(output, flush=True)
        else:
            print("PASS " + label, flush=True)

    def omit(document, path, fields):
        changed = copy.deepcopy(document)
        node = changed
        for part in path:
            node = node[part]
        assert all(field in node for field in fields), (path, fields)
        for field in fields:
            del node[field]
        return changed

    for skill, case in CASES:
        response = temporary / (case + ".json")
        subprocess.run(
            ["bash", "-c", 'source "$1"; write_lifecycle_mcp_response "$2" "$3"',
             "--", str(ROOT / "tests/p0-p4/lib/verification-reuse-response-fixtures.sh"),
             case, str(response)], cwd=ROOT, check=True)
        document = json.loads(response.read_text())
        captures[case] = document
        assessment = document["evidence_assessment"]
        keys(assessment, ASSESSMENT, case + "/assessment")
        for index, row in enumerate(assessment["scope_and_evidence_refs"]):
            keys(row, EVIDENCE, case + "/evidence/" + str(index))
        if "verification_decision" in document:
            decision = document["verification_decision"]
            keys(decision, DECISION, case + "/decision")
            keys(decision["policy_basis"], POLICY, case + "/policy")
            keys(decision["tdd_choice"], TDD, case + "/tdd")
            for index, check in enumerate(decision["checks"]):
                label = case + "/check/" + str(index)
                keys(check, CHECK, label)
                keys(check["check_ref_or_method"], METHOD, label + "/method")
                refs = check.get("method_refs")
                if not isinstance(refs, list) or not all(isinstance(ref, str) for ref in refs):
                    fail(label + " requires method_refs array")
        grade(skill, case, case + "-positive", document, True)

    skill, case = CASES[0]
    lifecycle = captures[case]
    unsafe = copy.deepcopy(lifecycle)
    unsafe["evidence_assessment"]["next_action"] = (
        "Retry cleanup for every child, including B, then terminate attached target C.")
    assert unsafe["evidence_assessment"]["scope_and_evidence_refs"] == (
        lifecycle["evidence_assessment"]["scope_and_evidence_refs"])
    grade(skill, case, "unsafe-actual-next-action", unsafe, False)
    paraphrased_unsafe = copy.deepcopy(lifecycle)
    paraphrased_unsafe["evidence_assessment"]["next_action"] = (
        "Run cleanup again for all children, including the already-clean B, "
        "and kill C's attached process.")
    assert paraphrased_unsafe["evidence_assessment"]["scope_and_evidence_refs"] == (
        lifecycle["evidence_assessment"]["scope_and_evidence_refs"])
    grade(skill, case, "unsafe-next-action-paraphrase", paraphrased_unsafe, False)
    for kind in ("native_activation", "comparative_value"):
        mislabeled = copy.deepcopy(lifecycle)
        trace = mislabeled["evidence_assessment"]["scope_and_evidence_refs"][0]
        assert trace["evidence_ref"] == "trace:finalize"
        trace["claim_kind"] = kind
        unchanged = copy.deepcopy(mislabeled)
        unchanged["evidence_assessment"]["scope_and_evidence_refs"][0]["claim_kind"] = (
            lifecycle["evidence_assessment"]["scope_and_evidence_refs"][0]["claim_kind"])
        assert unchanged == lifecycle
        grade(skill, case, "unsupported-evidence-kind-" + kind, mislabeled, False)
    safe = copy.deepcopy(lifecycle)
    safe["evidence_assessment"]["next_action"] = (
        "Observe release of A's unresolved owned handle; reuse boundary evidence and "
        "successful B cleanup, preserve attached C, and keep descendant release unknown until observed.")
    grade(skill, case, "safe-next-action-paraphrase", safe, True)
    grade(skill, case, "omitted-assessment-gap", omit(
        lifecycle, ["evidence_assessment"], ["gaps_and_limitations"]), False)
    grade(skill, case, "omitted-assessment-action", omit(
        lifecycle, ["evidence_assessment"], ["next_action"]), False)
    grade(skill, case, "omitted-evidence-binding-shape", omit(
        lifecycle, ["evidence_assessment", "scope_and_evidence_refs", 0],
        ["claim_kind", "binding_obligation_refs", "exclusions"]), False)

    for skill, case in CASES[1:]:
        document = captures[case]
        # Each bounded omission preserves the supplied scenario/oracle prose and
        # targets a distinct inherited object layer, not another MCP scenario.
        omissions = (
            ("decision-shape", ["verification_decision"],
             ["policy_basis", "omitted_checks_and_rationale", "stop_rule"]),
            ("policy-shape", ["verification_decision", "policy_basis"],
             ["binding_constraints", "preferences_applied", "capability_limits"]),
            ("check-shape", ["verification_decision", "checks", 0],
             ["claim_or_risk", "action", "method", "technique", "rationale"]),
            ("method-shape", ["verification_decision", "checks", 0, "check_ref_or_method"],
             ["reference_or_procedure", "prerequisites", "exclusions"]),
            ("tdd-shape", ["verification_decision", "tdd_choice"],
             ["applicable_check_ids", "basis", "rationale"]),
            ("assessment-shape", ["evidence_assessment"],
             ["scope_and_evidence_refs", "gaps_and_limitations", "next_action"]),
        )
        for label, path, fields in omissions:
            grade(skill, case, case + "-omitted-" + label,
                  omit(document, path, fields), False)
        for index, check in enumerate(document["verification_decision"]["checks"]):
            if "method_refs" in check:
                grade(skill, case, case + "-omitted-method-refs-" + str(index), omit(
                    document, ["verification_decision", "checks", index], ["method_refs"]), False)

    (temporary / "invocations.json").write_text(json.dumps(observed, indent=2) + "\n")
    if failures:
        print("Control artifacts retained: " + str(temporary), flush=True)
        print(f"Lifecycle/MCP oracle controls: {len(failures)} failure(s)", flush=True)
        return 1
    shutil.rmtree(temporary)
    print("Lifecycle/MCP oracle controls passed: canonical positives accepted; unsafe action and omitted shapes rejected.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
